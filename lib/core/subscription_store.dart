import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps provider tokens and node credentials out of ordinary preferences.
/// Runtime configuration copies managed by libbox still use its OS sandbox.
class SubscriptionStore {
  SubscriptionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );
  final FlutterSecureStorage _storage;
  static const key = 'airport.subscription-state.v1';
  static const legacyKeys = [
    'externalSubs',
    'activeSubKey',
    'selectedNodeId',
    'chain',
  ];
  Future<void> _writes = Future.value();

  Future<Map<String, dynamic>> load(SharedPreferences prefs) async {
    final raw = await _storage.read(key: key);
    Map<String, dynamic> data;
    if (raw != null) {
      // A corrupt secure record must not be silently replaced with defaults.
      data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } else {
      data = {
        'externalSubs': prefs.getStringList('externalSubs') ?? <String>[],
        'activeSubKey': prefs.getString('activeSubKey'),
        'selectedNodeId': prefs.getString('selectedNodeId') ?? '',
        'chain': prefs.getStringList('chain') ?? <String>[],
      };
      _validate(data);
      await save(data);
      if (await _storage.read(key: key) != jsonEncode(data)) {
        throw StateError('secure storage verification failed');
      }
    }
    _validate(data);
    // Crash-safe retry: never delete old values before verified secure storage.
    for (final name in legacyKeys) {
      if (!await prefs.remove(name)) throw StateError('legacy cleanup failed');
    }
    return data;
  }

  static void _validate(Map<String, dynamic> data) {
    if (data['selectedNodeId'] is! String ||
        (data['activeSubKey'] != null && data['activeSubKey'] is! String) ||
        data['chain'] is! List ||
        !(data['chain'] as List).every((v) => v is String) ||
        data['externalSubs'] is! List) {
      throw const FormatException('invalid subscription store');
    }
    for (final encoded in data['externalSubs'] as List) {
      final sub = jsonDecode(encoded as String);
      if (sub is! Map ||
          sub['url'] is! String ||
          sub['name'] is! String ||
          (sub['outbounds'] != null && sub['outbounds'] is! List)) {
        throw const FormatException('invalid subscription entry');
      }
    }
  }

  Future<void> save(Map<String, dynamic> data) {
    _validate(data);
    final encoded = jsonEncode(data);
    final next = _writes
        .catchError((Object _) {})
        .then((_) => _storage.write(key: key, value: encoded));
    _writes = next;
    return next;
  }
}
