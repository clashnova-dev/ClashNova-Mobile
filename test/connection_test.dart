import 'package:airport_mobile/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接状态机遵循合同', () async {
    final machine = await ConnectionMachine.load();
    expect(machine.reduce(Phase.idle, ConnEvent.start), Phase.preparing);
    expect(machine.reduce(Phase.preparing, ConnEvent.coreSpawned), Phase.connecting);
    expect(machine.reduce(Phase.connecting, ConnEvent.coreReady), Phase.connected);
    expect(machine.reduce(Phase.connected, ConnEvent.coreExited), Phase.reconnecting);
    expect(machine.reduce(Phase.connected, ConnEvent.stop), Phase.disconnecting);
    expect(machine.reduce(Phase.disconnecting, ConnEvent.stopped), Phase.idle);
    expect(machine.reduce(Phase.failed, ConnEvent.stop), Phase.idle);
    expect(() => machine.reduce(Phase.idle, ConnEvent.coreReady), throwsStateError);
  });
}
