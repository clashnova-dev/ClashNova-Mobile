import 'dart:convert';
import 'dart:io';

enum Phase { idle, preparing, connecting, connected, reconnecting, disconnecting, failed }

enum ConnEvent { start, coreSpawned, coreReady, coreExited, stop, stopped, fail }

const phaseNames = {
  Phase.idle: 'IDLE',
  Phase.preparing: 'PREPARING',
  Phase.connecting: 'CONNECTING',
  Phase.connected: 'CONNECTED',
  Phase.reconnecting: 'RECONNECTING',
  Phase.disconnecting: 'DISCONNECTING',
  Phase.failed: 'FAILED',
};

const eventNames = {
  ConnEvent.start: 'start',
  ConnEvent.coreSpawned: 'core_spawned',
  ConnEvent.coreReady: 'core_ready',
  ConnEvent.coreExited: 'core_exited',
  ConnEvent.stop: 'stop',
  ConnEvent.stopped: 'stopped',
  ConnEvent.fail: 'fail',
};

class ConnectionMachine {
  ConnectionMachine(this.transitions);
  final Map<String, String> transitions;

  static Future<ConnectionMachine> load() async {
    final file = File('${Directory.current.path}/contracts/connection-state.vectors.json');
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final transitions = <String, String>{};
    for (final item in raw['transitions'] as List<dynamic>) {
      final row = item as Map<String, dynamic>;
      transitions['${row['from']}|${row['event']}'] = row['to'] as String;
    }
    return ConnectionMachine(transitions);
  }

  Phase reduce(Phase from, ConnEvent event) {
    final next = transitions['${phaseNames[from]}|${eventNames[event]}'];
    if (next == null) {
      throw StateError('非法连接转移 $from + $event');
    }
    return phaseNames.entries.firstWhere((entry) => entry.value == next).key;
  }
}
