import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

class PlaceResult {
  const PlaceResult({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });

  final String displayName;
  final String shortName;
  final double lat;
  final double lng;
}

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? structured =
        json['structured_formatting'] as Map<String, dynamic>?;
    return PlacePrediction(
      placeId: (json['place_id'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      mainText: (structured?['main_text'] as String?) ?? '',
      secondaryText: (structured?['secondary_text'] as String?) ?? '',
    );
  }
}

// Google Maps Platform REST client for the three things WakeMe needs:
//   1. searchPlaces — autocomplete predictions for the search bar
//   2. getPlaceDetails — coordinates for a prediction the user tapped
//   3. reverseLookup — address for an arbitrary tapped-on-map point
//
// Forward search is handled here (not via google_places_flutter) so the
// dropdown UI stays fully under our control.
class GeocodingService {
  GeocodingService._();

  static Future<List<PlacePrediction>> searchPlaces(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <PlacePrediction>[];
    final String? key = dotenv.maybeGet(AppConstants.envMapsKey);
    if (key == null || key.isEmpty) return const <PlacePrediction>[];
    final Uri uri = Uri.https(
      AppConstants.directionsHost,
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': trimmed,
        'key': key,
      },
    );
    try {
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const <PlacePrediction>[];
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      final String? status = body['status'] as String?;
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        return const <PlacePrediction>[];
      }
      final List<dynamic>? predictions = body['predictions'] as List<dynamic>?;
      if (predictions == null) return const <PlacePrediction>[];
      return predictions
          .whereType<Map<String, dynamic>>()
          .map(PlacePrediction.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <PlacePrediction>[];
    }
  }

  static Future<PlaceResult?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty) return null;
    final String? key = dotenv.maybeGet(AppConstants.envMapsKey);
    if (key == null || key.isEmpty) return null;
    final Uri uri = Uri.https(
      AppConstants.directionsHost,
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId,
        'fields': 'name,formatted_address,geometry',
        'key': key,
      },
    );
    try {
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final Map<String, dynamic>? result =
          body['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final Map<String, dynamic>? geo =
          result['geometry'] as Map<String, dynamic>?;
      final Map<String, dynamic>? location =
          geo?['location'] as Map<String, dynamic>?;
      if (location == null) return null;
      return PlaceResult(
        displayName: (result['formatted_address'] as String?) ??
            (result['name'] as String?) ??
            '',
        shortName: (result['name'] as String?) ??
            (result['formatted_address'] as String?) ??
            'Destination',
        lat: (location['lat'] as num).toDouble(),
        lng: (location['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<PlaceResult?> reverseLookup(double lat, double lng) async {
    final String? key = dotenv.maybeGet(AppConstants.envMapsKey);
    if (key == null || key.isEmpty) return null;
    final Uri uri = Uri.https(
      AppConstants.directionsHost,
      AppConstants.geocodingPath,
      <String, String>{
        'latlng': '$lat,$lng',
        'key': key,
      },
    );
    try {
      final http.Response res =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final List<dynamic> results = body['results'] as List<dynamic>;
      if (results.isEmpty) return null;
      final Map<String, dynamic> first =
          results.first as Map<String, dynamic>;
      final String displayName =
          (first['formatted_address'] as String?) ?? 'Pinned location';
      final String shortName = _shortNameFrom(first) ?? displayName;
      final Map<String, dynamic> geo =
          first['geometry'] as Map<String, dynamic>;
      final Map<String, dynamic> location =
          geo['location'] as Map<String, dynamic>;
      return PlaceResult(
        displayName: displayName,
        shortName: shortName,
        lat: (location['lat'] as num).toDouble(),
        lng: (location['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _shortNameFrom(Map<String, dynamic> result) {
    final List<dynamic>? components =
        result['address_components'] as List<dynamic>?;
    if (components == null) return null;
    const List<String> preferredTypes = <String>[
      'point_of_interest',
      'establishment',
      'premise',
      'route',
      'neighborhood',
      'sublocality',
      'locality',
    ];
    for (final String type in preferredTypes) {
      for (final dynamic c in components) {
        final Map<String, dynamic> comp = c as Map<String, dynamic>;
        final List<dynamic> types = comp['types'] as List<dynamic>;
        if (types.contains(type)) return comp['long_name'] as String?;
      }
    }
    return null;
  }
}
