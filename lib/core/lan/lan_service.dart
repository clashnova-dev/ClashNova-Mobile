import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'lan_bonjour.dart';
import 'lan_discovery.dart';
import 'lan_identity.dart';
import 'lan_models.dart';
import 'lan_qr.dart';
import 'lan_scan.dart';
import 'lan_storage.dart';
import 'lan_transport.dart';

/// 在线发现到的设备（供 UI 展示/发送）。
class DiscoveredDevice {
  DiscoveredDevice({
    required this.fingerprint,
    required this.alias,
    required this.address,
    required this.port,
    this.deviceType,
    this.trusted = false,
  });
  final String fingerprint;
  final String alias;
  final String address;
  final int port;
  final LanDeviceType? deviceType;
  bool trusted;

  String get baseUrl => 'https://$address:$port';
}

/// 收到的配对请求（UI 弹窗确认）。
class PairRequest {
  const PairRequest(this.requestId, this.peer);
  final String requestId;
  final DeviceInfo peer;
}

/// 收到的（未配对）接收请求（文件/文本），逐次确认。
class IncomingRequest {
  const IncomingRequest(this.requestId, this.peer, this.files, this.text);
  final String requestId;
  final DeviceInfo peer;
  final List<FileDto> files;
  final String? text;
}

/// 进行中的传输（进度）。
class InFlight {
  InFlight(this.taskId, this.fingerprint, this.fileName, this.size, this.outgoing);
  final String taskId;
  final String fingerprint;
  final String fileName;
  final int size;
  final bool outgoing;
  int done = 0;
}

/// 局域网传输服务门面（ChangeNotifier）。编排身份/发现/传输/存储，供 Flutter UI 消费。
///
/// 与桌面 airport-lan 协议互通；配对即信任、配对后自动接收；未配对（含三方 LocalSend）
/// 回退到逐次确认。
class LanService extends ChangeNotifier {
  LanService({required this.storage, required this.defaultSaveDir});

  final LanStorage storage;
  final String defaultSaveDir;

  LanIdentity? _identity;
  LanReceiver? _receiver;
  LanDiscovery? _discovery;
  LanBonjour? _bonjour;
  int _port = kDefaultPort; // 接收端实际监听端口（bind 后确定）。
  LanSettings settings = LanSettings();

  final Map<String, DiscoveredDevice> _online = {}; // fingerprint → device
  final Map<String, int> _lastSeen = {}; // fingerprint → 最近发现的 epoch 秒
  Timer? _pruneTimer; // 周期剔除超时未再被发现的对端（自动下线）
  Timer? _keepAliveTimer; // 周期保活已在线设备，避免被动发现（Bonjour 边沿触发）下的 TTL 误删
  static const int _onlineTtlSec = 30;
  List<TrustedDevice> trusted = [];
  final Map<String, InFlight> inflight = {}; // taskId → progress

  final Map<String, Completer<bool>> _pendingPair = {};
  final Map<String, Completer<bool>> _pendingAccept = {};
  final Map<String, Completer<String?>> _pendingSync = {}; // requestId → payload/null
  PairRequest? pairRequest; // 当前待确认的配对请求
  PairRequest? syncRequest; // 当前待确认的「拉取同步」请求（复用 requestId+sender）
  IncomingRequest? incoming; // 当前待确认的（未配对）接收请求

  bool get ready => _receiver != null;

  /// 接收端实际监听端口（诊断/测试用）。
  int get receiverPort => _receiver?.port ?? 0;

  List<DiscoveredDevice> get devices => _online.values.toList();

  DeviceInfo get local => DeviceInfo(
        alias: settings.alias,
        fingerprint: _identity?.fingerprint ?? '',
        deviceType: _localType,
        port: _port,
        protocol: LanProtocol.https,
      );

  LanDeviceType? _localTypeCache;

  /// 本机设备类型（缓存首个确定结果，避免首帧前屏幕尺寸未知时误判）。
  LanDeviceType get _localType {
    final cached = _localTypeCache;
    if (cached != null) return cached;
    final detected = _detectLocalDeviceType();
    if (detected != null) _localTypeCache = detected;
    return detected ?? LanDeviceType.phone;
  }

  /// 探测本机设备类型：桌面平台→desktop；手机按屏幕最短边 <600dp 为 phone、
  /// ≥600dp 为 tablet。屏幕尺寸尚不可用（首帧前）时返回 null，留待下次再判。
  static LanDeviceType? _detectLocalDeviceType() {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return LanDeviceType.desktop;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final view = ui.PlatformDispatcher.instance.views.first;
        final size = view.physicalSize;
        if (size.shortestSide <= 0) return null; // 首帧前，尺寸未知
        final shortestSideDp = size.shortestSide / view.devicePixelRatio;
        return shortestSideDp >= 600
            ? LanDeviceType.tablet
            : LanDeviceType.phone;
      } catch (_) {
        return null;
      }
    }
    return LanDeviceType.phone;
  }

  /// 某设备的会话时间线（最旧在前）。
  List<ChatMessage> conversation(String fingerprint) {
    final list = storage.conversation(fingerprint);
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  // ———————————————————— 生命周期 ————————————————————

  Future<void> start({int port = kDefaultPort, bool discover = true}) async {
    if (_receiver != null) return;
    settings = storage.loadSettings(
      defaultAlias: _defaultAlias(),
      defaultSaveDir: defaultSaveDir,
    );
    if (settings.saveDir.isEmpty) settings.saveDir = defaultSaveDir;
    _identity = await LanIdentity.loadOrCreate();
    trusted = storage.listTrusted();

    final receiver = LanReceiver(
      identity: _identity!,
      local: () => local,
      onDecideUpload: _decideUpload,
      onDecidePair: _decidePair,
      onDecideText: _decideText,
      onDecideSync: _decideSync,
      onPeer: _notePeerLike,
      onProgress: _onProgress,
      onStarted: _onStarted,
      onReceived: _onReceived,
      onTextReceived: _onTextReceived,
    );
    await receiver.start(port);
    _receiver = receiver;
    _port = receiver.port; // 回退临时端口时以真实端口广播。

    if (discover) {
      // Bonjour/DNS-SD：全平台主发现（iOS 走原生 Bonjour，免组播权限）。best-effort。
      try {
        final bonjour = LanBonjour(local: local, onPeer: _addOnline);
        await bonjour.start();
        _bonjour = bonjour;
      } catch (e) {
        debugPrint('[lan] bonjour unavailable (non-fatal): $e');
      }
      // UDP 组播：兼容原版 LocalSend。仅在有组播权限的平台起（Android）；
      // iOS 无 Apple 组播权限，原始组播注定失败，跳过——iOS 靠 Bonjour + TCP 扫描。
      if (!Platform.isIOS) {
        try {
          final discovery = LanDiscovery(local: local, onPeer: _onDiscoverPeer);
          await discovery.start();
          _discovery = discovery;
        } catch (e) {
          debugPrint('[lan] discovery unavailable (non-fatal): $e');
        }
      }
      _pruneTimer ??=
          Timer.periodic(const Duration(seconds: 10), (_) => _pruneStale());
      // 保活：被动发现（Bonjour）是边沿触发、TCP 扫描只在进页/刷新跑，持续在线的
      // 设备不会被重复上报，光靠 TTL 会把仍在线的设备误删。周期（< TTL）对已在线
      // 设备做轻量 TCP 探活，通则续期，不通则留给 TTL 剔除。
      _keepAliveTimer ??=
          Timer.periodic(const Duration(seconds: 12), (_) => _keepAliveOnline());
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _lastSeen.clear();
    await _bonjour?.stop();
    _bonjour = null;
    await _discovery?.stop();
    _discovery = null;
    await _receiver?.stop();
    _receiver = null;
    notifyListeners();
  }

  void refresh() => _discovery?.refresh();

  static String _defaultAlias() {
    try {
      final h = Platform.localHostname.trim();
      if (h.isNotEmpty && h != 'localhost') return h;
    } catch (_) {}
    return Platform.isIOS ? 'iPhone' : 'ClashNova';
  }

  // ———————————————————— 配对 ————————————————————

  /// 主动向设备发起配对。
  Future<void> pair(String fingerprint) async {
    final dev = _online[fingerprint];
    if (dev == null) throw const LanException('msg.lanError');
    await sendPair(
      baseUrl: dev.baseUrl,
      sender: local,
      identity: _identity!,
      expectedFingerprint: dev.fingerprint,
    );
    await storage.upsertTrusted(
        dev.fingerprint, dev.alias, _platformOf(dev.deviceType));
    trusted = storage.listTrusted();
    dev.trusted = true;
    notifyListeners();
  }

  /// 响应收到的配对请求。
  void respondPair(String requestId, bool accept) {
    _pendingPair[requestId]?.complete(accept);
  }

  Future<bool> _decidePair(DeviceInfo sender) async {
    if (sender.fingerprint.isEmpty) return false;
    final requestId = _rid();
    final c = Completer<bool>();
    _pendingPair[requestId] = c;
    pairRequest = PairRequest(requestId, sender);
    notifyListeners();
    // 配对确认 30s 过期：超时视为拒绝，自动关弹窗（与桌面端一致）。
    final ok = await c.future
        .timeout(const Duration(seconds: 30), onTimeout: () => false);
    _pendingPair.remove(requestId);
    if (pairRequest?.requestId == requestId) {
      pairRequest = null;
      notifyListeners();
    }
    if (ok) {
      await storage.upsertTrusted(sender.fingerprint, sender.alias,
          deviceTypeToString(sender.deviceType));
      trusted = storage.listTrusted();
      _markTrusted(sender.fingerprint);
      notifyListeners();
    }
    return ok;
  }

  /// 解除配对。
  Future<void> unpair(String fingerprint) async {
    await storage.removeTrusted(fingerprint);
    trusted = storage.listTrusted();
    _online[fingerprint]?.trusted = false;
    notifyListeners();
  }

  // ———————————————————— 跨端同步 ————————————————————

  /// 主动从设备「拉取」配置：返回对方确认后发来的配置 payload（不透明字符串，由上层应用）。
  Future<String> syncPull(String fingerprint) async {
    final dev = _online[fingerprint];
    if (dev == null) throw const LanException('msg.lanError');
    return sendSyncPull(
      baseUrl: dev.baseUrl,
      sender: local,
      identity: _identity!,
      expectedFingerprint: dev.fingerprint,
    );
  }

  /// 响应收到的拉取同步请求：接受时传入本机配置 payload（由上层采集），拒绝传 null。
  void respondSync(String requestId, bool accept, String payload) {
    _pendingSync[requestId]?.complete(accept ? payload : null);
  }

  Future<String?> _decideSync(DeviceInfo sender) async {
    if (sender.fingerprint.isEmpty) return null;
    final requestId = _rid();
    final c = Completer<String?>();
    _pendingSync[requestId] = c;
    syncRequest = PairRequest(requestId, sender);
    notifyListeners();
    // 同步确认 30s 过期：超时视为拒绝，自动关弹窗（与桌面端一致）。
    final payload =
        await c.future.timeout(const Duration(seconds: 30), onTimeout: () => null);
    _pendingSync.remove(requestId);
    if (syncRequest?.requestId == requestId) {
      syncRequest = null;
      notifyListeners();
    }
    return payload;
  }

  // ———————————————————— 扫码连接 ————————————————————

  /// 本机私网 IPv4（展示二维码用）。无合适网卡时返回 null。
  Future<String?> localIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final b = a.rawAddress;
          final priv = b[0] == 10 ||
              (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
              (b[0] == 192 && b[1] == 168);
          if (priv) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 本机扫码连接载荷（供对端扫描直连）。缺 IP / 未就绪时返回 null。
  Future<LanQrPayload?> myQrPayload() async {
    final ip = await localIp();
    final fp = _identity?.fingerprint;
    if (ip == null || fp == null || fp.isEmpty) return null;
    return LanQrPayload(ip: ip, port: _port, fingerprint: fp, alias: settings.alias);
  }

  /// 扫码得到的设备：加入在线列表并发起配对（配对即信任）。返回其指纹。
  Future<String> connectByQr(LanQrPayload p) async {
    if (p.fingerprint == _identity?.fingerprint) {
      throw const LanException('msg.lanSelf'); // 扫到自己
    }
    _online[p.fingerprint] = DiscoveredDevice(
      fingerprint: p.fingerprint,
      alias: p.alias,
      address: p.ip,
      port: p.port,
      trusted: storage.isTrusted(p.fingerprint),
    );
    notifyListeners();
    await pair(p.fingerprint); // 单播直连 /pair，成功即记为可信
    return p.fingerprint;
  }

  /// TCP 单播扫描兜底：探活本机各 /24 内 `:kDefaultPort` 开放的主机并拉 /info 登记。
  /// 组播被路由挡住、或本平台无组播权限（iOS）时用它发现对端——纯单播。
  Future<void> scanSubnet() async {
    final me = _identity?.fingerprint;
    final targets = await scanTargets();
    const port = kDefaultPort;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final idx = next++;
        if (idx >= targets.length) return;
        final addr = targets[idx];
        if (!await probeTcp(addr, port, const Duration(milliseconds: 400))) {
          continue;
        }
        try {
          final info = await fetchInfo(
              baseUrl: 'https://${addr.address}:$port', identity: _identity!);
          if (info.fingerprint.isNotEmpty && info.fingerprint != me) {
            _addOnline(info, addr.address);
          }
        } catch (_) {/* 该地址不是对端接收服务，忽略 */}
      }
    }

    await Future.wait([for (var w = 0; w < 48; w++) worker()]);
  }

  /// 手动按地址连接：解析 `IP` 或 `IP:端口`，拉 /info 登记（之后用户可对其配对）。
  Future<DiscoveredDevice> addManualDevice(String addr) async {
    var host = addr.trim();
    var port = kDefaultPort;
    final colon = host.indexOf(':');
    if (colon > 0 && colon == host.lastIndexOf(':')) {
      final p = int.tryParse(host.substring(colon + 1));
      if (p != null && p > 0 && p <= 65535) {
        port = p;
        host = host.substring(0, colon);
      }
    }
    if (host.isEmpty) throw const LanException('msg.lanError');
    final info =
        await fetchInfo(baseUrl: 'https://$host:$port', identity: _identity!);
    if (info.fingerprint.isEmpty || info.fingerprint == _identity?.fingerprint) {
      throw const LanException('msg.lanSelf');
    }
    _addOnline(info, host);
    return _online[info.fingerprint]!;
  }

  // ———————————————————— 设置 ————————————————————

  /// 修改设备名：持久化 + 重启发现（以新名重新广播/注册）。
  Future<void> setAlias(String alias) async {
    final a = alias.trim();
    if (a.isEmpty || a.length > 64) {
      throw const LanException('msg.lanError');
    }
    settings.alias = a;
    await storage.saveSettings(settings);
    await _restartDiscovery();
    notifyListeners();
  }

  /// 是否对外可被发现：持久化 + 即时启停发现（Bonjour/组播）。
  Future<void> setDiscoverable(bool on) async {
    settings.discoverable = on;
    await storage.saveSettings(settings);
    await _restartDiscovery();
    notifyListeners();
  }

  /// 是否接收入站传输：持久化（作用于 _decideUpload/_decideText）。
  Future<void> setAcceptIncoming(bool on) async {
    settings.acceptIncoming = on;
    await storage.saveSettings(settings);
    notifyListeners();
  }

  /// 已配对设备是否自动接收文件：持久化（作用于 _decideUpload）。
  Future<void> setAutoAccept(bool on) async {
    settings.autoAccept = on;
    await storage.saveSettings(settings);
    notifyListeners();
  }

  /// 按当前别名/可发现状态重启发现：停旧的；若可发现且接收端在运行则重起。
  Future<void> _restartDiscovery() async {
    await _bonjour?.stop();
    _bonjour = null;
    await _discovery?.stop();
    _discovery = null;
    if (!settings.discoverable || _receiver == null) return;
    try {
      final b = LanBonjour(local: local, onPeer: _addOnline);
      await b.start();
      _bonjour = b;
    } catch (_) {}
    if (!Platform.isIOS) {
      try {
        final d = LanDiscovery(local: local, onPeer: _onDiscoverPeer);
        await d.start();
        _discovery = d;
      } catch (_) {}
    }
  }

  // ———————————————————— 发送 ————————————————————

  Future<void> sendFiles(String fingerprint, List<String> paths) async {
    final dev = _online[fingerprint];
    if (dev == null) throw const LanException('msg.lanError');
    for (final path in paths) {
      final file = File(path);
      final name = file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last;
      final size = await file.length();
      final task = _rid();
      final fly = InFlight(task, fingerprint, name, size, true)..done = 0;
      inflight[task] = fly;
      notifyListeners();
      try {
        await sendFile(
          baseUrl: dev.baseUrl,
          sender: local,
          file: file,
          identity: _identity!,
          expectedFingerprint: dev.fingerprint,
          onProgress: (done, total) {
            fly.done = done;
            notifyListeners();
          },
        );
        await _record(ChatMessage(
          id: task,
          peerFingerprint: fingerprint,
          outgoing: true,
          timestamp: _now(),
          fileName: name,
          size: size,
          state: 'completed',
        ));
      } catch (_) {
        await _record(ChatMessage(
          id: task,
          peerFingerprint: fingerprint,
          outgoing: true,
          timestamp: _now(),
          fileName: name,
          size: size,
          state: 'failed',
          savePath: path, // 存源路径，供失败后点击重发
        ));
      } finally {
        inflight.remove(task);
        notifyListeners();
      }
    }
  }

  Future<void> sendText(String fingerprint, String text) async {
    final dev = _online[fingerprint];
    if (dev == null) throw const LanException('msg.lanError');
    final id = _rid();
    try {
      await sendTextTo(
        baseUrl: dev.baseUrl,
        sender: local,
        id: id,
        text: text,
        identity: _identity!,
        expectedFingerprint: dev.fingerprint,
      );
      await _record(ChatMessage(
        id: id,
        peerFingerprint: fingerprint,
        outgoing: true,
        timestamp: _now(),
        text: text,
      ));
    } catch (_) {
      // 失败也落一条"失败"气泡，供点击重发（不再向上抛，由气泡上的重发按钮处理）。
      await _record(ChatMessage(
        id: id,
        peerFingerprint: fingerprint,
        outgoing: true,
        timestamp: _now(),
        text: text,
        state: 'failed',
      ));
    }
  }

  /// 重发失败的消息：移除旧失败条目，按原内容（文本/文件源路径）重发。
  Future<void> resend(ChatMessage m) async {
    if (!m.outgoing || m.state != 'failed') return;
    await storage.removeMessage(m.peerFingerprint, m.id);
    notifyListeners();
    if (m.fileName != null && m.savePath != null) {
      await sendFiles(m.peerFingerprint, [m.savePath!]);
    } else if (m.text != null && m.text!.isNotEmpty) {
      await sendText(m.peerFingerprint, m.text!);
    }
  }

  // ———————————————————— 接收审批 ————————————————————

  Future<String?> _decideUpload(
      DeviceInfo sender, Map<String, FileDto> files) async {
    if (!settings.acceptIncoming) return null;
    final fp = sender.fingerprint;
    if (fp.isNotEmpty &&
        storage.isTrusted(fp) &&
        (settings.autoAccept || storage.autoAcceptFor(fp))) {
      return settings.saveDir;
    }
    final ok = await _promptAccept(sender, files.values.toList(), null);
    return ok ? settings.saveDir : null;
  }

  Future<bool> _decideText(DeviceInfo sender, String text) async {
    if (!settings.acceptIncoming) return false;
    final fp = sender.fingerprint;
    // 文本风险低：已配对的对端直接接收，不弹确认（不受"自动接收文件"开关影响）。
    if (fp.isNotEmpty && storage.isTrusted(fp)) return true;
    return _promptAccept(sender, const [], text);
  }

  Future<bool> _promptAccept(
      DeviceInfo sender, List<FileDto> files, String? text) async {
    final requestId = _rid();
    final c = Completer<bool>();
    _pendingAccept[requestId] = c;
    incoming = IncomingRequest(requestId, sender, files, text);
    notifyListeners();
    final ok = await c.future
        .timeout(const Duration(seconds: 60), onTimeout: () => false);
    _pendingAccept.remove(requestId);
    if (incoming?.requestId == requestId) {
      incoming = null;
      notifyListeners();
    }
    // 接受未配对设备即记为可信（TOFU 配对）。
    if (ok && sender.fingerprint.isNotEmpty) {
      await storage.upsertTrusted(sender.fingerprint, sender.alias,
          deviceTypeToString(sender.deviceType));
      trusted = storage.listTrusted();
      _markTrusted(sender.fingerprint);
    }
    return ok;
  }

  /// 响应未配对接收请求。
  void respondIncoming(String requestId, bool accept) {
    _pendingAccept[requestId]?.complete(accept);
  }

  // ———————————————————— 接收端回调 ————————————————————

  void _onDiscoverPeer(DiscoveredPeer peer) =>
      _addOnline(peer.info, peer.address.address);

  void _notePeerLike(DiscoveredPeerLike peer) =>
      _addOnline(peer.info, peer.address.address);

  void _addOnline(DeviceInfo info, String address) {
    if (info.fingerprint.isEmpty) return;
    _lastSeen[info.fingerprint] = _now();
    _online[info.fingerprint] = DiscoveredDevice(
      fingerprint: info.fingerprint,
      alias: info.alias,
      address: address,
      port: info.port,
      deviceType: info.deviceType,
      trusted: storage.isTrusted(info.fingerprint),
    );
    notifyListeners();
  }

  /// 周期剔除超时未被任一发现源刷新的对端 → UI 自动显示离线（已配对设备会从
  /// 在线列表移除、回落到"已配对·离线"显示）。
  void _pruneStale() {
    final now = _now();
    final gone = _lastSeen.entries
        .where((e) => now - e.value > _onlineTtlSec)
        .map((e) => e.key)
        .toList();
    if (gone.isEmpty) return;
    for (final fp in gone) {
      _online.remove(fp);
      _lastSeen.remove(fp);
    }
    notifyListeners();
  }

  /// 对已在线设备做轻量 TCP 探活续期：端口仍可连 → 刷新 _lastSeen（视作仍在线），
  /// 探活失败不动，交给 _pruneStale 在 TTL 后剔除。只探已知设备，开销很小。
  Future<void> _keepAliveOnline() async {
    final snapshot = _online.values.toList();
    if (snapshot.isEmpty) return;
    await Future.wait(snapshot.map((d) async {
      final addr = InternetAddress.tryParse(d.address);
      if (addr == null) return;
      if (await probeTcp(addr, d.port, const Duration(milliseconds: 600))) {
        if (_online.containsKey(d.fingerprint)) _lastSeen[d.fingerprint] = _now();
      }
    }));
  }

  void _onStarted(String taskId, String fileName, int size, DeviceInfo peer) {
    inflight[taskId] =
        InFlight(taskId, peer.fingerprint, fileName, size, false)..done = 0;
    notifyListeners();
  }

  void _onProgress(String taskId, int done, int total) {
    final fly = inflight[taskId];
    if (fly != null) {
      fly.done = done;
      notifyListeners();
    }
  }

  Future<void> _onReceived(ReceivedItem item) async {
    inflight.remove(item.taskId);
    await _record(ChatMessage(
      id: item.taskId,
      peerFingerprint: item.peer.fingerprint,
      outgoing: false,
      timestamp: _now(),
      fileName: item.fileName,
      size: item.size,
      state: item.ok ? 'completed' : 'failed',
      savePath: item.savePath,
    ));
  }

  Future<void> _onTextReceived(DeviceInfo sender, String id, String text) =>
      _record(ChatMessage(
        id: id,
        peerFingerprint: sender.fingerprint,
        outgoing: false,
        timestamp: _now(),
        text: text,
      ));

  // ———————————————————— 内部工具 ————————————————————

  Future<void> _record(ChatMessage m) async {
    await storage.appendMessage(m);
    notifyListeners();
  }

  void _markTrusted(String fingerprint) => _online[fingerprint]?.trusted = true;

  String? _platformOf(LanDeviceType? t) => t == null ? null : deviceTypeToString(t);

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final Random _ridRng = Random.secure();
  // 生成标准 RFC-4122 UUID v4。桌面接收端对文本/会话 id 做 Uuid::parse_str 校验，
  // 非 UUID 会被判 400（表现为"文字发不出去"），故此处必须是合法 UUID。
  String _rid() {
    final b = List<int>.generate(16, (_) => _ridRng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
