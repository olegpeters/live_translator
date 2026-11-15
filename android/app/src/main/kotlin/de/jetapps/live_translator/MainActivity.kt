package de.jetapps.live_translator

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pcmPlayer: PcmStreamPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pcmPlayer = PcmStreamPlayer(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "live_translator/platform")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startForegroundService" -> {
                            TranslationForegroundService.start(applicationContext)
                            result.success(null)
                        }
                        "stopForegroundService" -> {
                            TranslationForegroundService.stop(applicationContext)
                            result.success(null)
                        }
                        "isHeadphoneConnected" -> result.success(isHeadphoneConnected())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("platform_error", e.message, null)
                }
            }
    }

    private fun isHeadphoneConnected(): Boolean {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val headphoneTypes = mutableSetOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            headphoneTypes += AudioDeviceInfo.TYPE_BLE_HEADSET
        }
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type in headphoneTypes }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pcmPlayer?.dispose()
        pcmPlayer = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
