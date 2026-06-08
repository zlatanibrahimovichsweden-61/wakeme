import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

// ─────────────────────────────────────────────────────────────────────────
// Background alarm service.
//
// The whole point of Wakey is to fire when the app ISN'T on screen. A widget's
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
const String _kDestLat = 'wakey.bg.dest_lat';
const String _kDestLng = 'wakey.bg.dest_lng';
const String _kDestName = 'wakey.bg.dest_name';
const String _kRadius = 'wakey.bg.radius';
const String _kSoundPath = 'wakey.bg.sound_path';
// Set by the isolate the moment the alarm fires. The UI reads this on resume
// so a "arrived" event that landed while the UI was suspended isn't lost.
const String kArrivedFlag = 'wakey.bg.arrived';

// Low-importance channel for the persistent "Wakey is armed" service
// notification; max-importance channel for the actual arrival alarm.
const String bgChannelId = 'wakey_foreground_channel';
const String alarmChannelId = 'wakey_alarm_channel';
const String _alarmChannelName = 'Wakey Arrival Alarm';
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
        'Wakey Tracking',
        description: 'Keeps Wakey running so it can wake you on arrival.',
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
        isForegroundMode: true,
        notificationChannelId: bgChannelId,
        initialNotificationTitle: 'Wakey is armed',
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
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kDestLat, lat);
    await prefs.setDouble(_kDestLng, lng);
    await prefs.setString(_kDestName, name);
    await prefs.setDouble(_kRadius, radius);
    if (soundPath != null && soundPath.isNotEmpty) {
      await prefs.setString(_kSoundPath, soundPath);
    } else {
      await prefs.remove(_kSoundPath);
    }
    await prefs.remove(kArrivedFlag);

    final bool running = await _service.isRunning();
    if (running) {
      _service.invoke('reconfigure');
    } else {
      await _service.startService();
    }
  }

  // Silence + tear down the service.
  static Future<void> stop() async {
    final bool running = await _service.isRunning();
    if (running) _service.invoke('stopService');
  }

  // Ask the isolate to silence the alarm (used by volume / lock dismissal).
  static void dismissAlarm() => _service.invoke('dismissAlarm');
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

  Future<void> tearDown() async {
    await silence();
    await posSub?.cancel();
    service.stopSelf();
  }

  service.on('stopService').listen((_) => tearDown());
  service.on('dismissAlarm').listen((_) => tearDown());

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final double? destLat = prefs.getDouble(_kDestLat);
  final double? destLng = prefs.getDouble(_kDestLng);
  final double radius = prefs.getDouble(_kRadius) ?? 500;
  final String name = prefs.getString(_kDestName) ?? 'your destination';
  final String? soundPath = prefs.getString(_kSoundPath);

  if (destLat == null || destLng == null) {
    service.stopSelf();
    return;
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

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Wakey is armed',
        content: distance >= 1000
            ? '${(distance / 1000).toStringAsFixed(1)} km to $name'
            : '${distance.round()} m to $name',
      );
    }

    if (!alarmFired && distance <= radius) {
      alarmFired = true;
      await prefs.setBool(kArrivedFlag, true);
      await _fireAlarm(plugin, player, name, soundPath);
      service.invoke('arrived', <String, dynamic>{'name': name});
    }
  });
}

Future<void> _fireAlarm(
  FlutterLocalNotificationsPlugin plugin,
  AudioPlayer player,
  String name,
  String? soundPath,
) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    alarmChannelId,
    _alarmChannelName,
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    playSound: true,
    enableVibration: true,
    ongoing: true,
    autoCancel: false,
  );

  try {
    await plugin.show(
      alarmNotificationId,
      'Wakey — almost there!',
      'You are approaching $name. Time to wake up.',
      const NotificationDetails(android: androidDetails),
    );
  } catch (_) {}

  try {
    final bool hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
    }
  } catch (_) {}

  try {
    final bool useCustom = soundPath != null &&
        soundPath.isNotEmpty &&
        File(soundPath).existsSync();
    if (useCustom) {
      await player.play(DeviceFileSource(soundPath), volume: 1.0);
    } else {
      await player.play(AssetSource(_alarmSoundAsset), volume: 1.0);
    }
  } catch (_) {}
}
