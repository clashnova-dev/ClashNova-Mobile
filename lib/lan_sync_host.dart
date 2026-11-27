import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'core/lan/lan_service.dart';

/// 全局监听「拉取同步」请求：被拉取方在任意页面都能弹出确认；接受则回传本机配置
/// payload。不强制启动 LAN（避免 iOS 本地网络权限弹窗）——LAN 运行时（已打开过
/// 局域网/同步）即生效。30s 未决自动拒绝（与后端 _decideSync 一致）。
class LanSyncHost extends StatefulWidget {
  const LanSyncHost({super.key, required this.child});
  final Widget child;

  @override
  State<LanSyncHost> createState() => _LanSyncHostState();
}

class _LanSyncHostState extends State<LanSyncHost> {
  AppState? _state;
  LanService? _svc;
  bool _dialogShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!identical(_state, state)) {
      _state?.removeListener(_onState);
      _state = state;
      state.addListener(_onState);
    }
    _onState();
  }

  void _onState() {
    final svc = _state?.lan;
    if (svc != null && !identical(svc, _svc)) {
      _svc?.removeListener(_onSvc);
      _svc = svc;
      svc.addListener(_onSvc);
    }
  }

  void _onSvc() {
    final svc = _svc;
    if (svc == null || !mounted) return;
    if (svc.syncRequest != null && !_dialogShown) {
      _dialogShown = true;
      _showConfirm(svc);
    }
  }

  Future<void> _showConfirm(LanService svc) async {
    final req = svc.syncRequest;
    if (req == null) {
      _dialogShown = false;
      return;
    }
    final state = AppScope.of(context);
    final t = state.t;
    Timer? autoClose;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        autoClose = Timer(const Duration(seconds: 30), () {
          if (Navigator.of(ctx).canPop()) Navigator.pop(ctx, false);
        });
        return AlertDialog(
          title: Text(t('lan.syncReqTitle')),
          content: Text(
              '${t('lan.syncReqBody', {'alias': req.peer.alias})}\n\n${t('lan.syncReqHint')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('common.cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('common.allow'))),
          ],
        );
      },
    );
    autoClose?.cancel();
    final payload = ok == true ? state.buildSyncPayload() : '';
    svc.respondSync(req.requestId, ok ?? false, payload);
    _dialogShown = false;
  }

  @override
  void dispose() {
    _state?.removeListener(_onState);
    _svc?.removeListener(_onSvc);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
