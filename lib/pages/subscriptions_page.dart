import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'scan_subscription_page.dart';

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    final airport = state.subscriptions
        .where((s) => s['subscriptionUrl'] is String && (s['subscriptionUrl'] as String).isNotEmpty)
        .toList();
    final external = state.externalSubs;
    final active = state.currentSub();

    final empty = airport.isEmpty && external.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(t('subs.title'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-subscription',
        onPressed: () => _showAddDialog(context, state),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus),
        label: Text(t('subs.add')),
      ),
      body: empty
          ? EmptyState(title: t('subs.empty'), hint: t('subs.emptyHint'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppMetrics.pad, AppMetrics.pad, AppMetrics.pad, 96),
              children: [
                if (airport.isNotEmpty) ...[
                  _SectionLabel(t('subs.airport')),
                  for (final s in airport) ...[
                    _AirportSubCard(
                      sub: s,
                      active: active != null &&
                          active.kind == 'airport' &&
                          active.url == s['subscriptionUrl'],
                      onUse: () => state.setActiveSub('airport:${s['id']}'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (external.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _SectionLabel(t('subs.custom')),
                  for (final e in external) ...[
                    _ExternalSubCard(
                      sub: e,
                      active: active != null && active.kind == 'external' && active.url == e.url,
                      refreshing: state.refreshingSubs.contains(e.key),
                      onUse: () => state.setActiveSub(e.key),
                      onRefresh: () => state.refreshExternalSub(e.key),
                      onRemove: () => state.removeExternalSub(e),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, AppState state) async {
    final t = state.t;
    final name = TextEditingController();
    final url = TextEditingController();
    final added = await showAppDialog<bool>(
      context,
      title: t('subs.add'),
      subtitle: t('subs.formats'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: t('subs.nameOptional'),
              prefixIcon: Icon(LucideIcons.tag, size: 20, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: t('subs.url'),
              hintText: 'https://…',
              prefixIcon: Icon(LucideIcons.link, size: 20, color: AppColors.muted),
              suffixIcon: IconButton(
                tooltip: t('common.paste'),
                icon: Icon(LucideIcons.clipboard, size: 18, color: AppColors.brand),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text != null && text.isNotEmpty) url.text = text;
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final link = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const ScanSubscriptionPage()),
                );
                if (link != null && link.isNotEmpty) url.text = link;
              },
              icon: const Icon(LucideIcons.scanQrCode, size: 18),
              label: Text(t('subs.scan')),
            ),
          ),
        ],
      ),
      actions: [
        Builder(
          builder: (ctx) => OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
        ),
        Builder(
          builder: (ctx) => FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('common.add')),
          ),
        ),
      ],
    );
    if (added == true && url.text.trim().isNotEmpty) {
      await state.addExternalSub(name.text, url.text);
    }
    name.dispose();
    url.dispose();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 2),
      child: Text(text,
          style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

class _AirportSubCard extends StatelessWidget {
  const _AirportSubCard({required this.sub, required this.active, required this.onUse});
  final Map<String, dynamic> sub;
  final bool active;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final url = sub['subscriptionUrl'] as String? ?? '';
    final status = sub['status'] as String? ?? '';
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(sub['planName'] as String? ?? t('subs.title'),
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
              ),
              if (status == 'active') Pill(t('subs.valid'), color: AppColors.good),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (active)
                Pill(t('common.current'), color: AppColors.brand)
              else
                OutlinedButton(onPressed: onUse, child: Text(t('common.setCurrent'))),
              const Spacer(),
              IconButton(
                tooltip: t('subs.copySub'),
                icon: Icon(LucideIcons.copy, size: 18, color: AppColors.muted),
                onPressed: () => Clipboard.setData(ClipboardData(text: url)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExternalSubCard extends StatelessWidget {
  const _ExternalSubCard({
    required this.sub,
    required this.active,
    required this.refreshing,
    required this.onUse,
    required this.onRefresh,
    required this.onRemove,
  });
  final ExternalSub sub;
  final bool active;
  final bool refreshing;
  final VoidCallback onUse;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    final meta = refreshing
        ? t('subs.refreshing')
        : [
            t('subs.nodeCount', {'n': '${sub.nodeCount}'}),
            if (sub.updatedAt != null) t('subs.updatedAt', {'ago': _ago(t, sub.updatedAt!)}),
          ].join(' · ');

    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(sub.name,
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (sub.nodeCount > 0) Pill('${sub.nodeCount}', color: AppColors.brand),
            ],
          ),
          const SizedBox(height: 4),
          Text(sub.url,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              if (refreshing)
                const SizedBox(
                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(
                  sub.nodeCount > 0 ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                  size: 14,
                  color: sub.nodeCount > 0 ? AppColors.good : AppColors.fair,
                ),
              const SizedBox(width: 6),
              Text(meta, style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (active)
                Pill(t('common.current'), color: AppColors.brand)
              else
                OutlinedButton(onPressed: onUse, child: Text(t('common.setCurrent'))),
              const Spacer(),
              IconButton(
                tooltip: t('subs.refreshNodes'),
                icon: Icon(LucideIcons.refreshCw, size: 18, color: AppColors.brand),
                onPressed: refreshing ? null : onRefresh,
              ),
              IconButton(
                tooltip: t('common.copy'),
                icon: Icon(LucideIcons.copy, size: 18, color: AppColors.muted),
                onPressed: () => Clipboard.setData(ClipboardData(text: sub.url)),
              ),
              IconButton(
                tooltip: t('common.delete'),
                icon: Icon(LucideIcons.trash2, size: 18, color: AppColors.bad),
                onPressed: onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _ago(String Function(String, [Map<String, String>?]) t, DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return t('time.justNow');
    if (d.inMinutes < 60) return t('time.minutesAgo', {'n': '${d.inMinutes}'});
    if (d.inHours < 24) return t('time.hoursAgo', {'n': '${d.inHours}'});
    return t('time.daysAgo', {'n': '${d.inDays}'});
  }
}
