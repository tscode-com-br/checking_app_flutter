import 'dart:async';
import 'dart:math';

import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:checking/src/features/checking/services/checking_location_logic.dart';
import 'package:checking/src/features/checking/services/checking_services.dart';
import 'package:checking/src/features/checking/services/location_catalog_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class CheckingBackgroundStartResult {
  const CheckingBackgroundStartResult({
    required this.ready,
    this.blockingMessage = '',
    this.warningMessage = '',
  });

  final bool ready;
  final String blockingMessage;
  final String warningMessage;
}

class CheckingBackgroundLocationSnapshot {
  const CheckingBackgroundLocationSnapshot({
    required this.chave,
    required this.registro,
    required this.checkInProjeto,
    required this.nightModeAfterCheckoutEnabled,
    required this.nightModeAfterCheckoutUntil,
    required this.locationSharingEnabled,
    required this.autoCheckInEnabled,
    required this.autoCheckOutEnabled,
    required this.locationUpdateIntervalSeconds,
    required this.locationAccuracyThresholdMeters,
    required this.minimumCheckoutDistanceMetersByProject,
    required this.lastMatchedLocation,
    required this.lastDetectedLocation,
    required this.lastLocationUpdateAt,
    required this.locationFetchHistory,
    required this.lastCheckInLocation,
    required this.lastCheckIn,
    required this.lastCheckOut,
    required this.statusMessage,
    required this.statusTone,
  });

  factory CheckingBackgroundLocationSnapshot.fromData(Object data) {
    final map = Map<Object?, Object?>.from(data as Map);
    final registroName =
        (map['registro'] as String? ?? RegistroType.checkIn.name).trim();
    final projetoName =
        (map['checkInProjeto'] as String? ?? ProjetoType.p80.name).trim();
    final statusToneName =
        (map['statusTone'] as String? ?? StatusTone.neutral.name).trim();

    return CheckingBackgroundLocationSnapshot(
      chave: CheckingState.sanitizeChave((map['chave'] as String? ?? '')),
      registro: RegistroType.values.firstWhere(
        (value) => value.name == registroName,
        orElse: () => RegistroType.checkIn,
      ),
      checkInProjeto: ProjetoType.values.firstWhere(
        (value) => value.name == projetoName,
        orElse: () => ProjetoType.p80,
      ),
      nightModeAfterCheckoutEnabled:
          map['nightModeAfterCheckoutEnabled'] as bool? ?? false,
      nightModeAfterCheckoutUntil: _readNullableDateTime(
        map['nightModeAfterCheckoutUntil'] as num?,
      ),
      locationSharingEnabled: map['locationSharingEnabled'] as bool? ?? false,
      autoCheckInEnabled: map['autoCheckInEnabled'] as bool? ?? false,
      autoCheckOutEnabled: map['autoCheckOutEnabled'] as bool? ?? false,
      locationUpdateIntervalSeconds:
          (map['locationUpdateIntervalSeconds'] as num?)?.toInt() ??
          CheckingLocationLogic.defaultLocationUpdateIntervalSeconds,
      locationAccuracyThresholdMeters:
          (map['locationAccuracyThresholdMeters'] as num?)?.toInt() ?? 30,
      minimumCheckoutDistanceMetersByProject:
          _readMinimumCheckoutDistanceMetersByProject(
            map['minimumCheckoutDistanceMetersByProject'],
          ),
      lastMatchedLocation: _readNullableString(map['lastMatchedLocation']),
      lastDetectedLocation: _readNullableString(map['lastDetectedLocation']),
      lastLocationUpdateAt: _readNullableDateTime(
        map['lastLocationUpdateAt'] as num?,
      ),
      locationFetchHistory: _readLocationFetchHistory(
        map['locationFetchHistory'],
      ),
      lastCheckInLocation: _readNullableString(map['lastCheckInLocation']),
      lastCheckIn: _readNullableDateTime(map['lastCheckIn'] as num?),
      lastCheckOut: _readNullableDateTime(map['lastCheckOut'] as num?),
      statusMessage: (map['statusMessage'] as String? ?? '').trim(),
      statusTone: StatusTone.values.firstWhere(
        (value) => value.name == statusToneName,
        orElse: () => StatusTone.neutral,
      ),
    );
  }

  final String chave;
  final RegistroType registro;
  final ProjetoType checkInProjeto;
  final bool nightModeAfterCheckoutEnabled;
  final DateTime? nightModeAfterCheckoutUntil;
  final bool locationSharingEnabled;
  final bool autoCheckInEnabled;
  final bool autoCheckOutEnabled;
  final int locationUpdateIntervalSeconds;
  final int locationAccuracyThresholdMeters;
  final Map<String, int> minimumCheckoutDistanceMetersByProject;
  final String? lastMatchedLocation;
  final String? lastDetectedLocation;
  final DateTime? lastLocationUpdateAt;
  final List<LocationFetchEntry> locationFetchHistory;
  final String? lastCheckInLocation;
  final DateTime? lastCheckIn;
  final DateTime? lastCheckOut;
  final String statusMessage;
  final StatusTone statusTone;

  int get minimumCheckoutDistanceMeters =>
      minimumCheckoutDistanceMetersByProject[checkInProjeto.apiValue] ??
      CheckingState.defaultMinimumCheckoutDistanceMeters;

  static String? _readNullableString(Object? value) {
    final normalized = (value as String?)?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static Map<String, int> _readMinimumCheckoutDistanceMetersByProject(
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

  static DateTime? _readNullableDateTime(num? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
  }

  static List<LocationFetchEntry> _readLocationFetchHistory(Object? value) {
    if (value is! List) {
      return const <LocationFetchEntry>[];
    }

    return LocationFetchEntry.normalizeHistory(
      value.map(LocationFetchEntry.tryParse).whereType<LocationFetchEntry>(),
      maxEntries: LocationFetchEntry.maxStoredEntries,
    );
  }
}

typedef CheckingBackgroundLocationListener =
    void Function(CheckingBackgroundLocationSnapshot snapshot);

class CheckingBackgroundLocationService {
  static const int _serviceId = 4012;
  static const String _taskDataKind = 'checking-background-snapshot';
  static const String _refreshCommandType = 'refresh';
  static const String _notificationTitle = 'Checking ativo';
  static const String _notificationText =
      'Monitoramento de localização em segundo plano em execução.';
  static const bool stopServiceOnTaskRemoval = false;
  static const bool allowAutomaticRestart = true;

  static final Map<CheckingBackgroundLocationListener, DataCallback>
  _listeners = <CheckingBackgroundLocationListener, DataCallback>{};

  static bool _initialized = false;
  static bool _communicationPortInitialized = false;
  static bool _configuredAutoRestart = allowAutomaticRestart;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool shouldRunForState(CheckingState state) {
    return state.locationSharingEnabled && state.hasAnyLocationAutomation;
  }

  static Future<bool> isNotificationPermissionGranted() async {
    if (!isSupported) {
      return true;
    }

    initialize();
    try {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      return notificationPermission == NotificationPermission.granted;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> requestNotificationPermission({
    required bool interactive,
  }) async {
    if (!isSupported) {
      return true;
    }

    initialize();
    try {
      if (await isNotificationPermissionGranted()) {
        return true;
      }
      if (!interactive) {
        return false;
      }

      final requestedPermission =
          await FlutterForegroundTask.requestNotificationPermission();
      if (requestedPermission == NotificationPermission.granted) {
        return true;
      }

      if (requestedPermission == NotificationPermission.permanently_denied) {
        await openAppSettings();
      }
      return false;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!isSupported) {
      return true;
    }

    initialize();
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimization({
    required bool interactive,
  }) async {
    if (!isSupported) {
      return true;
    }

    initialize();
    try {
      if (await isBatteryOptimizationIgnored()) {
        return true;
      }
      if (!interactive) {
        return false;
      }

      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } on MissingPluginException {
      return true;
    }
  }

  static void initialize() {
    _initialize(allowAutoRestart: _configuredAutoRestart);
  }

  static void configureAutoStart({required bool enabled}) {
    _initialize(allowAutoRestart: enabled);
  }

  static void _initialize({required bool allowAutoRestart}) {
    if (!isSupported) {
      return;
    }

    try {
      if (!_communicationPortInitialized) {
        FlutterForegroundTask.initCommunicationPort();
        _communicationPortInitialized = true;
      }
      if (_initialized && _configuredAutoRestart == allowAutoRestart) {
        return;
      }

      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'checking_location_tracking',
          channelName: 'Checking em segundo plano',
          channelDescription:
              'Mantém o monitoramento de localização ativo para a automação de presença.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: allowAutoRestart,
          autoRunOnMyPackageReplaced: allowAutoRestart,
          allowWakeLock: true,
          allowWifiLock: false,
          allowAutoRestart: allowAutoRestart,
          stopWithTask: stopServiceOnTaskRemoval,
        ),
      );
      _initialized = true;
      _configuredAutoRestart = allowAutoRestart;
    } on MissingPluginException {
      _initialized = false;
    }
  }

  static void addListener(CheckingBackgroundLocationListener listener) {
    if (!isSupported || _listeners.containsKey(listener)) {
      return;
    }

    initialize();
    void wrapper(Object data) {
      if (data is! Map) {
        return;
      }
      final kind = (data['kind'] as String? ?? '').trim();
      if (kind != _taskDataKind) {
        return;
      }
      listener(CheckingBackgroundLocationSnapshot.fromData(data));
    }

    _listeners[listener] = wrapper;
    FlutterForegroundTask.addTaskDataCallback(wrapper);
  }

  static void removeListener(CheckingBackgroundLocationListener listener) {
    final wrapper = _listeners.remove(listener);
    if (wrapper == null) {
      return;
    }

    FlutterForegroundTask.removeTaskDataCallback(wrapper);
  }

  static Future<CheckingBackgroundStartResult> ensureReadyForStart({
    required bool interactive,
  }) async {
    if (!isSupported) {
      return const CheckingBackgroundStartResult(ready: true);
    }

    initialize();

    try {
      if (!await requestNotificationPermission(interactive: interactive)) {
        return const CheckingBackgroundStartResult(
          ready: false,
          blockingMessage:
              'Permita as notificações do aplicativo para manter o monitoramento em segundo plano.',
        );
      }
    } on MissingPluginException {
      return const CheckingBackgroundStartResult(ready: true);
    }

    if (!interactive) {
      return const CheckingBackgroundStartResult(ready: true);
    }

    try {
      if (!await isBatteryOptimizationIgnored()) {
        final ignored = await requestIgnoreBatteryOptimization(
          interactive: true,
        );
        if (!ignored) {
          return const CheckingBackgroundStartResult(
            ready: true,
            warningMessage:
                'Busca por localização ativada. Para máxima confiabilidade com a tela bloqueada, permita ignorar a otimização de bateria do Android.',
          );
        }
      }
    } catch (_) {
      return const CheckingBackgroundStartResult(
        ready: true,
        warningMessage:
            'Busca por localização ativada. Verifique a otimização de bateria do Android se o sistema interromper o monitoramento.',
      );
    }

    return const CheckingBackgroundStartResult(ready: true);
  }

  static Future<void> start({bool? enableAutoStart}) async {
    if (!isSupported) {
      return;
    }

    if (enableAutoStart != null) {
      configureAutoStart(enabled: enableAutoStart);
    } else {
      initialize();
    }
    try {
      if (await FlutterForegroundTask.isRunningService) {
        return;
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationTitle: _notificationTitle,
        notificationText: _notificationText,
        callback: _startBackgroundLocationTask,
      );
      if (result is ServiceRequestFailure) {
        throw result.error;
      }
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> stop() async {
    if (!isSupported) {
      return;
    }

    try {
      if (!await FlutterForegroundTask.isRunningService) {
        return;
      }

      final result = await FlutterForegroundTask.stopService();
      if (result is ServiceRequestFailure) {
        throw result.error;
      }
    } on MissingPluginException {
      return;
    }
  }

  static Future<bool> isRunning() async {
    if (!isSupported) {
      return false;
    }

    try {
      return await FlutterForegroundTask.isRunningService;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> requestRefresh() async {
    if (!isSupported) {
      return;
    }

    try {
      if (!await FlutterForegroundTask.isRunningService) {
        return;
      }

      FlutterForegroundTask.sendDataToTask(const <String, Object>{
        'type': _refreshCommandType,
      });
    } on MissingPluginException {
      return;
    }
  }
}

@pragma('vm:entry-point')
void _startBackgroundLocationTask() {
  FlutterForegroundTask.setTaskHandler(
    _CheckingBackgroundLocationTaskHandler(),
  );
}

class _CheckingBackgroundLocationTaskHandler extends TaskHandler {
  _CheckingBackgroundLocationTaskHandler();

  final CheckingStorageService _storageService =
      const CheckingStorageService.backgroundSafe();
  final CheckingApiService _apiService = CheckingApiService();
  final LocationCatalogService _locationCatalogService =
      LocationCatalogService();
  final Random _random = Random();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _scheduleBoundaryTimer;
  Timer? _locationCaptureTimer;
  MobileStateResponse? _lastKnownRemoteState;
  DateTime? _lastKnownRemoteStateAt;
  int? _currentIntervalSeconds;
  bool _processingLocationUpdate = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _runGuarded(() => _reloadTrackingState(forceRestart: true));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _runGuarded(() async {
      await _cancelTracking(keepScheduleBoundaryTimer: false);
      _lastKnownRemoteState = null;
      _lastKnownRemoteStateAt = null;
      _currentIntervalSeconds = null;
    });
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    final type = (data['type'] as String? ?? '').trim();
    if (type != CheckingBackgroundLocationService._refreshCommandType) {
      return;
    }

    _lastKnownRemoteState = null;
    _lastKnownRemoteStateAt = null;
    unawaited(_runGuarded(() => _reloadTrackingState(forceRestart: true)));
  }

  Future<void> _reloadTrackingState({required bool forceRestart}) async {
    final state = CheckingLocationLogic.resolveLocationUpdateIntervalState(
      await _storageService.loadState(),
    );
    if (!CheckingBackgroundLocationService.shouldRunForState(state)) {
      await _cancelTracking(keepScheduleBoundaryTimer: false);
      _currentIntervalSeconds = null;
      await _stopService();
      return;
    }

    if (!CheckingLocationLogic.shouldRunBackgroundActivityNow(state: state)) {
      final pausedState = state.copyWith(
        statusMessage:
            CheckingLocationLogic.isNightModeAfterCheckoutActive(state: state)
            ? CheckingLocationLogic.postCheckoutNightModeStatusMessage
            : 'Atualizações em segundo plano pausadas no período noturno configurado.',
        statusTone: StatusTone.warning,
      );
      await _storageService.saveState(pausedState);
      _sendSnapshot(
        pausedState,
        statusMessage: pausedState.statusMessage,
        statusTone: pausedState.statusTone,
      );
      await _cancelTracking(keepScheduleBoundaryTimer: false);
      _currentIntervalSeconds = null;
      _restartScheduleBoundaryTimer(state);
      return;
    }

    final hasPermission = await _hasBackgroundLocationPermission();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!hasPermission || !serviceEnabled) {
      final statusMessage = serviceEnabled
          ? 'Permita a localização em segundo plano para retomar o monitoramento.'
          : 'Ative o serviço de localização do Android para retomar o monitoramento.';
      final blockedState = state.copyWith(
        statusMessage: statusMessage,
        statusTone: StatusTone.warning,
      );
      await _storageService.saveState(blockedState);
      _sendSnapshot(
        blockedState,
        statusMessage: statusMessage,
        statusTone: StatusTone.warning,
      );
      await _cancelTracking(keepScheduleBoundaryTimer: true);
      _currentIntervalSeconds = null;
      _scheduleTrackingRetry();
      return;
    }

    _restartScheduleBoundaryTimer(state);

    if (forceRestart ||
        _positionSubscription == null ||
        _currentIntervalSeconds != state.locationUpdateIntervalSeconds) {
      await _restartTracking(state);
    }
  }

  Future<void> _restartTracking(CheckingState state) async {
    await _cancelTracking(keepScheduleBoundaryTimer: true);
    _currentIntervalSeconds = state.locationUpdateIntervalSeconds;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: Duration(
        seconds: max(1, state.locationUpdateIntervalSeconds),
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) =>
              unawaited(_runGuarded(() => _handlePositionUpdate(position))),
          onError: (error) => unawaited(
            _runGuarded(
              () => _handleTrackingFailure(
                state,
                error,
                fallbackMessage:
                    'Falha ao atualizar a localização do aparelho.',
              ),
            ),
          ),
        );
    _restartLocationCaptureTimer(state);

    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      await _handlePositionUpdate(initialPosition);
    } catch (_) {
      // A stream continua tentando as próximas leituras.
    }
  }

  void _restartLocationCaptureTimer(CheckingState state) {
    _locationCaptureTimer?.cancel();
    _locationCaptureTimer = Timer.periodic(
      Duration(seconds: max(1, state.locationUpdateIntervalSeconds)),
      (_) => unawaited(_captureCurrentPositionNow()),
    );
  }

  Future<void> _captureCurrentPositionNow() async {
    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      await _runGuarded(() => _handlePositionUpdate(currentPosition));
    } catch (_) {
      // O serviço continua tentando as próximas leituras periódicas ou da stream.
    }
  }

  void _restartScheduleBoundaryTimer(CheckingState state) {
    _scheduleBoundaryTimer?.cancel();
    _scheduleBoundaryTimer = null;

    _scheduleBoundaryTimer = Timer(
      CheckingLocationLogic.delayUntilNextLocationUpdateIntervalBoundary(
        state: state,
      ),
      () {
        _lastKnownRemoteState = null;
        _lastKnownRemoteStateAt = null;
        unawaited(_runGuarded(() => _reloadTrackingState(forceRestart: true)));
      },
    );
  }

  void _scheduleTrackingRetry() {
    _scheduleBoundaryTimer?.cancel();
    _scheduleBoundaryTimer = Timer(const Duration(minutes: 1), () {
      _lastKnownRemoteState = null;
      _lastKnownRemoteStateAt = null;
      unawaited(_runGuarded(() => _reloadTrackingState(forceRestart: true)));
    });
  }

  Future<void> _runGuarded(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      await _handleUnexpectedBackgroundFailure();
    }
  }

  Future<void> _handleUnexpectedBackgroundFailure() async {
    try {
      final safeState = (await _storageService.loadState()).copyWith(
        statusMessage:
            'Falha ao manter o monitoramento em segundo plano. Abra o aplicativo para retomar a automação.',
        statusTone: StatusTone.error,
      );
      await _storageService.saveState(safeState);
      _sendSnapshot(
        safeState,
        statusMessage: safeState.statusMessage,
        statusTone: safeState.statusTone,
      );
    } catch (_) {
      // Se o estado não puder ser carregado, evitamos propagar a falha.
    }
  }

  Future<void> _handleTrackingFailure(
    CheckingState state,
    Object error, {
    required String fallbackMessage,
  }) async {
    final statusMessage = _resolveTrackingFailureMessage(
      error,
      fallbackMessage: fallbackMessage,
    );
    final warningState = state.copyWith(
      statusMessage: statusMessage,
      statusTone: StatusTone.warning,
    );
    await _storageService.saveState(warningState);
    _sendSnapshot(
      warningState,
      statusMessage: statusMessage,
      statusTone: StatusTone.warning,
    );
    await _cancelTracking(keepScheduleBoundaryTimer: true);
    _currentIntervalSeconds = null;
    _scheduleTrackingRetry();
  }

  Future<void> _cancelTracking({
    required bool keepScheduleBoundaryTimer,
  }) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _locationCaptureTimer?.cancel();
    _locationCaptureTimer = null;
    if (!keepScheduleBoundaryTimer) {
      _scheduleBoundaryTimer?.cancel();
      _scheduleBoundaryTimer = null;
    }
  }

  Future<void> _handlePositionUpdate(Position position) async {
    if (_processingLocationUpdate) {
      return;
    }

    final baseState = CheckingLocationLogic.resolveLocationUpdateIntervalState(
      await _storageService.loadState(),
    );
    if (!baseState.locationSharingEnabled) {
      await _reloadTrackingState(forceRestart: false);
      return;
    }

    final shouldRestartTracking =
        _currentIntervalSeconds != baseState.locationUpdateIntervalSeconds;
    if (!CheckingLocationLogic.isLocationAccuracyPreciseEnough(
      position.accuracy,
      maxAccuracyMeters: baseState.locationAccuracyThresholdMeters.toDouble(),
    )) {
      if (shouldRestartTracking) {
        await _restartTracking(baseState);
      }
      return;
    }

    final positionTimestamp = CheckingLocationLogic.resolvePositionTimestamp(
      position,
    );
    if (CheckingLocationLogic.shouldSkipDuplicateLocationFetch(
      history: baseState.locationFetchHistory,
      timestamp: positionTimestamp,
      latitude: position.latitude,
      longitude: position.longitude,
    )) {
      if (shouldRestartTracking) {
        await _restartTracking(baseState);
      }
      return;
    }

    _processingLocationUpdate = true;
    try {
      final managedLocations = await _locationCatalogService.loadLocations(
        preferCache: true,
      );
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final matchedLocation = matchResult.matchedLocation;
      final locationFetchHistory =
          CheckingLocationLogic.recordLocationFetchHistory(
            history: baseState.locationFetchHistory,
            timestamp: positionTimestamp,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      final capturedLocationLabel =
          CheckingLocationLogic.resolveCapturedLocationLabel(
            location: matchedLocation,
            nearestWorkplaceDistanceMeters:
                matchResult.nearestWorkplaceDistanceMeters,
            minimumCheckoutDistanceMeters: baseState
                .minimumCheckoutDistanceMeters
                .toDouble(),
          );
      final nextState = matchedLocation == null
          ? baseState.copyWith(
              lastMatchedLocation: null,
              lastDetectedLocation: capturedLocationLabel,
              lastLocationUpdateAt: positionTimestamp,
              locationFetchHistory: locationFetchHistory,
            )
          : baseState.copyWith(
              lastMatchedLocation: matchedLocation.automationAreaLabel,
              lastDetectedLocation: capturedLocationLabel,
              lastLocationUpdateAt: positionTimestamp,
              locationFetchHistory: locationFetchHistory,
            );

      await _storageService.saveState(nextState);
      _sendSnapshot(nextState);

      if (CheckingLocationLogic.isNightModeAfterCheckoutActive(
        state: nextState,
      )) {
        await _reloadTrackingState(forceRestart: true);
        return;
      }

      if (!nextState.hasAnyLocationAutomation ||
          !nextState.hasValidChave ||
          !nextState.hasApiConfig) {
        return;
      }

      if (matchedLocation == null) {
        final shouldAttemptOutOfRangeCheckout =
            CheckingLocationLogic.shouldAttemptAutomaticOutOfRangeCheckout(
              lastRecordedAction: nextState.lastRecordedAction,
              nearestDistanceMeters: matchResult.nearestWorkplaceDistanceMeters,
              minimumCheckoutDistanceMeters: nextState
                  .minimumCheckoutDistanceMeters
                  .toDouble(),
              autoCheckOutEnabled: nextState.autoCheckOutEnabled,
            );
        final shouldAttemptNearbyWorkplaceCheckIn =
            CheckingLocationLogic.shouldAttemptAutomaticNearbyWorkplaceCheckIn(
              lastRecordedAction: nextState.lastRecordedAction,
              nearestDistanceMeters: matchResult.nearestWorkplaceDistanceMeters,
              minimumCheckoutDistanceMeters: nextState
                  .minimumCheckoutDistanceMeters
                  .toDouble(),
              autoCheckInEnabled: nextState.autoCheckInEnabled,
            );
        if (!shouldAttemptOutOfRangeCheckout &&
            !shouldAttemptNearbyWorkplaceCheckIn) {
          return;
        }

        await _submitAutomaticWithoutLocationMatch(
          nextState,
          matchResult.nearestWorkplaceDistanceMeters,
        );
        return;
      }

      if (matchedLocation.isCheckoutZone && !nextState.autoCheckOutEnabled) {
        return;
      }
      if (!matchedLocation.isCheckoutZone && !nextState.autoCheckInEnabled) {
        return;
      }

      await _submitAutomaticLocationEvent(nextState, matchedLocation);
    } finally {
      _processingLocationUpdate = false;
      if (shouldRestartTracking) {
        await _restartTracking(baseState);
      }
    }
  }

  Future<void> _submitAutomaticLocationEvent(
    CheckingState state,
    ManagedLocation location,
  ) async {
    try {
      if (_canSkipFetchForLocation(state, location)) {
        return;
      }

      final remoteState = await _apiService.fetchState(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
      );
      _rememberRemoteState(remoteState);

      final nextAction =
          CheckingLocationLogic.resolveAutomaticActionForLocation(
            remoteState: remoteState,
            location: location,
            autoCheckInEnabled: state.autoCheckInEnabled,
            autoCheckOutEnabled: state.autoCheckOutEnabled,
            lastCheckInLocation: state.lastCheckInLocation,
          );
      if (nextAction == null) {
        return;
      }

      final resolvedLocal = CheckingLocationLogic.resolveAutomaticEventLocal(
        action: nextAction,
        location: location,
      );
      final response = await _apiService.submitEvent(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
        projeto: state.projetoFor(nextAction).apiValue,
        action: nextAction.apiValue,
        informe: InformeType.normal.name,
        clientEventId: _buildClientEventId(),
        eventTime: DateTime.now(),
        local: resolvedLocal,
      );
      _rememberRemoteState(response.state);

      var nextState = CheckingLocationLogic.applyRemoteState(
        currentState: state,
        response: response.state,
        statusMessage:
            '${nextAction.label} automático enviado para $resolvedLocal.',
        tone: StatusTone.success,
        recentAction: nextAction,
        recentLocal: resolvedLocal,
      );
      if (CheckingLocationLogic.isNightModeAfterCheckoutActive(
        state: nextState,
      )) {
        nextState = nextState.copyWith(
          statusMessage:
              CheckingLocationLogic.postCheckoutNightModeStatusMessage,
          statusTone: StatusTone.warning,
        );
      }
      await _storageService.saveState(nextState);
      _sendSnapshot(
        nextState,
        statusMessage: nextState.statusMessage,
        statusTone: nextState.statusTone,
      );
      if (CheckingLocationLogic.isNightModeAfterCheckoutActive(
        state: nextState,
      )) {
        await _reloadTrackingState(forceRestart: true);
      }
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao executar a automação por localização.';
      _sendSnapshot(
        state,
        statusMessage: message,
        statusTone: StatusTone.error,
      );
    }
  }

  Future<void> _submitAutomaticWithoutLocationMatch(
    CheckingState state,
    double? nearestDistanceMeters,
  ) async {
    try {
      final remoteState = await _apiService.fetchState(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
      );
      _rememberRemoteState(remoteState);

      final nextAction =
          CheckingLocationLogic.resolveAutomaticActionWithoutLocationMatch(
            remoteState: remoteState,
            nearestDistanceMeters: nearestDistanceMeters,
            minimumCheckoutDistanceMeters: state.minimumCheckoutDistanceMeters
                .toDouble(),
            autoCheckInEnabled: state.autoCheckInEnabled,
            autoCheckOutEnabled: state.autoCheckOutEnabled,
          );
      if (nextAction == null) {
        return;
      }

      final resolvedLocal = CheckingLocationLogic.resolveAutomaticEventLocal(
        action: nextAction,
      );
      final response = await _apiService.submitEvent(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
        projeto: state.projetoFor(nextAction).apiValue,
        action: nextAction.apiValue,
        informe: InformeType.normal.name,
        clientEventId: _buildClientEventId(),
        eventTime: DateTime.now(),
        local: resolvedLocal,
      );
      _rememberRemoteState(response.state);

      var nextState = CheckingLocationLogic.applyRemoteState(
        currentState: state,
        response: response.state,
        statusMessage: nextAction == RegistroType.checkOut
            ? 'Check-Out automático enviado por afastamento das áreas monitoradas.'
            : '${nextAction.label} automático enviado para $resolvedLocal.',
        tone: StatusTone.success,
        recentAction: nextAction,
        recentLocal: resolvedLocal,
      );
      if (CheckingLocationLogic.isNightModeAfterCheckoutActive(
        state: nextState,
      )) {
        nextState = nextState.copyWith(
          statusMessage:
              CheckingLocationLogic.postCheckoutNightModeStatusMessage,
          statusTone: StatusTone.warning,
        );
      }
      await _storageService.saveState(nextState);
      _sendSnapshot(
        nextState,
        statusMessage: nextState.statusMessage,
        statusTone: nextState.statusTone,
      );
      if (CheckingLocationLogic.isNightModeAfterCheckoutActive(
        state: nextState,
      )) {
        await _reloadTrackingState(forceRestart: true);
      }
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao executar a automação por localização.';
      _sendSnapshot(
        state,
        statusMessage: message,
        statusTone: StatusTone.error,
      );
    }
  }

  bool _canSkipFetchForLocation(CheckingState state, ManagedLocation location) {
    if (!_isRemoteStateCacheFresh || _lastKnownRemoteState == null) {
      return false;
    }

    return CheckingLocationLogic.resolveAutomaticActionForLocation(
          remoteState: _lastKnownRemoteState!,
          location: location,
          autoCheckInEnabled: state.autoCheckInEnabled,
          autoCheckOutEnabled: state.autoCheckOutEnabled,
          lastCheckInLocation: state.lastCheckInLocation,
        ) ==
        null;
  }

  bool get _isRemoteStateCacheFresh {
    if (_lastKnownRemoteState == null || _lastKnownRemoteStateAt == null) {
      return false;
    }

    return DateTime.now().difference(_lastKnownRemoteStateAt!) <
        const Duration(seconds: 45);
  }

  void _rememberRemoteState(MobileStateResponse remoteState) {
    _lastKnownRemoteState = remoteState;
    _lastKnownRemoteStateAt = DateTime.now();
  }

  Future<bool> _hasBackgroundLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }

  void _sendSnapshot(
    CheckingState state, {
    String? statusMessage,
    StatusTone? statusTone,
  }) {
    try {
      FlutterForegroundTask.sendDataToMain(<String, Object?>{
        'kind': CheckingBackgroundLocationService._taskDataKind,
        'chave': state.chave,
        'registro': state.registro.name,
        'checkInProjeto': state.checkInProjeto.name,
        'nightModeAfterCheckoutEnabled': state.nightModeAfterCheckoutEnabled,
        'nightModeAfterCheckoutUntil':
            state.nightModeAfterCheckoutUntil?.millisecondsSinceEpoch,
        'locationSharingEnabled': state.locationSharingEnabled,
        'autoCheckInEnabled': state.autoCheckInEnabled,
        'autoCheckOutEnabled': state.autoCheckOutEnabled,
        'locationUpdateIntervalSeconds': state.locationUpdateIntervalSeconds,
        'locationAccuracyThresholdMeters':
            state.locationAccuracyThresholdMeters,
        'minimumCheckoutDistanceMetersByProject':
            state.minimumCheckoutDistanceMetersByProject,
        'lastMatchedLocation': state.lastMatchedLocation,
        'lastDetectedLocation': state.lastDetectedLocation,
        'lastLocationUpdateAt':
            state.lastLocationUpdateAt?.millisecondsSinceEpoch,
        'locationFetchHistory': state.locationFetchHistory
            .map(
              (value) => <String, Object?>{
                'timestamp': value.timestamp.millisecondsSinceEpoch,
                'latitude': value.latitude,
                'longitude': value.longitude,
              },
            )
            .toList(growable: false),
        'lastCheckInLocation': state.lastCheckInLocation,
        'lastCheckIn': state.lastCheckIn?.millisecondsSinceEpoch,
        'lastCheckOut': state.lastCheckOut?.millisecondsSinceEpoch,
        'statusMessage': statusMessage ?? '',
        'statusTone': (statusTone ?? StatusTone.neutral).name,
      });
    } catch (_) {
      // Falhas de comunicação com a UI não devem derrubar o isolate de background.
    }
  }

  Future<void> _stopService() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      throw result.error;
    }
  }

  String _buildClientEventId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return 'flutter-auto-$now-$randomPart';
  }

  String _resolveTrackingFailureMessage(
    Object error, {
    required String fallbackMessage,
  }) {
    final normalizedMessage = error.toString().trim().toLowerCase();
    if (normalizedMessage.contains('permission') ||
        normalizedMessage.contains('denied')) {
      return 'Permita a localização em segundo plano para retomar o monitoramento.';
    }
    if (normalizedMessage.contains('location service') ||
        normalizedMessage.contains('service disabled')) {
      return 'Ative o serviço de localização do Android para retomar o monitoramento.';
    }
    return fallbackMessage;
  }
}
