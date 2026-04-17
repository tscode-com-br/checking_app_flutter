import 'package:checking/src/features/checking/checking_preset_config.dart';

enum RegistroType { checkIn, checkOut }

enum InformeType { normal, retroativo }

enum ProjetoType { p80, p82, p83 }

enum StatusTone { neutral, success, warning, error }

extension RegistroTypeX on RegistroType {
  String get label => this == RegistroType.checkIn ? 'Check-In' : 'Check-Out';
  String get apiValue => this == RegistroType.checkIn ? 'checkin' : 'checkout';
}

extension InformeTypeX on InformeType {
  String get label => this == InformeType.normal ? 'Normal' : 'Retroativo';
}

extension ProjetoTypeX on ProjetoType {
  String get label => switch (this) {
    ProjetoType.p80 => 'P-80',
    ProjetoType.p82 => 'P-82',
    ProjetoType.p83 => 'P-83',
  };

  String get apiValue => switch (this) {
    ProjetoType.p80 => 'P80',
    ProjetoType.p82 => 'P82',
    ProjetoType.p83 => 'P83',
  };
}

const _unset = Object();

class LocationFetchEntry {
  static const int maxStoredEntries = 10;
  static const Duration duplicateWindow = Duration(seconds: 1);
  static const double duplicateCoordinateTolerance = 1e-6;

  const LocationFetchEntry({
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  bool isDuplicateOf(
    LocationFetchEntry other, {
    Duration maxTimestampDifference = duplicateWindow,
    double coordinateTolerance = duplicateCoordinateTolerance,
  }) {
    final timestampDifferenceMillis = timestamp
        .difference(other.timestamp)
        .inMilliseconds
        .abs();
    if (timestampDifferenceMillis > maxTimestampDifference.inMilliseconds) {
      return false;
    }

    final currentLatitude = latitude;
    final currentLongitude = longitude;
    final otherLatitude = other.latitude;
    final otherLongitude = other.longitude;
    if (currentLatitude == null ||
        currentLongitude == null ||
        otherLatitude == null ||
        otherLongitude == null) {
      return currentLatitude == otherLatitude &&
          currentLongitude == otherLongitude;
    }

    return (currentLatitude - otherLatitude).abs() <= coordinateTolerance &&
        (currentLongitude - otherLongitude).abs() <= coordinateTolerance;
  }

  static List<LocationFetchEntry> normalizeHistory(
    Iterable<LocationFetchEntry> entries, {
    int? maxEntries,
  }) {
    final effectiveMaxEntries = maxEntries == null
        ? null
        : (maxEntries < 1 ? 1 : maxEntries);
    final normalized = <LocationFetchEntry>[];

    for (final entry in entries) {
      if (normalized.isNotEmpty && entry.isDuplicateOf(normalized.last)) {
        continue;
      }

      normalized.add(entry);
      if (effectiveMaxEntries != null &&
          normalized.length >= effectiveMaxEntries) {
        break;
      }
    }

    return List<LocationFetchEntry>.unmodifiable(normalized);
  }

  static LocationFetchEntry? tryParse(Object? value) {
    if (value is String) {
      final timestamp = DateTime.tryParse(value)?.toLocal();
      if (timestamp == null) {
        return null;
      }
      return LocationFetchEntry(timestamp: timestamp);
    }

    if (value is Map) {
      final map = Map<Object?, Object?>.from(value);
      final rawTimestamp = map['timestamp'];
      final timestamp = switch (rawTimestamp) {
        String _ => DateTime.tryParse(rawTimestamp)?.toLocal(),
        num _ => DateTime.fromMillisecondsSinceEpoch(
          rawTimestamp.toInt(),
        ).toLocal(),
        _ => null,
      };
      if (timestamp == null) {
        return null;
      }

      return LocationFetchEntry(
        timestamp: timestamp,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
      );
    }

    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class CheckingState {
  const CheckingState({
    required this.chave,
    required this.registro,
    required this.checkInInforme,
    required this.checkOutInforme,
    required this.checkInProjeto,
    required this.apiBaseUrl,
    required this.apiSharedKey,
    required this.locationUpdateIntervalSeconds,
    required this.nightUpdatesDisabled,
    required this.nightPeriodStartMinutes,
    required this.nightPeriodEndMinutes,
    required this.locationAccuracyThresholdMeters,
    required this.locationSharingEnabled,
    required this.canEnableLocationSharing,
    required this.autoCheckInEnabled,
    required this.autoCheckOutEnabled,
    required this.oemBackgroundSetupEnabled,
    required this.lastMatchedLocation,
    required this.lastDetectedLocation,
    required this.lastLocationUpdateAt,
    required this.locationFetchHistory,
    required this.lastCheckInLocation,
    required this.lastCheckIn,
    required this.lastCheckOut,
    required this.statusMessage,
    required this.statusTone,
    required this.isLoading,
    required this.isSubmitting,
    required this.isSyncing,
    required this.isLocationUpdating,
    required this.isAutomaticCheckingUpdating,
  });

  factory CheckingState.initial() {
    return const CheckingState(
      chave: '',
      registro: RegistroType.checkIn,
      checkInInforme: InformeType.normal,
      checkOutInforme: InformeType.normal,
      checkInProjeto: ProjetoType.p80,
      apiBaseUrl: CheckingPresetConfig.apiBaseUrl,
      apiSharedKey: CheckingPresetConfig.apiSharedKey,
      locationUpdateIntervalSeconds: 15 * 60,
      nightUpdatesDisabled: false,
      nightPeriodStartMinutes: 22 * 60,
      nightPeriodEndMinutes: 6 * 60,
      locationAccuracyThresholdMeters: 30,
      locationSharingEnabled: false,
      canEnableLocationSharing: false,
      autoCheckInEnabled: false,
      autoCheckOutEnabled: false,
      oemBackgroundSetupEnabled: false,
      lastMatchedLocation: null,
      lastDetectedLocation: null,
      lastLocationUpdateAt: null,
      locationFetchHistory: <LocationFetchEntry>[],
      lastCheckInLocation: null,
      lastCheckIn: null,
      lastCheckOut: null,
      statusMessage: '',
      statusTone: StatusTone.neutral,
      isLoading: true,
      isSubmitting: false,
      isSyncing: false,
      isLocationUpdating: false,
      isAutomaticCheckingUpdating: false,
    );
  }

  factory CheckingState.fromJson(Map<String, dynamic> json) {
    final locationSharingEnabled =
        json['locationSharingEnabled'] as bool? ?? false;
    final restoredAutoCheckInEnabled = json.containsKey('autoCheckInEnabled')
        ? json['autoCheckInEnabled'] as bool? ?? false
        : locationSharingEnabled;
    final restoredAutoCheckOutEnabled = json.containsKey('autoCheckOutEnabled')
        ? json['autoCheckOutEnabled'] as bool? ?? false
        : locationSharingEnabled;
    final autoCheckInEnabled = locationSharingEnabled
        ? restoredAutoCheckInEnabled
        : false;
    final autoCheckOutEnabled = locationSharingEnabled
        ? restoredAutoCheckOutEnabled
        : false;
    final storedRegistro = RegistroType.values.firstWhere(
      (value) => value.name == json['registro'],
      orElse: () => RegistroType.checkIn,
    );
    final legacyInforme = InformeType.values.firstWhere(
      (value) => value.name == json['informe'],
      orElse: () => InformeType.normal,
    );
    final legacyProjeto = ProjetoType.values.firstWhere(
      (value) => value.name == json['projeto'],
      orElse: () => ProjetoType.p80,
    );

    return CheckingState(
      chave: sanitizeChave((json['chave'] as String? ?? '').toUpperCase()),
      registro: inferSuggestedRegistro(
        lastCheckIn: null,
        lastCheckOut: null,
        fallback: storedRegistro,
      ),
      checkInInforme: InformeType.values.firstWhere(
        (value) => value.name == json['checkInInforme'],
        orElse: () => storedRegistro == RegistroType.checkIn
            ? legacyInforme
            : InformeType.normal,
      ),
      checkOutInforme: InformeType.values.firstWhere(
        (value) => value.name == json['checkOutInforme'],
        orElse: () => storedRegistro == RegistroType.checkOut
            ? legacyInforme
            : InformeType.normal,
      ),
      checkInProjeto: ProjetoType.values.firstWhere(
        (value) => value.name == (json['checkInProjeto'] ?? json['projeto']),
        orElse: () => legacyProjeto,
      ),
      apiBaseUrl:
          json['apiBaseUrl'] as String? ?? CheckingPresetConfig.apiBaseUrl,
      apiSharedKey:
          json['apiSharedKey'] as String? ?? CheckingPresetConfig.apiSharedKey,
      locationUpdateIntervalSeconds:
          (json['locationUpdateIntervalSeconds'] as num?)?.toInt() ?? 15 * 60,
      nightUpdatesDisabled: json['nightUpdatesDisabled'] as bool? ?? false,
      nightPeriodStartMinutes:
          (json['nightPeriodStartMinutes'] as num?)?.toInt() ?? 22 * 60,
      nightPeriodEndMinutes:
          (json['nightPeriodEndMinutes'] as num?)?.toInt() ?? 6 * 60,
      locationAccuracyThresholdMeters:
          (json['locationAccuracyThresholdMeters'] as num?)?.toInt() ?? 30,
      locationSharingEnabled: locationSharingEnabled,
      canEnableLocationSharing: false,
      autoCheckInEnabled: autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled,
      oemBackgroundSetupEnabled:
          json['oemBackgroundSetupEnabled'] as bool? ?? false,
      lastMatchedLocation: _normalizeOptionalText(
        json['lastMatchedLocation'] as String?,
      ),
      lastDetectedLocation: _normalizeOptionalText(
        json['lastDetectedLocation'] as String?,
      ),
      lastLocationUpdateAt: _parseOptionalDateTime(
        json['lastLocationUpdateAt'] as String?,
      ),
      locationFetchHistory: _parseLocationFetchHistory(
        json['locationFetchHistory'],
      ),
      lastCheckInLocation: _normalizeOptionalText(
        json['lastCheckInLocation'] as String?,
      ),
      lastCheckIn: null,
      lastCheckOut: null,
      statusMessage: '',
      statusTone: StatusTone.neutral,
      isLoading: false,
      isSubmitting: false,
      isSyncing: false,
      isLocationUpdating: false,
      isAutomaticCheckingUpdating: false,
    );
  }

  final String chave;
  final RegistroType registro;
  final InformeType checkInInforme;
  final InformeType checkOutInforme;
  final ProjetoType checkInProjeto;
  final String apiBaseUrl;
  final String apiSharedKey;
  final int locationUpdateIntervalSeconds;
  final bool nightUpdatesDisabled;
  final int nightPeriodStartMinutes;
  final int nightPeriodEndMinutes;
  final int locationAccuracyThresholdMeters;
  final bool locationSharingEnabled;
  final bool canEnableLocationSharing;
  final bool autoCheckInEnabled;
  final bool autoCheckOutEnabled;
  final bool oemBackgroundSetupEnabled;
  final String? lastMatchedLocation;
  final String? lastDetectedLocation;
  final DateTime? lastLocationUpdateAt;
  final List<LocationFetchEntry> locationFetchHistory;
  final String? lastCheckInLocation;
  final DateTime? lastCheckIn;
  final DateTime? lastCheckOut;
  final String statusMessage;
  final StatusTone statusTone;
  final bool isLoading;
  final bool isSubmitting;
  final bool isSyncing;
  final bool isLocationUpdating;
  final bool isAutomaticCheckingUpdating;

  InformeType get informe => informeFor(registro);
  ProjetoType get projeto => checkInProjeto;

  bool get hasValidChave => chave.trim().length == 4;
  bool get hasApiConfig =>
      apiBaseUrl.trim().isNotEmpty && apiSharedKey.trim().isNotEmpty;
  bool get automaticCheckInOutEnabled =>
      autoCheckInEnabled || autoCheckOutEnabled;
  bool get hasAnyLocationAutomation =>
      autoCheckInEnabled || autoCheckOutEnabled;
  RegistroType? get lastRecordedAction {
    final latestCheckIn = lastCheckIn;
    final latestCheckOut = lastCheckOut;
    if (latestCheckIn == null && latestCheckOut == null) {
      return null;
    }
    if (latestCheckIn != null && latestCheckOut == null) {
      return RegistroType.checkIn;
    }
    if (latestCheckIn == null && latestCheckOut != null) {
      return RegistroType.checkOut;
    }
    if (latestCheckIn!.isAfter(latestCheckOut!)) {
      return RegistroType.checkIn;
    }
    if (latestCheckOut.isAfter(latestCheckIn)) {
      return RegistroType.checkOut;
    }
    return null;
  }

  InformeType informeFor(RegistroType action) {
    return action == RegistroType.checkIn ? checkInInforme : checkOutInforme;
  }

  ProjetoType projetoFor(RegistroType action) {
    return checkInProjeto;
  }

  static String sanitizeChave(String value) {
    return value.trim().toUpperCase();
  }

  static RegistroType inferSuggestedRegistro({
    required DateTime? lastCheckIn,
    required DateTime? lastCheckOut,
    RegistroType fallback = RegistroType.checkIn,
  }) {
    if (lastCheckIn == null && lastCheckOut == null) {
      return fallback;
    }
    if (lastCheckIn != null && lastCheckOut == null) {
      return RegistroType.checkOut;
    }
    if (lastCheckIn == null && lastCheckOut != null) {
      return RegistroType.checkIn;
    }
    if (lastCheckIn!.isAfter(lastCheckOut!)) {
      return RegistroType.checkOut;
    }
    if (lastCheckIn.isBefore(lastCheckOut)) {
      return RegistroType.checkIn;
    }
    return fallback;
  }

  static String? _normalizeOptionalText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static DateTime? _parseOptionalDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }

  static List<LocationFetchEntry> _parseLocationFetchHistory(Object? value) {
    if (value is! List) {
      return const <LocationFetchEntry>[];
    }

    return LocationFetchEntry.normalizeHistory(
      value.map(LocationFetchEntry.tryParse).whereType<LocationFetchEntry>(),
      maxEntries: LocationFetchEntry.maxStoredEntries,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'chave': chave,
      'registro': registro.name,
      'informe': informe.name,
      'projeto': checkInProjeto.name,
      'checkInInforme': checkInInforme.name,
      'checkOutInforme': checkOutInforme.name,
      'checkInProjeto': checkInProjeto.name,
      'apiBaseUrl': apiBaseUrl,
      'locationUpdateIntervalSeconds': locationUpdateIntervalSeconds,
      'nightUpdatesDisabled': nightUpdatesDisabled,
      'nightPeriodStartMinutes': nightPeriodStartMinutes,
      'nightPeriodEndMinutes': nightPeriodEndMinutes,
      'locationAccuracyThresholdMeters': locationAccuracyThresholdMeters,
      'locationSharingEnabled': locationSharingEnabled,
      'autoCheckInEnabled': autoCheckInEnabled,
      'autoCheckOutEnabled': autoCheckOutEnabled,
      'oemBackgroundSetupEnabled': oemBackgroundSetupEnabled,
      'lastMatchedLocation': lastMatchedLocation,
      'lastDetectedLocation': lastDetectedLocation,
      'lastLocationUpdateAt': lastLocationUpdateAt?.toUtc().toIso8601String(),
      'locationFetchHistory': locationFetchHistory
          .map((value) => value.toJson())
          .toList(growable: false),
      'lastCheckInLocation': lastCheckInLocation,
    };
  }

  CheckingState copyWith({
    String? chave,
    RegistroType? registro,
    InformeType? checkInInforme,
    InformeType? checkOutInforme,
    ProjetoType? checkInProjeto,
    String? apiBaseUrl,
    String? apiSharedKey,
    int? locationUpdateIntervalSeconds,
    bool? nightUpdatesDisabled,
    int? nightPeriodStartMinutes,
    int? nightPeriodEndMinutes,
    int? locationAccuracyThresholdMeters,
    bool? locationSharingEnabled,
    bool? canEnableLocationSharing,
    bool? autoCheckInEnabled,
    bool? autoCheckOutEnabled,
    bool? oemBackgroundSetupEnabled,
    Object? lastMatchedLocation = _unset,
    Object? lastDetectedLocation = _unset,
    Object? lastLocationUpdateAt = _unset,
    Object? locationFetchHistory = _unset,
    Object? lastCheckInLocation = _unset,
    Object? lastCheckIn = _unset,
    Object? lastCheckOut = _unset,
    String? statusMessage,
    StatusTone? statusTone,
    bool? isLoading,
    bool? isSubmitting,
    bool? isSyncing,
    bool? isLocationUpdating,
    bool? isAutomaticCheckingUpdating,
  }) {
    return CheckingState(
      chave: chave ?? this.chave,
      registro: registro ?? this.registro,
      checkInInforme: checkInInforme ?? this.checkInInforme,
      checkOutInforme: checkOutInforme ?? this.checkOutInforme,
      checkInProjeto: checkInProjeto ?? this.checkInProjeto,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiSharedKey: apiSharedKey ?? this.apiSharedKey,
      locationUpdateIntervalSeconds:
          locationUpdateIntervalSeconds ?? this.locationUpdateIntervalSeconds,
      nightUpdatesDisabled: nightUpdatesDisabled ?? this.nightUpdatesDisabled,
      nightPeriodStartMinutes:
          nightPeriodStartMinutes ?? this.nightPeriodStartMinutes,
      nightPeriodEndMinutes:
          nightPeriodEndMinutes ?? this.nightPeriodEndMinutes,
      locationAccuracyThresholdMeters:
          locationAccuracyThresholdMeters ??
          this.locationAccuracyThresholdMeters,
      locationSharingEnabled:
          locationSharingEnabled ?? this.locationSharingEnabled,
      canEnableLocationSharing:
          canEnableLocationSharing ?? this.canEnableLocationSharing,
      autoCheckInEnabled: autoCheckInEnabled ?? this.autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled ?? this.autoCheckOutEnabled,
      oemBackgroundSetupEnabled:
          oemBackgroundSetupEnabled ?? this.oemBackgroundSetupEnabled,
      lastMatchedLocation: identical(lastMatchedLocation, _unset)
          ? this.lastMatchedLocation
          : lastMatchedLocation as String?,
      lastDetectedLocation: identical(lastDetectedLocation, _unset)
          ? this.lastDetectedLocation
          : lastDetectedLocation as String?,
      lastLocationUpdateAt: identical(lastLocationUpdateAt, _unset)
          ? this.lastLocationUpdateAt
          : lastLocationUpdateAt as DateTime?,
      locationFetchHistory: identical(locationFetchHistory, _unset)
          ? this.locationFetchHistory
          : List<LocationFetchEntry>.unmodifiable(
              locationFetchHistory as List<LocationFetchEntry>,
            ),
      lastCheckInLocation: identical(lastCheckInLocation, _unset)
          ? this.lastCheckInLocation
          : lastCheckInLocation as String?,
      lastCheckIn: identical(lastCheckIn, _unset)
          ? this.lastCheckIn
          : lastCheckIn as DateTime?,
      lastCheckOut: identical(lastCheckOut, _unset)
          ? this.lastCheckOut
          : lastCheckOut as DateTime?,
      statusMessage: statusMessage ?? this.statusMessage,
      statusTone: statusTone ?? this.statusTone,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSyncing: isSyncing ?? this.isSyncing,
      isLocationUpdating: isLocationUpdating ?? this.isLocationUpdating,
      isAutomaticCheckingUpdating:
          isAutomaticCheckingUpdating ?? this.isAutomaticCheckingUpdating,
    );
  }
}
