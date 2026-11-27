import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'lan_identity.dart';
import 'lan_models.dart';

/// 局域网传输异常（映射到前端可读文案）。
class LanException implements Exception {
  const LanException(this.message, {this.rejected = false, this.unsupported = false});
  final String message;
  final bool rejected;
  final bool unsupported;
  @override
  String toString() => message;
}

const String _partSuffix = '.clashnova-part';
const int _maxAttempts = 6;

/// 流式计算文件 SHA-256（小写 hex），不整文件载入内存。
Future<String> sha256File(File file) async {
  Digest? result;
  final sink = ChunkedConversionSink<Digest>.withCallback((d) => result = d.single);
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return result!.toString();
}

/// 构造局域网传输用 HTTP(S) 客户端：绕过系统代理（局域网直连），
/// https 下按指纹 pin 对端自签证书（TOFU）：`expectedFingerprint` 为 null 则接受
/// 任意证书（首次探测，如拉 /info），否则校验对端证书 DER 的 SHA-256 必须一致。
HttpClient buildLanHttpClient({LanIdentity? identity, String? expectedFingerprint}) {
  // 对端强制 mTLS：必须出示本机客户端证书，否则握手失败。identity 为空仅用于
  // 无需出示身份的场景（测试/明文）。
  final ctx = identity?.clientContext ?? SecurityContext(withTrustedRoots: false);
  final client = HttpClient(context: ctx)
    ..connectionTimeout = const Duration(seconds: 5)
    ..findProxy = (uri) => 'DIRECT';
  client.badCertificateCallback = (cert, host, port) {
    if (expectedFingerprint == null) return true; // 首次探测，TOFU
    return sha256.convert(cert.der).toString() == expectedFingerprint;
  };
  return client;
}

// ———————————————————————— 发送端 ————————————————————————

/// 向 `baseUrl`（如 `https://host:port`）发送单个文件：prepare-upload → 续传式 upload。
Future<void> sendFile({
  required String baseUrl,
  required DeviceInfo sender,
  required File file,
  required LanIdentity identity,
  String? expectedFingerprint,
  void Function(int done, int total)? onProgress,
}) async {
  final size = await file.length();
  final fileName = file.uri.pathSegments.isEmpty ? 'file' : file.uri.pathSegments.last;
  final sha = await sha256File(file);
  final fileId = _uuid();
  final dto = FileDto(id: fileId, fileName: fileName, size: size, sha256: sha);
  final req = PrepareUploadRequest(info: sender, files: {fileId: dto});

  final client = buildLanHttpClient(identity: identity, expectedFingerprint: expectedFingerprint);
  try {
    final prepared = PrepareUploadResponse.fromJson(
      await _postJson(client, '$baseUrl$kApiPrefix/prepare-upload', req.toJson()),
    );
    final token = prepared.files[fileId];
    if (token == null) {
      throw const LanException('msg.lanError');
    }
    final sessionId = prepared.sessionId;

    var attempt = 0;
    while (true) {
      final offset = await _queryOffset(client, baseUrl, sessionId, fileId, token);
      if (offset >= size) break;
      int received;
      try {
        received = await _uploadRange(
            client, baseUrl, sessionId, fileId, token, offset, file, size, onProgress);
      } catch (_) {
        received = 0;
      }
      if (received >= size) break;
      attempt++;
      if (attempt >= _maxAttempts) {
        throw const LanException('msg.lanError');
      }
      await Future.delayed(Duration(milliseconds: 150 * attempt));
    }
  } finally {
    client.close(force: true);
  }
}

/// 发送文本消息。
Future<void> sendTextTo({
  required String baseUrl,
  required DeviceInfo sender,
  required String id,
  required String text,
  required LanIdentity identity,
  String? expectedFingerprint,
}) async {
  final client = buildLanHttpClient(identity: identity, expectedFingerprint: expectedFingerprint);
  try {
    final resp = await _post(client, '$baseUrl$kTextPath',
        body: jsonEncode({'id': id, 'info': sender.toJson(), 'text': text}));
    switch (resp.statusCode) {
      case HttpStatus.ok:
        return;
      case HttpStatus.forbidden:
        throw const LanException('msg.lanRejected', rejected: true);
      case HttpStatus.notFound:
      case HttpStatus.methodNotAllowed:
        throw const LanException('msg.lanTextUnsupported', unsupported: true);
      default:
        throw const LanException('msg.lanError');
    }
  } finally {
    client.close(force: true);
  }
}

/// 发起配对：POST /pair 带本机信息，对端用户接受返回 200。
Future<bool> sendPair({
  required String baseUrl,
  required DeviceInfo sender,
  required LanIdentity identity,
  String? expectedFingerprint,
}) async {
  final client = buildLanHttpClient(identity: identity, expectedFingerprint: expectedFingerprint);
  try {
    final resp = await _post(client, '$baseUrl$kPairPath', body: jsonEncode(sender.toJson()));
    if (resp.statusCode == HttpStatus.ok) return true;
    if (resp.statusCode == HttpStatus.forbidden) {
      throw const LanException('msg.lanRejected', rejected: true);
    }
    throw const LanException('msg.lanError');
  } finally {
    client.close(force: true);
  }
}

/// 从对端「拉取」配置同步：POST /sync 带本机信息；对端用户确认后在响应体返回
/// 配置 payload（不透明字符串）。被拒/超时对端返回 403。客户端超时 > 对端 30s 确认窗。
Future<String> sendSyncPull({
  required String baseUrl,
  required DeviceInfo sender,
  required LanIdentity identity,
  String? expectedFingerprint,
}) async {
  final client = buildLanHttpClient(identity: identity, expectedFingerprint: expectedFingerprint);
  try {
    final resp = await _post(client, '$baseUrl$kSyncPath',
            body: jsonEncode({'info': sender.toJson()}))
        .timeout(const Duration(seconds: 45));
    if (resp.statusCode == HttpStatus.forbidden) {
      throw const LanException('msg.lanRejected', rejected: true);
    }
    if (resp.statusCode != HttpStatus.ok) {
      throw const LanException('msg.lanError');
    }
    final body = await utf8.decoder.bind(resp).join();
    final map = jsonDecode(body) as Map<String, dynamic>;
    return (map['payload'] as String?) ?? '';
  } finally {
    client.close(force: true);
  }
}

/// 拉取对端 /info（首次 TOFU，接受任意证书）。
Future<DeviceInfo> fetchInfo(
    {required String baseUrl, required LanIdentity identity, String? expectedFingerprint}) async {
  final client = buildLanHttpClient(identity: identity, expectedFingerprint: expectedFingerprint);
  try {
    final req = await client.getUrl(Uri.parse('$baseUrl$kApiPrefix/info'));
    final resp = await req.close();
    if (resp.statusCode != HttpStatus.ok) {
      throw const LanException('msg.lanError');
    }
    final body = await utf8.decoder.bind(resp).join();
    return DeviceInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

Future<int> _queryOffset(HttpClient client, String baseUrl, String sessionId,
    String fileId, String token) async {
  try {
    final map = await _postJson(client,
        '$baseUrl$kUploadOffsetPath?sessionId=$sessionId&fileId=$fileId&token=$token', null);
    return (map['received'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<int> _uploadRange(
  HttpClient client,
  String baseUrl,
  String sessionId,
  String fileId,
  String token,
  int offset,
  File file,
  int size,
  void Function(int done, int total)? onProgress,
) async {
  final uri = Uri.parse(
      '$baseUrl$kApiPrefix/upload?sessionId=$sessionId&fileId=$fileId&token=$token&offset=$offset');
  final httpReq = await client.postUrl(uri);
  httpReq.headers.contentType = ContentType.binary;
  httpReq.contentLength = size - offset;
  var done = offset;
  await for (final chunk in file.openRead(offset)) {
    httpReq.add(chunk);
    done += chunk.length;
    onProgress?.call(done, size);
  }
  final resp = await httpReq.close();
  final body = await utf8.decoder.bind(resp).join();
  final ack = jsonDecode(body) as Map<String, dynamic>;
  return (ack['received'] as num?)?.toInt() ?? 0;
}

Future<Map<String, dynamic>> _postJson(
    HttpClient client, String url, Map<String, dynamic>? json) async {
  final resp = await _post(client, url, body: json == null ? null : jsonEncode(json));
  final body = await utf8.decoder.bind(resp).join();
  if (resp.statusCode == HttpStatus.forbidden) {
    throw const LanException('msg.lanRejected', rejected: true);
  }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw const LanException('msg.lanError');
  }
  return body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
}

Future<HttpClientResponse> _post(HttpClient client, String url, {String? body}) async {
  final req = await client.postUrl(Uri.parse(url));
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(body));
  }
  return req.close();
}

// ———————————————————————— 接收端 ————————————————————————

/// prepare-upload 审批：接受返回保存目录，拒绝返回 null。
typedef UploadDecider = Future<String?> Function(
    DeviceInfo sender, Map<String, FileDto> files);

/// 配对审批：接受返回 true。
typedef PairDecider = Future<bool> Function(DeviceInfo sender);

/// 文本审批：接受返回 true。
typedef TextDecider = Future<bool> Function(DeviceInfo sender, String text);

/// 拉取同步审批：接受返回本机配置 payload（不透明字符串），拒绝/超时返回 null。
typedef SyncDecider = Future<String?> Function(DeviceInfo sender);

/// 一条接收完成/失败的结果。
class ReceivedItem {
  const ReceivedItem({
    required this.taskId,
    required this.peer,
    required this.fileName,
    required this.size,
    required this.ok,
    this.savePath,
  });
  final String taskId;
  final DeviceInfo peer;
  final String fileName;
  final int size;
  final bool ok;
  final String? savePath;
}

class _PendingFile {
  _PendingFile(this.token, this.dto, this.taskId);
  final String token;
  final FileDto dto;
  final String taskId;
}

class _Session {
  _Session(this.saveDir, this.sender, this.files);
  final String saveDir;
  final DeviceInfo sender;
  final Map<String, _PendingFile> files; // fileId → pending
}

/// 运行中的接收端（HTTPS 服务）。协议与桌面 airport-lan transport.rs 一致。
class LanReceiver {
  LanReceiver({
    required this.identity,
    required this.local,
    required this.onDecideUpload,
    required this.onDecidePair,
    required this.onDecideText,
    required this.onDecideSync,
    this.onPeer,
    this.onProgress,
    this.onStarted,
    this.onReceived,
    this.onTextReceived,
  });

  final LanIdentity identity;

  /// 本机设备信息提供者（动态求值：实际监听端口在 bind 后才确定）。
  final DeviceInfo Function() local;
  final UploadDecider onDecideUpload;
  final PairDecider onDecidePair;
  final TextDecider onDecideText;
  final SyncDecider onDecideSync;
  final void Function(DiscoveredPeerLike peer)? onPeer;
  final void Function(String taskId, int done, int total)? onProgress;
  final void Function(String taskId, String fileName, int size, DeviceInfo peer)? onStarted;
  final void Function(ReceivedItem item)? onReceived;
  final void Function(DeviceInfo sender, String id, String text)? onTextReceived;

  HttpServer? _server;
  final Map<String, _Session> _sessions = {};

  int get port => _server?.port ?? 0;

  Future<void> start([int bindPort = kDefaultPort]) async {
    if (_server != null) return;
    HttpServer server;
    try {
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        bindPort,
        identity.securityContext,
        shared: true,
      );
    } on SocketException {
      // 首选端口被占（如同机另有实例/桌面端共享网络栈时）→ 回退临时端口。
      // 对端通过组播 announce 获知真实端口，功能不受影响。
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        0,
        identity.securityContext,
        shared: true,
      );
    }
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sessions.clear();
  }

  void _handle(HttpRequest req) {
    final path = req.uri.path;
    if (req.method == 'GET' && path == '$kApiPrefix/info') {
      _json(req, local().toJson());
      return;
    }
    if (req.method == 'POST') {
      switch (path) {
        case '$kApiPrefix/register':
          _register(req);
          return;
        case '$kApiPrefix/prepare-upload':
          _prepareUpload(req);
          return;
        case '$kApiPrefix/upload':
          _upload(req);
          return;
        case kUploadOffsetPath:
          _uploadOffset(req);
          return;
        case '$kApiPrefix/cancel':
          _cancel(req);
          return;
        case kPairPath:
          _pair(req);
          return;
        case kTextPath:
          _text(req);
          return;
        case kSyncPath:
          _syncPull(req);
          return;
      }
    }
    _status(req, HttpStatus.notFound);
  }

  Future<void> _register(HttpRequest req) async {
    try {
      final info = DeviceInfo.fromJson(await _readJson(req));
      _notePeer(info, req);
    } catch (_) {}
    _json(req, local().toJson());
  }

  Future<void> _pair(HttpRequest req) async {
    DeviceInfo info;
    try {
      info = DeviceInfo.fromJson(await _readJson(req));
    } catch (_) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    if (info.fingerprint.isEmpty) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    _notePeer(info, req);
    final ok = await onDecidePair(info);
    if (ok) {
      _json(req, local().toJson());
    } else {
      _status(req, HttpStatus.forbidden);
    }
  }

  /// POST /sync：对端请求拉取本机配置。确认后返回 {payload}，拒绝/超时 403。不配对。
  Future<void> _syncPull(HttpRequest req) async {
    DeviceInfo info;
    try {
      final json = await _readJson(req);
      info = DeviceInfo.fromJson(json['info'] as Map<String, dynamic>);
    } catch (_) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    if (info.fingerprint.isEmpty) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    _notePeer(info, req);
    final payload = await onDecideSync(info);
    if (payload != null) {
      _json(req, {'payload': payload});
    } else {
      _status(req, HttpStatus.forbidden);
    }
  }

  Future<void> _text(HttpRequest req) async {
    Map<String, dynamic> json;
    try {
      json = await _readJson(req);
    } catch (_) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    final id = json['id'] as String? ?? '';
    final text = json['text'] as String? ?? '';
    final info = DeviceInfo.fromJson(
        Map<String, dynamic>.from((json['info'] as Map?) ?? const {}));
    if (id.isEmpty || text.isEmpty || info.fingerprint.isEmpty) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    final ok = await onDecideText(info, text);
    if (!ok) {
      _status(req, HttpStatus.forbidden);
      return;
    }
    onTextReceived?.call(info, id, text);
    _status(req, HttpStatus.ok);
  }

  Future<void> _prepareUpload(HttpRequest req) async {
    PrepareUploadRequest r;
    try {
      r = PrepareUploadRequest.fromJson(await _readJson(req));
    } catch (_) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    if (r.files.values.any((f) => f.fileType == kTextType)) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    _notePeer(r.info, req);
    final saveDir = await onDecideUpload(r.info, r.files);
    if (saveDir == null) {
      _status(req, HttpStatus.forbidden);
      return;
    }
    final sessionId = _uuid();
    final files = <String, _PendingFile>{};
    final respFiles = <String, String>{};
    for (final entry in r.files.entries) {
      if (_safeFileName(entry.value.fileName) == null) {
        _status(req, HttpStatus.badRequest);
        return;
      }
      final token = _uuid();
      respFiles[entry.key] = token;
      files[entry.key] = _PendingFile(token, entry.value, _uuid());
    }
    _sessions[sessionId] = _Session(saveDir, r.info, files);
    _json(req, PrepareUploadResponse(sessionId: sessionId, files: respFiles).toJson());
  }

  Future<void> _uploadOffset(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final session = _sessions[q['sessionId']];
    final pending = session?.files[q['fileId']];
    if (session == null || pending == null || pending.token != q['token']) {
      _json(req, {'received': 0});
      return;
    }
    final temp = File('${session.saveDir}/${_safeFileName(pending.dto.fileName)}$_partSuffix');
    final received = await temp.exists() ? await temp.length() : 0;
    _json(req, {'received': received});
  }

  Future<void> _upload(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final session = _sessions[q['sessionId']];
    final pending = session?.files[q['fileId']];
    if (session == null || pending == null) {
      _status(req, HttpStatus.conflict);
      return;
    }
    if (pending.token != q['token']) {
      _status(req, HttpStatus.forbidden);
      return;
    }
    final name = _safeFileName(pending.dto.fileName);
    if (name == null) {
      _status(req, HttpStatus.badRequest);
      return;
    }
    final finalPath = '${session.saveDir}/$name';
    final tempPath = '$finalPath$_partSuffix';
    final temp = File(tempPath);
    final current = await temp.exists() ? await temp.length() : 0;
    final offset = int.tryParse(q['offset'] ?? '0') ?? 0;
    if (offset != current) {
      _json(req, {'received': current}, status: HttpStatus.conflict);
      return;
    }

    final expectedSize = pending.dto.size;
    if (current == 0) {
      onStarted?.call(pending.taskId, name, expectedSize, session.sender);
    }

    var total = current;
    IOSink? sink;
    try {
      sink = temp.openWrite(mode: FileMode.writeOnlyAppend);
      // 必须读完整个请求体（否则连接框架错乱），只写到期望大小、多余的丢弃。
      await for (final chunk in req) {
        if (total >= expectedSize) continue;
        final remaining = expectedSize - total;
        if (chunk.length <= remaining) {
          sink.add(chunk);
          total += chunk.length;
        } else {
          sink.add(chunk.sublist(0, remaining));
          total = expectedSize;
        }
        onProgress?.call(pending.taskId, total, expectedSize);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } catch (_) {
      await sink?.close();
      // 网络中断：保留 .part 供续传，不删不报结束。
      _status(req, HttpStatus.internalServerError);
      return;
    }

    if (total < expectedSize) {
      // 发送端提前结束：保留 .part，等待续传。
      _json(req, {'received': total});
      return;
    }

    // 收满：校验整文件 SHA-256，原子重命名。
    var ok = true;
    if (pending.dto.sha256 != null) {
      ok = (await sha256File(temp)) == pending.dto.sha256;
    }
    if (ok) {
      await temp.rename(finalPath);
    } else {
      await temp.delete();
    }
    _finishFile(q['sessionId']!, q['fileId']!);
    onReceived?.call(ReceivedItem(
      taskId: pending.taskId,
      peer: session.sender,
      fileName: name,
      size: expectedSize,
      ok: ok,
      savePath: ok ? finalPath : null,
    ));
    _json(req, {'received': total},
        status: ok ? HttpStatus.ok : HttpStatus.unprocessableEntity);
  }

  void _cancel(HttpRequest req) {
    _sessions.remove(req.uri.queryParameters['sessionId']);
    _status(req, HttpStatus.ok);
  }

  void _finishFile(String sessionId, String fileId) {
    final s = _sessions[sessionId];
    if (s == null) return;
    s.files.remove(fileId);
    if (s.files.isEmpty) _sessions.remove(sessionId);
  }

  void _notePeer(DeviceInfo info, HttpRequest req) {
    if (info.fingerprint.isEmpty) return;
    final addr = req.connectionInfo?.remoteAddress;
    if (addr != null) {
      onPeer?.call(DiscoveredPeerLike(info, addr));
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    return body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
  }

  void _json(HttpRequest req, Map<String, dynamic> body, {int status = HttpStatus.ok}) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    req.response.close();
  }

  void _status(HttpRequest req, int status) {
    req.response.statusCode = status;
    req.response.close();
  }
}

/// 接收端在 register/prepare-upload 时看到的对端（供上层登记到发现列表）。
class DiscoveredPeerLike {
  const DiscoveredPeerLike(this.info, this.address);
  final DeviceInfo info;
  final InternetAddress address;
}

/// 文件名安全校验：仅允许纯文件名（无路径分隔/穿越），非法返回 null。
String? _safeFileName(String name) {
  if (name.isEmpty || name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\\') || name.contains('\x00')) {
    return null;
  }
  return name;
}

int _uuidCounter = 0;
String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final n = _uuidCounter++;
  final rand = (now ^ (n * 0x9E3779B1)) & 0xFFFFFFFF;
  return '${now.toRadixString(16)}-${n.toRadixString(16)}-${rand.toRadixString(16)}';
}
