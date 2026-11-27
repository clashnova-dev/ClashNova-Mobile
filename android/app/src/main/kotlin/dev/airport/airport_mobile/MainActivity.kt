package dev.airport.airport_mobile

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 局域网组播锁：WiFi 驱动默认过滤组播包，持锁后才能收到对端 announce。
                    "acquireMulticastLock" -> result.success(acquireMulticastLock())
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireMulticastLock(): Boolean {
        multicastLock?.let { if (it.isHeld) return true }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return false
        val lock = wifi.createMulticastLock("clashnova-lan").apply {
            setReferenceCounted(false)
            acquire()
        }
        multicastLock = lock
        return lock.isHeld
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "dev.airport/lan"
    }
}
