import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sing_box/sing_box.dart';

import 'connection.dart';
import 'core/latency.dart';
import 'core/mobile_http.dart';
import 'core/security.dart';
import 'core/sing_box_core.dart';
import 'core/lan/lan_service.dart';
import 'core/lan/lan_storage.dart';
import 'core/subscription_parser.dart';
import 'core/subscription_store.dart';
import 'env.dart';
import 'i18n.dart';
import 'mobile_config.dart';
import 'theme.dart';

/// A user-added generic subscription (a Clash / sing-box / share-link URL from
/// outside the control panel). Its parsed node [outbounds] are cached locally so
/// the node list shows immediately on restart and a connect needs no re-fetch.
class ExternalSub {
  const ExternalSub({
    required this.name,
    required this.url,
    this.outbounds = const [],
    this.updatedAt,
  });

  factory ExternalSub.fromJson(Map<String, dynamic> json) => ExternalSub(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        outbounds: (json['outbounds'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        updatedAt: json['updatedAt'] is String
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  final String name;
  final String url;

  /// Parsed sing-box outbound objects (one per node).
  final List<Map<String, dynamic>> outbounds;
  final DateTime? updatedAt;

  String get key => 'ext:$url';
  int get nodeCount => outbounds.length;

  ExternalSub copyWith({
    String? name,
    List<Map<String, dynamic>>? outbounds,
    DateTime? updatedAt,
  }) =>
      ExternalSub(
        name: name ?? this.name,
        url: url,
        outbounds: outbounds ?? this.outbounds,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'outbounds': outbounds,
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

/// A proxy node for display and selection, unified across the airport plan
/// subscription (from the panel API) and user-added external subscriptions
/// (parsed from their content). [tag] is the sing-box outbound tag the selector
/// switches to; [id] is the stable key the UI selects by.
class NodeView {
  const NodeView({
    required this.id,
    required this.name,
    required this.tag,
    this.detail = '',
    this.type,
    this.region,
    this.host,
    this.port,
    this.online,
  });

  final String id;
  final String name;
  final String tag;

  /// One-line secondary text (region and protocol). Server addresses stay
  /// available for latency checks and are not shown.
  final String detail;
  final String? type;

  /// Region code for airport nodes (used for the card chip).
  final String? region;

  /// Server host/port, used for the latency (TCP) test.
  final String? host;
  final int? port;

  /// Online status for airport nodes; null when unknown (external nodes).
  final bool? online;

  /// A short 2-char code for the card chip: region for airport nodes, a
  /// protocol abbreviation for external ones.
  String get chipCode {
    final r = (region ?? '').trim();
    if (r.isNotEmpty) return r.substring(0, r.length >= 2 ? 2 : 1).toUpperCase();
    const abbr = {
      'shadowsocks': 'SS',
      'vmess': 'VM',
      'vless': 'VL',
      'trojan': 'TR',
      'hysteria2': 'HY',
      'hysteria': 'HY',
      'tuic': 'TU',
      'socks': 'S5',
      'http': 'HT',
      'wireguard': 'WG',
      'anytls': 'AT',
    };
    return abbr[type] ?? (type == null || type!.isEmpty ? '··' : type!.substring(0, 2).toUpperCase());
  }
}

/// Node list ordering on the nodes page.
enum NodeSort { def, latency }

/// The subscription the connect button will use, resolved from the current
/// selection (an airport plan subscription or a user-added external one).
typedef SubSource = ({String kind, String name, String url});

/// Central app state: session, subscriptions, nodes, connection and settings.
/// Mirrors the desktop client's `useApp` controller, trimmed to mobile.
///
/// High-frequency core streams (live speed, logs, active connections) are kept
/// in dedicated [ValueNotifier]s so only the widgets that show them rebuild,
/// while structural changes (phase, subscriptions, nodes) go through
/// [notifyListeners].
class AppState extends ChangeNotifier {
  AppState({SingBoxCore? core, MobileHttp? transport, SubscriptionStore? subscriptionStore})
      : _core = core ?? SingBoxCore(),
        _transport = transport ?? MobileHttp(),
        _subscriptionStore = subscriptionStore ?? SubscriptionStore();

  final SingBoxCore _core;
  final MobileHttp _transport;
  final SubscriptionStore _subscriptionStore;
  bool _secureStoreReady = false;

  String _safeError(Object error) => error is MobileSecurityException
      ? t(error.key)
      : error is FormatException ? t('msg.requestFailed')
      : error.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');

  // ---- session / settings ----
  String baseUrl = AppEnv.baseUrl;
  String email = '';
  String _access = '';
  bool localMode = false;

  // ---- theme ----
  /// Light / dark / follow-system. Watched by the MaterialApp so a change
  /// re-themes the whole app.
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    _applyBrightness();
    notifyListeners();
    _savePrefs();
  }

  /// Resolve [themeMode] against the platform brightness and apply it to the
  /// runtime palette synchronously, so pages that rebuild from [notifyListeners]
  /// read the correct colors without waiting for the MaterialApp builder.
  void _applyBrightness() {
    AppColors.dark = switch (themeMode.value) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
    };
  }

  static ThemeMode _themeFromTag(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ---- i18n ----
  AppLanguage language = AppLanguage.system;
  String _localeCode = 'zh';
  final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('zh'));

  /// Translate an English key for the active locale, with `{name}` params.
  String t(String key, [Map<String, String>? params]) =>
      translate(_localeCode, key, params);

  String _systemLocaleCode() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
    if (code.startsWith('zh')) return 'zh';
    const supported = {'en', 'ja', 'ko', 'de', 'fr', 'ru'};
    return supported.contains(code) ? code : 'en';
  }

  void _recomputeLocale() {
    _localeCode = language == AppLanguage.system ? _systemLocaleCode() : languageTag(language);
    appLocale.value = Locale(_localeCode);
  }

  Future<void> setLanguage(AppLanguage l) async {
    language = l;
    _recomputeLocale();
    notifyListeners();
    _savePrefs();
  }

  // ---- data ----
  List<Map<String, dynamic>> subscriptions = [];
  List<Map<String, dynamic>> nodes = [];
  List<ExternalSub> externalSubs = [];
  String selectedNodeId = '';
  String? activeSubKey;

  /// Ordered node ids forming a proxy chain (entry → exit). A chain is active
  /// with two or more members: the exit (last) is the egress node and each hop
  /// dials through the previous one via sing-box `detour`.
  List<String> chain = [];

  /// Keys of external subscriptions currently being fetched/parsed (for UI).
  final Set<String> refreshingSubs = {};

  // ---- node ordering & latency test ----
  NodeSort nodeSort = NodeSort.def;

  /// Measured latency per node id, in milliseconds; a negative value means the
  /// last test timed out / failed.
  final Map<String, int> latencies = {};
  bool testing = false;
  int probeDone = 0;
  int probeTotal = 0;
  bool _cancelProbe = false;

  // ---- connection ----
  Phase phase = Phase.idle;
  String message = '';
  bool coreReady = false;
  bool busy = false;

  // ---- routing mode (clash modes: Rule / Global / Direct) ----
  /// Modes reported by the running tunnel; empty when not connected.
  List<String> clashModes = [];

  /// The mode the current tunnel is in (capitalised, e.g. "Rule").
  String clashMode = '';

  /// The mode the user wants; applied when the tunnel comes up and remembered
  /// across sessions.
  String preferredMode = 'Rule';

  /// Display order for the mode control.
  static const List<String> modeOrder = ['Rule', 'Global'];

  /// Localised label for a routing mode ('Rule' → 规则 / Rule).
  String modeLabel(String mode) => t('mode.${mode.toLowerCase()}');

  /// The mode shown in the UI: the live mode when connected, else the preferred.
  String get currentMode => connected && clashMode.isNotEmpty ? clashMode : preferredMode;

  // ---- live core streams ----
  final ValueNotifier<SingBoxConnectionStats?> stats = ValueNotifier(null);
  final ValueNotifier<List<SingBoxLogEntry>> logs = ValueNotifier(const []);
  final ValueNotifier<List<SingBoxConnection>> connections = ValueNotifier(const []);

  /// Live tunnel uptime, ticked each second while connected.
  final ValueNotifier<Duration> uptime = ValueNotifier(Duration.zero);
  DateTime? _connectedSince;
  Timer? _uptimeTimer;

  final List<StreamSubscription<dynamic>> _subs = [];

  bool get loggedIn => _access.isNotEmpty;
  bool get connected => phase == Phase.connected;
  bool get connecting => phase == Phase.connecting || phase == Phase.preparing;

  Future<void> init() async {
    await _loadPrefs();
    // Without the account system, run straight as a local subscription client.
    if (!AppEnv.enableLogin) localMode = true;
    _applyBrightness();
    _recomputeLocale();
    if (message.isEmpty) {
      message = AppEnv.enableLogin ? t('msg.welcome') : t('msg.addSubToStart');
    }
    if (!kIsWeb) {
      await _initCore();
    }
  }

  Future<void> _initCore() async {
    try {
      await _core.initialize();
      _subs.add(_core.watchState().listen((state) {
        phase = SingBoxCore.phaseOf(state.status);
        if (phase == Phase.connected) {
          _connectedSince ??= DateTime.now();
          message = t('msg.vpnConnected');
        } else {
          _connectedSince = null;
          uptime.value = Duration.zero;
          if (phase == Phase.idle && state.error != null) {
            phase = Phase.failed;
            message = t('msg.vpnStopped', {'error': '${state.error}'});
          }
        }
        notifyListeners();
      }));
      _subs.add(_core.watchStats().listen((s) => stats.value = s));
      _subs.add(_core.watchLogBuffer(maxEntries: 500).listen((l) => logs.value = l));
      _subs.add(_core.watchConnections().listen((c) => connections.value = c));
      _subs.add(_core.watchClashMode().listen((m) {
        clashModes = m.modes;
        if (m.current.isNotEmpty) clashMode = m.current;
        // Apply the user's preferred mode as soon as the tunnel exposes modes.
        if (connected &&
            clashModes.contains(preferredMode) &&
            clashMode != preferredMode) {
          _core.setClashMode(preferredMode).ignore();
        }
        notifyListeners();
      }));
      _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_connectedSince != null) {
          uptime.value = DateTime.now().difference(_connectedSince!);
        }
      });
      coreReady = true;
      notifyListeners();
    } catch (e) {
      message = t('msg.initFailed', {'error': '$e'});
      notifyListeners();
    }
  }

  /// 局域网传输服务（懒加载：首次进入局域网页面时创建并启动）。
  LanService? lan;

  /// 确保局域网服务已创建并启动（接收端 + 组播发现）。接收文件默认存到应用目录。
  Future<LanService> ensureLan() async {
    final existing = lan;
    if (existing != null) return existing;
    final storage = await LanStorage.open();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ClashNova');
    if (!await dir.exists()) await dir.create(recursive: true);
    final svc = LanService(storage: storage, defaultSaveDir: dir.path);
    await svc.start();
    lan = svc;
    notifyListeners();
    return svc;
  }

  @override
  void dispose() {
    lan?.dispose();
    _uptimeTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    stats.dispose();
    logs.dispose();
    connections.dispose();
    uptime.dispose();
    appLocale.dispose();
    themeMode.dispose();
    super.dispose();
  }

  /// Switch routing mode (Rule / Global / Direct). Remembered for next connect
  /// and applied live when the tunnel is up.
  Future<void> setMode(String mode) async {
    preferredMode = mode;
    notifyListeners();
    _savePrefs();
    if (connected && clashModes.contains(mode)) {
      try {
        await _core.setClashMode(mode);
      } catch (_) {
        // mode not available on this config; keep the preference.
      }
    }
  }

  // ---- persistence ----
  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      baseUrl = prefs.getString('baseUrl') ?? baseUrl;
      preferredMode = prefs.getString('preferredMode') ?? preferredMode;
      language = languageFromTag(prefs.getString('language'));
      themeMode.value = _themeFromTag(prefs.getString('themeMode'));
      final private = await _subscriptionStore.load(prefs);
      selectedNodeId = private['selectedNodeId'] as String? ?? '';
      chain = (private['chain'] as List<dynamic>? ?? []).cast<String>();
      activeSubKey = private['activeSubKey'] as String?;
      final raw = (private['externalSubs'] as List<dynamic>? ?? []).cast<String>();
      externalSubs = raw
          .map((s) => ExternalSub.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
      _secureStoreReady = true;
    } catch (_) {
      // Preserve inaccessible/corrupt data and prevent later default writes.
      message = t('msg.storageFailed');
    }
  }

  Future<void> _savePrefs() async {
    final private = {
      'selectedNodeId': selectedNodeId,
      'chain': [...chain],
      'activeSubKey': activeSubKey,
      'externalSubs': externalSubs.map((e) => jsonEncode(e.toJson())).toList(),
    };
    try {
      if (!_secureStoreReady) throw StateError('secure storage unavailable');
      await _subscriptionStore.save(private);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('baseUrl', baseUrl);
      await prefs.setString('preferredMode', preferredMode);
      await prefs.setString('language', languageTag(language));
      await prefs.setString('themeMode', themeMode.value.name);
    } catch (_) {
      message = t('msg.storageFailed');
    }
  }

  // ---- REST ----
  Future<Map<String, dynamic>> _api(String path, {String method = 'GET', Object? body}) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (_access.isNotEmpty) headers['authorization'] = 'Bearer $_access';
    final uri = Uri.parse('$baseUrl$path');
    final response = await _transport.request(uri, method: method,
        headers: headers, body: method == 'POST' ? jsonEncode(body) : null);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(decoded['message'] as String? ?? t('msg.requestFailed'));
    }
    return decoded;
  }

  // ---- auth ----
  Future<void> login(String base, String mail, String password) async {
    try {
      final uri = MobileHttp.validateUri(Uri.parse(base.trim()));
      if (uri.hasQuery) throw const MobileSecurityException('msg.httpsRequired');
      // Never send the previous account's bearer token to a new login host.
      _access = '';
      subscriptions = [];
      nodes = [];
      baseUrl = base.trim().replaceFirst(RegExp(r'/+$'), '');
      email = mail.trim();
      final body = await _api('/api/v1/app/auth/login', method: 'POST', body: {
        'email': email,
        'password': password,
      });
      final data = body['data'] as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;
      _access = tokens['accessToken'] as String;
      await _savePrefs();
      await refresh();
      message = t('msg.signedIn');
      notifyListeners();
    } catch (e) {
      message = _safeError(e);
      notifyListeners();
    }
  }

  void enterLocal(String base) {
    baseUrl = base.trim();
    localMode = true;
    message = externalSubs.isEmpty ? t('msg.localEmpty') : t('msg.localMode');
    _savePrefs();
    notifyListeners();
  }

  Future<bool> logout() async {
    if (busy) return false;
    _set(() => busy = true);
    try {
      // Do not display an idle/signed-out state while the old account's VPN
      // is still connected. A failed stop keeps the real status visible.
      if (coreReady && (connected || connecting || _core.isConnected)) {
        await _core.disconnect();
      }
      _access = '';
      localMode = false;
      subscriptions = [];
      nodes = [];
      selectedNodeId = '';
      phase = Phase.idle;
      message = t('msg.signedOut');
      return true;
    } catch (e) {
      message = t('msg.disconnectFailed', {'error': _safeError(e)});
      return false;
    } finally {
      _set(() => busy = false);
    }
  }

  // ---- data ----
  Future<void> refresh() async {
    if (!loggedIn) {
      notifyListeners();
      return;
    }
    final subs = await _api('/api/v1/app/subscriptions');
    final nodeBody = await _api('/api/v1/app/nodes');
    subscriptions = (subs['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    nodes = (nodeBody['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final online = nodes.where((n) => n['agentOnline'] == true).toList();
    _validateSelection();
    message = subscriptions.isEmpty
        ? t('msg.noSubs')
        : t('msg.loadedSubs', {'n': '${subscriptions.length}'});
    if (online.isEmpty && nodes.isNotEmpty) message = t('msg.nodesOffline');
    notifyListeners();
  }

  /// Refresh whatever the connect button would use right now: the airport data
  /// when logged in, plus the active external subscription.
  Future<void> refreshActive() async {
    if (loggedIn) await refresh();
    final sub = currentSub();
    if (sub != null && sub.kind == 'external') {
      final e = externalSubs.where((x) => x.url == sub.url).firstOrNull;
      if (e != null) await refreshExternalSub(e.key);
    }
  }

  // ---- node selection ----
  /// The nodes of the currently active subscription, unified for the node list
  /// and for connect. Airport nodes come from the panel API (with the
  /// `node-<id8>` tag convention and online status); external nodes come from
  /// the subscription's parsed outbounds.
  List<NodeView> get activeNodes {
    final sub = currentSub();
    if (sub != null && sub.kind == 'external') {
      final e = externalSubs.where((x) => x.url == sub.url).firstOrNull;
      final outs = e?.outbounds ?? const <Map<String, dynamic>>[];
      return [
        for (final o in outs)
          NodeView(
            id: (o['tag'] ?? '').toString(),
            name: (o['tag'] ?? '').toString(),
            tag: (o['tag'] ?? '').toString(),
            type: o['type']?.toString(),
            host: (o['server'] ?? '').toString().isEmpty ? null : o['server'].toString(),
            port: _asInt(o['server_port']),
            detail: [
              if ((o['type'] ?? '').toString().isNotEmpty) o['type'].toString(),
            ].join(' · '),
          ),
      ];
    }
    return [
      for (final n in nodes)
        NodeView(
          id: (n['id'] ?? '').toString(),
          name: (n['name'] ?? '').toString(),
          tag: _airportTag((n['id'] ?? '').toString()),
          online: n['agentOnline'] == true,
          type: (n['protocol'] ?? '').toString().isEmpty ? null : n['protocol'].toString(),
          region: (n['region'] ?? '').toString().isEmpty ? null : n['region'].toString(),
          host: (n['host'] ?? '').toString().isEmpty ? null : n['host'].toString(),
          port: _asInt(n['port']),
          detail: [
            if ((n['region'] ?? '').toString().isNotEmpty) n['region'].toString(),
            if ((n['protocol'] ?? '').toString().isNotEmpty) n['protocol'].toString(),
          ].join(' · '),
        ),
    ];
  }

  static String _airportTag(String id) {
    final hex = id.replaceAll('-', '');
    return 'node-${hex.length >= 8 ? hex.substring(0, 8) : hex}';
  }

  /// The outbound tag for the selected node; null when "auto" (let the plugin's
  /// urltest group pick the fastest).
  String? get selectedTag {
    if (selectedNodeId.isEmpty) return null;
    return activeNodes.where((n) => n.id == selectedNodeId).firstOrNull?.tag;
  }

  // ---- proxy chain (链式代理) ----
  /// A chain needs at least two hops to mean anything.
  bool get chainActive => chain.length >= 2;

  /// The chain resolved to outbound tags, entry → exit. Null when the chain is
  /// inactive or any hop is no longer in the active node list.
  List<String>? get chainTags {
    if (!chainActive) return null;
    final byId = {for (final n in activeNodes) n.id: n.tag};
    final tags = <String>[];
    for (final id in chain) {
      final tag = byId[id];
      if (tag == null) return null;
      tags.add(tag);
    }
    return tags;
  }

  /// Display names of the chain members, entry → exit (for summaries).
  List<String> get chainNames {
    final byId = {for (final n in activeNodes) n.id: n};
    return [for (final id in chain) (byId[id]?.name ?? id)];
  }

  /// A compact entry → exit summary of the active chain, e.g. "A → B".
  String get chainSummary => chainNames.join(' → ');

  /// Replace the chain (ordered entry → exit) and persist. Reconnects when live
  /// so the new `detour` wiring takes effect (it is baked in at connect time).
  Future<void> setChain(List<String> ids) async {
    chain = [...ids];
    notifyListeners();
    _savePrefs();
    if (connected || connecting) await reconnect();
  }

  /// Rewrite [outbounds] in place so the active chain dials entry → … → exit via
  /// sing-box `detour`, returning the exit tag to select. Returns null and
  /// leaves [outbounds] untouched when no valid chain applies. Hop maps are
  /// copied before mutation so cached external outbounds are never polluted.
  String? _applyChain(List<Map<String, dynamic>> outbounds) {
    final tags = chainTags;
    if (tags == null) return null;
    final present = {for (final o in outbounds) (o['tag'] ?? '').toString()};
    if (!tags.every(present.contains)) return null;
    for (var i = 1; i < tags.length; i++) {
      final idx = outbounds.indexWhere((o) => (o['tag'] ?? '').toString() == tags[i]);
      if (idx < 0) return null;
      outbounds[idx] = {...outbounds[idx], 'detour': tags[i - 1]};
    }
    return tags.last;
  }

  /// Label for the current node on the connect card.
  String get currentNodeLabel {
    final n = currentNode;
    return (n != null && n.name.isNotEmpty) ? n.name : t('home.autoSelect');
  }

  /// The selected node in the active list, or null when "auto".
  NodeView? get currentNode {
    if (selectedNodeId.isEmpty) return null;
    return activeNodes.where((x) => x.id == selectedNodeId).firstOrNull;
  }

  /// Drop the selection and any chain members no longer present in the active
  /// node list.
  void _validateSelection() {
    final ids = activeNodes.map((n) => n.id).toSet();
    if (selectedNodeId.isNotEmpty && !ids.contains(selectedNodeId)) {
      selectedNodeId = '';
    }
    if (chain.isNotEmpty) {
      final pruned = chain.where(ids.contains).toList();
      if (pruned.length != chain.length) chain = pruned;
    }
  }

  Future<void> selectNode(String id) async {
    selectedNodeId = id;
    notifyListeners();
    _savePrefs();
    if (connected) {
      final tag = selectedTag;
      if (tag != null) {
        try {
          await _core.select(tag);
        } catch (_) {
          // selector may not contain this tag; ignore and keep current.
        }
      }
    }
  }

  /// The active node list, ordered per [nodeSort]. Untested / failed nodes sink
  /// to the bottom when sorting by latency (mirrors the desktop node-order).
  List<NodeView> get sortedActiveNodes {
    final list = activeNodes;
    if (nodeSort != NodeSort.latency) return list;
    final copy = [...list];
    copy.sort((a, b) {
      final x = latencies[a.id];
      final y = latencies[b.id];
      final xv = (x == null || x < 0) ? null : x;
      final yv = (y == null || y < 0) ? null : y;
      if (xv == null) return yv == null ? 0 : 1;
      if (yv == null) return -1;
      return xv - yv;
    });
    return copy;
  }

  void setNodeSort(NodeSort sort) {
    nodeSort = sort;
    notifyListeners();
  }

  /// Measure latency for the active nodes.
  ///
  /// While the tunnel is up, each node is tested by a request through that
  /// node, which is the only measurement Hysteria2 and TUIC can answer.
  /// While it is down, TCP protocols get a direct handshake; UDP protocols
  /// are left untested because nothing is listening on TCP.
  Future<void> testLatencies() async {
    if (testing) {
      _cancelProbe = true;
      return;
    }
    final list = activeNodes
        .where((n) => (n.host ?? '').isNotEmpty && n.port != null)
        .toList();
    if (list.isEmpty) {
      _set(() => message = t('msg.noTestable'));
      return;
    }
    _cancelProbe = false;
    final byId = {for (final n in list) n.id: n};
    final plan = planLatency(
      list.map((n) => LatencyTarget(id: n.id, tag: n.tag, type: n.type, testable: true)),
      connected: _core.isConnected,
    );
    final reported = <String>{};
    var failed = false;
    _set(() {
      testing = true;
      probeDone = 0;
      probeTotal = plan.measure.length;
      for (final node in plan.skippedUdp) {
        latencies.remove(node.id);
      }
    });
    if (plan.throughTunnel) {
      try {
        await _core.urlTestDelays(
          plan.measure.map((n) => n.tag).toList(),
          cancelled: () => _cancelProbe,
          onResult: (tag, ms) {
            if (_cancelProbe) return;
            final node = plan.measure.where((n) => n.tag == tag).firstOrNull;
            if (node == null || !reported.add(node.id)) return;
            latencies[node.id] = ms;
            probeDone++;
            notifyListeners();
          },
        );
      } catch (error) {
        failed = true;
        if (!_cancelProbe) message = t('msg.testFailed', {'error': '$error'});
      }
    } else {
      const concurrency = 8;
      for (var i = 0; i < plan.measure.length && !_cancelProbe; i += concurrency) {
        final slice = plan.measure.skip(i).take(concurrency);
        await Future.wait(slice.map((target) async {
          final node = byId[target.id]!;
          final ms = await _tcpPing(node.host!, node.port!);
          latencies[target.id] = ms;
          probeDone++;
          notifyListeners();
        }));
      }
    }
    _set(() {
      testing = false;
      _cancelProbe = false;
      if (!failed) {
        message = plan.skippedUdp.isNotEmpty ? t('msg.udpTestNeedsConnection') : t('msg.testDone');
      }
    });
  }

  Future<int> _tcpPing(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      socket?.destroy();
    }
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  // ---- external subscriptions ----
  Future<void> addExternalSub(String name, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    try {
      MobileHttp.validateUri(resolveSubscriptionURL(trimmed, baseUrl));
    } catch (e) {
      _set(() => message = _safeError(e));
      return;
    }
    final sub = ExternalSub(
      name: name.trim().isEmpty ? trimmed : name.trim(),
      url: trimmed,
    );
    externalSubs = [...externalSubs.where((e) => e.url != trimmed), sub];
    activeSubKey = sub.key;
    selectedNodeId = ''; // new subscription defaults to auto
    await _savePrefs();
    notifyListeners();
    // Mainstream flow: fetch + parse immediately so the node list is populated.
    await refreshExternalSub(sub.key);
  }

  /// Fetch an external subscription and parse it into nodes.
  Future<void> refreshExternalSub(String key) async {
    final idx = externalSubs.indexWhere((e) => e.key == key);
    if (idx < 0 || refreshingSubs.contains(key)) return;
    final sub = externalSubs[idx];
    refreshingSubs.add(key);
    _set(() => message = t('msg.refreshingSub', {'name': sub.name}));
    try {
      final uri = resolveSubscriptionURL(sub.url, baseUrl);
      final resp = await _transport.request(uri, subscription: true);
      if (resp.statusCode != 200) {
        throw StateError(t('msg.downloadFailed', {'code': '${resp.statusCode}'}));
      }
      final outs = await compute(SubscriptionParser.parse, resp.body);
      // Re-locate by key: the list may have changed during the await.
      final at = externalSubs.indexWhere((e) => e.key == key);
      if (at >= 0) {
        final updated = externalSubs[at].copyWith(
          outbounds: outs,
          updatedAt: DateTime.now(),
        );
        externalSubs = [...externalSubs]..[at] = updated;
      }
      _validateSelection();
      await _savePrefs();
      _set(() => message = outs.isEmpty
          ? t('msg.parseEmpty', {'name': sub.name})
          : t('msg.subUpdated', {'name': sub.name, 'n': '${outs.length}'}));
    } catch (e) {
      _set(() => message =
          t('msg.refreshFailed', {'error': _safeError(e)}));
    } finally {
      refreshingSubs.remove(key);
      notifyListeners();
    }
  }

  Future<void> removeExternalSub(ExternalSub sub) async {
    externalSubs = externalSubs.where((e) => e.url != sub.url).toList();
    if (activeSubKey == sub.key) activeSubKey = null;
    _validateSelection();
    await _savePrefs();
    notifyListeners();
  }

  void setActiveSub(String key) {
    activeSubKey = key;
    _validateSelection();
    _savePrefs();
    notifyListeners();
  }

  // ---- LAN 跨端同步 ----
  /// 采集本机「自建订阅 + 当前选择」为统一 payload（跨端 schema，详见桌面实现）。
  /// content 用 sing-box JSON（outbounds），对端各自解析回自己的形态。
  String buildSyncPayload() {
    final active = externalSubs.where((e) => e.key == activeSubKey).firstOrNull;
    return jsonEncode({
      'v': 1,
      'subs': [
        for (final e in externalSubs)
          {
            'name': e.name,
            'url': e.url,
            'content': jsonEncode({'outbounds': e.outbounds}),
          },
      ],
      'sel': {
        'activeUrl': active?.url,
        'activeName': active?.name,
        'node': selectedNodeId.isEmpty ? null : selectedNodeId,
        'chain': [...chain],
      },
    });
  }

  /// 应用收到的配置 payload：按 url 合并自建订阅（content→outbounds，不重新下载），
  /// 再激活对应订阅并 best-effort 应用选中节点/链。返回合并的订阅条数。
  Future<int> applySyncedConfig(String payload) async {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    if (data['v'] != 1 || data['subs'] is! List) {
      throw const FormatException('lan.syncBadPayload');
    }
    final byUrl = {for (final e in externalSubs) e.url: e};
    var count = 0;
    for (final raw in (data['subs'] as List).whereType<Map>()) {
      final s = Map<String, dynamic>.from(raw);
      final url = (s['url'] as String?) ?? '';
      final content = (s['content'] as String?) ?? '';
      if (content.isEmpty) continue;
      final name = (s['name'] as String?)?.trim().isNotEmpty == true
          ? (s['name'] as String).trim()
          : (url.isEmpty ? 'sub' : url);
      List<Map<String, dynamic>> outs;
      try {
        outs = await compute(SubscriptionParser.parse, content);
      } catch (_) {
        continue; // 跳过无法解析的订阅
      }
      byUrl[url] =
          ExternalSub(name: name, url: url, outbounds: outs, updatedAt: DateTime.now());
      count++;
    }
    externalSubs = byUrl.values.toList();

    // 应用选择：激活对应订阅，再按 payload 覆盖选中节点/链（节点 id=outbound tag，
    // 同端可靠；跨端若 tag 体系不同则忽略，不影响订阅已同步）。
    final sel = (data['sel'] as Map?)?.cast<String, dynamic>() ?? const {};
    final activeUrl = sel['activeUrl'] as String?;
    final activeName = sel['activeName'] as String?;
    ExternalSub? active;
    if (activeUrl != null && activeUrl.isNotEmpty) {
      active = externalSubs.where((e) => e.url == activeUrl).firstOrNull;
    }
    active ??= (activeName != null && activeName.isNotEmpty)
        ? externalSubs.where((e) => e.name == activeName).firstOrNull
        : null;
    if (active != null) {
      activeSubKey = active.key;
      final tags = {for (final o in active.outbounds) (o['tag'] ?? '').toString()};
      final node = sel['node'] as String?;
      selectedNodeId = (node != null && tags.contains(node)) ? node : '';
      final chainIn = (sel['chain'] as List<dynamic>? ?? const []).cast<String>();
      chain = chainIn.where(tags.contains).toList();
    }
    _validateSelection();
    await _savePrefs();
    notifyListeners();
    return count;
  }

  /// Resolve which subscription the connect button uses right now.
  SubSource? currentSub() {
    bool hasUrl(Map<String, dynamic> s) =>
        s['subscriptionUrl'] is String && (s['subscriptionUrl'] as String).isNotEmpty;

    if (activeSubKey != null && activeSubKey!.startsWith('ext:')) {
      final e = externalSubs.where((x) => x.key == activeSubKey).firstOrNull;
      if (e != null) return (kind: 'external', name: e.name, url: e.url);
    }
    if (activeSubKey != null && activeSubKey!.startsWith('airport:')) {
      final a = subscriptions
          .where((s) => 'airport:${s['id']}' == activeSubKey && hasUrl(s))
          .firstOrNull;
      if (a != null) {
        return (kind: 'airport', name: a['planName'] as String? ?? '', url: a['subscriptionUrl'] as String);
      }
    }
    final active = subscriptions.where((s) => s['status'] == 'active' && hasUrl(s)).firstOrNull;
    if (active != null) {
      return (kind: 'airport', name: active['planName'] as String? ?? '', url: active['subscriptionUrl'] as String);
    }
    if (externalSubs.isNotEmpty) {
      final e = externalSubs.first;
      return (kind: 'external', name: e.name, url: e.url);
    }
    return null;
  }

  // ---- connect / disconnect ----
  Future<void> toggleConnect() async {
    if (busy) return;
    if (connected || connecting) {
      await _disconnect();
      return;
    }
    await _startConnect();
  }

  Future<void> _disconnect() async {
    _set(() => busy = true);
    try {
      await _core.disconnect();
      _set(() => message = t('msg.disconnected'));
    } catch (e) {
      _set(() {
        phase = Phase.failed;
        message = t('msg.disconnectFailed', {'error': '$e'});
      });
    } finally {
      _set(() => busy = false);
    }
  }

  /// Tear down and re-establish the tunnel so a changed config (e.g. a new
  /// proxy chain) takes effect. The chain's `detour` wiring is baked in at
  /// connect time, so a live selector switch is not enough.
  Future<void> reconnect() async {
    if (!(connected || connecting)) return;
    await _disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _startConnect();
  }

  Future<void> _startConnect() async {
    if (phase != Phase.idle && phase != Phase.failed) return;
    if (!coreReady || kIsWeb) {
      _set(() {
        phase = Phase.failed;
        message = t('msg.coreNotReady');
      });
      return;
    }
    final sub = currentSub();
    if (sub == null) {
      _set(() => message = t('msg.addSubFirst'));
      return;
    }
    _set(() {
      busy = true;
      phase = Phase.preparing;
      message = t('msg.preparing', {'name': sub.name});
    });
    try {
      final outbounds = await _resolveOutbounds(sub);
      if (outbounds.isEmpty) {
        // Guard: never bring up the tunnel with no usable node — that just
        // leaves the device with no internet.
        throw StateError(t('msg.noNodesGuard'));
      }
      // When a chain is active, wire the hops with `detour` and egress through
      // the chain's exit; otherwise fall back to the single selected node.
      final exitTag = _applyChain(outbounds);
      _set(() => message = t('msg.requestingVpn'));
      await _core.connectOutbounds(outbounds, selectedTag: exitTag ?? selectedTag);
    } catch (e) {
      _set(() {
        phase = Phase.failed;
        message = t('msg.connectFailed', {
          'error': _safeError(e),
        });
      });
    } finally {
      _set(() => busy = false);
    }
  }

  /// Produce the node outbounds for [sub]: download + extract for an airport
  /// plan, or the cached/parsed outbounds for an external subscription
  /// (fetching once if the cache is empty).
  Future<List<Map<String, dynamic>>> _resolveOutbounds(SubSource sub) async {
    if (sub.kind == 'airport') {
      final uri = resolveSubscriptionURL(sub.url, baseUrl);
      final response = await _transport.request(uri, subscription: true,
          timeout: const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError(t('msg.subDownloadFailed', {'code': '${response.statusCode}'}));
      }
      try {
        return extractProxyOutbounds(jsonDecode(response.body) as Map<String, dynamic>);
      } on StateError {
        throw StateError(t('msg.noNodesInSub'));
      }
    }
    var e = externalSubs.where((x) => x.url == sub.url).firstOrNull;
    if (e == null) return const [];
    if (e.outbounds.isEmpty) {
      _set(() => message = t('msg.refreshingSub', {'name': e!.name}));
      await refreshExternalSub(e.key);
      e = externalSubs.where((x) => x.url == sub.url).firstOrNull;
    }
    return e?.outbounds ?? const [];
  }

  Future<void> closeConnection(String id) => _core.closeConnection(id);

  void _set(VoidCallback fn) {
    fn();
    notifyListeners();
  }
}

/// Exposes [AppState] to the widget tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope not found in context');
    return scope!.notifier!;
  }

  /// Read without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
