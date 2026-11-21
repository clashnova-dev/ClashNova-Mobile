import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    return Scaffold(
      appBar: AppBar(title: Text(t('conn.title'))),
      body: ValueListenableBuilder<List<SingBoxConnection>>(
        valueListenable: state.connections,
        builder: (context, conns, _) {
          if (conns.isEmpty) {
            return EmptyState(
              title: t('conn.empty'),
              hint: t('conn.emptyHint'),
            );
          }
          final live = conns.where((c) => c.closedAt == null).toList();
          final list = live.isEmpty ? conns : live;
          return ListView.separated(
            padding: const EdgeInsets.all(AppMetrics.pad),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _ConnTile(
              conn: list[i],
              total: t('conn.total', {'bytes': formatBytes(list[i].uploadTotal + list[i].downloadTotal)}),
              closeTip: t('conn.close'),
              onClose: () => state.closeConnection(list[i].id),
            ),
          );
        },
      ),
    );
  }
}

class _ConnTile extends StatelessWidget {
  const _ConnTile({
    required this.conn,
    required this.total,
    required this.closeTip,
    required this.onClose,
  });
  final SingBoxConnection conn;
  final String total;
  final String closeTip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final target = conn.domain.isNotEmpty ? conn.domain : conn.destination;
    final meta = [
      if (conn.network.isNotEmpty) conn.network.toUpperCase(),
      if (conn.outbound.isNotEmpty) conn.outbound,
      if (conn.rule.isNotEmpty) conn.rule,
    ].join(' · ');

    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(target.isEmpty ? '—' : target,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
                Text(
                  '↑ ${formatRate(conn.uploadSpeed)}   ↓ ${formatRate(conn.downloadSpeed)}   $total',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: closeTip,
            icon: Icon(LucideIcons.x, size: 18, color: AppColors.bad),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
