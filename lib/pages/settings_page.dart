import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../env.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chain_page.dart';
import 'help_page.dart';
import 'nodes_page.dart';
import 'subscriptions_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const String _appVersion = '0.1.0';

/// Open an external About-page link (repository, chat group) in the browser.
void _openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null &&
      const {'https', 'tg'}.contains(uri.scheme) &&
      uri.host.isNotEmpty && uri.userInfo.isEmpty &&
      url.length <= 8192 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(url)) {
    launchUrl(uri, mode: LaunchMode.externalApplication).ignore();
  }
}

/// A brand mark (GitHub), tinted to match the other row icons.
Widget _brandIcon(String asset) => SvgPicture.asset(
      asset,
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(AppColors.brand, BlendMode.srcIn),
    );

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.t;
    final subCount = state.subscriptions.length + state.externalSubs.length;

    return Scaffold(
      appBar: AppBar(title: Text(t('settings.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppMetrics.pad, 8, AppMetrics.pad, 28),
        children: [
          if (AppEnv.enableLogin) ...[
            _Group(label: t('settings.account'), children: [
              _Row(
                icon: LucideIcons.circleUserRound,
                title: t('settings.accountRow'),
                value: state.loggedIn ? state.email : t('settings.localMode'),
                trailing: Pill(state.loggedIn ? t('settings.loggedIn') : t('settings.local'),
                    color: state.loggedIn ? AppColors.good : AppColors.idle),
              ),
              _Row(icon: LucideIcons.server, title: t('settings.controlPanel'), value: state.baseUrl),
            ]),
            const SizedBox(height: 18),
          ],
          _Group(label: t('settings.proxy'), children: [
            _Row(
              icon: LucideIcons.route,
              title: t('settings.routeMode'),
              value: state.modeLabel(state.currentMode),
              onTap: () => _showModePicker(context, state),
            ),
            _Row(
              icon: LucideIcons.layers,
              title: t('settings.node'),
              value: state.activeNodes.isEmpty ? t('common.none') : state.currentNodeLabel,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NodesPage()),
              ),
            ),
            _Row(
              icon: LucideIcons.link,
              title: t('chain.title'),
              value: state.chainActive ? state.chainSummary : t('chain.off'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChainPage()),
              ),
            ),
            _Row(
              icon: LucideIcons.rss,
              title: t('settings.subscription'),
              value: t('settings.subCount', {'n': '$subCount'}),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionsPage()),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _Group(label: t('settings.general'), children: [
            _Row(
              icon: LucideIcons.sunMoon,
              title: t('settings.theme'),
              value: _themeLabel(t, state.themeMode.value),
              onTap: () => _showThemePicker(context, state),
            ),
            _Row(
              icon: LucideIcons.languages,
              title: t('settings.language'),
              value: _langLabel(t, state.language),
              onTap: () => _showLanguagePicker(context, state),
            ),
          ]),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(t('settings.about'),
                style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/icon/icon.png', width: 44, height: 44),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ClashNova',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text('v$_appVersion', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ],
            ),
          ),
          _GroupBody(children: [
            _Row(
              icon: LucideIcons.circleHelp,
              title: t('settings.help'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpPage()),
              ),
            ),
            if (AppEnv.githubUrl.isNotEmpty)
              _Row(
                leading: _brandIcon('assets/brand/github.svg'),
                title: 'GitHub',
                onTap: () => _openUrl(AppEnv.githubUrl),
              ),
            const _Row(icon: LucideIcons.info, title: '', value: 'v$_appVersion', titleKey: 'settings.version'),
            const _Row(icon: LucideIcons.cpu, title: '', value: 'sing-box · libbox', titleKey: 'settings.kernel'),
            const _Row(icon: LucideIcons.fileText, title: '', value: 'GPL-3.0', titleKey: 'settings.license'),
          ]),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t('settings.vpnNote'),
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
            ),
          ),
          if (AppEnv.enableLogin) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: state.busy ? null : () async {
                if (await state.logout() && context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: AppColors.bad,
                side: BorderSide(color: AppColors.border),
              ),
              icon: const Icon(LucideIcons.logOut),
              label: Text(state.loggedIn ? t('settings.logout') : t('settings.logoutLocal')),
            ),
          ],
        ],
      ),
    );
  }

  String _langLabel(String Function(String, [Map<String, String>?]) t, AppLanguage l) =>
      switch (l) {
        AppLanguage.system => t('lang.system'),
        AppLanguage.zh => t('lang.zh'),
        AppLanguage.en => t('lang.en'),
        AppLanguage.ja => '日本語',
        AppLanguage.ko => '한국어',
        AppLanguage.de => 'Deutsch',
        AppLanguage.fr => 'Français',
        AppLanguage.ru => 'Русский',
      };

  String _themeLabel(String Function(String, [Map<String, String>?]) t, ThemeMode m) =>
      switch (m) {
        ThemeMode.system => t('theme.system'),
        ThemeMode.light => t('theme.light'),
        ThemeMode.dark => t('theme.dark'),
      };

  void _showThemePicker(BuildContext context, AppState state) {
    final t = state.t;
    _showSheet(
      context,
      title: t('theme.title'),
      children: [
        for (final m in ThemeMode.values)
          _PickerOption(
            label: _themeLabel(t, m),
            desc: '',
            selected: state.themeMode.value == m,
            onTap: () {
              state.setThemeMode(m);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  void _showModePicker(BuildContext context, AppState state) {
    final t = state.t;
    _showSheet(
      context,
      title: t('settings.routeMode'),
      children: [
        for (final mode in AppState.modeOrder)
          _PickerOption(
            label: state.modeLabel(mode),
            desc: t('mode.${mode.toLowerCase()}Desc'),
            selected: state.currentMode == mode,
            onTap: () {
              state.setMode(mode);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  void _showLanguagePicker(BuildContext context, AppState state) {
    final t = state.t;
    _showSheet(
      context,
      title: t('lang.title'),
      children: [
        for (final l in AppLanguage.values)
          _PickerOption(
            label: _langLabel(t, l),
            desc: '',
            selected: state.language == l,
            onTap: () {
              state.setLanguage(l);
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  void _showSheet(BuildContext context, {required String title, required List<Widget> children}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.ink)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
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

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(label,
              style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        _GroupBody(children: children),
      ],
    );
  }
}

/// The card body of a settings group (rows separated by hairlines), without the
/// section label — used on its own when a header sits between the label and the card.
class _GroupBody extends StatelessWidget {
  const _GroupBody({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Divider(height: 1, color: AppColors.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    this.icon,
    this.leading,
    required this.title,
    this.titleKey,
    this.value,
    this.trailing,
    this.onTap,
  }) : assert(icon != null || leading != null, 'row needs an icon or a leading widget');
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? titleKey;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = trailing;
    final label = titleKey != null ? AppScope.of(context).t(titleKey!) : title;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: Center(child: leading ?? Icon(icon, size: 20, color: AppColors.brand))),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 15, color: AppColors.ink)),
            const SizedBox(width: 12),
            Expanded(
              child: t != null
                  ? Align(alignment: Alignment.centerRight, child: t)
                  : Text(
                      value ?? '',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: AppColors.muted),
                    ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 20, color: AppColors.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? AppColors.brandText : AppColors.ink)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(desc, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (selected) Icon(LucideIcons.circleCheck, size: 20, color: AppColors.brand),
          ],
        ),
      ),
    );
  }
}
