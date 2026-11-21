import 'dart:convert';

import 'package:http/http.dart' as http;

const _repository = 'clashnova-dev/ClashNova-Mobile';

class GitHubUpdate {
  const GitHubUpdate(this.version, this.releaseUrl);
  final String version;
  final Uri releaseUrl;
}

List<int> _version(String value) {
  final match = RegExp(r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$').firstMatch(value);
  if (match == null) throw const FormatException('Invalid release version');
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

bool isNewerVersion(String candidate, String current) {
  final a = _version(candidate), b = _version(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

Future<GitHubUpdate?> checkGitHubUpdate({
  required String currentVersion,
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final response = await transport.get(
      Uri.https('api.github.com', '/repos/$_repository/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Cannot read GitHub release');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['draft'] != false ||
        data['prerelease'] != false || data['tag_name'] is! String) {
      throw const FormatException('Invalid GitHub release');
    }
    final tag = data['tag_name'] as String;
    if (!isNewerVersion(tag, currentVersion)) return null;
    final assets = data['assets'];
    if (assets is! List || !assets.any((asset) {
      if (asset is! Map || asset['browser_download_url'] is! String) return false;
      final uri = Uri.tryParse(asset['browser_download_url'] as String);
      return uri != null && uri.scheme == 'https' && uri.host == 'github.com' &&
          uri.port == 443 && uri.userInfo.isEmpty && !uri.hasQuery &&
          !uri.hasFragment && uri.path.startsWith('/$_repository/releases/download/$tag/') &&
          uri.path.endsWith('.apk');
    })) {
      throw const FormatException('Release has no supported Android download');
    }
    return GitHubUpdate(tag.replaceFirst(RegExp(r'^v'), ''),
        Uri.https('github.com', '/$_repository/releases/tag/$tag'));
  } finally {
    if (client == null) transport.close();
  }
}
