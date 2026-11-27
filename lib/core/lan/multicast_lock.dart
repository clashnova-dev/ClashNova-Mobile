import 'dart:io';

import 'package:flutter/services.dart';

/// Android 组播锁封装。
///
/// 安卓 WiFi 驱动默认丢弃组播包，要收到对端的 LocalSend announce 必须先持有
/// `WifiManager.MulticastLock`（需 CHANGE_WIFI_MULTICAST_STATE 权限）。其余平台
/// （iOS/桌面）无此限制，这里为 no-op；通道缺失（单元测试/宿主）时静默忽略。
class MulticastLock {
  const MulticastLock._();

  static const MethodChannel _ch = MethodChannel('dev.airport/lan');

  /// 获取组播锁（仅 Android 生效）。返回是否成功持锁。
  static Future<bool> acquire() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('acquireMulticastLock') ?? false;
    } catch (_) {
      return false; // 通道不可用 → 忽略，发现退化为 best-effort。
    }
  }

  /// 释放组播锁（仅 Android 生效）。
  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('releaseMulticastLock');
    } catch (_) {/* 忽略 */}
  }
}
