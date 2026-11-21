import 'package:flutter/material.dart';
import 'package:sing_box/sing_box.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  Color _levelColor(SingBoxLogLevel level) {
    switch (level) {
      case SingBoxLogLevel.panic:
      case SingBoxLogLevel.fatal:
      case SingBoxLogLevel.error:
        return AppColors.bad;
      case SingBoxLogLevel.warn:
        return AppColors.fair;
      case SingBoxLogLevel.info:
        return AppColors.good;
      case SingBoxLogLevel.debug:
      case SingBoxLogLevel.trace:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    return Scaffold(
      appBar: AppBar(title: Text(t('logs.title'))),
      body: ValueListenableBuilder<List<SingBoxLogEntry>>(
        valueListenable: state.logs,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return EmptyState(
              title: t('logs.empty'),
              hint: t('logs.emptyHint'),
            );
          }
          // Newest first.
          final items = logs.reversed.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(AppMetrics.pad),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 12, color: AppColors.line),
            itemBuilder: (context, i) {
              final e = items[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: StatusDot(_levelColor(e.level), size: 7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.plainMessage,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.ink,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
