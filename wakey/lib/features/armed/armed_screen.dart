import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/destination_model.dart';
import '../../core/services/background_alarm_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/routing_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/widgets/map_controls.dart';

class ArmedScreen extends StatefulWidget {
  const ArmedScreen({
    super.key,
    required this.destination,
    required this.radiusMeters,
  });

  final DestinationModel destination;
  final double radiusMeters;

  @override
  State<ArmedScreen> createState() => _ArmedScreenState();
}

class _ArmedScreenState extends State<ArmedScreen>
    with WidgetsBindingObserver {
  // Shared with MainActivity.kt — native invokes "dismissAlarm" when a volume
  // key is pressed while the alarm is ringing.
  static const MethodChannel _keyChannel = MethodChannel('wakey/alarm_keys');
  // Friendly captions that replace the old "WAKEY ARMED" pill — one is
  // randomly chosen per arm, so every Sleep tap feels a little different.
  static const List<String> _captions = <String>[
    'Sleep tight 😴',
    'Sweet dreams ahead',
    "We've got you",
    'Snooze mode on',
    'Rest easy',
    'Drift off — Wakey is awake',
    'Zzz mode engaged',
    'Catching some Z\'s',
    'Naptime ✨',
    'Eyes closed, alarm armed',
    'Power nap activated',
    "We'll wake you in time",
    'Dreamland, here you come',
  ];

  GoogleMapController? _mapController;
  // Live position now comes from the background service's 'update' events
  // (single GPS stream, owned by the service) rather than a second stream
  // here. These subscriptions are the bridge.
  StreamSubscription<Map<String, dynamic>?>? _updateSub;
  StreamSubscription<Map<String, dynamic>?>? _arrivedSub;
  LatLng? _userPosition;
  double? _distance;
  bool _arrived = false;
  bool _dialogShown = false;

  // Navigation view state.
  //  _isFollowing  — true after the recenter button: camera locks to the user,
  //                  tilts, and rotates so heading is "up". Any manual map
  //                  gesture drops back to false (free pan); recenter re-enters.
  //  _heading      — last good GPS course (deg, cw from north). Only updated
  //                  while actually moving so the arrow doesn't spin in place.
  //  _animatingCamera — set around our own animateCamera calls so the
  //                  onCameraMoveStarted handler can tell a programmatic move
  //                  from the user grabbing the map.
  bool _isFollowing = false;
  double _heading = 0;
  bool _animatingCamera = false;

  static const double _navZoom = 17.5;
  static const double _navTilt = 50;

  List<RouteResult> _routes = const <RouteResult>[];
  DateTime? _lastRerouteAt;
  bool _rerouting = false;

  RouteResult? get _primaryRoute => _routes.isEmpty ? null : _routes.first;

  late final LatLng _destination = LatLng(
    widget.destination.lat,
    widget.destination.lng,
  );
  late final String _topCaption =
      _captions[Random().nextInt(_captions.length)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Native pushes "dismissAlarm" here when a volume key is pressed while
    // the alarm rings (handler set in MainActivity.kt).
    _keyChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'dismissAlarm') {
        await _dismissAlarm();
      }
      return null;
    });
    // Live position + arrival both come from the background service isolate.
    _updateSub =
        BackgroundAlarmService.instance.on('update').listen(_onServiceUpdate);
    _arrivedSub =
        BackgroundAlarmService.instance.on('arrived').listen((_) {
      _onArrived();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  // Single dismissal path used by the Dismiss button, the volume keys, and
  // the lock button. Stops the background service, then returns all the way
  // home — popUntil(isFirst) clears both the arrival dialog and this screen.
  Future<void> _dismissAlarm() async {
    if (!_arrived) return;
    _arrived = false;
    final LocationService location = context.read<LocationService>();
    final NavigatorState navigator = Navigator.of(context);
    await BackgroundAlarmService.stop();
    _keyChannel.invokeMethod<void>('setAlarmActive', false);
    location.stopTracking();
    unawaited(WakelockPlus.disable());
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pressing the lock / power button sends the app to paused. If the alarm
    // is actively ringing, treat that as "silence it" — matches how a phone
    // alarm stops when you hit the side button. Only when arrived, so locking
    // the phone BEFORE arrival (the whole background point) doesn't dismiss.
    if (state == AppLifecycleState.paused && _arrived) {
      _dismissAlarm();
    }
    // Coming back to the foreground (e.g. via the alarm's full-screen intent):
    // the 'arrived' event may have fired while we were suspended, so check the
    // persisted flag and surface the dialog if we missed the live event.
    if (state == AppLifecycleState.resumed && !_arrived) {
      _checkArrivedFlag();
    }
  }

  Future<void> _checkArrivedFlag() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kArrivedFlag) ?? false) {
      _onArrived();
    }
  }

  Future<void> _arm() async {
    final LocationService location = context.read<LocationService>();
    final String? customPath = context.read<StorageService>().alarmSoundPath;
    await WakelockPlus.enable();
    await location.init();
    await location.ensureBackgroundPermission(allowPrompt: false);

    // Hand the destination to the background service, which owns the GPS
    // stream + arrival alarm from here on. This is what keeps the alarm
    // firing when the app is backgrounded / the screen is locked.
    await BackgroundAlarmService.startArmed(
      lat: widget.destination.lat,
      lng: widget.destination.lng,
      name: widget.destination.name,
      radius: widget.radiusMeters,
      soundPath: customPath,
    );

    // Seed the camera + initial route from a one-shot position read; live
    // updates then arrive via the service 'update' stream.
    final Position? current = await location.getCurrentPosition();
    if (current != null && mounted) {
      setState(() {
        _userPosition = LatLng(current.latitude, current.longitude);
        _distance = _distanceFromPosition(current);
      });
      _fitCameraToBoth();
      await _ensureRoute(force: true);
    }
  }

  // Off-route detection: if the user has drifted further than the threshold
  // from the planned line AND the cooldown has elapsed, ask Google Directions
  // for a new route. The cooldown prevents hammering the API.
  Future<void> _ensureRoute({bool force = false}) async {
    final LatLng? user = _userPosition;
    if (user == null) return;
    if (_rerouting) return;
    if (!force) {
      final DateTime? last = _lastRerouteAt;
      if (last != null &&
          DateTime.now().difference(last) < AppConstants.rerouteCooldown) {
        return;
      }
    }
    setState(() => _rerouting = true);
    final List<RouteResult> routes =
        await RoutingService.getDrivingRoutes(user, _destination);
    if (!mounted) return;
    setState(() {
      if (routes.isNotEmpty) _routes = routes;
      _rerouting = false;
      _lastRerouteAt = DateTime.now();
    });
  }

  double _distanceFromPosition(Position pos) {
    return Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.destination.lat,
      widget.destination.lng,
    );
  }

  // Fit-view (⤢) button: leave follow mode and frame the whole route
  // (newLatLngBounds resets tilt + bearing to north-up automatically).
  void _fitCameraToBoth() {
    if (_isFollowing) setState(() => _isFollowing = false);
    final LatLng? user = _userPosition;
    if (user == null || _mapController == null) {
      _animatingCamera = true;
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_destination, 15));
      return;
    }
    final List<LatLng> points = <LatLng>[user, _destination];
    final RouteResult? route = _primaryRoute;
    if (route != null) points.addAll(route.points);
    final LatLngBounds bounds = _boundsFromPoints(points);
    _animatingCamera = true;
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  // Recenter button: enter the navigation follow-cam (tilted, heading-up,
  // glued to the user). Stays until a manual gesture drops it to free mode.
  void _centerOnUser() {
    setState(() => _isFollowing = true);
    _animateNavCamera();
  }

  LatLngBounds _boundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final LatLng p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Live GPS pushed from the background service isolate while the app is on
  // screen. Updates the map + distance + reroute. Arrival/alarm is handled by
  // the service itself (see _onArrived), not here.
  void _onServiceUpdate(Map<String, dynamic>? data) {
    if (!mounted || data == null) return;
    final double? lat = (data['lat'] as num?)?.toDouble();
    final double? lng = (data['lng'] as num?)?.toDouble();
    final double? distance = (data['distance'] as num?)?.toDouble();
    final double? heading = (data['heading'] as num?)?.toDouble();
    final double? speed = (data['speed'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final LatLng userLatLng = LatLng(lat, lng);

    // Only trust GPS course while actually moving — below ~0.5 m/s it's noise,
    // so we hold the last heading instead of letting the arrow spin in place.
    if (heading != null &&
        heading >= 0 &&
        speed != null &&
        speed > 0.5) {
      _heading = heading;
    }

    setState(() {
      _userPosition = userLatLng;
      _distance = distance;
    });

    // Follow mode: keep the camera glued to the user, heading up. Free mode:
    // leave the camera wherever the user last put it.
    if (_isFollowing) {
      _animateNavCamera();
    }

    final RouteResult? route = _primaryRoute;
    if (route != null) {
      final double offRoute = RoutingService.pointToPolylineDistanceMeters(
        userLatLng,
        route.points,
      );
      if (offRoute > AppConstants.rerouteDistanceThresholdMeters) {
        unawaited(_ensureRoute());
      }
    }
  }

  // Animate to the tilted, heading-up navigation framing centered on the user.
  void _animateNavCamera() {
    final LatLng? user = _userPosition;
    if (user == null || _mapController == null) return;
    _animatingCamera = true;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: user,
          zoom: _navZoom,
          tilt: _navTilt,
          bearing: _heading,
        ),
      ),
    );
  }

  // Fired by the service when the user enters the radius. The service has
  // already started the notification + sound + vibration; here we just bring
  // up the dialog and arm the volume-key interception for the live screen.
  void _onArrived() {
    if (_arrived) return;
    _arrived = true;
    _keyChannel.invokeMethod<void>('setAlarmActive', true);
    if (!_dialogShown && mounted) {
      _dialogShown = true;
      _showArrivalDialog();
    }
  }

  Future<void> _showArrivalDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title:
              const Text("You're almost there!", style: AppTextStyles.title),
          content: Text(
            'Wakey is buzzing because you are within ${widget.radiusMeters.round()}m of ${widget.destination.name}.\n\n'
            'Tip: press volume or the lock button to silence it.',
            style: AppTextStyles.bodyMuted,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _dismissAlarm,
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
  }

  void _cancel() {
    // Pop FIRST so a slow plugin call can never strand the user here.
    // Cancel explicitly tears down the background service — leaving the Armed
    // screen by Cancel means "disarm". (dispose() deliberately does NOT stop
    // the service, so backgrounding keeps the alarm alive.)
    final LocationService location = context.read<LocationService>();
    Navigator.of(context)
        .popUntil((Route<dynamic> route) => route.isFirst);
    _keyChannel.invokeMethod<void>('setAlarmActive', false);
    unawaited(BackgroundAlarmService.stop());
    location.stopTracking();
    unawaited(WakelockPlus.disable());
  }

  String _distanceLabel() {
    final double? d = _distance;
    if (d == null) return 'Tracking position…';
    if (d.isInfinite) return 'Searching for GPS…';
    if (d >= 1000) {
      return '${(d / 1000).toStringAsFixed(1)} km away';
    }
    return '${d.round()} m away';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyChannel.setMethodCallHandler(null);
    _updateSub?.cancel();
    _arrivedSub?.cancel();
    _mapController?.dispose();
    // NOTE: deliberately does NOT stop the background service — if the screen
    // is disposed because the app was backgrounded, we WANT the service to
    // keep tracking. Only Cancel / Dismiss tear it down.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _destination,
              zoom: 15,
            ),
            // Google's own location indicator — blue dot + heading beam,
            // drawn and rotated natively. Professional and free; the tilt /
            // heading follow-cam is still driven by our GPS heading.
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            // A camera move that starts WITHOUT us flagging _animatingCamera is
            // the user's finger → drop out of follow mode and stay put.
            onCameraMoveStarted: () {
              if (!_animatingCamera && _isFollowing) {
                setState(() => _isFollowing = false);
              }
            },
            onCameraIdle: () => _animatingCamera = false,
            markers: <Marker>{
              Marker(
                markerId: MarkerId(widget.destination.id),
                position: _destination,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet,
                ),
                infoWindow: InfoWindow(title: widget.destination.name),
              ),
            },
            circles: <Circle>{
              Circle(
                circleId: CircleId('radius_${widget.destination.id}'),
                center: _destination,
                radius: widget.radiusMeters,
                fillColor: AppColors.mapCircleFill,
                strokeColor: AppColors.mapCircleStroke,
                strokeWidth: 2,
              ),
            },
            polylines: <Polyline>{
              // Alternatives behind primary (lower zIndex).
              for (int i = _routes.length - 1; i > 0; i--)
                Polyline(
                  polylineId: PolylineId('route_alt_$i'),
                  points: _routes[i].points,
                  color: Colors.grey.withValues(alpha: 0.65),
                  width: 5,
                  zIndex: 0,
                ),
              if (_primaryRoute != null)
                Polyline(
                  polylineId: const PolylineId('route_primary'),
                  // Trim the polyline so the segment already travelled drops
                  // off the map and the line visually starts at the user.
                  points: _userPosition == null
                      ? _primaryRoute!.points
                      : RoutingService.trimPolylineFromPosition(
                          _userPosition!,
                          _primaryRoute!.points,
                        ),
                  color: AppColors.primaryLight,
                  width: 6,
                  zIndex: 1,
                ),
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primaryLight.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _topCaption,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_rerouting) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Rerouting…',
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            // Just above the bottom card (name + distance + ETA + Cancel).
            bottom: 250,
            child: MapControls(
              onMyLocation: _centerOnUser,
              onFitView: _fitCameraToBoth,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomCard(
              destinationName: widget.destination.name,
              distanceLabel: _distanceLabel(),
              routeEta: _primaryRoute == null
                  ? null
                  : '${RoutingService.formatDuration(_primaryRoute!.durationSeconds)} · '
                      '${RoutingService.formatDistance(_primaryRoute!.distanceMeters)} via map',
              onCancel: _cancel,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.destinationName,
    required this.distanceLabel,
    required this.routeEta,
    required this.onCancel,
  });

  final String destinationName;
  final String distanceLabel;
  final String? routeEta;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              destinationName,
              textAlign: TextAlign.center,
              style: AppTextStyles.headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              distanceLabel,
              textAlign: TextAlign.center,
              style: AppTextStyles.title.copyWith(
                color: AppColors.primaryLight,
              ),
            ),
            if (routeEta != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                routeEta!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  foregroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cancel() => onCancel();
}
