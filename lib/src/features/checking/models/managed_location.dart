String _normalizeLocationKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class ManagedLocation {
  static const String checkoutZoneLabel = 'Zona de CheckOut';
  static final Set<String> _checkoutZoneNames = <String>{
    'zona de checkout 1',
    'zona de checkout 2',
    'zona de checkout 3',
    'zona de checkout 4',
    'zona de checkout 5',
  };

  const ManagedLocation({
    required this.id,
    required this.local,
    required this.latitude,
    required this.longitude,
    required this.toleranceMeters,
    required this.updatedAt,
  });

  factory ManagedLocation.fromApiJson(Map<String, dynamic> json) {
    return ManagedLocation(
      id: json['id'] as int? ?? 0,
      local: (json['local'] as String? ?? '').trim(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      toleranceMeters: json['tolerance_meters'] as int? ?? 0,
      updatedAt:
          _parseDateTime(json['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory ManagedLocation.fromDatabase(Map<String, Object?> row) {
    return ManagedLocation(
      id: row['id'] as int? ?? 0,
      local: (row['local'] as String? ?? '').trim(),
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0,
      toleranceMeters: row['tolerance_meters'] as int? ?? 0,
      updatedAt:
          _parseDateTime(row['updated_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int id;
  final String local;
  final double latitude;
  final double longitude;
  final int toleranceMeters;
  final DateTime updatedAt;

  bool get isCheckoutZone =>
      _checkoutZoneNames.contains(_normalizeLocationKey(local));

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
      'tolerance_meters': toleranceMeters,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
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
    required this.locationUpdateIntervalSeconds,
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
      locationUpdateIntervalSeconds:
          (json['location_update_interval_seconds'] as num?)?.toInt() ?? 60,
    );
  }

  final List<ManagedLocation> items;
  final DateTime syncedAt;
  final int locationUpdateIntervalSeconds;
}
