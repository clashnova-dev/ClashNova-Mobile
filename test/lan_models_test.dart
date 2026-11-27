import 'dart:convert';

import 'package:airport_mobile/core/lan/lan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DeviceInfo / MulticastAnnounce round-trip', () {
    const info = DeviceInfo(
      alias: 'Phone',
      fingerprint: 'abc123',
      deviceType: LanDeviceType.phone,
    );
    final json = info.toJson();
    expect(json['alias'], 'Phone');
    expect(json['deviceType'], 'phone');
    expect(json['protocol'], 'https');

    final back = DeviceInfo.fromJson(json);
    expect(back.deviceType, LanDeviceType.phone);
    expect(back.protocol, LanProtocol.https);
    expect(back.fingerprint, 'abc123');

    final ann = MulticastAnnounce.fromJson(
        MulticastAnnounce(device: info, announce: true).toJson());
    expect(ann.announce, true);
    expect(ann.device.fingerprint, 'abc123');
  });

  test('解析桌面端线上格式的 DeviceInfo（跨语言互通）', () {
    final json = jsonDecode(
            '{"alias":"ClashNova","version":"2.0","deviceType":"desktop","fingerprint":"3fac6746a376","port":53317,"protocol":"https","download":false}')
        as Map<String, dynamic>;
    final info = DeviceInfo.fromJson(json);
    expect(info.alias, 'ClashNova');
    expect(info.deviceType, LanDeviceType.desktop);
    expect(info.protocol, LanProtocol.https);
    expect(info.port, 53317);
    expect(info.fingerprint, '3fac6746a376');
  });

  test('PrepareUpload 请求/应答 round-trip', () {
    const req = PrepareUploadRequest(
      info: DeviceInfo(alias: 'a', fingerprint: 'f'),
      files: {
        'id1': FileDto(id: 'id1', fileName: 'x.bin', size: 100, sha256: 'dead'),
      },
    );
    final back = PrepareUploadRequest.fromJson(req.toJson());
    expect(back.files['id1']!.fileName, 'x.bin');
    expect(back.files['id1']!.size, 100);
    expect(back.files['id1']!.sha256, 'dead');

    const resp = PrepareUploadResponse(sessionId: 's1', files: {'id1': 'tok'});
    final rb = PrepareUploadResponse.fromJson(resp.toJson());
    expect(rb.sessionId, 's1');
    expect(rb.files['id1'], 'tok');
  });
}
