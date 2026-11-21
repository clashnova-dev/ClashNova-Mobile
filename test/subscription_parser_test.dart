import 'dart:convert';

import 'package:airport_mobile/core/subscription_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> byTag(List<Map<String, dynamic>> outs, String tag) =>
    outs.firstWhere((o) => o['tag'] == tag);

void main() {
  group('Clash YAML', () {
    const clash = '''
proxies:
  - name: "SS-US"
    type: ss
    server: us.example.com
    port: 8388
    cipher: aes-256-gcm
    password: pass123
  - name: "VMess-WS"
    type: vmess
    server: v.example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    alterId: 0
    cipher: auto
    tls: true
    servername: v.example.com
    network: ws
    ws-opts:
      path: /ray
      headers:
        Host: v.example.com
  - name: "VLESS-Reality"
    type: vless
    server: r.example.com
    port: 443
    uuid: 22222222-2222-2222-2222-222222222222
    network: tcp
    tls: true
    servername: www.microsoft.com
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: PUBKEY
      short-id: ab12
  - name: "Trojan-1"
    type: trojan
    server: t.example.com
    port: 443
    password: trojanpass
    sni: t.example.com
  - name: "Hy2"
    type: hysteria2
    server: h.example.com
    port: 443
    password: hypass
    sni: h.example.com
  - name: "Unknown-XYZ"
    type: some-unsupported
    server: x.example.com
    port: 1
''';

    test('parses supported proxies and skips unsupported', () {
      final outs = SubscriptionParser.parse(clash);
      // 5 supported, 1 unsupported skipped.
      expect(outs.length, 5);
      expect(outs.map((o) => o['tag']),
          containsAll(['SS-US', 'VMess-WS', 'VLESS-Reality', 'Trojan-1', 'Hy2']));
    });

    test('shadowsocks fields', () {
      final o = byTag(SubscriptionParser.parse(clash), 'SS-US');
      expect(o['type'], 'shadowsocks');
      expect(o['server'], 'us.example.com');
      expect(o['server_port'], 8388);
      expect(o['method'], 'aes-256-gcm');
      expect(o['password'], 'pass123');
    });

    test('vmess ws transport + tls', () {
      final o = byTag(SubscriptionParser.parse(clash), 'VMess-WS');
      expect(o['type'], 'vmess');
      expect(o['uuid'], '11111111-1111-1111-1111-111111111111');
      expect(o['alter_id'], 0);
      expect((o['tls'] as Map)['enabled'], true);
      expect((o['tls'] as Map)['server_name'], 'v.example.com');
      final tr = o['transport'] as Map;
      expect(tr['type'], 'ws');
      expect(tr['path'], '/ray');
      expect((tr['headers'] as Map)['Host'], 'v.example.com');
    });

    test('vless reality + flow + utls', () {
      final o = byTag(SubscriptionParser.parse(clash), 'VLESS-Reality');
      expect(o['type'], 'vless');
      expect(o['flow'], 'xtls-rprx-vision');
      final tls = o['tls'] as Map;
      expect((tls['reality'] as Map)['public_key'], 'PUBKEY');
      expect((tls['reality'] as Map)['short_id'], 'ab12');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
    });

    test('trojan + hysteria2 tls defaults on', () {
      final outs = SubscriptionParser.parse(clash);
      final trojan = byTag(outs, 'Trojan-1');
      expect(trojan['type'], 'trojan');
      expect(trojan['password'], 'trojanpass');
      expect((trojan['tls'] as Map)['server_name'], 't.example.com');
      final hy2 = byTag(outs, 'Hy2');
      expect(hy2['type'], 'hysteria2');
      expect(hy2['password'], 'hypass');
      expect((hy2['tls'] as Map)['enabled'], true);
    });

    test('duplicate names get suffixed unique tags', () {
      const dup = '''
proxies:
  - { name: Dup, type: trojan, server: a.com, port: 443, password: p }
  - { name: Dup, type: trojan, server: b.com, port: 443, password: p }
''';
      final outs = SubscriptionParser.parse(dup);
      expect(outs.length, 2);
      expect(outs.map((o) => o['tag']).toSet(), {'Dup', 'Dup (2)'});
    });
  });

  group('non-Clash formats delegate to the plugin parser', () {
    test('share-link list', () {
      const list = '''
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@s.example.com:8388#SS-Node
trojan://secret@t.example.com:443#Trojan-Node
''';
      final outs = SubscriptionParser.parse(list);
      expect(outs.length, 2);
      expect(outs.map((o) => o['type']), containsAll(['shadowsocks', 'trojan']));
    });

    test('base64-wrapped share-link list', () {
      const list =
          'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@s.example.com:8388#SS\n'
          'trojan://secret@t.example.com:443#Trojan';
      final b64 = base64.encode(utf8.encode(list));
      final outs = SubscriptionParser.parse(b64);
      expect(outs.length, 2);
    });

    test('sing-box config JSON keeps proxies, drops groups', () {
      const cfg =
          '{"outbounds":[{"type":"shadowsocks","tag":"n1","server":"a.com",'
          '"server_port":1080,"method":"aes-128-gcm","password":"p"},'
          '{"type":"selector","tag":"proxy","outbounds":["n1"]},'
          '{"type":"direct","tag":"direct"}]}';
      final outs = SubscriptionParser.parse(cfg);
      expect(outs.length, 1);
      expect(outs.first['type'], 'shadowsocks');
      expect(outs.first['tag'], 'n1');
    });

    test('empty content yields empty list', () {
      expect(SubscriptionParser.parse('   '), isEmpty);
    });
  });
}
