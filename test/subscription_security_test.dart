import 'dart:convert';

import 'package:airport_mobile/core/security.dart';
import 'package:airport_mobile/core/sing_box_core.dart';
import 'package:airport_mobile/core/subscription_parser.dart';
import 'package:airport_mobile/mobile_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file reads and executable plugins fail before reaching native VPN', () {
    for (final extra in [
      {
        'tls': {'private_key_path': '/private/key.pem'},
      },
      {'plugin': '/bin/command'},
      {
        'transport': {'script': 'run'},
      },
      {'certificate_path': '/private/cert.pem'},
    ]) {
      final outbounds = [
        {
          'type': 'trojan',
          'tag': 'node',
          'server': 'example.com',
          'server_port': 443,
          'password': 'synthetic',
          ...extra,
        },
      ];
      expect(
        () => SubscriptionParser.parse(jsonEncode(outbounds)),
        throwsA(isA<MobileSecurityException>()),
      );
      expect(
        () => SingBoxCore().connectOutbounds(outbounds),
        throwsA(isA<MobileSecurityException>()),
      );
    }
  });

  test('transport URI paths and inline TLS certificates are permitted', () {
    expect(
      () => validateProxyOutbounds([
        {
          'type': 'trojan',
          'tag': 'node',
          'transport': {'type': 'ws', 'path': '/websocket'},
          'tls': {
            'certificate': ['inline synthetic certificate'],
          },
        },
      ]),
      returnsNormally,
    );
  });

  test('direct/group entries cannot masquerade as node proxies', () {
    final proxies = extractProxyOutbounds({
      'outbounds': [
        {'type': 'direct', 'tag': 'node-bypass'},
        {'type': 'selector', 'tag': 'node-group'},
        {'type': 'trojan', 'tag': 'node-real'},
      ],
    });
    expect(proxies.map((p) => p['tag']), ['node-real']);
    expect(
      () => validateProxyOutbounds([
        {'type': 'direct', 'tag': 'node-bypass'},
      ]),
      throwsA(isA<MobileSecurityException>()),
    );
  });

  test(
    'size, nesting and node-count limits reject resource-exhaustion input',
    () {
      expect(
        () => SubscriptionParser.parse('x' * (maxSubscriptionBytes + 1)),
        throwsA(isA<MobileSecurityException>()),
      );
      expect(
        () => validateProxyOutbounds(
          List.generate(maxProxyNodes + 1, (_) => {'type': 'trojan'}),
        ),
        throwsA(isA<MobileSecurityException>()),
      );
      Object nested = 'value';
      for (var i = 0; i < 40; i++) {
        nested = {'next': nested};
      }
      expect(
        () => validateProxyOutbounds([
          {'type': 'trojan', 'extra': nested},
        ]),
        throwsA(isA<MobileSecurityException>()),
      );
      final yaml =
          'proxies:\n  - {name: n, type: trojan, server: e.com, port: 443, password: p}\nextra: ${'[' * 40}0${']' * 40}';
      expect(
        () => SubscriptionParser.parse(yaml),
        throwsA(isA<MobileSecurityException>()),
      );
    },
  );
}
