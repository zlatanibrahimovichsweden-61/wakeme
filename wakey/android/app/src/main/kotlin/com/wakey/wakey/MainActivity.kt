package com.wakey.wakey

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Channel shared with the Dart AlarmService. Dart toggles `alarmActive`
    // via setAlarmActive; while it's true we intercept the hardware volume
    // keys and tell Dart to dismiss the alarm instead of changing volume —
    // the same "press any key to silence" behaviour a real alarm clock has.
    private val channelName = "wakey/alarm_keys"
    private var methodChannel: MethodChannel? = null
    private var alarmActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarmActive" -> {
                    alarmActive = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (alarmActive &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            methodChannel?.invokeMethod("dismissAlarm", null)
            return true // consume the key so the volume doesn't change
        }
        return super.onKeyDown(keyCode, event)
    }
}
