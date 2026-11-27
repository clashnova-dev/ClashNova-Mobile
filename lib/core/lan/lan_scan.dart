import 'dart:io';

/// TCP 单播子网扫描目标/探活。
///
/// 组播被路由挡住、或本平台无组播权限（iOS）时，靠逐一探活本机各物理网卡 /24 内的
/// 主机来发现对端——纯单播 TCP，不依赖组播。探到开放端口后由上层拉 /info 登记。

/// 枚举本机各物理网卡 /24 内的候选地址（跳过本机自身）。
Future<List<InternetAddress>> scanTargets() async {
  final out = <InternetAddress>[];
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in ifaces) {
      for (final a in iface.addresses) {
        final b = a.rawAddress;
        final priv = b[0] == 10 ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168);
        if (!priv) continue;
        for (var host = 1; host <= 254; host++) {
          if (host == b[3]) continue; // 跳过本机
          out.add(InternetAddress('${b[0]}.${b[1]}.${b[2]}.$host'));
        }
      }
    }
  } catch (_) {}
  return out;
}

/// 轻量 TCP 探活：超时内能建连即认为该地址有接收端在监听。
Future<bool> probeTcp(InternetAddress addr, int port, Duration timeout) async {
  try {
    final sock = await Socket.connect(addr, port, timeout: timeout);
    sock.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
