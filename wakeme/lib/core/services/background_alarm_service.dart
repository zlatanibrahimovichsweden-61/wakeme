import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../testing/test_mode.dart'; // TEST-ONLY

// TEST-ONLY diagnostic logger. Prints to logcat (tag shows under "flutter").
// Remove with the test harness.
void _dbg(String m) {
  if (kTestMode) {
    // ignore: avoid_print
    print('WAKEYDBG $m');
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Background alarm service.
//
// The whole point of WakeMe is to fire when the app ISN'T on screen. A widget's
// position listener dies the moment Android suspends the Flutter UI (which
// Samsung does aggressively). So the arrival check runs here instead, inside a
// dedicated background isolate hosted by a foreground service that survives
// backgrounding and even app-swipe-away.
//
// Data flow:
//   UI  → SharedPreferences (destination) + startService()
//   ISO → reads prefs, watches GPS, fires the alarm itself, and invoke()s
//         'update' / 'arrived' back to the UI for the live map + dialog.
//   UI  → invoke('dismissAlarm' | 'stopService') to silence / tear down.
// ─────────────────────────────────────────────────────────────────────────

// Prefs keys the UI writes and the isolate reads.
const String _kDestLat = 'wakeme.bg.dest_lat';
const String _kDestLng = 'wakeme.bg.dest_lng';
const String _kDestName = 'wakeme.bg.dest_name';
const String _kRadius = 'wakeme.bg.radius';
const String _kSoundPath = 'wakeme.bg.sound_path';
const String _kVolume = 'wakeme.bg.volume';
const String _kVibrate = 'wakeme.bg.vibrate';
// Set by the isolate the moment the alarm fires. The UI reads this on resume
// so a "arrived" event that landed while the UI was suspended isn't lost.
const String kArrivedFlag = 'wakeme.bg.arrived';
// True only while a REAL arm is active — set on Sleep, cleared on cancel /
// arrival-dismiss. If the OS ever resurrects the foreground service without an
// active arm (sticky restart, etc.), onStart reads this and stops immediately,
// so the "armed" notification never shows unless the user actually armed.
const String _kArmed = 'wakeme.bg.armed';
// Set true by the UI when its full-screen alarm takes over (which hides the
// notification on purpose). The service's notification-disappeared poll skips
// teardown while this is set, so a UI takeover isn't mistaken for a Dismiss tap.
const String _kUiActive = 'wakeme.bg.ui_active';

// Low-importance channel for the persistent "WakeMe is armed" service
// notification; max-importance channel for the actual arrival alarm.
const String bgChannelId = 'wakeme_foreground_channel';
const String alarmChannelId = 'wakeme_alarm_channel';
const String _alarmChannelName = 'WakeMe Arrival Alarm';
const int bgNotificationId = 1002;
const int alarmNotificationId = 1001;
const String _alarmSoundAsset = 'sounds/alarm.wav';
const List<int> _vibrationPattern = <int>[0, 500, 200, 500, 200, 500];

class BackgroundAlarmService {
  BackgroundAlarmService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static FlutterBackgroundService get instance => _service;

  // Called once at app start (main.dart). Creates the notification channels
  // and configures the service. autoStart is false — we only run while armed.
  static Future<void> initialize() async {
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    final AndroidFlutterLocalNotificationsPlugin? android =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        bgChannelId,
        'WakeMe Tracking',
        description: 'Keeps WakeMe running so it can wake you on arrival.',
        importance: Importance.low,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        alarmChannelId,
        _alarmChannelName,
        description:
            'Full-screen alarm fired when you approach your destination.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        // Don't let the OS resurrect the service on reboot or app-update — a
        // reboot/update mid-trip should NOT silently re-arm. The user re-arms.
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: bgChannelId,
        initialNotificationTitle: 'WakeMe is armed',
        initialNotificationContent:
            'Tracking your location to wake you on arrival.',
        foregroundServiceNotificationId: bgNotificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  // Persist the armed destination, then start (or reconfigure) the service.
  static Future<void> startArmed({
    required double lat,
    required double lng,
    required String name,
    required double radius,
    String? soundPath,
    double volume = 1.0,
    bool vibrate = true,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kArmed, true);
    await prefs.setDouble(_kDestLat, lat);
    await prefs.setDouble(_kDestLng, lng);
    await prefs.setString(_kDestName, name);
    await prefs.setDouble(_kRadius, radius);
    await prefs.setDouble(_kVolume, volume.clamp(0.0, 1.0));
    await prefs.setBool(_kVibrate, vibrate);
    if (soundPath != null && soundPath.isNotEmpty) {
      await prefs.setString(_kSoundPath, soundPath);
    } else {
      await prefs.remove(_kSoundPath);
    }
    await prefs.remove(kArrivedFlag);
    await prefs.remove(_kUiActive);
    if (kTestMode) await prefs.remove(kTestArriveAt); // TEST-ONLY

    final bool running = await _service.isRunning();
    if (running) {
      _service.invoke('reconfigure');
    } else {
      await _service.startService();
    }
  }

  // Silence + tear down the service.
  static Future<void> stop() async {
    // Clear the armed state + destination FIRST so a resurrected service sees
    // "not armed" and self-terminates instead of re-arming with a stale trip.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kArmed, false);
    await prefs.remove(_kDestLat);
    await prefs.remove(_kDestLng);
    await prefs.remove(kArrivedFlag);

    final bool running = await _service.isRunning();
    if (running) _service.invoke('stopService');
  }

  // Ask the isolate to silence the alarm (used by volume / lock dismissal).
  static void dismissAlarm() => _service.invoke('dismissAlarm');

  // Mute the alarm audio + vibration but keep it active and dismissible — the
  // volume keys call this on the full-screen alarm (a "silence, don't dismiss").
  static void silenceAlarm() => _service.invoke('silence');

  // Called by the UI right before its full-screen alarm hides the notification,
  // so the service's notification-disappeared poll doesn't read that deliberate
  // hide as the user tapping Dismiss.
  static Future<void> markUiActive() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUiActive, true);
  }

  // Remove the arrival notification's visible card. Called from the UI once the
  // full-screen alarm screen is showing, so the user sees only the screen — not
  // the screen AND a notification. The full-screen-intent notification has
  // already done its one job (launching the screen over the lock screen) by
  // this point; cancelling its card does NOT stop the alarm audio (that lives
  // in the isolate's player and is only silenced on dismiss).
  static Future<void> hideArrivalNotification() async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(alarmNotificationId);
    } catch (_) {}
  }

  // Authoritative "stop the alarm" entry point for the notification's Dismiss
  // action. That action's callback runs in a short-lived isolate whose
  // service.invoke() can't be trusted to reach the running service, and the
  // alarm audio is owned by the service isolate's own AudioPlayer — so the only
  // reliable cross-isolate signal is SharedPreferences. We clear the armed flag
  // here; the service's dismissWatch timer (see onStart) sees it and tears
  // itself down, which is what actually silences the sound. The invoke below is
  // just a best-effort fast path.
  static Future<void> requestDismiss() async {
    _dbg('requestDismiss (main/bg isolate)');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kArmed, false);
    await prefs.remove(_kDestLat);
    await prefs.remove(_kDestLng);
    await prefs.remove(kArrivedFlag);
    try {
      if (await _service.isRunning()) _service.invoke('dismissAlarm');
    } catch (_) {}
    // The notification card and vibration are process-global, so we can stop
    // those from here immediately — only the audio has to wait for the service.
    try {
      await FlutterLocalNotificationsPlugin().cancel(alarmNotificationId);
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
  }

  // TEST-ONLY ───────────────────────────────────────────────────────────
  // In-app testing harness hooks (see lib/core/testing/test_mode.dart).
  // Fire a fake arrival without travelling into the radius. Remove with the
  // harness.

  // Scheduled fake-arrival timestamp (ms since epoch). The service isolate
  // polls this while armed and fires arrival once it's due — owning the
  // countdown in the service means it triggers even if the UI is gone.
  static const String kTestArriveAt = 'wakeme.test.arrive_at_ms';

  static Future<bool> isArmed() async {
    try {
      if (!await _service.isRunning()) return false;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kArmed) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> armedName() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDestName) ?? '';
  }

  static Future<double> armedRadius() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kRadius) ?? 500;
  }

  // Instant fake arrival — used while the app is open, so a direct invoke
  // reliably reaches the running service isolate.
  static Future<void> testArriveNow() async {
    if (await _service.isRunning()) _service.invoke('testArrive');
  }

  // Schedule a fake arrival `delay` from now. The poll in onStart fires it
  // even while backgrounded / locked / swiped away.
  static Future<void> testArriveIn(Duration delay) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      kTestArriveAt,
      DateTime.now().millisecondsSinceEpoch + delay.inMilliseconds,
    );
  }

  static Future<void> testReset() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(kTestArriveAt);
  }

  // Arm a throwaway trip if nothing is armed, so the test panel can fire an
  // arrival without the user first picking a destination and pressing Sleep.
  // Coordinates don't matter — arrival is forced regardless of real distance.
  static Future<void> testEnsureArmed() async {
    if (await _service.isRunning()) return;
    await startArmed(
      lat: 30.0444,
      lng: 31.2357,
      name: 'Test destination',
      radius: 500,
    );
    // Wait (up to ~3s) for the foreground service to actually come up so the
    // scheduled/instant arrival has something to fire in.
    for (int i = 0; i < 20; i++) {
      if (await _service.isRunning()) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // The isolate is a fresh Dart VM — register plugins before using any.
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer player = AudioPlayer();
  bool alarmFired = false;
  StreamSubscription<Position>? posSub;
  // Polls the armed flag once the alarm is ringing so a dismiss from the
  // notification action (which can't reliably reach us via invoke) still stops
  // the audio this isolate owns. Cancelled in tearDown. See requestDismiss().
  Timer? dismissWatch;
  Timer? testWatch; // TEST-ONLY: polls the scheduled fake-arrival timestamp.
  bool tearingDown = false;
  int? arrivedAtMs; // when the alarm started ringing (for the 60s timeout).
  bool notifSeen = false; // the alarm notification was observed at least once.
  final AndroidFlutterLocalNotificationsPlugin? androidNotifs =
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  // Route alarm audio through the alarm stream so it rings past ringer-silent.
  try {
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.music,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const <AVAudioSessionOptions>{
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ),
    );
  } catch (_) {}

  Future<void> silence() async {
    try {
      await player.stop();
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
    try {
      await plugin.cancel(alarmNotificationId);
    } catch (_) {}
  }

  // Stop the audible alarm (sound + vibration) but keep the notification, the
  // arrived state, and the service alive — the alarm stays "ringing-but-muted"
  // until the user dismisses it or the 60s timeout fires. Used by the volume
  // keys on the full-screen alarm.
  Future<void> silenceAudioOnly() async {
    try {
      await player.stop();
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
  }

  Future<void> tearDown() async {
    if (tearingDown) return;
    _dbg('tearDown');
    tearingDown = true;
    dismissWatch?.cancel();
    testWatch?.cancel(); // TEST-ONLY
    await silence();
    await posSub?.cancel();
    // Clear armed state + destination so neither ArmedScreen re-shows the
    // arrival dialog on resume nor a resurrected service re-arms with a stale
    // trip. Covers the notification-action / volume dismiss paths that tear
    // down via the isolate rather than BackgroundAlarmService.stop().
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setBool(_kArmed, false);
      await p.remove(_kDestLat);
      await p.remove(_kDestLng);
      await p.remove(kArrivedFlag);
      await p.remove(_kUiActive);
    } catch (_) {}
    service.stopSelf();
  }

  service.on('stopService').listen((_) => tearDown());
  service.on('dismissAlarm').listen((_) => tearDown());
  service.on('silence').listen((_) => silenceAudioOnly());

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool armed = prefs.getBool(_kArmed) ?? false;
  final double? destLat = prefs.getDouble(_kDestLat);
  final double? destLng = prefs.getDouble(_kDestLng);
  final double radius = prefs.getDouble(_kRadius) ?? 500;
  final String name = prefs.getString(_kDestName) ?? 'your destination';
  final String? soundPath = prefs.getString(_kSoundPath);
  final double volume = prefs.getDouble(_kVolume) ?? 1.0;
  final bool vibrate = prefs.getBool(_kVibrate) ?? true;

  // Resurrected without an active arm (sticky restart, etc.)? Stop immediately
  // so the "armed" notification never appears unless the user pressed Sleep.
  if (!armed || destLat == null || destLng == null) {
    service.stopSelf();
    return;
  }

  // Shared arrival path: fire the alarm once, then poll the armed flag so a
  // dismiss (which clears the flag from the main isolate) stops the audio this
  // isolate owns even when the GPS stream has gone quiet at the destination.
  Future<void> triggerArrival() async {
    if (alarmFired) return;
    _dbg('triggerArrival -> firing alarm');
    alarmFired = true;
    arrivedAtMs = DateTime.now().millisecondsSinceEpoch;
    await prefs.setBool(kArrivedFlag, true);
    await _fireAlarm(plugin, player, name, soundPath, volume, vibrate);
    service.invoke('arrived', <String, dynamic>{'name': name});

    // While ringing, poll once a second for any reason to stop:
    //  1. armed flag cleared → app-open dismiss / Cancel / a resurrected stop.
    //  2. notification gone  → the user tapped the notification's Dismiss
    //     (cancelNotification removes it natively, no app launch). Skipped while
    //     the UI has taken over with its full-screen alarm, which also hides
    //     the notification on purpose (_kUiActive guards against that).
    //  3. 60s elapsed        → nobody dismissed; auto-give-up like a real alarm.
    dismissWatch ??= Timer.periodic(
      const Duration(seconds: 1),
      (Timer _) async {
        await prefs.reload();
        final bool stillArmed = prefs.getBool(_kArmed) ?? false;
        final bool uiActive = prefs.getBool(_kUiActive) ?? false;
        int activeCount = -1;
        bool present = false;
        try {
          final List<ActiveNotification>? active =
              await androidNotifs?.getActiveNotifications();
          if (active != null) {
            activeCount = active.length;
            present = active.any(
              (ActiveNotification n) => n.id == alarmNotificationId,
            );
          }
        } catch (e) {
          _dbg('getActiveNotifications ERROR $e');
        }
        _dbg('tick armed=$stillArmed ui=$uiActive present=$present '
            'seen=$notifSeen count=$activeCount');
        // 1. armed flag cleared.
        if (!stillArmed) {
          _dbg('-> teardown (disarmed)');
          await tearDown();
          return;
        }
        // 3. 60-second timeout — tell the UI to drop its alarm screen too.
        final int? since = arrivedAtMs;
        if (since != null &&
            DateTime.now().millisecondsSinceEpoch - since >= 60000) {
          _dbg('-> teardown (timeout)');
          service.invoke('forceDismiss');
          await tearDown();
          return;
        }
        // 2. notification disappeared (Dismiss tapped) — but not when the UI
        //    deliberately hid it for its own full-screen takeover.
        if (uiActive) return;
        if (present) {
          notifSeen = true;
        } else if (notifSeen) {
          _dbg('-> teardown (notif gone)');
          await tearDown();
        }
      },
    );
  }

  // TEST-ONLY: fake-arrival triggers. 'testArrive' fires instantly (app open);
  // the poll fires a scheduled (e.g. 5s) arrival even while backgrounded/locked.
  if (kTestMode) {
    service.on('testArrive').listen((_) => triggerArrival());
    testWatch = Timer.periodic(const Duration(seconds: 1), (Timer _) async {
      await prefs.reload();
      final int? dueMs = prefs.getInt(BackgroundAlarmService.kTestArriveAt);
      if (dueMs != null && DateTime.now().millisecondsSinceEpoch >= dueMs) {
        await prefs.remove(BackgroundAlarmService.kTestArriveAt);
        await triggerArrival();
      }
    });
  }

  posSub = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  ).listen((Position pos) async {
    final double distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      destLat,
      destLng,
    );

    // Feed the live UI (map marker + distance label + heading arrow) when
    // it's on screen. heading/speed drive the navigation chevron + follow cam.
    service.invoke('update', <String, dynamic>{
      'lat': pos.latitude,
      'lng': pos.longitude,
      'distance': distance,
      'heading': pos.heading,
      'speed': pos.speed,
    });

    // NOTE: deliberately NOT calling setForegroundNotificationInfo with the
    // live distance — the user doesn't want a "current state" notification. The
    // foreground-service notification stays as its minimal static line (Android
    // requires *some* notification for the service that keeps the alarm alive
    // while locked; it can't be removed entirely).

    if (!alarmFired && distance <= radius) {
      await triggerArrival();
    }
  });
}

Future<void> _fireAlarm(
  FlutterLocalNotificationsPlugin plugin,
  AudioPlayer player,
  String name,
  String? soundPath,
  double volume,
  bool vibrate,
) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    alarmChannelId,
    _alarmChannelName,
    // Branded white status-bar silhouette (see res/drawable-*/ic_bg_service_small).
    icon: 'ic_bg_service_small',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    playSound: true,
    enableVibration: true,
    ongoing: true,
    autoCancel: false,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        'dismiss_alarm',
        'Dismiss',
        // showsUserInterface MUST be true on Samsung One UI. Device logs proved
        // that with false, the action's background Dart dispatch is killed (so
        // requestDismiss never runs) AND the notification isn't even cancelled
        // (FLN couples the cancel to that dead dispatch) — the alarm rings on
        // forever. true routes the tap to the FOREGROUND handler, which fires
        // reliably; the app then immediately drops back (moveTaskToBack) so the
        // user barely sees it. cancelNotification stays so the card clears too.
        cancelNotification: true,
        showsUserInterface: true,
      ),
    ],
  );

  try {
    await plugin.show(
      alarmNotificationId,
      'WakeMe — almost there!',
      'You are approaching $name. Time to wake up.',
      const NotificationDetails(android: androidDetails),
    );
  } catch (_) {}

  // Remove the tracking notification so only the alarm notification is visible.
  try {
    await plugin.cancel(bgNotificationId);
  } catch (_) {}

  try {
    if (vibrate) {
      final bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
      }
    }
  } catch (_) {}

  try {
    final double vol = volume.clamp(0.0, 1.0);
    final bool useCustom = soundPath != null &&
        soundPath.isNotEmpty &&
        File(soundPath).existsSync();
    if (useCustom) {
      await player.play(DeviceFileSource(soundPath), volume: vol);
    } else {
      await player.play(AssetSource(_alarmSoundAsset), volume: vol);
    }
  } catch (_) {}
}
