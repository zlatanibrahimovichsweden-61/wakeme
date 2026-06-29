import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

enum LocationPermissionState {
  unknown,
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class LocationService extends ChangeNotifier {
  LocationService();

  // Foreground-mode settings (used when the app is in front and screen on).
  static const LocationSettings _foregroundSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  // Background-mode settings: on Android we attach a ForegroundNotificationConfig
  // so the OS keeps the location stream + Dart isolate alive while the screen
  // is locked or the app is in the background. On iOS we flip
  // allowBackgroundLocationUpdates. Without these, the stream silently pauses
  // and the arrival alarm never fires.
  static LocationSettings _backgroundSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'WakeMe is armed',
          notificationText:
              'Tracking your location so we can wake you near your stop.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return _foregroundSettings;
  }

  LocationPermissionState _permission = LocationPermissionState.unknown;
  Position? _lastPosition;
  StreamSubscription<Position>? _subscription;
  bool _backgroundMode = false;
  // Cached "Allow all the time" permission state. Refreshed silently on every
  // arm so we never re-prompt the user mid-session, but kept up-to-date if
  // they grant it later via Settings.
  bool _backgroundPermissionGranted = false;
  final StreamController<Position> _broadcast =
      StreamController<Position>.broadcast();

  LocationPermissionState get permission => _permission;
  bool get backgroundPermissionGranted => _backgroundPermissionGranted;
  Position? get lastPosition => _lastPosition;
  Stream<Position> get positionStream => _broadcast.stream;

  Future<LocationPermissionState> init() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setPermission(LocationPermissionState.serviceDisabled);
      return _permission;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        _setPermission(LocationPermissionState.granted);
        break;
      case LocationPermission.deniedForever:
        _setPermission(LocationPermissionState.deniedForever);
        break;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        _setPermission(LocationPermissionState.denied);
        break;
    }
    return _permission;
  }

  // Checks the current "Allow all the time" location permission, and only
  // shows the system prompt when `allowPrompt: true` AND it isn't already
  // granted. Use `allowPrompt: true` once at app start; everywhere else
  // (e.g. arming) call with `allowPrompt: false` so the user isn't pestered.
  Future<bool> ensureBackgroundPermission({bool allowPrompt = false}) async {
    final ph.PermissionStatus current =
        await ph.Permission.locationAlways.status;
    if (current.isGranted) {
      _backgroundPermissionGranted = true;
      return true;
    }
    if (!allowPrompt) {
      _backgroundPermissionGranted = false;
      return false;
    }
    final ph.PermissionStatus requested =
        await ph.Permission.locationAlways.request();
    _backgroundPermissionGranted = requested.isGranted;
    return _backgroundPermissionGranted;
  }

  // Asks Android to exempt WakeMe from battery optimization. This is the single
  // biggest factor in whether aggressive OEMs (Samsung One UI especially) let
  // the foreground location service keep running once the screen is off. Shows
  // a one-tap system dialog; no-op if already exempt or unsupported.
  Future<bool> ensureBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    final ph.PermissionStatus status =
        await ph.Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return true;
    final ph.PermissionStatus requested =
        await ph.Permission.ignoreBatteryOptimizations.request();
    return requested.isGranted;
  }

  Future<Position?> getCurrentPosition() async {
    if (_permission != LocationPermissionState.granted) {
      await init();
    }
    if (_permission != LocationPermissionState.granted) {
      return null;
    }
    try {
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPosition = pos;
      notifyListeners();
      return pos;
    } catch (_) {
      return _lastPosition;
    }
  }

  void startTracking({bool background = false}) {
    // If we're already tracking in the right mode, do nothing. If the caller
    // is asking for background mode but we started in foreground (or vice
    // versa), tear down and restart with the correct settings.
    if (_subscription != null && _backgroundMode == background) return;
    _subscription?.cancel();
    _subscription = null;
    _backgroundMode = background;
    final LocationSettings settings =
        background ? _backgroundSettings() : _foregroundSettings;
    _subscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position pos) {
        _lastPosition = pos;
        _broadcast.add(pos);
        notifyListeners();
      },
      onError: (_) {},
    );
  }

  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    _backgroundMode = false;
  }

  double distanceTo(LatLng destination) {
    final Position? pos = _lastPosition;
    if (pos == null) return double.infinity;
    return Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      destination.latitude,
      destination.longitude,
    );
  }

  static double distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  void _setPermission(LocationPermissionState state) {
    if (_permission == state) return;
    _permission = state;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    _broadcast.close();
    super.dispose();
  }
}
