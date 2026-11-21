/// Extract the proxy node outbounds from a control-panel sing-box config.
///
/// The `sing_box` plugin's config builder wraps raw outbounds with its own
/// TUN/DNS/routing and selector + urltest groups, so we only hand it the node
/// proxies and drop the panel's inbounds/route/dns/experimental scaffolding.
/// Node credentials and outbound fields are passed through untouched.
List<Map<String, dynamic>> extractProxyOutbounds(Map<String, dynamic> source) {
  const builtin = {'direct', 'block', 'dns', 'selector', 'urltest'};
  final outbounds = source['outbounds'];
  if (outbounds is! List) {
    throw StateError('订阅中没有可用节点');
  }
  final proxies = outbounds
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) {
        final tag = item['tag'] as String? ?? '';
        final type = item['type'] as String? ?? '';
        // A misleading node-* tag must never turn a direct/group outbound
        // into a selectable proxy.
        return tag.isNotEmpty && type.isNotEmpty && !builtin.contains(type);
      })
      .toList();
  if (proxies.isEmpty) {
    throw StateError('订阅中没有可用节点');
  }
  return proxies;
}

/// Android 模拟器中的 127.0.0.1 指向模拟器自身；仅在开发地址明确为 10.0.2.2 时改写。
Uri resolveSubscriptionURL(String value, String controlBase) {
  final source = Uri.parse(value);
  final base = Uri.parse(controlBase);
  if ((source.host == '127.0.0.1' || source.host == 'localhost') &&
      base.host == '10.0.2.2') {
    return source.replace(scheme: base.scheme, host: base.host, port: base.port);
  }
  return source;
}
