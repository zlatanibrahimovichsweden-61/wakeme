import 'package:google_maps_flutter/google_maps_flutter.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'WakeMe';
  static const String tagline = 'Sleep tight. Arrive right.';

  // Store / legal.
  static const String privacyPolicyUrl =
      'https://github.com/zlatanibrahimovichsweden-61/wakeme/blob/main/wakeme/PRIVACY_POLICY.md';
  static const String supportEmail = 'mohamed61fouad@gmail.com';

  static const LatLng fallbackLocation = LatLng(30.0444, 31.2357); // Cairo

  static const double defaultRadiusMeters = 500;
  static const double minRadiusMeters = 200;
  static const double maxRadiusMeters = 2000;

  static const int maxRecentPlaces = 5;
  static const int positionUpdateIntervalSeconds = 5;
  static const int positionDistanceFilterMeters = 10;

  static const Duration pulseDuration = Duration(milliseconds: 1500);

  static const String prefsRecentKey = 'wakeme.recent_destinations';
  static const String prefsSavedKey = 'wakeme.saved_places';
  static const String prefsAlarmSoundPathKey = 'wakeme.alarm_sound_path';
  static const String prefsAlarmSoundLabelKey = 'wakeme.alarm_sound_label';
  static const String prefsAlarmVolumeKey = 'wakeme.alarm_volume';
  static const String prefsAlarmVibrateKey = 'wakeme.alarm_vibrate';

  // Alarm playback defaults. Volume is 0.0–1.0 (full blast by default — it's an
  // alarm); vibration on. Both are user-overridable from Settings and read at
  // fire-time by the background isolate.
  static const double defaultAlarmVolume = 1.0;
  static const bool defaultAlarmVibrate = true;
  // Set true the first time we walk the user through the "Allow all the time"
  // background-location request, so we never nag them about it again.
  static const String prefsAskedBackgroundKey = 'wakeme.asked_background_perm';

  static const String envMapsKey = 'MAPS_API_KEY';

  // Off-route detection (Armed screen) thresholds. Recompute the route only
  // when both conditions hold so we don't spam the Directions API:
  //   user is > this many meters from the planned line, AND
  //   at least this many seconds have passed since the last reroute.
  static const double rerouteDistanceThresholdMeters = 100;
  static const Duration rerouteCooldown = Duration(seconds: 30);

  // Google Directions API host (REST, not packaged in google_maps_flutter).
  static const String directionsHost = 'maps.googleapis.com';
  static const String directionsPath = '/maps/api/directions/json';
  static const String geocodingPath = '/maps/api/geocode/json';

  // Embedded dark map style — matches the indigo/black palette of the app.
  static const String darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d0d1a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0d0d1a"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#252540"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#cbd5f5"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6b7280"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#15233a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#252540"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca3af"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4f46e5"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#0d0d1a"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#252540"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#080814"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4f46e5"}]}
]
''';
}
