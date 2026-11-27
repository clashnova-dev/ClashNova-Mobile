import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 已配对（可信）设备。配对即信任：`autoAccept` 默认开。
class TrustedDevice {
  const TrustedDevice({
    required this.fingerprint,
    required this.alias,
    this.platform,
    this.autoAccept = true,
    this.lastSeen = 0,
  });

  final String fingerprint;
  final String alias;
  final String? platform;
  final bool autoAccept;
  final int lastSeen;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'alias': alias,
        if (platform != null) 'platform': platform,
        'autoAccept': autoAccept,
        'lastSeen': lastSeen,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> j) => TrustedDevice(
        fingerprint: j['fingerprint'] as String? ?? '',
        alias: j['alias'] as String? ?? '',
        platform: j['platform'] as String?,
        autoAccept: j['autoAccept'] as bool? ?? true,
        lastSeen: (j['lastSeen'] as num?)?.toInt() ?? 0,
      );
}

/// 一条会话时间线记录（文本或文件），按 peer 指纹分线。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peerFingerprint,
    required this.outgoing,
    required this.timestamp,
    this.text,
    this.fileName,
    this.size = 0,
    this.state = 'completed',
    this.savePath,
  });

  final String id;
  final String peerFingerprint;
  final bool outgoing; // true=发送，false=接收
  final int timestamp; // epoch 秒
  final String? text; // null 表示文件
  final String? fileName;
  final int size;
  final String state; // completed / failed / sending / receiving / canceled
  final String? savePath;

  bool get isFile => text == null;

  ChatMessage copyWith({String? state, String? savePath}) => ChatMessage(
        id: id,
        peerFingerprint: peerFingerprint,
        outgoing: outgoing,
        timestamp: timestamp,
        text: text,
        fileName: fileName,
        size: size,
        state: state ?? this.state,
        savePath: savePath ?? this.savePath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'peer': peerFingerprint,
        'out': outgoing,
        'ts': timestamp,
        if (text != null) 'text': text,
        if (fileName != null) 'fileName': fileName,
        'size': size,
        'state': state,
        if (savePath != null) 'savePath': savePath,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        peerFingerprint: j['peer'] as String? ?? '',
        outgoing: j['out'] as bool? ?? false,
        timestamp: (j['ts'] as num?)?.toInt() ?? 0,
        text: j['text'] as String?,
        fileName: j['fileName'] as String?,
        size: (j['size'] as num?)?.toInt() ?? 0,
        state: j['state'] as String? ?? 'completed',
        savePath: j['savePath'] as String?,
      );
}

/// 本地 LAN 设置。
class LanSettings {
  LanSettings({
    this.alias = 'ClashNova',
    this.discoverable = true,
    this.acceptIncoming = true,
    this.autoAccept = true,
    this.saveDir = '',
  });

  String alias;
  bool discoverable;
  bool acceptIncoming;
  bool autoAccept;
  String saveDir;
}

/// 本地存储（shared_preferences，JSON）。可信设备 / 按设备会话 / 设置。
///
/// v1 用 shared_preferences 存 JSON（会话每设备上限 [_historyCap] 条）；后续可迁移
/// sqflite。测试中用 `SharedPreferences.setMockInitialValues({})` 走内存。
class LanStorage {
  LanStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _kTrusted = 'lan_trusted';
  static const _kHistoryPrefix = 'lan_history_';
  static const _kAlias = 'lan_alias';
  static const _kDiscoverable = 'lan_discoverable';
  static const _kAccept = 'lan_accept_incoming';
  static const _kAutoAccept = 'lan_auto_accept';
  static const _kSaveDir = 'lan_save_dir';
  static const _historyCap = 500;

  static Future<LanStorage> open() async =>
      LanStorage(await SharedPreferences.getInstance());

  // ———— 可信设备 ————

  List<TrustedDevice> listTrusted() {
    final raw = _prefs.getString(_kTrusted);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => TrustedDevice.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    } catch (_) {
      return [];
    }
  }

  Map<String, TrustedDevice> _trustedMap() =>
      {for (final t in listTrusted()) t.fingerprint: t};

  bool isTrusted(String fingerprint) =>
      fingerprint.isNotEmpty && _trustedMap().containsKey(fingerprint);

  bool autoAcceptFor(String fingerprint) =>
      _trustedMap()[fingerprint]?.autoAccept ?? false;

  Future<void> upsertTrusted(String fingerprint, String alias, String? platform) async {
    if (fingerprint.isEmpty) return;
    final map = _trustedMap();
    map[fingerprint] = TrustedDevice(
      fingerprint: fingerprint,
      alias: alias,
      platform: platform,
      autoAccept: true,
      lastSeen: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _saveTrusted(map.values.toList());
  }

  Future<void> removeTrusted(String fingerprint) async {
    final map = _trustedMap()..remove(fingerprint);
    await _saveTrusted(map.values.toList());
  }

  Future<void> _saveTrusted(List<TrustedDevice> list) =>
      _prefs.setString(_kTrusted, jsonEncode(list.map((t) => t.toJson()).toList()));

  // ———— 会话历史（按设备指纹分线）————

  List<ChatMessage> conversation(String fingerprint) {
    final raw = _prefs.getString('$_kHistoryPrefix$fingerprint');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> appendMessage(ChatMessage m) async {
    final list = conversation(m.peerFingerprint);
    // 去重（同 id）后追加；超出上限裁剪最旧。
    list.removeWhere((x) => x.id == m.id);
    list.add(m);
    if (list.length > _historyCap) {
      list.removeRange(0, list.length - _historyCap);
    }
    await _saveConversation(m.peerFingerprint, list);
  }

  Future<void> removeMessage(String fingerprint, String id) async {
    final list = conversation(fingerprint)..removeWhere((x) => x.id == id);
    await _saveConversation(fingerprint, list);
  }

  Future<void> _saveConversation(String fingerprint, List<ChatMessage> list) =>
      _prefs.setString(
        '$_kHistoryPrefix$fingerprint',
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );

  // ———— 设置 ————

  LanSettings loadSettings({required String defaultAlias, required String defaultSaveDir}) =>
      LanSettings(
        alias: _prefs.getString(_kAlias) ?? defaultAlias,
        discoverable: _prefs.getBool(_kDiscoverable) ?? true,
        acceptIncoming: _prefs.getBool(_kAccept) ?? true,
        autoAccept: _prefs.getBool(_kAutoAccept) ?? true,
        saveDir: _prefs.getString(_kSaveDir) ?? defaultSaveDir,
      );

  Future<void> saveSettings(LanSettings s) async {
    await _prefs.setString(_kAlias, s.alias);
    await _prefs.setBool(_kDiscoverable, s.discoverable);
    await _prefs.setBool(_kAccept, s.acceptIncoming);
    await _prefs.setBool(_kAutoAccept, s.autoAccept);
    await _prefs.setString(_kSaveDir, s.saveDir);
  }
}
