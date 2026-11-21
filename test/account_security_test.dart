import 'dart:convert';

import 'package:airport_mobile/app_state.dart';
import 'package:airport_mobile/core/mobile_http.dart';
import 'package:airport_mobile/core/sing_box_core.dart';
import 'package:airport_mobile/connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class LogoutCore extends SingBoxCore {
  LogoutCore({this.fail = false});
  final bool fail;
  int stopped = 0;
  @override
  Future<void> disconnect() async {
    stopped++;
    if (fail) throw StateError('stop failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('logout waits for VPN shutdown', () async {
    final core = LogoutCore();
    final state = AppState(core: core)..coreReady = true..phase = Phase.connected;
    expect(await state.logout(), isTrue);
    expect(core.stopped, 1);
    expect(state.phase, Phase.idle);
    state.dispose();
  });
  test('failed VPN shutdown never reports a successful idle logout', () async {
    final core = LogoutCore(fail: true);
    final state = AppState(core: core)..coreReady = true..phase = Phase.connected;
    expect(await state.logout(), isFalse);
    expect(state.phase, Phase.connected);
    expect(state.busy, isFalse);
    state.dispose();
  });
  test('changing login hosts does not leak the old session token', () async {
    var loginCount = 0;
    final state = AppState(
      transport: MobileHttp(
        clientFactory: () => MockClient((req) async {
          if (req.url.path.endsWith('/login')) {
            loginCount++;
            expect(req.headers['authorization'], isNull);
            return http.Response(
              jsonEncode({
                'data': {
                  'tokens': {'accessToken': 'synthetic-$loginCount'},
                },
              }),
              200,
            );
          }
          expect(req.headers['authorization'], 'Bearer synthetic-$loginCount');
          return http.Response('{"data":[]}', 200);
        }),
      ),
    );
    await state.login('https://first.example', 'user@example.com', 'synthetic');
    expect(state.loggedIn, isTrue);
    await state.login(
      'https://second.example',
      'other@example.com',
      'synthetic',
    );
    expect(state.loggedIn, isTrue);
    expect(loginCount, 2);
    state.dispose();
  });
}
