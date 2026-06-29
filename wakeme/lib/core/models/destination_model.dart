import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

class DestinationModel {
  const DestinationModel({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.iconName = 'place',
    this.removable = true,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String iconName;
  // Seeded favorites (Home/University/Work) ship as removable=false so the
  // UI hides the delete badge for them — the user can re-point them, but
  // they're meant to stay in the favorites row as defaults.
  final bool removable;

  LatLng get latLng => LatLng(lat, lng);

  factory DestinationModel.create({
    required String name,
    required String address,
    required double lat,
    required double lng,
    String iconName = 'place',
    bool removable = true,
  }) {
    return DestinationModel(
      id: const Uuid().v4(),
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      iconName: iconName,
      removable: removable,
    );
  }

  DestinationModel copyWith({
    String? id,
    String? name,
    String? address,
    double? lat,
    double? lng,
    String? iconName,
    bool? removable,
  }) {
    return DestinationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      iconName: iconName ?? this.iconName,
      removable: removable ?? this.removable,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'iconName': iconName,
        'removable': removable,
      };

  String toJson() => jsonEncode(toMap());

  factory DestinationModel.fromMap(Map<String, dynamic> map) {
    return DestinationModel(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Unknown',
      address: map['address'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      iconName: map['iconName'] as String? ?? 'place',
      removable: map['removable'] as bool? ?? true,
    );
  }

  factory DestinationModel.fromJson(String source) =>
      DestinationModel.fromMap(jsonDecode(source) as Map<String, dynamic>);

  static IconData iconFor(String name) {
    switch (name) {
      case 'home':
        return Icons.home_rounded;
      case 'university':
      case 'school':
        return Icons.school_rounded;
      case 'work':
      case 'briefcase':
        return Icons.work_rounded;
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'cafe':
        return Icons.local_cafe_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'history':
        return Icons.history_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DestinationModel &&
          other.id == id &&
          other.lat == lat &&
          other.lng == lng);

  @override
  int get hashCode => Object.hash(id, lat, lng);
}
