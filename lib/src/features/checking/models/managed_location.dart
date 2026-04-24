import 'dart:convert';

String _normalizeLocationKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class ManagedLocationCoordinate {
  const ManagedLocationCoordinate({
    required this.latitude,
    required this.longitude,
  });

  factory ManagedLocationCoordinate.fromJson(Map<String, dynamic> json) {
    return ManagedLocationCoordinate(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() {
    return <String, Object?>{'latitude': latitude, 'longitude': longitude};
  }
}

class ManagedLocation {
  static const String checkoutZoneLabel = 'Zona de CheckOut';
  static final RegExp _checkoutZoneNamePattern = RegExp(
    r'^zona de checkout(?: \d+)?$',
  );

  ManagedLocation({
    required this.id,
    required this.local,
    required this.latitude,
    required this.longitude,
    required this.toleranceMeters,
    required this.updatedAt,
    List<ManagedLocationCoordinate>? coordinates,
  }) : coordinates = List.unmodifiable(
         (coordinates == null || coordinates.isEmpty)
             ? <ManagedLocationCoordinate>[
                 ManagedLocationCoordinate(
                   latitude: latitude,
                   longitude: longitude,
                 ),
               ]
             : coordinates,
       );

  factory ManagedLocation.fromApiJson(Map<String, dynamic> json) {
    final fallbackLatitude = (json['latitude'] as num?)?.toDouble() ?? 0;
    final fallbackLongitude = (json['longitude'] as num?)?.toDouble() ?? 0;
    return ManagedLocation(
      id: json['id'] as int? ?? 0,
      local: (json['local'] as String? ?? '').trim(),
      latitude: fallbackLatitude,
      longitude: fallbackLongitude,
      toleranceMeters: json['tolerance_meters'] as int? ?? 0,
      updatedAt:
          _parseDateTime(json['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      coordinates: _parseCoordinates(
        json['coordinates'],
        fallbackLatitude: fallbackLatitude,
        fallbackLongitude: fallbackLongitude,
      ),
    );
  }

  factory ManagedLocation.fromDatabase(Map<String, Object?> row) {
    final fallbackLatitude = (row['latitude'] as num?)?.toDouble() ?? 0;
    final fallbackLongitude = (row['longitude'] as num?)?.toDouble() ?? 0;
    return ManagedLocation(
      id: row['id'] as int? ?? 0,
      local: (row['local'] as String? ?? '').trim(),
      latitude: fallbackLatitude,
      longitude: fallbackLongitude,
      toleranceMeters: row['tolerance_meters'] as int? ?? 0,
      updatedAt:
          _parseDateTime(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      coordinates: _parseCoordinates(
        _decodeCoordinatesJson(row['coordinates_json']),
        fallbackLatitude: fallbackLatitude,
        fallbackLongitude: fallbackLongitude,
      ),
    );
  }

  final int id;
  final String local;
  final double latitude;
  final double longitude;
  final List<ManagedLocationCoordinate> coordinates;
  final int toleranceMeters;
  final DateTime updatedAt;

  bool get isCheckoutZone =>
      _checkoutZoneNamePattern.hasMatch(_normalizeLocationKey(local));

  String get automationAreaLabel => isCheckoutZone ? checkoutZoneLabel : local;

  bool matchesLocationName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    return _normalizeLocationKey(local) == _normalizeLocationKey(value);
  }

  Map<String, Object?> toDatabase() {
    return <String, Object?>{
      'id': id,
      'local': local,
      'latitude': latitude,
      'longitude': longitude,
      'coordinates_json': jsonEncode(
        coordinates
            .map((coordinate) => coordinate.toJson())
            .toList(growable: false),
      ),
      'tolerance_meters': toleranceMeters,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  static Object? _decodeCoordinatesJson(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static List<ManagedLocationCoordinate> _parseCoordinates(
    Object? value, {
    required double fallbackLatitude,
    required double fallbackLongitude,
  }) {
    if (value is List) {
      final parsedCoordinates = value
          .whereType<Map<String, dynamic>>()
          .map(ManagedLocationCoordinate.fromJson)
          .toList(growable: false);
      if (parsedCoordinates.isNotEmpty) {
        return parsedCoordinates;
      }
    }

    return <ManagedLocationCoordinate>[
      ManagedLocationCoordinate(
        latitude: fallbackLatitude,
        longitude: fallbackLongitude,
      ),
    ];
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}

class LocationCatalogResponse {
  const LocationCatalogResponse({
    required this.items,
    required this.syncedAt,
    required this.locationAccuracyThresholdMeters,
    required this.minimumCheckoutDistanceMetersByProject,
  });

  factory LocationCatalogResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const <dynamic>[];
    return LocationCatalogResponse(
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(ManagedLocation.fromApiJson)
          .toList(growable: false),
      syncedAt:
          ManagedLocation._parseDateTime(json['synced_at']) ?? DateTime.now(),
      locationAccuracyThresholdMeters:
          (json['location_accuracy_threshold_meters'] as num?)?.toInt() ?? 30,
      minimumCheckoutDistanceMetersByProject:
          _parseMinimumCheckoutDistanceMetersByProject(
            json['minimum_checkout_distance_meters_by_project'],
          ),
    );
  }

  static Map<String, int> _parseMinimumCheckoutDistanceMetersByProject(
    Object? value,
  ) {
    if (value is! Map) {
      return const <String, int>{};
    }

    final parsed = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key is String
          ? entry.key.toString().trim().toUpperCase()
          : '';
      final meters = (entry.value as num?)?.toInt();
      if (key.isEmpty || meters == null || meters < 1) {
        continue;
      }
      parsed[key] = meters;
    }
    return Map<String, int>.unmodifiable(parsed);
  }

  final List<ManagedLocation> items;
  final DateTime syncedAt;
  final int locationAccuracyThresholdMeters;
  final Map<String, int> minimumCheckoutDistanceMetersByProject;
}
