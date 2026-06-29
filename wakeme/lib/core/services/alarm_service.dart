import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import 'background_alarm_service.dart';

// Called when the user taps the Dismiss action on the alarm notification while
// the app is in the background or killed. Runs in a fresh Dart isolate, so it
// can't reach the service isolate via invoke reliably — requestDismiss() clears
// the armed flag in SharedPreferences instead, which the service polls.
@pragma('vm:entry-point')
void _onBgNotificationDismissed(NotificationResponse response) {
  DartPluginRegistrant.ensureInitialized();
  // ignore: avoid_print
  print('WAKEYDBG bgNotificationResponse action=${response.actionId}');
  if (response.actionId == 'dismiss_alarm') {
    BackgroundAlarmService.requestDismiss();
  }
}

class AlarmService extends ChangeNotifier {
  AlarmService();

  static const String _channelId = 'wakeme_alarm_channel';
  static const String _channelName = 'WakeMe Arrival Alarm';
  static const String _channelDesc =
      'Full-screen alarm fired when you approach your destination.';
  static const int _notificationId = 1001;
  static const List<int> _vibrationPattern = <int>[0, 500, 200, 500, 200, 500];
  static const String _alarmSoundAsset = 'sounds/alarm.wav';

  // Bridge to MainActivity so it can intercept the hardware volume keys
  // while the alarm is ringing (see MainActivity.kt).
  static const MethodChannel _keyChannel = MethodChannel('wakeme/alarm_keys');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();
  bool _initialized = false;
  bool _isAlarmActive = false;

  bool get isAlarmActive => _isAlarmActive;

  // Tell the native layer whether to intercept volume keys. Best-effort.
  Future<void> _setNativeAlarmActive(bool active) async {
    try {
      await _keyChannel.invokeMethod<void>('setAlarmActive', active);
    } catch (_) {}
  }

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // ignore: avoid_print
        print('WAKEYDBG fgNotificationResponse action=${response.actionId}');
        if (response.actionId == 'dismiss_alarm') {
          // Backup stop. The native MainActivity.handleDismissLaunch already
          // disarmed and (only if we were backgrounded) bounced the app back —
          // so we must NOT moveToBack here, or a Dismiss tapped while WakeMe is
          // open would background the app the user is using.
          await BackgroundAlarmService.requestDismiss();
        }
      },
      onDidReceiveBackgroundNotificationResponse: _onBgNotificationDismissed,
    );

    // Cold-start fallback: if the OS destroyed the UI engine while the alarm was
    // ringing, tapping the notification's Dismiss action launches the app fresh
    // and onDidReceiveNotificationResponse never fires. Recover the action from
    // the launch details here so the alarm is still silenced on a cold open.
    try {
      final NotificationAppLaunchDetails? launch =
          await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true &&
          launch?.notificationResponse?.actionId == 'dismiss_alarm') {
        // Native handleDismissLaunch already handled the stop + bounce-back.
        await BackgroundAlarmService.requestDismiss();
      }
    } catch (_) {}

    final AndroidFlutterLocalNotificationsPlugin? androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    // NOTE: POST_NOTIFICATIONS / exact-alarm / iOS prompts are deliberately NOT
    // requested here. init() runs at provider-create, which races the location
    // permission dialog the home screen fires at the same moment — Android can't
    // show two system permission dialogs at once, so the notification request
    // silently loses and notifications stay disabled (importance=NONE), dropping
    // every alarm. The startup flow instead calls ensureNotificationPermission()
    // SEQUENTIALLY, once the location dialog has been dismissed.

    // Loop the alarm tone so it keeps ringing until the user dismisses it,
    // and route through the alarm stream so it survives "ringer silent".
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
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

    _initialized = true;
  }

  // Request POST_NOTIFICATIONS (Android 13+) / iOS alert permission. MUST be
  // driven sequentially from the startup flow — never at provider-create time —
  // so it doesn't collide with the location permission dialog (see the note in
  // init()). Returns whether notifications are enabled afterwards.
  Future<bool> ensureNotificationPermission() async {
    if (!_initialized) {
      try {
        await init();
      } catch (_) {}
    }

    final AndroidFlutterLocalNotificationsPlugin? androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      try {
        bool granted = await androidImpl.areNotificationsEnabled() ?? false;
        if (!granted) {
          granted = await androidImpl.requestNotificationsPermission() ?? false;
        }
        return granted;
      } catch (_) {
        return false;
      }
    }

    final IOSFlutterLocalNotificationsPlugin? iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      try {
        return await iosImpl.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> triggerAlarm(
    String destinationName, {
    String? customSoundPath,
  }) async {
    if (!_initialized) {
      try {
        await init();
      } catch (_) {}
    }

    // Hard reset before firing — best-effort, never throws.
    try {
      await _plugin.cancel(_notificationId);
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
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

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Each piece of the alarm fires independently. If notifications are
    // blocked, audio still plays; if vibration plugin chokes, the
    // notification still fires; if audio fails, the arrival dialog still
    // shows. Critically, nothing here can hang _onPosition.
    try {
      await _plugin.show(
        _notificationId,
        'WakeMe — almost there!',
        'You are approaching $destinationName. Time to wake up.',
        details,
      );
    } catch (_) {}

    try {
      final bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: _vibrationPattern, repeat: 0);
      }
    } catch (_) {}

    try {
      final bool useCustom = customSoundPath != null &&
          customSoundPath.isNotEmpty &&
          File(customSoundPath).existsSync();
      if (useCustom) {
        await _player.play(DeviceFileSource(customSoundPath), volume: 1.0);
      } else {
        await _player.play(AssetSource(_alarmSoundAsset), volume: 1.0);
      }
    } catch (_) {}

    _isAlarmActive = true;
    // Arm the native volume-key interception now that we're ringing.
    await _setNativeAlarmActive(true);
    notifyListeners();
  }

  Future<void> cancelAlarm() async {
    // Silence the AUDIBLE parts first and independently. Previously the
    // notification-cancel ran first; if it hung (Samsung + ongoing
    // notification), _player.stop never executed and the alarm kept ringing
    // even though the user tapped Dismiss / Cancel.
    try {
      await _player.stop();
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
    try {
      await _plugin.cancel(_notificationId);
    } catch (_) {}
    _isAlarmActive = false;
    await _setNativeAlarmActive(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
