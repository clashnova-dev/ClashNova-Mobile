import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import '../app_state.dart';
import '../connection.dart';
import '../theme.dart';
import '../widgets.dart';
import 'connections_page.dart';
import 'lan_page.dart';
import 'logs_page.dart';
import 'nodes_page.dart';
import 'settings_page.dart';
import 'subscriptions_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Color _toneFor(Phase phase) {
    switch (phase) {
      case Phase.connected:
        return AppColors.good;
      case Phase.connecting:
      case Phase.preparing:
      case Phase.reconnecting:
      case Phase.disconnecting:
        return AppColors.fair;
      case Phase.failed:
        return AppColors.bad;
      case Phase.idle:
        return AppColors.idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    final tone = _toneFor(state.phase);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ClashNova'),
        actions: [
          if (state.loggedIn)
            IconButton(
              tooltip: t('common.refresh'),
              icon: const Icon(LucideIcons.refreshCw),
              onPressed: () => state.refresh(),
            ),
          IconButton(
            tooltip: t('settings.title'),
            icon: const Icon(LucideIcons.settings),
            onPressed: () => _push(context, const SettingsPage()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.refreshActive(),
        child: ListView(
          padding: const EdgeInsets.all(AppMetrics.pad),
          children: [
            _ConnectCard(state: state, tone: tone),
            const SizedBox(height: AppMetrics.gap),
            _ModeSelector(state: state),
            const SizedBox(height: AppMetrics.gap),
            _CurrentNodeCard(state: state),
            const SizedBox(height: AppMetrics.gap),
            MenuTile(
              icon: LucideIcons.rss,
              title: t('home.subscription'),
              subtitle: t('home.subsSubtitle',
                  {'n': '${state.subscriptions.length + state.externalSubs.length}'}),
              onTap: () => _push(context, const SubscriptionsPage()),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<List<SingBoxConnection>>(
              valueListenable: state.connections,
              builder: (context, conns, _) => MenuTile(
                icon: LucideIcons.network,
                title: t('home.connections'),
                subtitle: t('home.connSubtitle',
                    {'n': '${conns.where((c) => c.closedAt == null).length}'}),
                onTap: () => _push(context, const ConnectionsPage()),
              ),
            ),
            const SizedBox(height: 10),
            MenuTile(
              icon: LucideIcons.scrollText,
              title: t('home.logs'),
              subtitle: t('home.logsSubtitle'),
              onTap: () => _push(context, const LogsPage()),
            ),
            const SizedBox(height: 10),
            MenuTile(
              icon: LucideIcons.share2,
              title: t('home.lan'),
              subtitle: t('home.lanSubtitle'),
              onTap: () => _push(context, const LanPage()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.state, required this.tone});

  final AppState state;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final phase = state.phase;
    final label = _statusText(phase);
    final isBusy = state.connecting || state.busy;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          _PowerButton(
            tone: tone,
            busy: isBusy,
            onTap: state.busy ? null : () => state.toggleConnect(),
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: tone)),
          const SizedBox(height: 4),
          _SubLine(state: state),
          if (state.connected) ...[
            const SizedBox(height: 16),
            _SpeedRow(state: state),
          ],
        ],
      ),
    );
  }

  String _statusText(Phase phase) {
    switch (phase) {
      case Phase.connected:
        return state.t('status.connected');
      case Phase.connecting:
      case Phase.preparing:
      case Phase.reconnecting:
        return state.t('status.connecting');
      case Phase.disconnecting:
        return state.t('status.disconnecting');
      case Phase.failed:
        return state.t('status.failed');
      case Phase.idle:
        return state.t('status.idle');
    }
  }
}

/// Current node name + live uptime when connected, otherwise the status message.
class _SubLine extends StatelessWidget {
  const _SubLine({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.connected) {
      return Text(state.message,
          style: TextStyle(color: AppColors.muted, fontSize: 13),
          textAlign: TextAlign.center);
    }
    final label = state.chainActive ? state.chainSummary : state.currentNodeLabel;
    return ValueListenableBuilder<Duration>(
      valueListenable: state.uptime,
      builder: (context, d, _) => Text(
        '$label · ${_fmt(d)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.muted, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

/// Routing-mode segmented control: 规则 / 全局.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final current = state.currentMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(state.t('home.routeMode'),
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.pillBg,
            borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
          ),
          child: Row(
            children: [
              for (final mode in AppState.modeOrder)
                Expanded(
                  child: _Segment(
                    label: state.modeLabel(mode),
                    selected: current == mode,
                    onTap: () => state.setMode(mode),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? AppColors.line : Colors.transparent),
          boxShadow: selected ? AppColors.shadowCard : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.brandText : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// The current node row, tapping opens the node list.
class _CurrentNodeCard extends StatelessWidget {
  const _CurrentNodeCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final chain = state.chainActive;
    final node = state.currentNode;
    final empty = state.activeNodes.isEmpty;
    final ms = (chain || node == null) ? null : state.latencies[node.id];

    final title = chain
        ? state.t('chain.title')
        : (node?.name.isNotEmpty == true ? node!.name : state.t('home.autoSelect'));
    final subtitle = chain
        ? state.chainSummary
        : (empty
            ? state.t('home.noNodeHint')
            : (node == null
                ? state.t('home.autoDesc')
                : state.t('home.currentNode', {'detail': node.detail})));

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NodesPage()),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppMetrics.radius),
            boxShadow: AppColors.shadowCard,
          ),
          child: Row(
            children: [
              CodeChip(
                code: chain ? null : node?.chipCode,
                icon: chain ? LucideIcons.link : (node == null ? LucideIcons.zap : null),
                tone: AppColors.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (ms != null && ms >= 0) ...[
                const SizedBox(width: 8),
                Pill('$ms ms',
                    color: ms <= 100 ? AppColors.good : (ms <= 300 ? AppColors.fair : AppColors.bad)),
              ],
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SingBoxConnectionStats?>(
      valueListenable: state.stats,
      builder: (context, s, _) {
        final up = s?.uploadSpeed ?? 0;
        final down = s?.downloadSpeed ?? 0;
        return Row(
          children: [
            Expanded(child: _SpeedTile(icon: LucideIcons.arrowUp, label: state.t('home.up'), value: formatRate(up))),
            const SizedBox(width: 12),
            Expanded(child: _SpeedTile(icon: LucideIcons.arrowDown, label: state.t('home.down'), value: formatRate(down))),
          ],
        );
      },
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.tone, required this.busy, this.onTap});
  final Color tone;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tone.withValues(alpha: 0.10),
          border: Border.all(color: tone.withValues(alpha: 0.35), width: 3),
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: tone))
              : Icon(LucideIcons.power, size: 54, color: tone),
        ),
      ),
    );
  }
}
