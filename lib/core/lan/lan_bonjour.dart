import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import 'lan_models.dart';

/// 全平台通用的 DNS-SD 服务类型（nsd 内部补 `.local` 域，和桌面 mdns-sd 的
/// `_localsend._tcp.local.` 为同一服务，跨端互通）。
const String _serviceType = '_localsend._tcp';

/// Bonjour / DNS-SD 发现（原生）。
///
/// iOS 走系统原生 Bonjour（NSNetService），**不需要 Apple 组播权限**（只要
/// Info.plist 配了 NSBonjourServices + 本地网络用途）；Android 走 NsdManager。
/// 注册本机 `_localsend._tcp` 服务（TXT 带指纹/别名/类型）并浏览对端，发现即回调。
class LanBonjour {
  LanBonjour({required this.local, required this.onPeer});

  final DeviceInfo local;
  final void Function(DeviceInfo info, String address) onPeer;

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;

  Future<void> start() async {
    // 注册本机服务（best-effort）。
    try {
      _registration = await nsd.register(nsd.Service(
        name: _instanceName(),
        type: _serviceType,
        port: local.port,
        txt: {
          'fp': _bytes(local.fingerprint),
          'alias': _bytes(local.alias),
          'type': _bytes(deviceTypeToString(local.deviceType)),
          'proto': _bytes('https'),
          'v': _bytes('2'),
        },
      ));
    } catch (_) {/* 注册失败不致命，仍可浏览 */}

    // 浏览对端（autoResolve + 查 IPv4 地址）。
    try {
      final disc = await nsd.startDiscovery(
        _serviceType,
        ipLookupType: nsd.IpLookupType.v4,
      );
      disc.addListener(() => _onServices(disc.services));
      _discovery = disc;
    } catch (_) {/* 发现不可用不致命 */}
  }

  void _onServices(List<nsd.Service> services) {
    for (final s in services) {
      final txt = s.txt;
      if (txt == null) continue;
      final fp = _str(txt['fp']);
      if (fp == null || fp.isEmpty || fp == local.fingerprint) continue;
      final addrs = s.addresses;
      if (addrs == null || addrs.isEmpty) continue;
      final v4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
      final address = (v4.isNotEmpty ? v4.first : addrs.first).address;
      onPeer(
        DeviceInfo(
          alias: _str(txt['alias']) ?? address,
          fingerprint: fp,
          deviceType: deviceTypeFromString(_str(txt['type'])),
          port: s.port ?? kDefaultPort,
          protocol: LanProtocol.https,
        ),
        address,
      );
    }
  }

  Future<void> stop() async {
    final r = _registration;
    final d = _discovery;
    _registration = null;
    _discovery = null;
    try {
      if (d != null) await nsd.stopDiscovery(d);
    } catch (_) {}
    try {
      if (r != null) await nsd.unregister(r);
    } catch (_) {}
  }

  // mDNS 实例名：别名 + 指纹短前缀，避免同名冲突；去掉不合规字符。
  String _instanceName() {
    final short = local.fingerprint.isEmpty
        ? '0000'
        : local.fingerprint.substring(0, local.fingerprint.length.clamp(0, 8));
    final alias = local.alias.replaceAll(RegExp(r'[.\\]'), '_').trim();
    return '${alias.isEmpty ? 'ClashNova' : alias}-$short';
  }
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

String? _str(Uint8List? b) => b == null ? null : utf8.decode(b, allowMalformed: true);
