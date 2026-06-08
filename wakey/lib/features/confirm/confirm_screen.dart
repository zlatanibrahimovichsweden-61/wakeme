import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/destination_model.dart';
import '../../core/services/location_service.dart';
import '../../core/services/routing_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/widgets/map_controls.dart';
import '../armed/armed_screen.dart';
import 'widgets/radius_slider.dart';

class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key, required this.destination});

  final DestinationModel destination;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  GoogleMapController? _mapController;
  double _radius = AppConstants.defaultRadiusMeters;
  LatLng? _userPosition;
  List<RouteResult> _routes = const <RouteResult>[];
  bool _loadingRoute = false;

  RouteResult? get _primaryRoute => _routes.isEmpty ? null : _routes.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
  }

  Future<void> _loadRoute() async {
    final LocationService location = context.read<LocationService>();
    Position? pos = location.lastPosition;
    pos ??= await _safePosition(location);
    if (!mounted || pos == null) return;
    final LatLng user = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _userPosition = user;
      _loadingRoute = true;
    });
    final List<RouteResult> routes = await RoutingService.getDrivingRoutes(
      user,
      widget.destination.latLng,
    );
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _loadingRoute = false;
    });
    _fitCamera();
  }

  Future<Position?> _safePosition(LocationService service) async {
    try {
      return await service.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  void _fitCamera() {
    final LatLng? user = _userPosition;
    if (user == null || _mapController == null) return;
    final List<LatLng> points = <LatLng>[user, widget.destination.latLng];
    final RouteResult? r = _primaryRoute;
    if (r != null) points.addAll(r.points);
    final LatLngBounds bounds = _boundsFromPoints(points);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _centerOnUser() {
    final LatLng? user = _userPosition;
    if (user == null) return;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(user, 17));
  }

  // Google's LatLngBounds requires SW + NE corners explicitly, unlike
  // flutter_map's fromPoints constructor. Build them by min/maxing manually.
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

  String get _subtitle {
    final RouteResult? r = _primaryRoute;
    if (r != null) {
      final String base = '${RoutingService.formatDuration(r.durationSeconds)} · '
          '${RoutingService.formatDistance(r.distanceMeters)} via map';
      final int altCount = _routes.length - 1;
      return altCount > 0 ? '$base · $altCount alt route${altCount > 1 ? 's' : ''}' : base;
    }
    if (_loadingRoute) return 'Planning route…';
    if (_userPosition == null) return 'Waiting for your location…';
    return 'Route unavailable — using straight-line distance';
  }

  Future<void> _startAlarm() async {
    await context.read<StorageService>().addRecent(widget.destination);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ArmedScreen(
          destination: widget.destination,
          radiusMeters: _radius,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
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
              target: widget.destination.latLng,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            markers: <Marker>{
              Marker(
                markerId: MarkerId(widget.destination.id),
                position: widget.destination.latLng,
                infoWindow: InfoWindow(title: widget.destination.name),
              ),
            },
            circles: <Circle>{
              Circle(
                circleId: CircleId('radius_${widget.destination.id}'),
                center: widget.destination.latLng,
                radius: _radius,
                fillColor: AppColors.mapCircleFill,
                strokeColor: AppColors.mapCircleStroke,
                strokeWidth: 2,
              ),
            },
            polylines: <Polyline>{
              // Alternatives first (lower zIndex) so primary draws on top.
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
                  points: _primaryRoute!.points,
                  color: AppColors.primaryLight,
                  width: 6,
                  zIndex: 1,
                ),
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _BackButton(onTap: () => Navigator.of(context).pop()),
            ),
          ),
          Positioned(
            right: 16,
            // Just above the fixed 304-px bottom card (name + radius slider).
            bottom: 316,
            child: MapControls(
              onMyLocation: _centerOnUser,
              onFitView: _fitCamera,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomCard(
              destination: widget.destination,
              radius: _radius,
              subtitle: _subtitle,
              routeDistanceMeters: _primaryRoute?.distanceMeters,
              routeDurationSeconds: _primaryRoute?.durationSeconds,
              onRadiusChanged: (double v) {
                setState(() => _radius = v);
              },
              onArm: _startAlarm,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.85),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.destination,
    required this.radius,
    required this.subtitle,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    required this.onRadiusChanged,
    required this.onArm,
  });

  final DestinationModel destination;
  final double radius;
  final String subtitle;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onArm;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 304,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black87,
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            destination.name,
            style: AppTextStyles.headline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTextStyles.bodyMuted),
          const SizedBox(height: 18),
          RadiusSlider(
            value: radius,
            min: AppConstants.minRadiusMeters,
            max: AppConstants.maxRadiusMeters,
            onChanged: onRadiusChanged,
            routeDistanceMeters: routeDistanceMeters,
            routeDurationSeconds: routeDurationSeconds,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: onArm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text('Sleep 😴', style: AppTextStyles.buttonLarge),
            ),
          ),
        ],
      ),
    );
  }
}
