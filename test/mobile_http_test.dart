import 'dart:async';

import 'package:airport_mobile/core/mobile_http.dart';
import 'package:airport_mobile/core/security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('release URLs require HTTPS without credentials or fragments', () {
    for (final value in [
      'http://example.com/sub',
      'http://127.0.0.1/sub',
      'file:///private/config',
      'https://name:secret@example.com',
      'https://example.com/#token',
    ]) {
      expect(
        () => MobileHttp.validateUri(
          Uri.parse(value),
          allowDevelopmentHttp: false,
        ),
        throwsA(isA<MobileSecurityException>()),
      );
    }
    expect(
      MobileHttp.validateUri(
        Uri.parse('https://example.com/sub?token=value'),
        allowDevelopmentHttp: false,
      ).host,
      'example.com',
    );
    expect(
      MobileHttp.validateUri(Uri.parse('http://10.0.2.2:8080/sub')).host,
      '10.0.2.2',
    );
    expect(
      MobileHttp.redirectAllowed(
        Uri.parse('https://example.com/sub'),
        Uri.parse('http://localhost/admin'),
      ),
      isFalse,
    );
    expect(
      MobileHttp.redirectAllowed(
        Uri.parse('http://localhost:8080/sub'),
        Uri.parse('http://localhost:8081/admin'),
      ),
      isFalse,
    );
  });

  test('API redirects never replay bearer tokens or password bodies', () async {
    var calls = 0;
    final transport = MobileHttp(
      clientFactory: () => MockClient((request) async {
        calls++;
        expect(request.followRedirects, isFalse);
        return http.Response(
          '',
          307,
          headers: {'location': 'https://other.example/steal'},
        );
      }),
    );
    await expectLater(
      transport.request(
        Uri.parse('https://api.example/login'),
        method: 'POST',
        headers: {'authorization': 'Bearer synthetic'},
        body: 'synthetic',
      ),
      throwsA(isA<MobileSecurityException>()),
    );
    expect(calls, 1);
  });

  test('subscription redirects are bounded and cannot downgrade', () async {
    var calls = 0;
    final transport = MobileHttp(
      clientFactory: () => MockClient((request) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://cdn.example/sub'},
        );
      }),
    );
    await expectLater(
      transport.request(
        Uri.parse('https://example.com/sub'),
        subscription: true,
      ),
      throwsA(isA<MobileSecurityException>()),
    );
    expect(calls, 4);
  });

  test('bounds unknown-length streaming responses and request time', () async {
    final transport = MobileHttp(
      clientFactory: () => MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          Stream.fromIterable([List.filled(8, 65), List.filled(8, 66)]),
          200,
        ),
      ),
    );
    await expectLater(
      transport.request(Uri.parse('https://example.com/sub'), maxBytes: 10),
      throwsA(isA<MobileSecurityException>()),
    );
    final stalled = MobileHttp(
      clientFactory: () => MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return http.Response('late', 200);
      }),
    );
    await expectLater(
      stalled.request(
        Uri.parse('https://example.com/?token=private'),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<MobileSecurityException>().having(
          (e) => e.toString(),
          'redacted',
          'msg.networkFailed',
        ),
      ),
    );
  });

  test('transport errors do not expose token URLs', () async {
    final transport = MobileHttp(
      clientFactory: () => MockClient((_) async {
        throw http.ClientException('failed https://example.com/?token=private');
      }),
    );
    await expectLater(
      transport.request(Uri.parse('https://example.com/sub')),
      throwsA(
        isA<MobileSecurityException>().having(
          (e) => e.toString(),
          'redacted',
          'msg.networkFailed',
        ),
      ),
    );
  });
}
