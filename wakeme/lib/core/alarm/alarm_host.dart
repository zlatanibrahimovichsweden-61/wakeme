import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../features/armed/alarm_ringing_screen.dart';
import '../services/background_alarm_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// Global arrival-alarm host.
//
// This owns the ENTIRE on-screen alarm experience and is mounted once, at the
// app root (see app.dart), so it stays alive regardless of which screen is on
// top. Lifting it out of ArmedScreen is what makes every arrival behave the
// same — whether the trip was armed through the real Sleep flow OR the test
// panel from any screen.
//
// Responsibilities (all moved here from ArmedScreen):
//   • listen for the service's 'arrived' event + recover it on resume
//   • show the full-screen AlarmRingingScreen when the app is foregrounded
//     (and over the lock screen); when in another app, the service's heads-up
//     notification stands in until the user opens WakeMe
//   • route hardware volume keys to "silence" (sound/vibration off, screen
//     stays) via the native MethodChannel
//   • dismiss (slider / 60s timeout) → stop the service + close the alarm
//
// The service still owns sound, vibration, the notification, and the 60s
// auto-dismiss timer; this widget is purely the foreground UI for it.
// ─────────────────────────────────────────────────────────────────────────
class AlarmHost extends StatefulWidget {
  const AlarmHost({super.key, required this.child});

  final Widget child;

  @override
  State<AlarmHost> createState() => _AlarmHostState();
}

class _AlarmHostState extends State<AlarmHost> with WidgetsBindingObserver {
  // Shared with MainActivity.kt — native invokes 'silenceAlarm' when a volume
  // key is pressed while the alarm rings, and reads alarmActive for the
  // lock-screen / volume-intercept behaviour.
  static const MethodChannel _keyChannel = MethodChannel('wakeme/alarm_keys');

  StreamSubscription<Map<String, dynamic>?>? _arrivedSub;
  StreamSubscription<Map<String, dynamic>?>? _forceDismissSub;

  bool _arrived = false;
  bool _screenShown = false;
  String _destName = 'your destination';
  double _radius = 500;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyChannel.setMethodCallHandler((MethodCall call) async {
      // Volume keys SILENCE only (sound + vibration off) and leave the alarm
      // screen up; the user slides to dismiss, or it times out at 60s.
      if (call.method == 'silenceAlarm' && _arrived) {
        BackgroundAlarmService.silenceAlarm();
      }
      return null;
    });
    _arrivedSub = BackgroundAlarmService.instance.on('arrived').listen(
      (Map<String, dynamic>? data) {
        final String? name = data?['name'] as String?;
        if (name != null && name.isNotEmpty) _destName = name;
        _onArrived();
      },
    );
    _forceDismissSub = BackgroundAlarmService.instance
        .on('forceDismiss')
        .listen((_) => _dismiss());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrivedSub?.cancel();
    _forceDismissSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Locking the phone does NOT dismiss — the alarm keeps ringing and shows
    // over the lock screen (MainActivity declares showWhenLocked).
    if (state == AppLifecycleState.resumed) _syncOnResume();
  }

  // On every foreground return, trust the service's flag (reloaded across the
  // isolate boundary) rather than our in-memory state. This both surfaces an
  // arrival that happened while we were suspended AND tears down a stale alarm
  // screen if the trip was dismissed / timed-out while we were away — e.g. the
  // native notification-Dismiss bounce, which clears the flag before we resume.
  Future<void> _syncOnResume() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final bool arrivedNow = prefs.getBool(kArrivedFlag) ?? false;
    if (arrivedNow) {
      await _onArrived();
    } else if (_screenShown || _arrived) {
      await _dismiss();
    }
  }

  Future<void> _onArrived() async {
    if (_arrived && _screenShown) return;
    _arrived = true;
    // Pull the trip details straight from the service's store so the alarm
    // screen reads correctly no matter how we got here.
    _destName = await BackgroundAlarmService.armedName().then(
      (String n) => n.isNotEmpty ? n : _destName,
    );
    _radius = await BackgroundAlarmService.armedRadius();
    _keyChannel.invokeMethod<void>('setAlarmActive', true);
    _maybeShowAlarmScreen();
  }

  // Show the full-screen alarm ONLY when the app is actually foreground — we're
  // already in WakeMe, or the full-screen intent (locked arrival) just brought us
  // forward. In another app we deliberately do NOT take over; the heads-up
  // notification stands in until the user opens WakeMe.
  void _maybeShowAlarmScreen() {
    if (_screenShown || !_arrived || !mounted) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return; // backgrounded (another app, or still locked) — wait for resume
    }
    _screenShown = true;
    // The takeover screen now stands in for the notification. Tell the service
    // we're hiding it ON PURPOSE so its Dismiss-detection poll doesn't read the
    // hide as the user tapping Dismiss, then remove the card.
    BackgroundAlarmService.markUiActive();
    BackgroundAlarmService.hideArrivalNotification();
    _showAlarmScreen();
  }

  Future<void> _showAlarmScreen() async {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    unawaited(WakelockPlus.enable());
    await navigator.push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => AlarmRingingScreen(
          destinationName: _destName,
          radiusMeters: _radius,
          onDismiss: _dismiss,
        ),
        transitionsBuilder: (_, Animation<double> anim, __, Widget child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // Single dismissal path: the slider, the volume-then-timeout, and the 60s
  // forceDismiss all land here. Stops the service, drops the alarm screen, and
  // returns to Home — WITHOUT closing the app.
  Future<void> _dismiss() async {
    if (!_arrived && !_screenShown) return;
    final bool wasShown = _screenShown;
    _arrived = false;
    _screenShown = false;
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    await BackgroundAlarmService.stop();
    _keyChannel.invokeMethod<void>('setAlarmActive', false);
    unawaited(WakelockPlus.disable());
    // Close the alarm screen (and any armed/confirm screens beneath it) back to
    // Home. If the alarm screen was never shown (dismissed from a notification
    // while in another app), there's nothing to pop.
    if (wasShown) {
      navigator.popUntil((Route<dynamic> route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
