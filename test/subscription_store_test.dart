import 'dart:convert';

import 'package:airport_mobile/core/subscription_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailedWrite extends FlutterSecureStorage {
  const FailedWrite();
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('locked');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final encoded = jsonEncode({
    'name': 'old subscription',
    'url': 'https://example.com/sub?token=synthetic',
    'outbounds': [
      {'type': 'trojan', 'tag': 'node', 'password': 'synthetic'},
    ],
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'externalSubs': [encoded],
      'activeSubKey': 'ext:https://example.com/sub?token=synthetic',
      'selectedNodeId': 'node',
      'chain': <String>[],
      'themeMode': 'dark',
    });
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'migrates old credentials without loss then removes plaintext copies',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SubscriptionStore();
      final data = await store.load(prefs);
      expect((data['externalSubs'] as List).single, encoded);
      expect(data['selectedNodeId'], 'node');
      for (final name in SubscriptionStore.legacyKeys) {
        expect(prefs.containsKey(name), isFalse);
      }
      expect(prefs.getString('themeMode'), 'dark');
      expect(await SubscriptionStore().load(prefs), data);
    },
  );

  test('failed migration retains every legacy value', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      SubscriptionStore(storage: const FailedWrite()).load(prefs),
      throwsStateError,
    );
    expect(prefs.getStringList('externalSubs'), [encoded]);
    expect(prefs.getString('selectedNodeId'), 'node');
  });

  test(
    'corrupt secure data does not overwrite or delete legacy data',
    () async {
      FlutterSecureStorage.setMockInitialValues({SubscriptionStore.key: '{}'});
      final prefs = await SharedPreferences.getInstance();
      await expectLater(SubscriptionStore().load(prefs), throwsFormatException);
      expect(prefs.getStringList('externalSubs'), [encoded]);
      expect(
        await const FlutterSecureStorage().read(key: SubscriptionStore.key),
        '{}',
      );
    },
  );

  test(
    'rapid preference changes retain the latest complete snapshot',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SubscriptionStore();
      final data = await store.load(prefs);
      await Future.wait([
        store.save({...data, 'selectedNodeId': 'first'}),
        store.save({...data, 'selectedNodeId': 'last'}),
      ]);
      expect((await store.load(prefs))['selectedNodeId'], 'last');
    },
  );
}
