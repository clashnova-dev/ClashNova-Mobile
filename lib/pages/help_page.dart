import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Help / FAQ grouped by topic. Content lives in i18n (`help.*` keys); this
/// file only lays it out. Structure: (category key, [(question key, answer key)]).
const List<(String, List<(String, String)>)> _faq = [
  (
    'help.cat.subs',
    [
      ('help.q.start', 'help.a.start'),
      ('help.q.formats', 'help.a.formats'),
      ('help.q.noNodes', 'help.a.noNodes'),
      ('help.q.latency', 'help.a.latency'),
    ],
  ),
  (
    'help.cat.conn',
    [
      ('help.q.modes', 'help.a.modes'),
      ('help.q.chain', 'help.a.chain'),
      ('help.q.ios', 'help.a.ios'),
      ('help.q.noNet', 'help.a.noNet'),
    ],
  ),
  (
    'help.cat.privacy',
    [
      ('help.q.privacy', 'help.a.privacy'),
    ],
  ),
];

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return Scaffold(
      appBar: AppBar(title: Text(t('help.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 8, AppMetrics.pad, 28),
        children: [
          for (final group in _faq) ...[
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8, top: 10),
              child: Text(t(group.$1),
                  style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(AppMetrics.radius),
                boxShadow: AppColors.shadowCard,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < group.$2.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: AppColors.line),
                    _FaqItem(question: t(group.$2[i].$1), answer: t(group.$2[i].$2)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.question,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                ),
                const SizedBox(width: 10),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(LucideIcons.chevronRight, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(widget.answer,
                    style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.6)),
              ),
              crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
            ),
          ],
        ),
      ),
    );
  }
}
