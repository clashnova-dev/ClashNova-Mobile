/// 扫码连接载荷。
///
/// iOS 下原始 UDP 组播需 Apple 审批的 multicast 权限,未获批前无法自动发现;
/// 扫码直连走单播(有 NSLocalNetworkUsageDescription 即可),绕开该限制,
/// 同时也适用于禁组播的网络。两端以同一 URI 格式互通:
///
///   clashnova://lan?v=1&ip={IPv4}&port={port}&fp={cert-sha256}&alias={设备名}
class LanQrPayload {
  const LanQrPayload({
    required this.ip,
    required this.port,
    required this.fingerprint,
    required this.alias,
  });

  final String ip;
  final int port;
  final String fingerprint;
  final String alias;

  static const _scheme = 'clashnova';
  static const _host = 'lan';

  String toUri() => Uri(
        scheme: _scheme,
        host: _host,
        queryParameters: {
          'v': '1',
          'ip': ip,
          'port': '$port',
          'fp': fingerprint,
          'alias': alias,
        },
      ).toString();

  /// 解析扫到的文本;格式不符返回 null。
  static LanQrPayload? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != _scheme || uri.host != _host) return null;
    final q = uri.queryParameters;
    final ip = q['ip']?.trim() ?? '';
    final port = int.tryParse(q['port'] ?? '') ?? 0;
    final fp = q['fp']?.trim() ?? '';
    final alias = (q['alias']?.trim() ?? '');
    if (ip.isEmpty || port <= 0 || port > 65535 || fp.isEmpty) return null;
    return LanQrPayload(
      ip: ip,
      port: port,
      fingerprint: fp,
      alias: alias.isEmpty ? ip : alias,
    );
  }
}
