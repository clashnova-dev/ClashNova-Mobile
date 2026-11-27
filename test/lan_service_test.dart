import 'dart:io';

import 'package:airport_mobile/core/lan/lan_identity.dart';
import 'package:airport_mobile/core/lan/lan_models.dart';
import 'package:airport_mobile/core/lan/lan_service.dart';
import 'package:airport_mobile/core/lan/lan_storage.dart';
import 'package:airport_mobile/core/lan/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _until(bool Function() cond, {int tries = 150}) async {
  for (var i = 0; i < tries; i++) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('condition not met in time');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LanService：配对请求→接受→可信；配对后自动接收文件与文本；会话分线', () async {
    HttpOverrides.global = null; // 走真实环回网络
    SharedPreferences.setMockInitialValues({});

    final recvDir = await Directory.systemTemp.createTemp('svc_recv');
    final sendDir = await Directory.systemTemp.createTemp('svc_send');
    final storage = await LanStorage.open();
    final svc = LanService(storage: storage, defaultSaveDir: recvDir.path);
    await svc.start(port: 0, discover: false);
    final base = 'https://127.0.0.1:${svc.receiverPort}';
    final recvFp = svc.local.fingerprint;

    const sender = DeviceInfo(
        alias: 'Sender', fingerprint: 'sender-fp', deviceType: LanDeviceType.mobile);
    final clientId = await LanIdentity.generate(); // 发送方（客户端）身份，供 mTLS 出示

    // —— 配对：发起 pair，收端弹 pairRequest，用户接受 ——
    final pairFuture = sendPair(
        baseUrl: base, sender: sender, identity: clientId, expectedFingerprint: recvFp);
    await _until(() => svc.pairRequest != null);
    expect(svc.pairRequest!.peer.fingerprint, 'sender-fp');
    svc.respondPair(svc.pairRequest!.requestId, true);
    expect(await pairFuture, true);
    expect(svc.trusted.any((t) => t.fingerprint == 'sender-fp'), true);

    // —— 配对后发文件：自动接收，无需再确认，SHA-256 校验落盘 ——
    final src = File('${sendDir.path}/paired.bin');
    final payload = List<int>.generate(80 * 1024, (i) => (i * 3) & 0xff);
    await src.writeAsBytes(payload);
    await sendFile(
        baseUrl: base, sender: sender, file: src, identity: clientId, expectedFingerprint: recvFp);

    await _until(() => svc.conversation('sender-fp').any((m) => m.isFile));
    final fileMsg =
        svc.conversation('sender-fp').firstWhere((m) => m.isFile);
    expect(fileMsg.outgoing, false);
    expect(fileMsg.state, 'completed');
    expect(fileMsg.savePath, isNotNull);
    expect(await File(fileMsg.savePath!).readAsBytes(), payload);

    // —— 配对后发文本：自动接收，会话加一条文本 ——
    await sendTextTo(
        baseUrl: base,
        sender: sender,
        id: 'txt1',
        text: '收到了吗',
        identity: clientId,
        expectedFingerprint: recvFp);
    await _until(
        () => svc.conversation('sender-fp').any((m) => m.text == '收到了吗'));

    // 会话按时间正序，含文件与文本各一条。
    final conv = svc.conversation('sender-fp');
    expect(conv.where((m) => m.isFile).length, 1);
    expect(conv.where((m) => m.text != null).length, 1);

    await svc.stop();
    await recvDir.delete(recursive: true);
    await sendDir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
