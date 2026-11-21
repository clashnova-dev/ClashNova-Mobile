import 'package:airport_mobile/core/latency.dart';
import 'package:flutter_test/flutter_test.dart';

LatencyTarget _target(String id, String? type, {bool testable = true}) =>
    LatencyTarget(id: id, tag: 'tag-$id', type: type, testable: testable);

void main() {
  test('udp protocols are not measured with a tcp handshake', () {
    expect(nodeUsesUdp('hysteria2'), isTrue);
    expect(nodeUsesUdp('HY2'), isTrue);
    expect(nodeUsesUdp('hysteria'), isTrue);
    expect(nodeUsesUdp('tuic'), isTrue);
    expect(nodeUsesUdp('wireguard'), isTrue);
    expect(nodeUsesUdp('vmess'), isFalse);
    expect(nodeUsesUdp('trojan'), isFalse);
    expect(nodeUsesUdp(null), isFalse);
  });

  group('planLatency', () {
    final nodes = [
      _target('a', 'vmess'),
      _target('b', 'hysteria2'),
      _target('c', 'tuic'),
      _target('d', 'trojan'),
      _target('e', 'vless', testable: false),
    ];

    test('connected measures every testable node, including UDP, through the tunnel', () {
      final plan = planLatency(nodes, connected: true);
      expect(plan.throughTunnel, isTrue);
      expect(plan.measure.map((n) => n.id), ['a', 'b', 'c', 'd']);
      expect(plan.skippedUdp, isEmpty);
    });

    test('disconnected handshakes TCP nodes and skips UDP-only ones', () {
      final plan = planLatency(nodes, connected: false);
      expect(plan.throughTunnel, isFalse);
      expect(plan.measure.map((n) => n.id), ['a', 'd']);
      expect(plan.skippedUdp.map((n) => n.id), ['b', 'c']);
    });

    test('untestable nodes are never measured', () {
      expect(
        planLatency(nodes, connected: true).measure.any((n) => n.id == 'e'),
        isFalse,
      );
    });
  });

  group('keepPolling', () {
    test('keeps waiting only while results are pending', () {
      expect(
        keepPolling(pending: true, cancelled: false, deadlinePassed: false),
        isTrue,
      );
      expect(
        keepPolling(pending: false, cancelled: false, deadlinePassed: false),
        isFalse,
      );
    });

    test('cancellation stops the loop immediately', () {
      expect(
        keepPolling(pending: true, cancelled: true, deadlinePassed: false),
        isFalse,
      );
    });

    test('a real timeout stops the loop', () {
      expect(
        keepPolling(pending: true, cancelled: false, deadlinePassed: true),
        isFalse,
      );
    });
  });
}
