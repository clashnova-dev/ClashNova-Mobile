import 'dart:convert';

import 'package:sing_box/sing_box.dart';

import '../connection.dart';
import 'latency.dart';
import 'security.dart';
import 'subscription_parser.dart';

/// Thin wrapper over the `sing_box` plugin: tunnel control + state/stats/logs
/// streams, and mapping of the plugin status to the shared [Phase] machine.
class SingBoxCore {
  final SingBox _sb = SingBox.instance;

  /// App Group and Packet Tunnel bundle id shared with the iOS Network
  /// Extension (see `ios/PacketTunnel/*`, scaffolded by the plugin's
  /// `add_packet_tunnel.rb`). These match the plugin defaults
  /// (`group.<bundle>` / `<bundle>.PacketTunnel`) but are stated explicitly so
  /// the app<->extension contract is visible in one place.
  static const String iosAppGroup = 'group.dev.airport.airportMobile';
  static const String iosTunnelBundleId = 'dev.airport.airportMobile.PacketTunnel';

  Future<void> initialize() => _sb.initialize(
        const SingBoxOptions(
          ios: SingBoxIosOptions(
            appGroup: iosAppGroup,
            tunnelBundleIdentifier: iosTunnelBundleId,
            profileName: 'ClashNova',
          ),
        ),
      );

  bool get isConnected => _sb.isConnected;
  SingBoxConnectionStatus get status => _sb.status;

  Stream<SingBoxConnectionState> watchState() => _sb.watchConnectionState();
  Stream<SingBoxConnectionStats> watchStats() => _sb.watchConnectionStats();
  Stream<List<SingBoxLogEntry>> watchLogBuffer({int maxEntries = 500}) =>
      _sb.watchLogBuffer(maxEntries: maxEntries);
  Stream<List<SingBoxConnection>> watchConnections() => _sb.watchConnections();
  Future<void> closeConnection(String id) => _sb.closeConnection(id);
  Future<void> closeAllConnections() => _sb.closeAllConnections();

  /// Clash routing mode (Rule / Global / Direct). The config builder enables
  /// these by default, so they are live whenever the tunnel is up.
  Stream<SingBoxClashMode> watchClashMode() => _sb.watchClashMode();
  Future<void> setClashMode(String mode) => _sb.setClashMode(mode);

  /// Map the plugin tunnel status to the app's connection [Phase].
  static Phase phaseOf(SingBoxConnectionStatus status) {
    switch (status) {
      case SingBoxConnectionStatus.connected:
        return Phase.connected;
      case SingBoxConnectionStatus.connecting:
        return Phase.connecting;
      case SingBoxConnectionStatus.disconnecting:
        return Phase.disconnecting;
      case SingBoxConnectionStatus.disconnected:
        return Phase.idle;
    }
  }

  /// Connect with a list of sing-box outbound JSON objects (node proxies). The
  /// plugin's config builder wraps them with TUN/DNS/routing and a
  /// selector + urltest group, so node selection and auto-pick work natively.
  Future<void> connectOutbounds(
    List<Map<String, dynamic>> outbounds, {
    String? selectedTag,
  }) {
    validateProxyOutbounds(outbounds);
    return _sb.connect(jsonEncode(outbounds), selectedTag: selectedTag);
  }

  /// Connect with one or more share links / a base64 subscription (external
  /// generic subscription in local mode).
  Future<void> connectShareLinks(String links) =>
      connectOutbounds(SubscriptionParser.parse(links));

  Future<void> disconnect() => _sb.disconnect();

  /// Instant server switch inside the running selector group (no reconnect).
  Future<void> select(String outboundTag) =>
      _sb.selectOutbound(SingBoxConfigBuilder.proxyTag, outboundTag);

  /// Measure each [tags] outbound through the running tunnel. Hysteria2 and TUIC
  /// only answer UDP, so a TCP handshake to their port cannot succeed.
  ///
  /// [onResult] fires as each tag gets a fresh result. A negative delay means
  /// the URL test failed. Tags still pending when [timeout] elapses are reported
  /// as failures.
  Future<void> urlTestDelays(
    List<String> tags, {
    Duration timeout = const Duration(seconds: 20),
    bool Function()? cancelled,
    void Function(String tag, int delayMs)? onResult,
  }) async {
    final pending = tags.where((tag) => tag.isNotEmpty).toSet();
    if (pending.isEmpty) return;
    final started = DateTime.now().subtract(const Duration(seconds: 1));
    final sub = _sb.watchOutbounds().listen((items) {
      for (final item in items) {
        if (!pending.contains(item.tag)) continue;
        final time = item.urlTestTime;
        if (time == null || time.isBefore(started)) continue;
        pending.remove(item.tag);
        onResult?.call(item.tag, item.urlTestDelay ?? -1);
      }
    });
    try {
      var started = false;
      if (pending.length > 1) {
        try {
          await _sb.urlTest(SingBoxConfigBuilder.autoTag);
          started = true;
        } catch (_) {
          for (final tag in pending.toList()) {
            try {
              await _sb.urlTest(tag);
              started = true;
            } catch (_) {}
          }
        }
      } else {
        await _sb.urlTest(pending.single);
        started = true;
      }
      if (!started) {
        throw StateError('url test did not start');
      }
      final deadline = DateTime.now().add(timeout);
      while (keepPolling(
        pending: pending.isNotEmpty,
        cancelled: cancelled?.call() == true,
        deadlinePassed: !DateTime.now().isBefore(deadline),
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (cancelled?.call() == true) return;
      for (final tag in pending.toList()) {
        onResult?.call(tag, -1);
      }
    } finally {
      await sub.cancel();
    }
  }
}
