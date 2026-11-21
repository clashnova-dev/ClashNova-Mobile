import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_state.dart';
import '../core/mobile_http.dart';
import '../theme.dart';

/// Pull a subscription URL out of a scanned code.
/// Accepts an http(s) link, or a wrapper such as clash://install-config?url=…
String? subscriptionLinkFromQr(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final direct = Uri.tryParse(text);
  if (direct != null && _isHttp(direct)) return direct.toString();
  final nested = direct?.queryParameters['url'];
  if (nested != null) {
    final inner = Uri.tryParse(nested);
    if (inner != null && _isHttp(inner)) return inner.toString();
  }
  return null;
}

bool _isHttp(Uri uri) {
  try {
    MobileHttp.validateUri(uri);
    return true;
  } catch (_) {
    return false;
  }
}

class ScanSubscriptionPage extends StatefulWidget {
  const ScanSubscriptionPage({super.key});

  @override
  State<ScanSubscriptionPage> createState() => _ScanSubscriptionPageState();
}

class _ScanSubscriptionPageState extends State<ScanSubscriptionPage> {
  var _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final link = subscriptionLinkFromQr(code.rawValue ?? '');
      if (link == null) continue;
      _done = true;
      Navigator.pop(context, link);
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
        title: Text(t('subs.scan')),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
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
                t('subs.scanHint'),
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
