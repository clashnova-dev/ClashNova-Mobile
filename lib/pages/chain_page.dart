import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Builds an ordered proxy chain (链式代理): the user arranges nodes from entry
/// to exit, and on apply each hop is wired through the previous one via
/// sing-box `detour`. A chain needs at least two nodes to take effect.
class ChainPage extends StatefulWidget {
  const ChainPage({super.key});

  @override
  State<ChainPage> createState() => _ChainPageState();
}

class _ChainPageState extends State<ChainPage> {
  List<String>? _ids;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    final ids = _ids ??= [...state.chain];
    final byId = {for (final n in state.activeNodes) n.id: n};

    String roleLabel(int i) {
      if (ids.length < 2) return t('chain.node');
      if (i == 0) return t('chain.entry');
      if (i == ids.length - 1) return t('chain.exit');
      return t('chain.relay');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('chain.title')),
        actions: [
          if (ids.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _ids = []),
              child: Text(t('chain.clear'), style: TextStyle(color: AppColors.bad)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 12, AppMetrics.pad, 4),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(LucideIcons.link, size: 18, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ids.length >= 2
                          ? '${t('chain.device')} → ${ids.map((id) => byId[id]?.name ?? id).join(' → ')} → ${t('chain.target')}'
                          : t('chain.hint'),
                      style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ids.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                      EmptyState(title: t('chain.empty'), hint: t('chain.emptyHint')),
                    ],
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 8, AppMetrics.pad, 8),
                    itemCount: ids.length,
                    onReorder: (from, to) => setState(() {
                      if (to > from) to -= 1;
                      final id = ids.removeAt(from);
                      ids.insert(to, id);
                    }),
                    itemBuilder: (context, i) {
                      final node = byId[ids[i]];
                      return Padding(
                        key: ValueKey(ids[i]),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ChainRow(
                          index: i,
                          role: roleLabel(i),
                          name: node?.name ?? ids[i],
                          detail: node?.detail ?? '',
                          onRemove: () => setState(() => ids.removeAt(i)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 4, AppMetrics.pad, 12),
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _addNode(context, state, ids),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      foregroundColor: AppColors.brand,
                      side: BorderSide(color: AppColors.border),
                    ),
                    icon: const Icon(LucideIcons.plus, size: 20),
                    label: Text(t('chain.add')),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      await state.setChain(ids);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: AppColors.brand,
                    ),
                    child: Text(ids.length >= 2 ? t('chain.apply') : t('chain.applyOff')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addNode(BuildContext context, AppState state, List<String> ids) async {
    final chosen = ids.toSet();
    final available = state.activeNodes.where((n) => !chosen.contains(n.id)).toList();
    final t = state.t;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('chain.allAdded'))));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration:
                      BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text(t('chain.pick'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: available.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final n = available[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                      onTap: () => Navigator.of(ctx).pop(n.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Row(
                          children: [
                            CodeChip(code: n.chipCode, tone: AppColors.brand),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.name.isEmpty ? t('nodes.unnamed') : n.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600, color: AppColors.ink)),
                                  if (n.detail.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(n.detail,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => ids.add(picked));
  }
}

class _ChainRow extends StatelessWidget {
  const _ChainRow({
    required this.index,
    required this.role,
    required this.name,
    required this.detail,
    required this.onRemove,
  });

  final int index;
  final String role;
  final String name;
  final String detail;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        boxShadow: AppColors.shadowCard,
      ),
      child: Row(
        children: [
          Pill(role, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(LucideIcons.circleMinus, size: 20, color: AppColors.muted),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 4),
              child: Icon(LucideIcons.gripVertical, size: 20, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
