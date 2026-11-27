import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../core/lan/lan_models.dart';
import '../core/lan/lan_qr.dart';
import '../core/lan/lan_service.dart';
import '../core/lan/lan_storage.dart';
import '../theme.dart';
import 'lan_scan_page.dart';

String _fmtSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = (i > 0 && v < 10) ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
  return '$s ${units[i]}';
}

IconData _deviceIcon(LanDeviceType? t) {
  switch (t) {
    case LanDeviceType.desktop:
      return LucideIcons.monitor;
    case LanDeviceType.laptop:
      return LucideIcons.laptop;
    case LanDeviceType.phone:
      return LucideIcons.smartphone;
    case LanDeviceType.tablet:
      return LucideIcons.tablet;
    case LanDeviceType.server:
      return LucideIcons.server;
    case LanDeviceType.tv:
      return LucideIcons.tv;
    case LanDeviceType.unknown:
    case null:
      return LucideIcons.circleHelp;
  }
}

/// 局域网传输：设备列表页（已配对 + 附近），点进去是会话。
class LanPage extends StatefulWidget {
  const LanPage({super.key});

  @override
  State<LanPage> createState() => _LanPageState();
}

class _LanPageState extends State<LanPage> {
  LanService? _svc;
  Object? _error;
  bool _started = false;
  bool _pairShown = false;
  bool _incomingShown = false;
  // Fingerprints with an in-flight pair request, so the tile can show "pairing…".
  final Set<String> _pairing = {};

  // 依赖就绪后再初始化：InheritedWidget（AppScope）不能在 initState 里访问，
  // didChangeDependencies 是首次安全访问点，用 _started 保证只跑一次。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _init();
  }

  Future<void> _init() async {
    try {
      final state = AppScope.of(context);
      final svc = await state.ensureLan();
      if (!mounted) return;
      svc.addListener(_onChange);
      setState(() => _svc = svc);
      // 进页跑一次 TCP 单播扫描兜底（组播被挡 / iOS 无组播权限时也能发现对端）。
      unawaited(svc.scanSubnet());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _svc?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final svc = _svc;
    if (svc == null || !mounted) return;
    if (svc.pairRequest != null && !_pairShown) {
      _pairShown = true;
      _showPairDialog(svc);
    }
    if (svc.incoming != null && !_incomingShown) {
      _incomingShown = true;
      _showIncomingDialog(svc);
    }
    setState(() {});
  }

  Future<void> _showPairDialog(LanService svc) async {
    final req = svc.pairRequest;
    if (req == null) {
      _pairShown = false;
      return;
    }
    final t = AppScope.of(context).t;
    Timer? autoClose;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // 配对确认 30s 过期：到点自动关闭并视为拒绝（与 LanService 超时一致）。
        autoClose = Timer(const Duration(seconds: 30), () {
          if (Navigator.of(ctx).canPop()) Navigator.pop(ctx, false);
        });
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(t('lan.pairRequest')),
          content: Text('${t('lan.from')} ${req.peer.alias}\n${t('lan.pairDesc')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('lan.reject'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('lan.accept'))),
          ],
        );
      },
    );
    autoClose?.cancel();
    svc.respondPair(req.requestId, ok ?? false);
    _pairShown = false;
  }

  Future<void> _showIncomingDialog(LanService svc) async {
    final req = svc.incoming;
    if (req == null) {
      _incomingShown = false;
      return;
    }
    final t = AppScope.of(context).t;
    final body = req.text != null
        ? req.text!
        : req.files.map((f) => '${f.fileName} · ${_fmtSize(f.size)}').join('\n');
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(req.text != null
            ? t('lan.incomingText')
            : t('lan.incomingTitle')),
        content: Text('${t('lan.from')} ${req.peer.alias}\n\n$body'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('lan.reject'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('lan.accept'))),
        ],
      ),
    );
    svc.respondIncoming(req.requestId, ok ?? false);
    _incomingShown = false;
  }

  Future<void> _pair(LanService svc, String fingerprint) async {
    final t = AppScope.of(context).t;
    if (_pairing.contains(fingerprint)) return;
    setState(() => _pairing.add(fingerprint));
    try {
      await svc.pair(fingerprint);
      _toast(t('lan.pairedOk'));
    } catch (e) {
      _toast(t(e.toString()));
    } finally {
      if (mounted) setState(() => _pairing.remove(fingerprint));
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// 扫对端二维码 → 单播直连配对 → 进入会话。
  Future<void> _scanConnect(LanService svc) async {
    final t = AppScope.of(context).t;
    final payload = await Navigator.of(context).push<LanQrPayload>(
      MaterialPageRoute(builder: (_) => const LanScanPage()),
    );
    if (payload == null || !mounted) return;
    try {
      final fp = await svc.connectByQr(payload);
      if (!mounted) return;
      _toast(t('lan.pairedOk'));
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LanChatPage(service: svc, fingerprint: fp),
      ));
    } catch (e) {
      _toast(t(e.toString()));
    }
  }

  /// 出示本机二维码，供对端扫描直连。
  Future<void> _showMyQr(LanService svc) async {
    final t = AppScope.of(context).t;
    final payload = await svc.myQrPayload();
    if (!mounted) return;
    if (payload == null) {
      _toast(t('lan.qrNoIp'));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(t('lan.myQr')),
        // 固定宽度：AlertDialog 会对内容求 intrinsic 宽度，而 QrImageView
        // (CustomPaint) 不支持 intrinsic 尺寸，直接放会触发 RenderBox 未布局断言。
        content: SizedBox(
          width: 260,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload.toUri(),
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(payload.alias,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 2),
            Text('${payload.ip}:${payload.port}',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 10),
            Text(t('lan.myQrHint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('common.done')),
          ),
        ],
      ),
    );
  }

  /// 设置面板：设备名 + 可被发现/接收/自动接收开关 + 手动连接 + 已配对管理。
  void _openSettings(LanService svc) {
    final nameCtl = TextEditingController(text: svc.settings.alias);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final t = AppScope.of(ctx).t;
        return AnimatedBuilder(
          animation: svc,
          builder: (ctx, _) => SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('lan.settings'),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  const SizedBox(height: 14),
                  Text(t('lan.deviceName'),
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtl,
                    maxLength: 64,
                    decoration: InputDecoration(
                      counterText: '',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(LucideIcons.check, size: 18),
                        onPressed: () async {
                          try {
                            await svc.setAlias(nameCtl.text);
                            _toast(t('lan.saved'));
                          } catch (e) {
                            _toast(t(e.toString()));
                          }
                        },
                      ),
                    ),
                    onSubmitted: (v) => unawaited(svc.setAlias(v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('lan.discoverable')),
                    value: svc.settings.discoverable,
                    onChanged: (v) => unawaited(svc.setDiscoverable(v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('lan.acceptIncoming')),
                    value: svc.settings.acceptIncoming,
                    onChanged: (v) => unawaited(svc.setAcceptIncoming(v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('lan.autoAccept')),
                    value: svc.settings.autoAccept,
                    onChanged: svc.settings.acceptIncoming
                        ? (v) => unawaited(svc.setAutoAccept(v))
                        : null,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(LucideIcons.link2, color: AppColors.brandText),
                    title: Text(t('lan.manualConnect')),
                    subtitle: Text(t('lan.manualHint'),
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openManualConnect(svc);
                    },
                  ),
                  const Divider(),
                  Text('${t('lan.paired')} · ${svc.trusted.length}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  if (svc.trusted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(t('lan.noPaired'),
                          style:
                              TextStyle(fontSize: 13, color: AppColors.muted)),
                    ),
                  for (final d in svc.trusted)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.alias,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: TextButton.icon(
                        icon: const Icon(LucideIcons.unlink, size: 15),
                        label: Text(t('lan.unpair')),
                        style:
                            TextButton.styleFrom(foregroundColor: AppColors.bad),
                        onPressed: () => unawaited(svc.unpair(d.fingerprint)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 手动连接：输入 IP 或 IP:端口直连。
  void _openManualConnect(LanService svc) {
    final ctl = TextEditingController();
    final t = AppScope.of(context).t;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(t('lan.manualConnect')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: t('lan.manualPlaceholder'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submitManual(ctx, svc, ctl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('common.cancel'))),
          FilledButton(
            onPressed: () => _submitManual(ctx, svc, ctl.text),
            child: Text(t('lan.connect')),
          ),
        ],
      ),
    );
  }

  Future<void> _submitManual(
      BuildContext dialogCtx, LanService svc, String raw) async {
    final t = AppScope.of(context).t;
    final addr = raw.trim();
    Navigator.pop(dialogCtx);
    if (addr.isEmpty) return;
    try {
      await svc.addManualDevice(addr);
      _toast(t('lan.added'));
    } catch (e) {
      _toast(t(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final svc = _svc;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(t('lan.title')),
        actions: [
          IconButton(
            tooltip: t('lan.myQr'),
            icon: const Icon(LucideIcons.qrCode, size: 20),
            onPressed: svc == null ? null : () => _showMyQr(svc),
          ),
          IconButton(
            tooltip: t('lan.scan'),
            icon: const Icon(LucideIcons.scanLine, size: 20),
            onPressed: svc == null ? null : () => _scanConnect(svc),
          ),
          IconButton(
            tooltip: t('lan.settingsTitle'),
            icon: const Icon(LucideIcons.settings, size: 20),
            onPressed: svc == null ? null : () => _openSettings(svc),
          ),
          IconButton(
            tooltip: t('common.refresh'),
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: svc == null
                ? null
                : () {
                    svc.refresh();
                    unawaited(svc.scanSubnet());
                  },
          ),
        ],
      ),
      body: _error != null
          ? _centerHint(LucideIcons.triangleAlert, t('lan.startFailed'),
              AppScope.of(context).t(_error.toString()))
          : svc == null
              ? const Center(child: CircularProgressIndicator())
              : AnimatedBuilder(
                  animation: svc,
                  builder: (context, _) => _deviceList(svc, t),
                ),
    );
  }

  Widget _deviceList(LanService svc, String Function(String, [Map<String, String>?]) t) {
    final paired = svc.trusted;
    final nearby = svc.devices
        .where((d) => !svc.trusted.any((tr) => tr.fingerprint == d.fingerprint))
        .toList();
    if (paired.isEmpty && nearby.isEmpty) {
      return _centerHint(
          LucideIcons.radio, t('lan.noDevices'), t('lan.deviceHint'));
    }
    final online = {for (final d in svc.devices) d.fingerprint: d};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (paired.isNotEmpty) ...[
          _sectionLabel('${t('lan.paired')} · ${paired.length}'),
          for (final tr in paired)
            _pairedTile(svc, tr, online[tr.fingerprint], t),
        ],
        if (nearby.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionLabel('${t('lan.nearby')} · ${nearby.length}'),
          for (final d in nearby) _nearbyTile(svc, d, t),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
      );

  Widget _pairedTile(
      LanService svc, TrustedDevice tr, DiscoveredDevice? dev,
      String Function(String, [Map<String, String>?]) t) {
    final isOnline = dev != null;
    return Card(
      color: AppColors.card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line)),
      child: ListTile(
        leading: Icon(_deviceIcon(dev?.deviceType), color: AppColors.brandText),
        title: Text(tr.alias,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? AppColors.good : AppColors.muted)),
          Text(t(isOnline ? 'lan.online' : 'lan.offline'),
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          if (isOnline) ...[
            Text('  ·  ${dev.address}',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ]),
        trailing: const Icon(LucideIcons.chevronRight, size: 18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LanChatPage(service: svc, fingerprint: tr.fingerprint))),
      ),
    );
  }

  Widget _nearbyTile(LanService svc, DiscoveredDevice d,
      String Function(String, [Map<String, String>?]) t) {
    return Card(
      color: AppColors.card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.line)),
      child: ListTile(
        leading: Icon(_deviceIcon(d.deviceType), color: AppColors.muted),
        title: Text(d.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(d.address,
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
        trailing: _pairing.contains(d.fingerprint)
            ? FilledButton.tonalIcon(
                icon: const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                label: Text(t('lan.pairing')),
                onPressed: null,
              )
            : FilledButton.tonalIcon(
                icon: const Icon(LucideIcons.link2, size: 14),
                label: Text(t('lan.pair')),
                onPressed: svc.ready ? () => _pair(svc, d.fingerprint) : null,
              ),
      ),
    );
  }

  Widget _centerHint(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      );
}

/// 与某设备的会话（时间线 + 输入框 + 发文件）。
class LanChatPage extends StatefulWidget {
  const LanChatPage({super.key, required this.service, required this.fingerprint});

  final LanService service;
  final String fingerprint;

  @override
  State<LanChatPage> createState() => _LanChatPageState();
}

class _LanChatPageState extends State<LanChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  LanService get svc => widget.service;
  String get fp => widget.fingerprint;

  @override
  void initState() {
    super.initState();
    svc.addListener(_onChange);
  }

  @override
  void dispose() {
    svc.removeListener(_onChange);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _alias() {
    final dev = svc.devices.where((d) => d.fingerprint == fp);
    if (dev.isNotEmpty) return dev.first.alias;
    final tr = svc.trusted.where((t) => t.fingerprint == fp);
    return tr.isNotEmpty ? tr.first.alias : fp;
  }

  bool get _online => svc.devices.any((d) => d.fingerprint == fp);

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_online) return;
    setState(() => _sending = true);
    final t = AppScope.of(context).t;
    try {
      await svc.sendText(fp, text);
      _input.clear();
      _scrollToEnd();
    } catch (e) {
      _toast(t(e.toString()));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFiles() async {
    if (!_online) return;
    final t = AppScope.of(context).t;
    try {
      final picked = await FilePicker.pickFiles();
      final paths = picked.map((f) => f.path).whereType<String>().toList();
      if (paths.isEmpty) return;
      await svc.sendFiles(fp, paths);
      _scrollToEnd();
    } catch (e) {
      _toast(t(e.toString()));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final messages = svc.conversation(fp);
    final live = svc.inflight.values.where((f) => f.fingerprint == fp).toList();
    return Scaffold(
      backgroundColor: AppColors.selected,
      appBar: AppBar(title: Text(_alias())),
      body: Column(children: [
        Expanded(
          child: (messages.isEmpty && live.isEmpty)
              ? Center(
                  child: Text(t('lan.emptyChat'),
                      style: TextStyle(color: AppColors.muted, fontSize: 13)))
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  children: [
                    for (final m in messages) _bubble(m, t),
                    for (final f in live) _liveBubble(f, t),
                  ],
                ),
        ),
        _composer(t),
      ]),
    );
  }

  Widget _composer(String Function(String, [Map<String, String>?]) t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.line))),
        child: Row(children: [
          IconButton(
            icon: const Icon(LucideIcons.paperclip, size: 22),
            onPressed: _online ? _sendFiles : null,
            tooltip: t('lan.sendFile'),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: _online,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
              decoration: InputDecoration(
                hintText: t('lan.messageHint'),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
          ),
          // 发送按钮：圆形填充 + 上箭头，与桌面端一致（IM 风格）。
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Material(
              color: (_online && !_sending) ? AppColors.brand : AppColors.muted,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: (_online && !_sending) ? _sendText : null,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(LucideIcons.arrowUp, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(ChatMessage m, String Function(String, [Map<String, String>?]) t) {
    final me = m.outgoing;
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: m.isFile
            ? AppColors.card
            : (me ? AppColors.brand : AppColors.card),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: m.isFile
          ? _fileBody(m, t)
          : Text(m.text ?? '',
              style: TextStyle(
                  fontSize: 14, color: me ? Colors.white : AppColors.ink)),
    );
    // 失败的发出消息：气泡左侧红色感叹号，点击重发（IM 风格）。重发若再失败会
    // 自动落一条新的失败气泡，无需额外提示。
    if (me && m.state == 'failed') {
      return Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: t('lan.resend'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              icon: Icon(LucideIcons.circleAlert, color: AppColors.bad, size: 20),
              onPressed: () => unawaited(svc.resend(m)),
            ),
            const SizedBox(width: 2),
            bubble,
          ],
        ),
      );
    }
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }

  Widget _fileBody(ChatMessage m, String Function(String, [Map<String, String>?]) t) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(LucideIcons.file, size: 22, color: AppColors.brandText),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.fileName ?? 'file',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(
                  '${_fmtSize(m.size)} · ${t(m.state == 'completed' ? 'lan.completed' : 'lan.failed')}',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
      ),
    ]);
  }

  Widget _liveBubble(InFlight f, String Function(String, [Map<String, String>?]) t) {
    final pct = f.size > 0 ? (f.done / f.size).clamp(0.0, 1.0) : 0.0;
    return Align(
      alignment: f.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(f.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: pct, minHeight: 4, backgroundColor: AppColors.line),
              ),
              const SizedBox(height: 4),
              Text('${_fmtSize(f.done)} / ${_fmtSize(f.size)} · ${t('lan.sending')}',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
      ),
    );
  }
}
