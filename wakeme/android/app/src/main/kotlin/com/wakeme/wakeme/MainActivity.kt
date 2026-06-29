package com.wakeme.wakeme

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
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
    private val channelName = "wakeme/alarm_keys"
    private var methodChannel: MethodChannel? = null
    private var alarmActive = false
    // Set when we were launched purely to dismiss the alarm; we bounce the task
    // back in onResume (calling it in onCreate can be too early to take effect).
    private var pendingMoveToBack = false
    // Whether Wakey was already visible. A Dismiss tapped while we're foreground
    // must NOT background the app (req: keep the app open, just stop the alarm).
    private var inForeground = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Notification "Dismiss" tap: handle it entirely here (stop the alarm +
        // bounce straight back) so Wakey never visibly comes forward. Must run
        // before the lock-screen flags below, which would otherwise surface us.
        if (handleDismissLaunch(intent)) return
        // A full-screen-intent launch on a locked phone lands here with the
        // arrived flag already set. Show over the keyguard + wake the screen
        // immediately so the alarm screen appears without a tap.
        if (isArrivedFlagSet()) applyLockScreenFlags(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (handleDismissLaunch(intent)) return
        // Same as onCreate but for the warm path (activity already existed).
        if (isArrivedFlagSet()) applyLockScreenFlags(true)
    }

    override fun onResume() {
        super.onResume()
        inForeground = true
        if (pendingMoveToBack) {
            pendingMoveToBack = false
            moveTaskToBack(true)
        }
    }

    override fun onPause() {
        super.onPause()
        inForeground = false
    }

    // True (and fully handled) when the activity was launched by tapping the
    // alarm notification's "Dismiss" action. flutter_local_notifications routes
    // a showsUserInterface action through the launcher activity with this exact
    // action string + actionId extra. We stop the alarm natively (clearing the
    // armed flag the background service polls) instead of waiting for Flutter to
    // spin up — and never let the UI render, so there's no flicker.
    private fun handleDismissLaunch(launchIntent: Intent?): Boolean {
        if (launchIntent?.action != "SELECT_FOREGROUND_NOTIFICATION") return false
        if (launchIntent.getStringExtra("actionId") != "dismiss_alarm") return false
        val prefs = getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        prefs.edit()
            .putBoolean("flutter.wakeme.bg.armed", false)
            .remove("flutter.wakeme.bg.arrived")
            .remove("flutter.wakeme.bg.dest_lat")
            .remove("flutter.wakeme.bg.dest_lng")
            .apply()
        NotificationManagerCompat.from(applicationContext)
            .cancel(launchIntent.getIntExtra("notificationId", 1001))
        // Only bounce back to the previous app if Wakey was NOT already in front.
        // If the user was using Wakey, keep it open — just stop the alarm.
        if (!inForeground) {
            pendingMoveToBack = true
            moveTaskToBack(true)
        }
        return true
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
                "moveToBack" -> {
                    // Drop the app to the background (revealing whatever the
                    // user was in) after a notification-Dismiss brought us
                    // forward, so the takeover is barely perceptible.
                    moveTaskToBack(true)
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
        return prefs.getBoolean("flutter.wakeme.bg.arrived", false)
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
                // Silence (not dismiss): mutes sound + vibration but leaves the
                // alarm on screen so the user still explicitly dismisses it.
                methodChannel?.invokeMethod("silenceAlarm", null)
                return true // consume the key so the volume doesn't change
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
