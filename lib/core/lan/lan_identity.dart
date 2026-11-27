import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 本机 TLS 身份：自签证书 + 私钥（PEM），以及证书指纹。
///
/// 与桌面端 airport-lan 协议一致：fingerprint = 证书 DER 的 SHA-256（小写 hex），
/// LocalSend HTTPS 模式据此 pin 对端证书（TOFU）。证书与私钥持久化于安全存储，
/// 重启复用（指纹不变 = 对端配对记录持续有效）。
class LanIdentity {
  LanIdentity({
    required this.certPem,
    required this.keyPem,
    required this.fingerprint,
  });

  final String certPem;
  final String keyPem;

  /// 证书 DER 的 SHA-256（小写 hex，64 字符）。
  final String fingerprint;

  static const _certKey = 'lan_identity_cert_pem';
  static const _keyKey = 'lan_identity_key_pem';

  /// 接收端 HTTPS 用的 TLS 配置（自签证书 + 私钥）。只构建一次。
  late final SecurityContext securityContext = _buildContext(withTrustedRoots: true);

  /// 客户端用的 TLS 配置：出示本机证书（供对端强制 mTLS 校验），不信任系统根证书
  /// （对端自签证书由 badCertificateCallback 按指纹 pin）。只构建一次。
  late final SecurityContext clientContext = _buildContext(withTrustedRoots: false);

  SecurityContext _buildContext({required bool withTrustedRoots}) {
    final ctx = SecurityContext(withTrustedRoots: withTrustedRoots);
    ctx.useCertificateChainBytes(utf8.encode(certPem));
    ctx.usePrivateKeyBytes(utf8.encode(keyPem));
    return ctx;
  }

  /// 从安全存储加载，没有则生成并持久化。
  static Future<LanIdentity> loadOrCreate([FlutterSecureStorage? storage]) async {
    final store = storage ?? const FlutterSecureStorage();
    String? certPem;
    String? keyPem;
    try {
      certPem = await store.read(key: _certKey);
      keyPem = await store.read(key: _keyKey);
    } catch (_) {
      // 安全存储不可用（如测试环境）→ 下面生成临时身份。
    }
    if (certPem != null &&
        keyPem != null &&
        certPem.contains('CERTIFICATE') &&
        keyPem.contains('PRIVATE KEY')) {
      return LanIdentity(
        certPem: certPem,
        keyPem: keyPem,
        fingerprint: fingerprintOfPem(certPem),
      );
    }
    final id = await generate();
    try {
      await store.write(key: _certKey, value: id.certPem);
      await store.write(key: _keyKey, value: id.keyPem);
    } catch (_) {/* 持久化失败不致命，本次会话内可用 */}
    return id;
  }

  /// 生成一套新的自签身份（ECDSA P-256 + 自签 X509）。
  ///
  /// 用椭圆曲线而非 RSA：密钥生成近乎瞬时（一次标量乘，对比 RSA 的素数搜索），
  /// debug/JIT 下首启不再卡数十秒；证书更小、TLS 握手更快。协议不受影响——
  /// 指纹仍是证书 DER 的 SHA-256，对端按 TOFU pin，不关心密钥类型。
  /// 仍放到后台 isolate 以免偶发抖动卡 UI。
  static Future<LanIdentity> generate() async {
    final data = await compute(_generateIdentityData, 'clashnova.local');
    return LanIdentity(
      certPem: data['cert']!,
      keyPem: data['key']!,
      fingerprint: data['fp']!,
    );
  }

  /// 证书 PEM → DER 的 SHA-256 指纹（小写 hex）。
  static String fingerprintOfPem(String certPem) =>
      sha256.convert(pemToDer(certPem)).toString();

  /// 从 PEM 文本还原 DER 字节（取 BEGIN/END 之间的 base64）。
  static Uint8List pemToDer(String pem) {
    final body = pem
        .split(RegExp(r'\r?\n'))
        .where((l) => l.isNotEmpty && !l.contains('-----'))
        .join();
    return base64.decode(body);
  }
}

/// isolate 内生成身份数据（纯 Dart，无平台通道，可在 isolate 运行）。
/// ECDSA P-256（prime256v1）自签证书 + SEC1 私钥 PEM。
Map<String, String> _generateIdentityData(String cn) {
  final pair = CryptoUtils.generateEcKeyPair(); // 默认 prime256v1
  final priv = pair.privateKey as ECPrivateKey;
  final pub = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem({'CN': cn}, priv, pub);
  final certPem = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
  final keyPem = CryptoUtils.encodeEcPrivateKeyToPem(priv);
  final fp = sha256.convert(LanIdentity.pemToDer(certPem)).toString();
  return {'cert': certPem, 'key': keyPem, 'fp': fp};
}
