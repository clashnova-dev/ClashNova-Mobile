import 'dart:convert';

import 'package:sing_box/sing_box.dart';
import 'package:yaml/yaml.dart';
import 'security.dart';

/// Turns raw subscription content into sing-box outbound objects.
///
/// Delegates most formats to the plugin's [SingBoxShareLink.parseSubscription]
/// (sing-box config JSON, a JSON array of outbounds, SIP008, and share links —
/// plain or base64, i.e. the Shadowrocket / v2rayN / NekoBox style). The one
/// thing the plugin explicitly does not handle is **Clash YAML**, so this layer
/// detects a Clash document and converts its `proxies:` into sing-box outbounds
/// before handing anything over.
///
/// Everything is best effort: unknown proxy types and malformed entries are
/// skipped rather than failing the whole import, mirroring how mainstream
/// clients degrade.
abstract final class SubscriptionParser {
  /// Parse [content] into outbound objects (ready for
  /// `SingBoxConfigBuilder` / `connect`). Returns an empty list when nothing
  /// usable is found.
  static List<Map<String, dynamic>> parse(String content) {
    validateSubscriptionSize(content);
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];

    if (_looksLikeClash(trimmed)) {
      final clash = _parseClash(trimmed);
      if (clash.isNotEmpty) {
        validateProxyOutbounds(clash);
        return clash;
      }
      // Fall through: a `proxies:`-less YAML or an all-unsupported list still
      // gets a chance at the generic parser below.
    }

    try {
      final outbounds = SingBoxShareLink.parseSubscription(content)
          .map((o) => o.json)
          .toList();
      validateProxyOutbounds(outbounds);
      return outbounds;
    } on MobileSecurityException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Heuristic: a Clash document is YAML (not JSON) with a `proxies:` block.
  static bool _looksLikeClash(String s) {
    if (s.startsWith('{') || s.startsWith('[')) return false; // JSON
    // A base64 blob is a single run without a YAML mapping colon.
    final hasProxiesKey =
        RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(s);
    return hasProxiesKey;
  }

  static List<Map<String, dynamic>> _parseClash(String yamlText) {
    final dynamic doc;
    try {
      doc = loadYaml(yamlText);
    } catch (_) {
      return const [];
    }
    final root = _plain(doc);
    if (root is! Map) return const [];
    final proxies = root['proxies'];
    if (proxies is! List) return const [];

    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final raw in proxies) {
      final p = _plain(raw);
      if (p is! Map) continue;
      final ob = _clashProxyToOutbound(p.cast<String, dynamic>());
      if (ob == null) continue;
      ob['tag'] = _uniqueTag((ob['tag'] as String?) ?? ob['type'] as String, seen);
      result.add(ob);
    }
    return result;
  }

  static String _uniqueTag(String base, Set<String> seen) {
    final name = base.trim().isEmpty ? 'proxy' : base.trim();
    if (seen.add(name)) return name;
    var i = 2;
    while (!seen.add('$name ($i)')) {
      i++;
    }
    return '$name ($i)';
  }

  /// Convert one Clash proxy map into a sing-box outbound, or null if the type
  /// is not supported.
  static Map<String, dynamic>? _clashProxyToOutbound(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().toLowerCase();
    final name = (m['name'] ?? '').toString();
    final server = (m['server'] ?? '').toString();
    final port = _int(m['port']);
    if (server.isEmpty || port == null) return null;

    Map<String, dynamic> base() => {
          'tag': name,
          'server': server,
          'server_port': port,
        };

    switch (type) {
      case 'ss':
      case 'shadowsocks':
        final o = base()
          ..['type'] = 'shadowsocks'
          ..['method'] = (m['cipher'] ?? '').toString()
          ..['password'] = (m['password'] ?? '').toString();
        _applyPlugin(o, m);
        return o;
      case 'trojan':
        final o = base()
          ..['type'] = 'trojan'
          ..['password'] = (m['password'] ?? '').toString();
        _applyTls(o, m, defaultOn: true);
        _applyTransport(o, m);
        return o;
      case 'vmess':
        final o = base()
          ..['type'] = 'vmess'
          ..['uuid'] = (m['uuid'] ?? '').toString()
          ..['alter_id'] = _int(m['alterId']) ?? 0
          ..['security'] = (m['cipher'] ?? 'auto').toString();
        _applyTls(o, m, defaultOn: m['tls'] == true);
        _applyTransport(o, m);
        return o;
      case 'vless':
        final o = base()
          ..['type'] = 'vless'
          ..['uuid'] = (m['uuid'] ?? '').toString();
        final flow = (m['flow'] ?? '').toString();
        if (flow.isNotEmpty) o['flow'] = flow;
        _applyTls(o, m, defaultOn: m['tls'] == true);
        _applyTransport(o, m);
        return o;
      case 'hysteria2':
      case 'hy2':
        final o = base()
          ..['type'] = 'hysteria2'
          ..['password'] = (m['password'] ?? m['auth'] ?? '').toString();
        final obfs = m['obfs'];
        if (obfs != null && obfs.toString().isNotEmpty) {
          o['obfs'] = {
            'type': obfs.toString(),
            'password': (m['obfs-password'] ?? '').toString(),
          };
        }
        _applyTls(o, m, defaultOn: true);
        return o;
      case 'tuic':
        final o = base()
          ..['type'] = 'tuic'
          ..['uuid'] = (m['uuid'] ?? '').toString()
          ..['password'] = (m['password'] ?? '').toString();
        final cc = (m['congestion-controller'] ?? '').toString();
        if (cc.isNotEmpty) o['congestion_control'] = cc;
        _applyTls(o, m, defaultOn: true);
        return o;
      case 'socks5':
      case 'socks':
        final o = base()..['type'] = 'socks';
        if (m['username'] != null) o['username'] = m['username'].toString();
        if (m['password'] != null) o['password'] = m['password'].toString();
        return o;
      case 'http':
      case 'https':
        final o = base()..['type'] = 'http';
        if (m['username'] != null) o['username'] = m['username'].toString();
        if (m['password'] != null) o['password'] = m['password'].toString();
        if (type == 'https' || m['tls'] == true) {
          _applyTls(o, m, defaultOn: true);
        }
        return o;
      default:
        return null;
    }
  }

  /// Shadowsocks obfs / v2ray-plugin, expressed as a sing-box plugin string.
  static void _applyPlugin(Map<String, dynamic> o, Map<String, dynamic> m) {
    final plugin = (m['plugin'] ?? '').toString();
    if (plugin.isEmpty) return;
    final opts = _plain(m['plugin-opts']);
    if (plugin == 'obfs' && opts is Map) {
      final mode = (opts['mode'] ?? 'http').toString();
      final host = (opts['host'] ?? '').toString();
      o['plugin'] = 'obfs-local';
      o['plugin_opts'] =
          'obfs=$mode${host.isEmpty ? '' : ';obfs-host=$host'}';
    } else if ((plugin == 'v2ray-plugin') && opts is Map) {
      final mode = (opts['mode'] ?? 'websocket').toString();
      final host = (opts['host'] ?? '').toString();
      final path = (opts['path'] ?? '').toString();
      final tls = opts['tls'] == true;
      o['plugin'] = 'v2ray-plugin';
      o['plugin_opts'] = [
        'mode=$mode',
        if (tls) 'tls',
        if (host.isNotEmpty) 'host=$host',
        if (path.isNotEmpty) 'path=$path',
      ].join(';');
    }
  }

  static void _applyTls(
    Map<String, dynamic> o,
    Map<String, dynamic> m, {
    required bool defaultOn,
  }) {
    final on = m['tls'] == true || defaultOn;
    if (!on) return;
    final tls = <String, dynamic>{'enabled': true};
    final sni =
        (m['servername'] ?? m['sni'] ?? m['server'] ?? '').toString();
    if (sni.isNotEmpty) tls['server_name'] = sni;
    if (m['skip-cert-verify'] == true) tls['insecure'] = true;
    final alpn = _plain(m['alpn']);
    if (alpn is List && alpn.isNotEmpty) {
      tls['alpn'] = alpn.map((e) => e.toString()).toList();
    }
    final fp = (m['client-fingerprint'] ?? '').toString();
    if (fp.isNotEmpty) tls['utls'] = {'enabled': true, 'fingerprint': fp};
    final reality = _plain(m['reality-opts']);
    if (reality is Map) {
      tls['reality'] = {
        'enabled': true,
        'public_key': (reality['public-key'] ?? '').toString(),
        'short_id': (reality['short-id'] ?? '').toString(),
      };
      tls['utls'] ??= {
        'enabled': true,
        'fingerprint': fp.isEmpty ? 'chrome' : fp,
      };
    }
    o['tls'] = tls;
  }

  static void _applyTransport(Map<String, dynamic> o, Map<String, dynamic> m) {
    final net = (m['network'] ?? '').toString().toLowerCase();
    switch (net) {
      case 'ws':
        final t = <String, dynamic>{'type': 'ws'};
        final ws = _plain(m['ws-opts']);
        if (ws is Map) {
          if (ws['path'] != null) t['path'] = ws['path'].toString();
          final headers = _plain(ws['headers']);
          if (headers is Map && headers['Host'] != null) {
            t['headers'] = {'Host': headers['Host'].toString()};
          }
        }
        o['transport'] = t;
        break;
      case 'grpc':
        final t = <String, dynamic>{'type': 'grpc'};
        final g = _plain(m['grpc-opts']);
        if (g is Map && g['grpc-service-name'] != null) {
          t['service_name'] = g['grpc-service-name'].toString();
        }
        o['transport'] = t;
        break;
      case 'h2':
      case 'http':
        final t = <String, dynamic>{'type': 'http'};
        final h = _plain(m['h2-opts'] ?? m['http-opts']);
        if (h is Map) {
          final path = h['path'];
          if (path is List && path.isNotEmpty) {
            t['path'] = path.first.toString();
          } else if (path != null) {
            t['path'] = path.toString();
          }
          final host = h['host'] ?? h['Host'];
          if (host is List) {
            t['host'] = host.map((e) => e.toString()).toList();
          } else if (host != null) {
            t['host'] = [host.toString()];
          }
        }
        o['transport'] = t;
        break;
    }
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  /// Recursively convert YAML nodes (YamlMap/YamlList) into plain Dart
  /// Map/List/scalars so the rest of the converter is YAML-agnostic.
  static Object? _plain(Object? node) {
    var visited = 0;
    Object? walk(Object? value, int depth) {
      if (depth > 32 || ++visited > 100000) {
        throw const MobileSecurityException('msg.unsafeSubscription');
      }
      if (value is YamlMap) {
        return value.map((k, v) => MapEntry(k.toString(), walk(v, depth + 1)));
      }
      if (value is YamlList) {
        return value.map((v) => walk(v, depth + 1)).toList();
      }
      if (value is YamlScalar) return value.value;
      return value;
    }
    return walk(node, 0);
  }
}

/// A test seam: re-export JSON helpers if callers want to inspect results.
String encodeOutbounds(List<Map<String, dynamic>> outbounds) =>
    jsonEncode(outbounds);
