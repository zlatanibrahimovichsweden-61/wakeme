import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class AlarmService extends ChangeNotifier {
  AlarmService();

  static const String _channelId = 'wakey_alarm_channel';
  static const String _channelName = 'Wakey Arrival Alarm';
  static const String _channelDesc =
      'Full-screen alarm fired when you approach your destination.';
  static const int _notificationId = 1001;
  static const List<int> _vibrationPattern = <int>[0, 500, 200, 500, 200, 500];
  static const String _alarmSoundAsset = 'sounds/alarm.wav';

  // Bridge to MainActivity so it can intercept the hardware volume keys
  // while the alarm is ringing (see MainActivity.kt).
  static const MethodChannel _keyChannel = MethodChannel('wakey/alarm_keys');

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

    await _plugin.initialize(settings);

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
    // Android 13+ requires runtime POST_NOTIFICATIONS. Without it Android
    // silently drops every notification we enqueue, including the alarm.
    try {
      await androidImpl?.requestNotificationsPermission();
    } catch (_) {}
    // Also request the exact-alarm permission used by scheduled notifications
    // (cheap, no-op if already granted or unsupported).
    try {
      await androidImpl?.requestExactAlarmsPermission();
    } catch (_) {}

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

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
        'Wakey — almost there!',
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
