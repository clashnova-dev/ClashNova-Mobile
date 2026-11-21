import 'package:airport_mobile/pages/scan_subscription_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads an https subscription link from a QR code', () {
    expect(
      subscriptionLinkFromQr('https://example.com/sub?token=1'),
      'https://example.com/sub?token=1',
    );
  });

  test('unwraps a clash install link', () {
    expect(
      subscriptionLinkFromQr('clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub'),
      'https://example.com/sub',
    );
  });

  test('rejects text that is not a subscription link', () {
    expect(subscriptionLinkFromQr('not a link'), isNull);
    expect(subscriptionLinkFromQr(''), isNull);
  });
}
