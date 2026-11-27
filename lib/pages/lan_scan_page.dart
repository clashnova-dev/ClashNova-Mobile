import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_state.dart';
import '../core/lan/lan_qr.dart';
import '../theme.dart';

/// 扫描对端的局域网二维码，成功后 pop 返回解析出的 [LanQrPayload]。
class LanScanPage extends StatefulWidget {
  const LanScanPage({super.key});

  @override
  State<LanScanPage> createState() => _LanScanPageState();
}

class _LanScanPageState extends State<LanScanPage> {
  var _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final p = LanQrPayload.parse(code.rawValue ?? '');
      if (p == null) continue;
      _done = true;
      Navigator.pop(context, p);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).t;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(t('lan.scanTitle')),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final denied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppMetrics.pad),
                  child: Text(
                    denied ? t('subs.cameraDenied') : t('subs.scanFailed'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
              child: Text(
                t('lan.scanHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
