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
    required this.locationSharingEnabled,
    required this.autoCheckInEnabled,
    required this.autoCheckOutEnabled,
    required this.locationUpdateIntervalSeconds,
    required this.locationAccuracyThresholdMeters,
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
      locationSharingEnabled: map['locationSharingEnabled'] as bool? ?? false,
      autoCheckInEnabled: map['autoCheckInEnabled'] as bool? ?? false,
      autoCheckOutEnabled: map['autoCheckOutEnabled'] as bool? ?? false,
      locationUpdateIntervalSeconds:
          (map['locationUpdateIntervalSeconds'] as num?)?.toInt() ?? 60,
      locationAccuracyThresholdMeters:
          (map['locationAccuracyThresholdMeters'] as num?)?.toInt() ?? 30,
      lastMatchedLocation: _readNullableString(map['lastMatchedLocation']),
      lastDetectedLocation: _readNullableString(map['lastDetectedLocation']),
      lastLocationUpdateAt: _readNullableDateTime(
        map['lastLocationUpdateAt'] as num?,
      ),
      locationFetchHistory: _readDateTimeList(map['locationFetchHistory']),
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
  final bool locationSharingEnabled;
  final bool autoCheckInEnabled;
  final bool autoCheckOutEnabled;
  final int locationUpdateIntervalSeconds;
  final int locationAccuracyThresholdMeters;
  final String? lastMatchedLocation;
  final String? lastDetectedLocation;
  final DateTime? lastLocationUpdateAt;
  final List<DateTime> locationFetchHistory;
  final String? lastCheckInLocation;
  final DateTime? lastCheckIn;
  final DateTime? lastCheckOut;
  final String statusMessage;
  final StatusTone statusTone;

  static String? _readNullableString(Object? value) {
    final normalized = (value as String?)?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static DateTime? _readNullableDateTime(num? value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
  }

  static List<DateTime> _readDateTimeList(Object? value) {
    if (value is! List) {
      return const <DateTime>[];
    }

    return value
        .whereType<num>()
        .map((entry) => DateTime.fromMillisecondsSinceEpoch(entry.toInt()).toLocal())
        .toList(growable: false);
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
  static const bool stopServiceOnTaskRemoval = true;
  static const bool allowAutomaticRestart = false;

  static final Map<CheckingBackgroundLocationListener, DataCallback>
  _listeners = <CheckingBackgroundLocationListener, DataCallback>{};

  static bool _initialized = false;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool shouldRunForState(CheckingState state) {
    return state.locationSharingEnabled && state.hasAnyLocationAutomation;
  }

  static void initialize() {
    if (!isSupported || _initialized) {
      return;
    }

    try {
      FlutterForegroundTask.initCommunicationPort();
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
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: false,
          allowAutoRestart: allowAutomaticRestart,
          stopWithTask: stopServiceOnTaskRemoval,
        ),
      );
      _initialized = true;
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
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        if (!interactive) {
          return const CheckingBackgroundStartResult(
            ready: false,
            blockingMessage:
                'Permita as notificações do aplicativo para habilitar a busca por localização.',
          );
        }

        final requestedPermission =
            await FlutterForegroundTask.requestNotificationPermission();
        if (requestedPermission != NotificationPermission.granted) {
          if (requestedPermission ==
              NotificationPermission.permanently_denied) {
            await openAppSettings();
          }
          return const CheckingBackgroundStartResult(
            ready: false,
            blockingMessage:
                'Permita as notificações do aplicativo para manter o monitoramento em segundo plano.',
          );
        }
      }
    } on MissingPluginException {
      return const CheckingBackgroundStartResult(ready: true);
    }

    if (!interactive) {
      return const CheckingBackgroundStartResult(ready: true);
    }

    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        final ignored =
            await FlutterForegroundTask.requestIgnoreBatteryOptimization();
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

  static Future<void> start() async {
    if (!isSupported) {
      return;
    }

    initialize();
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

  final CheckingStorageService _storageService = const CheckingStorageService();
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
    await _reloadTrackingState(forceRestart: true);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _scheduleBoundaryTimer?.cancel();
    _scheduleBoundaryTimer = null;
    _locationCaptureTimer?.cancel();
    _locationCaptureTimer = null;
    _lastKnownRemoteState = null;
    _lastKnownRemoteStateAt = null;
    _currentIntervalSeconds = null;
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
    unawaited(_reloadTrackingState(forceRestart: true));
  }

  Future<void> _reloadTrackingState({required bool forceRestart}) async {
    final state = CheckingLocationLogic.resolveLocationUpdateIntervalState(
      await _storageService.loadState(),
    );
    if (!CheckingBackgroundLocationService.shouldRunForState(state)) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _scheduleBoundaryTimer?.cancel();
      _scheduleBoundaryTimer = null;
      _locationCaptureTimer?.cancel();
      _locationCaptureTimer = null;
      _currentIntervalSeconds = null;
      await _stopService();
      return;
    }

    final hasPermission = await _hasBackgroundLocationPermission();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!hasPermission || !serviceEnabled) {
      final disabledState = state.copyWith(
        locationSharingEnabled: false,
        autoCheckInEnabled: false,
        autoCheckOutEnabled: false,
        lastMatchedLocation: null,
        lastDetectedLocation: null,
        lastLocationUpdateAt: null,
      );
      await _storageService.saveState(disabledState);
      _sendSnapshot(
        disabledState,
        statusMessage: serviceEnabled
            ? 'Permita a localização em segundo plano para retomar o monitoramento.'
            : 'Ative o serviço de localização do Android para retomar o monitoramento.',
        statusTone: StatusTone.warning,
      );
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _scheduleBoundaryTimer?.cancel();
      _scheduleBoundaryTimer = null;
      _currentIntervalSeconds = null;
      await _stopService();
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
    await _positionSubscription?.cancel();
    _positionSubscription = null;
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
          (position) => unawaited(_handlePositionUpdate(position)),
          onError: (_) {
            _sendSnapshot(
              state,
              statusMessage: 'Falha ao atualizar a localização do aparelho.',
              statusTone: StatusTone.error,
            );
          },
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
      await _handlePositionUpdate(currentPosition);
    } catch (_) {
      // O serviço continua tentando as próximas leituras periódicas ou da stream.
    }
  }

  void _restartScheduleBoundaryTimer(CheckingState state) {
    _scheduleBoundaryTimer?.cancel();
    _scheduleBoundaryTimer = null;

    _scheduleBoundaryTimer = Timer(
      CheckingLocationLogic.delayUntilNextLocationUpdateIntervalBoundary(),
      () {
        _lastKnownRemoteState = null;
        _lastKnownRemoteStateAt = null;
        unawaited(_reloadTrackingState(forceRestart: true));
      },
    );
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

    _processingLocationUpdate = true;
    try {
      final managedLocations = await _locationCatalogService.loadLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final matchedLocation = matchResult.matchedLocation;
      final positionTimestamp = CheckingLocationLogic.resolvePositionTimestamp(
        position,
      );
      final locationFetchHistory = CheckingLocationLogic.recordLocationFetchHistory(
        history: baseState.locationFetchHistory,
        timestamp: positionTimestamp,
      );
      final capturedLocationLabel =
          CheckingLocationLogic.resolveCapturedLocationLabel(
            location: matchedLocation,
            nearestWorkplaceDistanceMeters:
                matchResult.nearestWorkplaceDistanceMeters,
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

      if (!nextState.hasAnyLocationAutomation ||
          !nextState.hasValidChave ||
          !nextState.hasApiConfig) {
        return;
      }

      if (matchedLocation == null) {
        if (!nextState.autoCheckOutEnabled ||
            matchResult.nearestWorkplaceDistanceMeters == null ||
            matchResult.nearestWorkplaceDistanceMeters! <=
                CheckingLocationLogic.outOfRangeCheckoutDistanceMeters) {
          return;
        }

        await _submitAutomaticOutOfRangeCheckout(
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

      final nextState = CheckingLocationLogic.applyRemoteState(
        currentState: state,
        response: response.state,
        statusMessage:
            '${nextAction.label} automático enviado para $resolvedLocal.',
        tone: StatusTone.success,
        recentAction: nextAction,
        recentLocal: resolvedLocal,
      );
      await _storageService.saveState(nextState);
      _sendSnapshot(
        nextState,
        statusMessage: nextState.statusMessage,
        statusTone: nextState.statusTone,
      );
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

  Future<void> _submitAutomaticOutOfRangeCheckout(
    CheckingState state,
    double? nearestDistanceMeters,
  ) async {
    try {
      if (_canSkipFetchOutOfRange(state, nearestDistanceMeters)) {
        return;
      }

      final remoteState = await _apiService.fetchState(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
      );
      _rememberRemoteState(remoteState);

      final nextAction = CheckingLocationLogic.resolveAutomaticActionOutOfRange(
        remoteState: remoteState,
        nearestDistanceMeters: nearestDistanceMeters,
        autoCheckOutEnabled: state.autoCheckOutEnabled,
      );
      if (nextAction == null) {
        return;
      }

      final response = await _apiService.submitEvent(
        baseUrl: state.apiBaseUrl,
        sharedKey: state.apiSharedKey,
        chave: state.chave,
        projeto: state.projetoFor(nextAction).apiValue,
        action: nextAction.apiValue,
        informe: InformeType.normal.name,
        clientEventId: _buildClientEventId(),
        eventTime: DateTime.now(),
        local: CheckingLocationLogic.automaticCheckoutLocation,
      );
      _rememberRemoteState(response.state);

      final nextState = CheckingLocationLogic.applyRemoteState(
        currentState: state,
        response: response.state,
        statusMessage:
            'Check-Out automático enviado por afastamento das áreas monitoradas.',
        tone: StatusTone.success,
        recentAction: nextAction,
        recentLocal: CheckingLocationLogic.automaticCheckoutLocation,
      );
      await _storageService.saveState(nextState);
      _sendSnapshot(
        nextState,
        statusMessage: nextState.statusMessage,
        statusTone: nextState.statusTone,
      );
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao executar o check-out automático por afastamento.';
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

  bool _canSkipFetchOutOfRange(
    CheckingState state,
    double? nearestDistanceMeters,
  ) {
    if (!_isRemoteStateCacheFresh || _lastKnownRemoteState == null) {
      return false;
    }

    return CheckingLocationLogic.resolveAutomaticActionOutOfRange(
          remoteState: _lastKnownRemoteState!,
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckOutEnabled: state.autoCheckOutEnabled,
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
    final whenInUseStatus = await Permission.locationWhenInUse.status;
    final alwaysStatus = await Permission.locationAlways.status;
    return whenInUseStatus.isGranted && alwaysStatus.isGranted;
  }

  void _sendSnapshot(
    CheckingState state, {
    String? statusMessage,
    StatusTone? statusTone,
  }) {
    FlutterForegroundTask.sendDataToMain(<String, Object?>{
      'kind': CheckingBackgroundLocationService._taskDataKind,
      'chave': state.chave,
      'registro': state.registro.name,
      'checkInProjeto': state.checkInProjeto.name,
      'locationSharingEnabled': state.locationSharingEnabled,
      'autoCheckInEnabled': state.autoCheckInEnabled,
      'autoCheckOutEnabled': state.autoCheckOutEnabled,
      'locationUpdateIntervalSeconds': state.locationUpdateIntervalSeconds,
      'locationAccuracyThresholdMeters': state.locationAccuracyThresholdMeters,
      'lastMatchedLocation': state.lastMatchedLocation,
      'lastDetectedLocation': state.lastDetectedLocation,
      'lastLocationUpdateAt':
          state.lastLocationUpdateAt?.millisecondsSinceEpoch,
        'locationFetchHistory': state.locationFetchHistory
          .map((value) => value.millisecondsSinceEpoch)
          .toList(growable: false),
      'lastCheckInLocation': state.lastCheckInLocation,
      'lastCheckIn': state.lastCheckIn?.millisecondsSinceEpoch,
      'lastCheckOut': state.lastCheckOut?.millisecondsSinceEpoch,
      'statusMessage': statusMessage ?? '',
      'statusTone': (statusTone ?? StatusTone.neutral).name,
    });
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
}
