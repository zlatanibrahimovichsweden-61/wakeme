package com.wakey.wakey

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Channel shared with the Dart side. Dart toggles `alarmActive` via
    // setAlarmActive; while it's true we (a) intercept the hardware volume keys
    // so they silence the alarm instead of changing volume, and (b) put the
    // activity over the lock screen + turn the screen on (the alarm-clock
    // behaviour). When false, the activity behaves like any normal app — so a
    // plain lock/unlock shows the system lock screen, not Wakey.
    private val channelName = "wakey/alarm_keys"
    private var methodChannel: MethodChannel? = null
    private var alarmActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A full-screen-intent launch on a locked phone lands here with the
        // arrived flag already set. Show over the keyguard + wake the screen
        // immediately so the alarm screen appears without a tap.
        if (isArrivedFlagSet()) applyLockScreenFlags(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Same as onCreate but for the warm path (activity already existed).
        if (isArrivedFlagSet()) applyLockScreenFlags(true)
    }

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
                    applyLockScreenFlags(alarmActive)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Put the activity over the keyguard and turn the screen on while the alarm
    // is ringing; clear both otherwise so normal lock/unlock is unaffected.
    private fun applyLockScreenFlags(show: Boolean) {
        runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(show)
                setTurnScreenOn(show)
            } else {
                val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                if (show) window.addFlags(flags) else window.clearFlags(flags)
            }
        }
    }

    private fun isArrivedFlagSet(): Boolean {
        val prefs = getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        return prefs.getBoolean("flutter.wakey.bg.arrived", false)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        ) {
            // alarmActive is set via the Dart MethodChannel, but on lock-screen
            // wake there's a race before Dart calls setAlarmActive. Fall back to
            // reading kArrivedFlag from SharedPreferences directly so volume
            // keys always work the moment the alarm fires.
            if (alarmActive || isArrivedFlagSet()) {
                methodChannel?.invokeMethod("dismissAlarm", null)
                return true // consume the key so the volume doesn't change
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
