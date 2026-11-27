/// LocalSend v2 兼容的协议模型与常量。
///
/// 字段/JSON 与桌面端 airport-lan 的 protocol.rs 一致（camelCase 线上格式），
/// 保证移动端（Dart）与桌面端（Rust）**跨语言互通**——双方只需说同一套线上协议。
library;

/// 组播发现地址（链路本地组播，LocalSend 同款）。
const String kMulticastAddr = '224.0.0.167';

/// HTTP/组播默认端口。
const int kDefaultPort = 53317;

/// LocalSend v2 API 前缀。
const String kApiPrefix = '/api/localsend/v2';

/// 协议版本。
const String kProtocolVersion = '2.0';

/// 文本消息端点（自有扩展）。
const String kTextPath = '/api/clashnova/v1/messages';

/// 显式配对端点（自有扩展）。
const String kPairPath = '/api/clashnova/v1/pair';

/// 跨端配置同步「拉取」端点（自有扩展，与桌面 SYNC_PATH 一致）。
const String kSyncPath = '/api/clashnova/v1/sync';

/// 续传偏移查询端点（自有扩展）。
const String kUploadOffsetPath = '/api/clashnova/v1/upload-offset';

/// 文本消息的 file_type 标记。
const String kTextType = 'application/vnd.clashnova.text';

/// 设备类型。
enum LanDeviceType { desktop, laptop, phone, tablet, server, tv, unknown }

LanDeviceType deviceTypeFromString(String? s) {
  switch (s) {
    case 'desktop':
      return LanDeviceType.desktop;
    case 'laptop':
      return LanDeviceType.laptop;
    case 'phone':
    case 'mobile': // 旧版本归一
      return LanDeviceType.phone;
    case 'tablet':
      return LanDeviceType.tablet;
    case 'server':
    case 'headless': // 旧版本归一
      return LanDeviceType.server;
    case 'tv':
      return LanDeviceType.tv;
  }
  return LanDeviceType.unknown;
}

String deviceTypeToString(LanDeviceType t) => t.name;

/// 传输协议。
enum LanProtocol { http, https }

/// 设备信息（发现广播 / /info / prepare-upload 携带）。
class DeviceInfo {
  const DeviceInfo({
    required this.alias,
    required this.fingerprint,
    this.version = kProtocolVersion,
    this.deviceModel,
    this.deviceType = LanDeviceType.phone,
    this.port = kDefaultPort,
    this.protocol = LanProtocol.https,
    this.download = false,
  });

  final String alias;
  final String fingerprint;
  final String version;
  final String? deviceModel;
  final LanDeviceType deviceType;
  final int port;
  final LanProtocol protocol;
  final bool download;

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'version': version,
        if (deviceModel != null) 'deviceModel': deviceModel,
        'deviceType': deviceTypeToString(deviceType),
        'fingerprint': fingerprint,
        'port': port,
        'protocol': protocol == LanProtocol.https ? 'https' : 'http',
        'download': download,
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        alias: (json['alias'] as String?) ?? '',
        version: (json['version'] as String?) ?? kProtocolVersion,
        deviceModel: json['deviceModel'] as String?,
        deviceType: deviceTypeFromString(json['deviceType'] as String?),
        fingerprint: (json['fingerprint'] as String?) ?? '',
        port: (json['port'] as num?)?.toInt() ?? kDefaultPort,
        protocol: (json['protocol'] as String?) == 'http'
            ? LanProtocol.http
            : LanProtocol.https,
        download: (json['download'] as bool?) ?? false,
      );
}

/// 单个文件描述（prepare-upload 携带）。
class FileDto {
  const FileDto({
    required this.id,
    required this.fileName,
    required this.size,
    this.fileType = 'application/octet-stream',
    this.sha256,
    this.preview,
  });

  final String id;
  final String fileName;
  final int size;
  final String fileType;
  final String? sha256;
  final String? preview;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'size': size,
        'fileType': fileType,
        if (sha256 != null) 'sha256': sha256,
        if (preview != null) 'preview': preview,
      };

  factory FileDto.fromJson(Map<String, dynamic> json) => FileDto(
        id: (json['id'] as String?) ?? '',
        fileName: (json['fileName'] as String?) ?? 'file',
        size: (json['size'] as num?)?.toInt() ?? 0,
        fileType:
            (json['fileType'] as String?) ?? 'application/octet-stream',
        sha256: json['sha256'] as String?,
        preview: json['preview'] as String?,
      );
}

/// prepare-upload 请求：发送方信息 + 待传文件表（id → FileDto）。
class PrepareUploadRequest {
  const PrepareUploadRequest({required this.info, required this.files});

  final DeviceInfo info;
  final Map<String, FileDto> files;

  Map<String, dynamic> toJson() => {
        'info': info.toJson(),
        'files': files.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory PrepareUploadRequest.fromJson(Map<String, dynamic> json) {
    final files = <String, FileDto>{};
    final raw = (json['files'] as Map?) ?? const {};
    raw.forEach((k, v) {
      files['$k'] = FileDto.fromJson(Map<String, dynamic>.from(v as Map));
    });
    return PrepareUploadRequest(
      info: DeviceInfo.fromJson(
        Map<String, dynamic>.from((json['info'] as Map?) ?? const {}),
      ),
      files: files,
    );
  }
}

/// prepare-upload 应答：会话 id + 每文件的上传 token（id → token）。
class PrepareUploadResponse {
  const PrepareUploadResponse({required this.sessionId, required this.files});

  final String sessionId;
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'files': files,
      };

  factory PrepareUploadResponse.fromJson(Map<String, dynamic> json) {
    final files = <String, String>{};
    final raw = (json['files'] as Map?) ?? const {};
    raw.forEach((k, v) => files['$k'] = '$v');
    return PrepareUploadResponse(
      sessionId: (json['sessionId'] as String?) ?? '',
      files: files,
    );
  }
}

/// 组播 announce 报文：设备信息 + 是否要求对端回应。
class MulticastAnnounce {
  const MulticastAnnounce({required this.device, required this.announce});

  final DeviceInfo device;
  final bool announce;

  Map<String, dynamic> toJson() => {
        'device': device.toJson(),
        'announce': announce,
      };

  factory MulticastAnnounce.fromJson(Map<String, dynamic> json) =>
      MulticastAnnounce(
        device: DeviceInfo.fromJson(
          Map<String, dynamic>.from((json['device'] as Map?) ?? const {}),
        ),
        announce: (json['announce'] as bool?) ?? false,
      );
}
