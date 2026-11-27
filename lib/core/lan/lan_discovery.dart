import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_models.dart';
import 'multicast_lock.dart';

/// 发现到的对端（地址取自组播报文来源，端口取自其 DeviceInfo）。
class DiscoveredPeer {
  const DiscoveredPeer({required this.info, required this.address});
  final DeviceInfo info;
  final InternetAddress address;
}

/// UDP 组播设备发现（LocalSend 兼容，与桌面 airport-lan 的 discovery.rs 对齐）。
///
/// 启动时逐物理网卡广播本机 announce、在每块可用网卡加入组播组，并持续监听对端
/// announce：收到后回调；若对端 `announce=true` 再单播回应（覆盖“我先上线”）。
/// 另加 5 秒周期重播，覆盖丢包与晚上线的对端。明文 best-effort。
///
/// 逐网卡设 IP_MULTICAST_IF 发送：手机开着 VPN(sing-box TUN) 时默认组播出口常被
/// TUN 抢占，显式指定物理网卡才能把报文送上真正的局域网。
class LanDiscovery {
  LanDiscovery({required this.local, required this.onPeer});

  final DeviceInfo local;
  final void Function(DiscoveredPeer peer) onPeer;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<InternetAddress> _sendAddrs = const [];
  bool _running = false;

  static final InternetAddress _group = InternetAddress(kMulticastAddr);

  /// 平台相关的 IP_MULTICAST_IF 选项号（BSD/mac/iOS/Win=9，Linux/Android=32）。
  static int get _ipMulticastIf =>
      (Platform.isMacOS || Platform.isIOS || Platform.isWindows) ? 9 : 32;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    // 安卓需持组播锁才能收到组播；其他平台 no-op。
    await MulticastLock.acquire();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDefaultPort,
      reuseAddress: true,
    );
    socket.multicastLoopback = false;
    _socket = socket;

    final ifaces = await _usableInterfaces();
    _sendAddrs = [
      for (final i in ifaces)
        ...i.addresses.where(_isPrivateV4),
    ];
    var joined = 0;
    for (final iface in ifaces) {
      try {
        socket.joinMulticast(_group, iface);
        joined++;
      } catch (_) {/* 单块网卡加入失败不致命 */}
    }
    if (joined == 0) {
      try {
        socket.joinMulticast(_group);
      } catch (_) {}
    }

    socket.listen(_onEvent);
    _announceAll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _announceAll());
  }

  /// 主动重新广播（UI 刷新时调用）。
  void refresh() => _announceAll();

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
    await MulticastLock.release();
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    MulticastAnnounce msg;
    try {
      msg = MulticastAnnounce.fromJson(
        jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>,
      );
    } catch (_) {
      return;
    }
    if (msg.device.fingerprint.isEmpty ||
        msg.device.fingerprint == local.fingerprint) {
      return; // 忽略无指纹/自己的报文
    }
    onPeer(DiscoveredPeer(info: msg.device, address: dg.address));
    // 对端要求回应则单播回一份自身信息（announce=false，避免回环风暴）。
    if (msg.announce) {
      final reply = utf8.encode(jsonEncode(
        MulticastAnnounce(device: local, announce: false).toJson(),
      ));
      try {
        _socket?.send(reply, dg.address, dg.port);
      } catch (_) {}
    }
  }

  void _announceAll() {
    final socket = _socket;
    if (socket == null) return;
    final bytes = utf8.encode(jsonEncode(
      MulticastAnnounce(device: local, announce: true).toJson(),
    ));
    if (_sendAddrs.isEmpty) {
      try {
        socket.send(bytes, _group, kDefaultPort);
      } catch (_) {}
      return;
    }
    for (final addr in _sendAddrs) {
      try {
        // 指定该网卡为组播出口，再发送。
        socket.setRawOption(RawSocketOption(
          RawSocketOption.levelIPv4,
          _ipMulticastIf,
          addr.rawAddress,
        ));
      } catch (_) {/* 不支持则退回默认出口 */}
      try {
        socket.send(bytes, _group, kDefaultPort);
      } catch (_) {}
    }
  }

  static bool _isPrivateV4(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  /// 适合局域网直连的物理网卡（私网 IPv4、非回环），按名排除 TUN/VPN/蜂窝。
  static Future<List<NetworkInterface>> _usableInterfaces() async {
    final all = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    bool virtual(String name) {
      final n = name.toLowerCase();
      const prefixes = [
        'utun', 'tun', 'tap', 'ipsec', 'ppp', 'pdp', 'rmnet', 'wg',
        'zt', 'awdl', 'llw',
      ];
      return prefixes.any(n.startsWith);
    }

    return all
        .where((i) => !virtual(i.name) && i.addresses.any(_isPrivateV4))
        .toList();
  }
}
