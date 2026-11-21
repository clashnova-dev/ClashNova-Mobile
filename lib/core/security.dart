import 'dart:convert';

/// Messages contain no subscription URLs, credentials or file contents.
class MobileSecurityException implements Exception {
  const MobileSecurityException(this.key);
  final String key;
  @override
  String toString() => key;
}

const maxSubscriptionBytes = 2 * 1024 * 1024;
const maxProxyNodes = 512;

void validateSubscriptionSize(String content) {
  if (content.length > maxSubscriptionBytes ||
      utf8.encode(content).length > maxSubscriptionBytes) {
    throw const MobileSecurityException('msg.subscriptionTooLarge');
  }
}

/// Imported outbounds may describe proxies, never local files or executable
/// plugins. Rechecked at connect time so old cached profiles are covered too.
void validateProxyOutbounds(List<Map<String, dynamic>> outbounds) {
  if (outbounds.length > maxProxyNodes) {
    throw const MobileSecurityException('msg.subscriptionTooLarge');
  }
  const types = {
    'shadowsocks',
    'vmess',
    'vless',
    'trojan',
    'hysteria',
    'hysteria2',
    'tuic',
    'anytls',
    'shadowtls',
    'socks',
    'http',
    'ssh',
    'wireguard',
    'snell',
    'naive',
  };
  var visited = 0;
  void inspect(Object? value, int depth, String parent) {
    if (depth > 32 || ++visited > 100000) {
      throw const MobileSecurityException('msg.unsafeSubscription');
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key.endsWith('_path') ||
            key.endsWith('_paths') ||
            key.endsWith('_file') ||
            key.endsWith('_files') ||
            key.endsWith('_directory') ||
            const {
              'include',
              'rule_set',
              'acme',
              'cache_file',
              'output',
              'directory',
              'command',
              'script',
              'plugin',
              'plugin_opts',
              'netns',
            }.contains(key) ||
            (key == 'path' && parent != 'transport')) {
          throw const MobileSecurityException('msg.unsafeSubscription');
        }
        inspect(entry.value, depth + 1, key);
      }
    } else if (value is List) {
      for (final item in value) {
        inspect(item, depth + 1, parent);
      }
    }
  }

  for (final outbound in outbounds) {
    if (!types.contains(outbound['type'])) {
      throw const MobileSecurityException('msg.unsafeSubscription');
    }
    inspect(outbound, 0, '');
  }
  if (utf8.encode(jsonEncode(outbounds)).length > 4 * 1024 * 1024) {
    throw const MobileSecurityException('msg.subscriptionTooLarge');
  }
}
