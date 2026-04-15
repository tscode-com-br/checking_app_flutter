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
    required this.locationAccuracyThresholdMeters,
    required this.locationSharingEnabled,
    required this.canEnableLocationSharing,
    required this.autoCheckInEnabled,
    required this.autoCheckOutEnabled,
    required this.lastMatchedLocation,
    required this.lastDetectedLocation,
    required this.lastLocationUpdateAt,
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
      locationUpdateIntervalSeconds: 60,
      locationAccuracyThresholdMeters: 30,
      locationSharingEnabled: false,
      canEnableLocationSharing: false,
      autoCheckInEnabled: false,
      autoCheckOutEnabled: false,
      lastMatchedLocation: null,
      lastDetectedLocation: null,
      lastLocationUpdateAt: null,
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
          (json['locationUpdateIntervalSeconds'] as num?)?.toInt() ?? 60,
      locationAccuracyThresholdMeters:
          (json['locationAccuracyThresholdMeters'] as num?)?.toInt() ?? 30,
      locationSharingEnabled: locationSharingEnabled,
      canEnableLocationSharing: false,
      autoCheckInEnabled: autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled,
      lastMatchedLocation: _normalizeOptionalText(
        json['lastMatchedLocation'] as String?,
      ),
      lastDetectedLocation: _normalizeOptionalText(
        json['lastDetectedLocation'] as String?,
      ),
      lastLocationUpdateAt: _parseOptionalDateTime(
        json['lastLocationUpdateAt'] as String?,
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
  final int locationAccuracyThresholdMeters;
  final bool locationSharingEnabled;
  final bool canEnableLocationSharing;
  final bool autoCheckInEnabled;
  final bool autoCheckOutEnabled;
  final String? lastMatchedLocation;
  final String? lastDetectedLocation;
  final DateTime? lastLocationUpdateAt;
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
      'locationAccuracyThresholdMeters': locationAccuracyThresholdMeters,
      'locationSharingEnabled': locationSharingEnabled,
      'autoCheckInEnabled': autoCheckInEnabled,
      'autoCheckOutEnabled': autoCheckOutEnabled,
      'lastMatchedLocation': lastMatchedLocation,
      'lastDetectedLocation': lastDetectedLocation,
      'lastLocationUpdateAt': lastLocationUpdateAt?.toUtc().toIso8601String(),
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
    int? locationAccuracyThresholdMeters,
    bool? locationSharingEnabled,
    bool? canEnableLocationSharing,
    bool? autoCheckInEnabled,
    bool? autoCheckOutEnabled,
    Object? lastMatchedLocation = _unset,
    Object? lastDetectedLocation = _unset,
    Object? lastLocationUpdateAt = _unset,
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
      locationAccuracyThresholdMeters:
          locationAccuracyThresholdMeters ??
          this.locationAccuracyThresholdMeters,
      locationSharingEnabled:
          locationSharingEnabled ?? this.locationSharingEnabled,
      canEnableLocationSharing:
          canEnableLocationSharing ?? this.canEnableLocationSharing,
      autoCheckInEnabled: autoCheckInEnabled ?? this.autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled ?? this.autoCheckOutEnabled,
      lastMatchedLocation: identical(lastMatchedLocation, _unset)
          ? this.lastMatchedLocation
          : lastMatchedLocation as String?,
      lastDetectedLocation: identical(lastDetectedLocation, _unset)
          ? this.lastDetectedLocation
          : lastDetectedLocation as String?,
      lastLocationUpdateAt: identical(lastLocationUpdateAt, _unset)
          ? this.lastLocationUpdateAt
          : lastLocationUpdateAt as DateTime?,
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
