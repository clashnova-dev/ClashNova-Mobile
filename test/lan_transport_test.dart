import 'dart:io';

import 'package:airport_mobile/core/lan/lan_identity.dart';
import 'package:airport_mobile/core/lan/lan_models.dart';
import 'package:airport_mobile/core/lan/lan_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HTTPS 环回：发文件→接收端 SHA-256 校验落盘；指纹 pin 生效', () async {
    // 测试绑定会把 HttpClient mock 成返回 400，这里取消它以走真实环回网络。
    HttpOverrides.global = null;
    final id = await LanIdentity.generate();
    final saveDir = await Directory.systemTemp.createTemp('lan_recv');
    final sendDir = await Directory.systemTemp.createTemp('lan_send');
    final local = DeviceInfo(
        alias: 'recv', fingerprint: id.fingerprint, deviceType: LanDeviceType.desktop);

    ReceivedItem? received;
    final receiver = LanReceiver(
      identity: id,
      local: () => local,
      onDecideUpload: (sender, files) async => saveDir.path,
      onDecidePair: (sender) async => true,
      onDecideText: (sender, text) async => true,
      onDecideSync: (sender) async => null,
      onReceived: (item) => received = item,
    );
    await receiver.start(0); // 临时端口
    final base = 'https://127.0.0.1:${receiver.port}';

    final src = File('${sendDir.path}/report.bin');
    final payload = List<int>.generate(200 * 1024, (i) => (i * 7) & 0xff);
    await src.writeAsBytes(payload);
    const sender = DeviceInfo(
        alias: 'send', fingerprint: 'sender-fp', deviceType: LanDeviceType.phone);

    // 正确指纹：发送成功，接收端校验落盘。
    await sendFile(
        baseUrl: base,
        sender: sender,
        file: src,
        identity: id,
        expectedFingerprint: id.fingerprint);

    final got = await File('${saveDir.path}/report.bin').readAsBytes();
    expect(got, payload);
    expect(received?.ok, true);
    expect(received?.fileName, 'report.bin');
    expect(received?.savePath, '${saveDir.path}/report.bin');

    // 错误指纹：TLS 握手阶段即被拒（证明确实在 pin，而非仅加密）。
    var mismatchRejected = false;
    try {
      await sendFile(
          baseUrl: base, sender: sender, file: src, identity: id, expectedFingerprint: '0' * 64);
    } catch (_) {
      mismatchRejected = true;
    }
    expect(mismatchRejected, true);

    await receiver.stop();
    await saveDir.delete(recursive: true);
    await sendDir.delete(recursive: true);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
