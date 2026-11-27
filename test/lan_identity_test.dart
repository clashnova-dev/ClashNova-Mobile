import 'dart:io';

import 'package:airport_mobile/core/lan/lan_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成自签身份：64 位 hex 指纹，且证书可用于 TLS 服务端', () async {
    final id = await LanIdentity.generate();

    // 指纹 = 证书 DER 的 SHA-256（小写 hex）。
    expect(id.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(id.certPem, contains('CERTIFICATE'));
    expect(id.keyPem, contains('PRIVATE KEY'));

    // 关键：用生成的证书+私钥真正绑定一个 HTTPS 服务端（证明 TLS 配置有效）。
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      id.securityContext,
    );
    expect(server.port, greaterThan(0));
    await server.close(force: true);

    // 从 PEM 还原 DER 再算指纹应一致（持久化后用此法复算）。
    expect(LanIdentity.fingerprintOfPem(id.certPem), id.fingerprint);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
