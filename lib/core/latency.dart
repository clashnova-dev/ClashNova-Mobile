/// Shared latency-test model and planning, kept free of Flutter and plugin
/// dependencies so the rules can be unit-tested on both measurement paths.
///
/// A result is a delay in milliseconds, or a negative value when the node did
/// not answer — the same convention the desktop client uses for a failed probe.
library;

/// Protocols that listen on UDP only. A TCP handshake to their port always
/// fails, so they can only be measured by a real request through the node.
bool nodeUsesUdp(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'hysteria':
    case 'hysteria2':
    case 'hy2':
    case 'tuic':
    case 'wireguard':
      return true;
    default:
      return false;
  }
}

/// A node reduced to just what the latency test needs.
class LatencyTarget {
  const LatencyTarget({
    required this.id,
    required this.tag,
    required this.type,
    required this.testable,
  });

  final String id;

  /// The outbound tag used for a through-tunnel URL test.
  final String tag;

  /// Node protocol, used to tell UDP-only nodes apart.
  final String? type;

  /// False when the node has no host/port and cannot be probed at all.
  final bool testable;
}

/// What a latency run will do, decided up front so the UI message and the
/// measurement agree on the same set of nodes.
class LatencyPlan {
  const LatencyPlan({
    required this.throughTunnel,
    required this.measure,
    required this.skippedUdp,
  });

  /// Measure through the live tunnel (a real request per node) rather than a
  /// direct TCP handshake. The only path that can measure Hysteria2 / TUIC.
  final bool throughTunnel;

  /// Nodes that will be measured.
  final List<LatencyTarget> measure;

  /// UDP-only nodes left untested because the tunnel is down and nothing
  /// answers on TCP; the UI tells the user to connect first.
  final List<LatencyTarget> skippedUdp;
}

/// Decide which nodes to measure and how. While connected, every testable node
/// is measured through the tunnel. While disconnected, TCP protocols get a
/// direct handshake and UDP-only protocols are skipped.
LatencyPlan planLatency(Iterable<LatencyTarget> nodes, {required bool connected}) {
  final testable = nodes.where((n) => n.testable).toList();
  if (connected) {
    return LatencyPlan(throughTunnel: true, measure: testable, skippedUdp: const []);
  }
  return LatencyPlan(
    throughTunnel: false,
    measure: testable.where((n) => !nodeUsesUdp(n.type)).toList(),
    skippedUdp: testable.where((n) => nodeUsesUdp(n.type)).toList(),
  );
}

/// Whether a url-test poll loop should keep waiting: results are still pending,
/// the run has not been cancelled, and the deadline has not passed. Cancellation
/// and a real timeout both stop the loop; only pending work keeps it going.
bool keepPolling({
  required bool pending,
  required bool cancelled,
  required bool deadlinePassed,
}) =>
    pending && !cancelled && !deadlinePassed;
