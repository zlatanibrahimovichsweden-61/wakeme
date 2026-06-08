import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

// Google Directions REST client. Returns a decoded polyline plus the total
// road distance / duration as reported by Google for the requested mode.
class RoutingService {
  RoutingService._();

  // Returns up to 3 routes from Google Directions. Index 0 is Google's
  // "primary" recommendation; the rest are alternatives.
  static Future<List<RouteResult>> getDrivingRoutes(
    LatLng start,
    LatLng end,
  ) async {
    final String? key = dotenv.maybeGet(AppConstants.envMapsKey);
    if (key == null || key.isEmpty) return const <RouteResult>[];
    final Uri uri = Uri.https(
      AppConstants.directionsHost,
      AppConstants.directionsPath,
      <String, String>{
        'origin': '${start.latitude},${start.longitude}',
        'destination': '${end.latitude},${end.longitude}',
        'mode': 'driving',
        'alternatives': 'true',
        'key': key,
      },
    );
    try {
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const <RouteResult>[];
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return const <RouteResult>[];
      final List<dynamic> routes = body['routes'] as List<dynamic>;
      return routes
          .whereType<Map<String, dynamic>>()
          .map(_parseRoute)
          .whereType<RouteResult>()
          .toList(growable: false);
    } catch (_) {
      return const <RouteResult>[];
    }
  }

  static RouteResult? _parseRoute(Map<String, dynamic> route) {
    try {
      final Map<String, dynamic> overview =
          route['overview_polyline'] as Map<String, dynamic>;
      final String encoded = overview['points'] as String;
      final List<LatLng> points = decodePolyline(encoded);

      double distance = 0;
      double duration = 0;
      for (final dynamic leg in route['legs'] as List<dynamic>) {
        final Map<String, dynamic> legMap = leg as Map<String, dynamic>;
        distance += (legMap['distance']['value'] as num).toDouble();
        duration += (legMap['duration']['value'] as num).toDouble();
      }

      return RouteResult(
        points: points,
        distanceMeters: distance,
        durationSeconds: duration,
      );
    } catch (_) {
      return null;
    }
  }

  // Standard Google Encoded Polyline decoder.
  // See https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = <LatLng>[];
    int index = 0;
    final int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // Minimum distance (in meters) from `point` to any segment of the polyline.
  // Uses a local equirectangular projection — accurate within a few km, which
  // is plenty for off-route detection.
  static double pointToPolylineDistanceMeters(
    LatLng point,
    List<LatLng> line,
  ) {
    if (line.length < 2) return double.infinity;
    double minDist = double.infinity;
    for (int i = 0; i < line.length - 1; i++) {
      final _SegmentProjection p =
          _projectOntoSegment(point, line[i], line[i + 1]);
      if (p.distance < minDist) minDist = p.distance;
    }
    return minDist;
  }

  // Returns the polyline with everything *before* the user's current position
  // removed, so the drawn route only covers what's left to travel. The first
  // point is the exact projection of the user onto the route, so the line
  // visually starts right at the user marker.
  static List<LatLng> trimPolylineFromPosition(
    LatLng user,
    List<LatLng> line,
  ) {
    if (line.length < 2) return line;
    int bestIdx = 0;
    double bestT = 0;
    double minDist = double.infinity;
    for (int i = 0; i < line.length - 1; i++) {
      final _SegmentProjection p =
          _projectOntoSegment(user, line[i], line[i + 1]);
      if (p.distance < minDist) {
        minDist = p.distance;
        bestIdx = i;
        bestT = p.t;
      }
    }
    final LatLng a = line[bestIdx];
    final LatLng b = line[bestIdx + 1];
    final LatLng snapped = LatLng(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    );
    return <LatLng>[snapped, ...line.sublist(bestIdx + 1)];
  }

  static _SegmentProjection _projectOntoSegment(LatLng p, LatLng a, LatLng b) {
    const double mPerDegLat = 111320.0;
    final double mPerDegLng = 111320.0 * math.cos(a.latitude * math.pi / 180);
    final double px = (p.longitude - a.longitude) * mPerDegLng;
    final double py = (p.latitude - a.latitude) * mPerDegLat;
    final double bx = (b.longitude - a.longitude) * mPerDegLng;
    final double by = (b.latitude - a.latitude) * mPerDegLat;
    final double segLenSq = bx * bx + by * by;
    if (segLenSq == 0) {
      return _SegmentProjection(math.sqrt(px * px + py * py), 0);
    }
    double t = (px * bx + py * by) / segLenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final double dx = px - t * bx;
    final double dy = py - t * by;
    return _SegmentProjection(math.sqrt(dx * dx + dy * dy), t);
  }

  static String formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.round()} s';
    final int minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final int hours = minutes ~/ 60;
    final int rem = minutes % 60;
    return rem == 0 ? '$hours h' : '$hours h $rem min';
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class _SegmentProjection {
  const _SegmentProjection(this.distance, this.t);
  final double distance;
  final double t;
}
