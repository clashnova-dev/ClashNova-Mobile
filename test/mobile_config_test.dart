import 'package:airport_mobile/mobile_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('提取节点 outbounds，保留凭证并丢弃非代理出站', () {
    final source = <String, dynamic>{
      'inbounds': [
        {'type': 'mixed', 'listen_port': 2080},
      ],
      'outbounds': [
        {
          'type': 'shadowsocks',
          'tag': 'node-abc',
          'method': 'aes-128-gcm',
          'password': 'secret',
        },
        {'type': 'selector', 'tag': 'select'},
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
      ],
      'route': {'final': 'select'},
    };
    final proxies = extractProxyOutbounds(source);
    expect(proxies, hasLength(1));
    expect(proxies.first['tag'], 'node-abc');
    expect(proxies.first['method'], 'aes-128-gcm');
    expect(proxies.first['password'], 'secret');
  });

  test('订阅无可用节点时抛出', () {
    expect(
      () => extractProxyOutbounds({
        'outbounds': [
          {'type': 'selector', 'tag': 'select'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      }),
      throwsStateError,
    );
    expect(() => extractProxyOutbounds({'outbounds': []}), throwsStateError);
  });

  test('仅模拟器开发地址改写本机订阅主机', () {
    expect(
      resolveSubscriptionURL('http://127.0.0.1:8080/sub/token', 'http://10.0.2.2:8080').host,
      '10.0.2.2',
    );
    expect(
      resolveSubscriptionURL('https://example.com/sub/token', 'http://10.0.2.2:8080').host,
      'example.com',
    );
  });
}
