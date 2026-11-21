import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chain_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NodesPage extends StatefulWidget {
  const NodesPage({super.key});

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  final _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    final all = state.sortedActiveNodes;
    final kw = _keyword.trim().toLowerCase();
    final nodes = kw.isEmpty
        ? all
        : all
            .where((n) => [n.name, n.detail, n.type ?? '', n.region ?? '']
                .join(' ')
                .toLowerCase()
                .contains(kw))
            .toList();
    final online = state.activeNodes.where((n) => n.online == true).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('nodes.title')),
        actions: [
          IconButton(
            tooltip: t('common.refresh'),
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => state.refreshActive(),
          ),
        ],
      ),
      body: Column(
        children: [
          _Tools(
            search: _search,
            onSearch: (v) => setState(() => _keyword = v),
            state: state,
          ),
          _MetaBar(total: state.activeNodes.length, online: online, state: state),
          if (state.activeNodes.isNotEmpty) _ChainEntry(state: state),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => state.refreshActive(),
              child: state.activeNodes.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                        EmptyState(
                          title: t('nodes.empty'),
                          hint: state.loggedIn
                              ? t('nodes.emptyHintLoggedIn')
                              : t('nodes.emptyHintLocal'),
                        ),
                      ],
                    )
                  : nodes.isEmpty
                      ? EmptyState(title: t('nodes.noMatch'), hint: t('nodes.noMatchHint'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              AppMetrics.pad, 4, AppMetrics.pad, AppMetrics.pad),
                          itemCount: nodes.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return _AutoTile(
                                label: t('home.autoSelect'),
                                desc: t('nodes.autoDesc'),
                                selected: state.selectedNodeId.isEmpty,
                                onTap: () => state.selectNode(''),
                              );
                            }
                            final n = nodes[i - 1];
                            return _NodeTile(
                              node: n,
                              unnamed: t('nodes.unnamed'),
                              timeoutText: t('nodes.timeout'),
                              offlineText: t('nodes.offline'),
                              selected: n.id == state.selectedNodeId,
                              latency: state.latencies[n.id],
                              onTap: () => state.selectNode(n.id),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools({required this.search, required this.onSearch, required this.state});
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final testLabel =
        state.testing ? t('nodes.stopProgress', {'done': '${state.probeDone}', 'total': '${state.probeTotal}'}) : t('nodes.testAll');
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 12, AppMetrics.pad, 8),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: TextField(
              controller: search,
              onChanged: onSearch,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.muted),
                hintText: t('nodes.search'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppSelect<NodeSort>(
                  value: state.nodeSort,
                  icon: LucideIcons.arrowDownWideNarrow,
                  onChanged: state.setNodeSort,
                  options: [
                    AppSelectOption(NodeSort.def, t('nodes.sortDefault')),
                    AppSelectOption(NodeSort.latency, t('nodes.sortLatency')),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: () => state.testLatencies(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: state.testing ? AppColors.fair : AppColors.brand,
                    ),
                    icon: Icon(state.testing ? LucideIcons.square : LucideIcons.wifi, size: 18),
                    label: Text(testLabel, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Entry point to the proxy-chain builder; shows the live chain summary when a
/// chain is active, otherwise a prompt to build one.
class _ChainEntry extends StatelessWidget {
  const _ChainEntry({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final active = state.chainActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 0, AppMetrics.pad, 8),
      child: Material(
        color: active ? AppColors.selected : AppColors.card,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppMetrics.radius),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChainPage()),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: active ? AppColors.selectedBorder : AppColors.line),
              borderRadius: BorderRadius.circular(AppMetrics.radius),
              boxShadow: active ? null : AppColors.shadowCard,
            ),
            child: Row(
              children: [
                CodeChip(icon: LucideIcons.link, tone: AppColors.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('chain.title'),
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(active ? state.chainSummary : t('chain.entryHint'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (active) ...[
                  Pill(t('chain.active'), color: AppColors.good),
                  const SizedBox(width: 6),
                ],
                Icon(LucideIcons.chevronRight, color: AppColors.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaBar extends StatelessWidget {
  const _MetaBar({required this.total, required this.online, required this.state});
  final int total;
  final int online;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final showOnline = state.activeNodes.any((n) => n.online != null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 0, AppMetrics.pad, 6),
      child: Row(
        children: [
          Text(
            showOnline
                ? state.t('nodes.metaOnline', {'total': '$total', 'online': '$online'})
                : state.t('nodes.metaCount', {'total': '$total'}),
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const Spacer(),
          if (state.testing)
            SizedBox(
              width: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.probeTotal == 0 ? null : state.probeDone / state.probeTotal,
                  minHeight: 5,
                  backgroundColor: AppColors.line,
                  color: AppColors.brand,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AutoTile extends StatelessWidget {
  const _AutoTile({
    required this.label,
    required this.desc,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SelectableRow(
      selected: selected,
      onTap: onTap,
      leading: CodeChip(icon: LucideIcons.zap, tone: AppColors.brand),
      title: label,
      subtitle: desc,
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.unnamed,
    required this.timeoutText,
    required this.offlineText,
    required this.selected,
    required this.latency,
    required this.onTap,
  });
  final NodeView node;
  final String unnamed;
  final String timeoutText;
  final String offlineText;
  final bool selected;
  final int? latency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offline = node.online == false;
    return _SelectableRow(
      selected: selected,
      onTap: offline ? null : onTap,
      leading: CodeChip(code: node.chipCode, tone: AppColors.brand),
      title: node.name.isEmpty ? unnamed : node.name,
      subtitle: node.detail,
      trailing: _LatencyPill(
        ms: latency,
        offline: offline,
        timeoutText: timeoutText,
        offlineText: offlineText,
      ),
    );
  }
}

/// Latency chip: green/amber/red by the desktop thresholds (<=100 / <=300),
/// a timeout label for a failed test, nothing before a node has been tested.
class _LatencyPill extends StatelessWidget {
  const _LatencyPill({
    required this.ms,
    required this.offline,
    required this.timeoutText,
    required this.offlineText,
  });
  final int? ms;
  final bool offline;
  final String timeoutText;
  final String offlineText;

  @override
  Widget build(BuildContext context) {
    if (offline) return Pill(offlineText, color: AppColors.idle);
    final v = ms;
    if (v == null) return const SizedBox.shrink();
    if (v < 0) return Pill(timeoutText, color: AppColors.bad);
    final tone = v <= 100 ? AppColors.good : (v <= 300 ? AppColors.fair : AppColors.bad);
    return Pill('$v ms', color: tone);
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.leading,
    this.trailing,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final String subtitle;
  final Widget leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.selected : AppColors.card,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? AppColors.selectedBorder : AppColors.line),
              borderRadius: BorderRadius.circular(AppMetrics.radius),
              boxShadow: selected ? null : AppColors.shadowCard,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(LucideIcons.circleCheck, color: AppColors.brand, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
