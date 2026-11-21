import 'package:flutter/material.dart';

import 'theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A white rounded card used across pages (the desktop "panel").
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppMetrics.pad),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        boxShadow: AppColors.shadowCard,
      ),
      child: child,
    );
  }
}

/// A compact square chip holding a 2-char code (region / protocol), echoing the
/// desktop node card's `.region-chip`.
class CodeChip extends StatelessWidget {
  const CodeChip({super.key, this.code, this.icon, this.tone});
  final String? code;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone ?? AppColors.brand;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon != null
          ? Icon(icon, color: tone, size: 18)
          : Text(
              (code == null || code!.isEmpty) ? '··' : code!,
              style: TextStyle(color: tone, fontSize: 12, fontWeight: FontWeight.w700),
            ),
    );
  }
}

/// A tappable row in the home menu list (icon · title · subtitle · chevron),
/// echoing the desktop sidebar nav.
class MenuTile extends StatelessWidget {
  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppMetrics.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppMetrics.radius),
            boxShadow: AppColors.shadowCard,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.brand, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// A reusable, app-styled modal dialog: rounded card, title with a close
/// button, optional subtitle, free-form [child] body, and an action row where
/// every button stretches to equal width (primary last). Use via [showAppDialog].
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(LucideIcons.x, size: 20, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 18),
            child,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows an [AppDialog] and returns its result (what an action pops with).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => AppDialog(title: title, subtitle: subtitle, actions: actions, child: child),
  );
}

/// One choice in an [AppSelect].
class AppSelectOption<T> {
  const AppSelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// A reusable dropdown control styled like the app: a bordered trigger that
/// matches control height, opening a rounded bottom sheet of options with a
/// check on the current one (replaces the default Material popup menu).
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.sheetTitle,
    this.height = 40,
  });

  final T value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final String? sheetTitle;
  final double height;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == value).isNotEmpty
        ? options.firstWhere((o) => o.value == value)
        : options.first;
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppMetrics.radiusBtn),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(current.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.strong, fontWeight: FontWeight.w600)),
            ),
            Icon(LucideIcons.chevronDown, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
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
              if (sheetTitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(sheetTitle!,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
                ),
              for (final o in options)
                InkWell(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                  onTap: () {
                    onChanged(o.value);
                    Navigator.of(ctx).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(o.label,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: o.value == value ? FontWeight.w600 : FontWeight.w500,
                                  color: o.value == value ? AppColors.brandText : AppColors.ink)),
                        ),
                        if (o.value == value)
                          Icon(LucideIcons.circleCheck, size: 20, color: AppColors.brand),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small colored status dot.
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// A rounded tag/pill with a tone color.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Centered empty-state for list pages.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.hint, this.action});
  final String title;
  final String hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(hint,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
                textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Human-readable byte/rate helpers shared by the stats and connection views.
String formatBytes(num n) {
  if (n < 1024) return '${n.toStringAsFixed(0)} B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatRate(num bytesPerSec) => '${formatBytes(bytesPerSec)}/s';
