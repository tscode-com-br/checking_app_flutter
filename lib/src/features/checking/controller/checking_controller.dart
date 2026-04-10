import 'dart:async';
import 'dart:math';

import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:checking/src/features/checking/services/checking_android_bridge.dart';
import 'package:checking/src/features/checking/services/checking_services.dart';
import 'package:checking/src/features/checking/services/location_catalog_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class CheckingController extends ChangeNotifier {
  static const double outOfRangeCheckoutDistanceMeters = 2000;
  static const double maxAcceptedLocationAccuracyMeters = 30;
  static const String automaticCheckoutLocation = 'Fora do Local de Trabalho';

  CheckingController({
    CheckingStorageService? storageService,
    CheckingApiService? apiService,
    CheckingAndroidBridge? androidBridge,
    LocationCatalogService? locationCatalogService,
  }) : _storageService = storageService ?? const CheckingStorageService(),
       _apiService = apiService ?? CheckingApiService(),
       _androidBridge = androidBridge ?? CheckingAndroidBridge(),
       _locationCatalogService =
           locationCatalogService ?? LocationCatalogService();

  final CheckingStorageService _storageService;
  final CheckingApiService _apiService;
  final CheckingAndroidBridge _androidBridge;
  final LocationCatalogService _locationCatalogService;
  final Random _random = Random();
  static const Duration _historyRefreshInterval = Duration(seconds: 5);

  CheckingState _state = CheckingState.initial();
  bool _initialized = false;
  DateTime? _lastNativeActionAt;
  RegistroType? _lastNativeAction;
  Timer? _historyRefreshTimer;
  StreamSubscription<Position>? _positionSubscription;
  List<ManagedLocation> _managedLocations = const [];
  bool _processingLocationUpdate = false;
  Future<void> _pendingStateSave = Future.value();

  CheckingState get state => _state;
  List<ManagedLocation> get managedLocations =>
      List.unmodifiable(_managedLocations);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _state = await _storageService.loadState();
      _managedLocations = await _locationCatalogService.loadLocations();
      notifyListeners();
      if (_state.hasApiConfig) {
        await refreshLocationsCatalog(silent: true, updateStatus: false);
      }
      await _androidBridge.initialize(onNativeAction: _handleNativeAction);
      await _syncNativeAutomation();
      if (_state.hasApiConfig && _state.hasValidChave) {
        await syncHistory(silent: true, updateStatus: true);
        _restartHistoryAutoRefresh();
      } else {
        _stopHistoryAutoRefresh();
        _clearHistoryFields(updateStatus: true);
      }
      if (_state.locationSharingEnabled) {
        await _restoreLocationSharing();
      }
    } catch (_) {
      _setState(
        CheckingState.initial().copyWith(
          isLoading: false,
          statusMessage: 'Falha ao carregar dados locais do aplicativo.',
          statusTone: StatusTone.error,
        ),
      );
    }
  }

  void updateChave(String value) {
    final normalized = _normalizeKey(value);
    if (normalized == _state.chave) {
      return;
    }

    final nextState = _state.copyWith(
      chave: normalized,
      lastMatchedLocation: null,
      lastDetectedLocation: null,
      lastLocationUpdateAt: null,
      lastCheckInLocation: null,
      lastCheckIn: null,
      lastCheckOut: null,
    );
    _updateAndPersist(nextState, syncAutomation: false);

    if (!_state.hasValidChave || !_state.hasApiConfig) {
      _stopHistoryAutoRefresh();
      _clearHistoryFields(updateStatus: false);
      return;
    }

    _restartHistoryAutoRefresh();
    unawaited(syncHistory(silent: true, updateStatus: true));
  }

  void updateInforme(InformeType value) => _updateAndPersist(
    _state.registro == RegistroType.checkIn
        ? _state.copyWith(checkInInforme: value)
        : _state.copyWith(checkOutInforme: value),
    syncAutomation: false,
  );

  void updateRegistro(RegistroType value) => _updateAndPersist(
    _state.copyWith(registro: value),
    syncAutomation: false,
  );

  void updateProjeto(ProjetoType value) => _updateAndPersist(
    _state.copyWith(checkInProjeto: value),
    syncAutomation: false,
  );

  void updateApiBaseUrl(String value) => _updateAndPersist(
    _state.copyWith(apiBaseUrl: value.trim()),
    syncAutomation: false,
  );
  void updateApiSharedKey(String value) => _updateAndPersist(
    _state.copyWith(apiSharedKey: value.trim()),
    syncAutomation: false,
  );

  Future<void> setLocationSharingEnabled(bool value) async {
    if (_state.isLocationUpdating) {
      return;
    }

    if (!value) {
      await _stopLocationTracking();
      _updateAndPersist(
        _state.copyWith(
          locationSharingEnabled: false,
          lastMatchedLocation: null,
        ),
        syncAutomation: false,
      );
      _setStatus(
        'Compartilhamento de localização desativado.',
        StatusTone.warning,
      );
      return;
    }

    _setState(_state.copyWith(isLocationUpdating: true));
    try {
      final permissionResult = await _ensureLocationPermissionGranted(
        interactive: true,
      );
      if (!permissionResult.granted) {
        _setState(
          _state.copyWith(
            isLocationUpdating: false,
            locationSharingEnabled: false,
          ),
        );
        if (permissionResult.message.isNotEmpty) {
          _setStatus(permissionResult.message, StatusTone.error);
        }
        return;
      }

      await refreshLocationsCatalog(silent: true, updateStatus: false);
      _setState(
        _state.copyWith(
          locationSharingEnabled: true,
          isLocationUpdating: false,
        ),
      );
      unawaited(flushStatePersistence());
      await _startLocationTracking();
      _setStatus(
        'Compartilhamento de localização ativado com monitoramento em segundo plano.',
        StatusTone.success,
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          isLocationUpdating: false,
          locationSharingEnabled: false,
        ),
      );
      _setStatus(
        'Falha ao ativar o compartilhamento de localização.',
        StatusTone.error,
      );
    }
  }

  Future<void> setAutoCheckInEnabled(bool value) async {
    if (value && !_canEnableLocationAutomation()) {
      return;
    }

    _updateAndPersist(
      _state.copyWith(
        autoCheckInEnabled: value,
        lastMatchedLocation: value || _state.autoCheckOutEnabled
            ? _state.lastMatchedLocation
            : null,
      ),
      syncAutomation: false,
    );
  }

  Future<void> setAutoCheckOutEnabled(bool value) async {
    if (value && !_canEnableLocationAutomation()) {
      return;
    }

    _updateAndPersist(
      _state.copyWith(
        autoCheckOutEnabled: value,
        lastMatchedLocation: value || _state.autoCheckInEnabled
            ? _state.lastMatchedLocation
            : null,
      ),
      syncAutomation: false,
    );
  }

  Future<String> syncHistory({
    bool silent = false,
    bool updateStatus = true,
  }) async {
    if (!_state.hasValidChave) {
      _clearHistoryFields(updateStatus: updateStatus);
      return _state.statusMessage;
    }
    if (!_state.hasApiConfig) {
      if (updateStatus) {
        _setStatus(
          'A configuração interna da API do aplicativo está incompleta.',
          StatusTone.warning,
        );
      }
      return _state.statusMessage;
    }

    if (_state.isSyncing) {
      return _state.statusMessage;
    }

    _setState(_state.copyWith(isSyncing: true));
    try {
      final response = await _apiService.fetchState(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
        chave: _state.chave,
      );
      _applyRemoteState(
        response,
        statusMessage: updateStatus
            ? response.found
                  ? 'Histórico sincronizado com a API.'
                  : 'Nenhum histórico encontrado para a chave informada.'
            : _state.statusMessage,
        tone: updateStatus
            ? (response.found ? StatusTone.success : StatusTone.warning)
            : _state.statusTone,
        updateStatus: updateStatus,
      );
      return _state.statusMessage;
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao consultar a API.';
      if (updateStatus) {
        _setStatus(message, StatusTone.error);
      }
      if (!silent) rethrow;
      return message;
    } finally {
      _setState(_state.copyWith(isSyncing: false));
    }
  }

  Future<int> refreshLocationsCatalog({
    bool silent = false,
    bool updateStatus = true,
  }) async {
    if (!_state.hasApiConfig) {
      if (updateStatus) {
        _setStatus(
          'A configuração interna da API do aplicativo está incompleta.',
          StatusTone.warning,
        );
      }
      return _managedLocations.length;
    }

    try {
      final response = await _apiService.fetchLocations(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
      );
      await _locationCatalogService.replaceLocations(response.items);
      _managedLocations = response.items;
      notifyListeners();
      if (updateStatus) {
        _setStatus(
          '${response.items.length} localizações atualizadas no aplicativo.',
          StatusTone.success,
        );
      }
      return response.items.length;
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao atualizar as localizações do aplicativo.';
      if (updateStatus) {
        _setStatus(message, StatusTone.error);
      }
      if (!silent) {
        rethrow;
      }
      return _managedLocations.length;
    }
  }

  Future<String> submitCurrent() async {
    return _submit(registroForcado: null, source: 'manual');
  }

  Future<String> _submit({
    required RegistroType? registroForcado,
    required String source,
    String? local,
  }) async {
    if (!_state.hasValidChave) {
      throw const CheckingApiException(
        'Informe uma chave Petrobras com 4 caracteres.',
      );
    }
    if (!_state.hasApiConfig) {
      throw const CheckingApiException(
        'A configuração interna da API do aplicativo está incompleta.',
      );
    }

    _setState(_state.copyWith(isSubmitting: true));
    try {
      final registro = registroForcado ?? _state.registro;
      final response = await _apiService.submitEvent(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
        chave: _state.chave,
        projeto: _state.projetoFor(registro).apiValue,
        action: registro.apiValue,
        informe: _state.informeFor(registro).name,
        clientEventId: _buildClientEventId(
          prefix: source == 'location-automation' ? 'flutter-auto' : 'flutter',
        ),
        eventTime: DateTime.now(),
        local: local,
      );
      _applyRemoteState(
        response.state,
        statusMessage: response.message,
        tone: StatusTone.success,
        recentAction: registro,
        recentLocal: local,
      );
      return response.message;
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao enviar evento pela API.';
      _setStatus(
        '$message (${source == 'manual' ? 'manual' : 'automático'})',
        StatusTone.error,
      );
      rethrow;
    } finally {
      _setState(_state.copyWith(isSubmitting: false));
    }
  }

  Future<void> _handleNativeAction(String action) async {
    final normalized = action.trim().toLowerCase();
    final registro = switch (normalized) {
      'check-in' => RegistroType.checkIn,
      'check-out' => RegistroType.checkOut,
      _ => null,
    };

    if (registro == null) {
      return;
    }

    final now = DateTime.now();
    if (_state.isSubmitting) {
      return;
    }
    if (_lastNativeAction == registro &&
        _lastNativeActionAt != null &&
        now.difference(_lastNativeActionAt!).inSeconds < 60) {
      return;
    }

    _lastNativeAction = registro;
    _lastNativeActionAt = now;

    try {
      await _submit(registroForcado: registro, source: 'android-native');
    } catch (_) {
      // Status já atualizado em _submit.
    }
  }

  Future<void> _restoreLocationSharing() async {
    final permissionResult = await _ensureLocationPermissionGranted(
      interactive: false,
    );
    if (!permissionResult.granted) {
      _updateAndPersist(
        _state.copyWith(
          locationSharingEnabled: false,
          lastMatchedLocation: null,
        ),
        syncAutomation: false,
      );
      if (permissionResult.message.isNotEmpty) {
        _setStatus(permissionResult.message, StatusTone.warning);
      }
      return;
    }

    try {
      await _startLocationTracking();
    } catch (_) {
      _updateAndPersist(
        _state.copyWith(locationSharingEnabled: false),
        syncAutomation: false,
      );
      _setStatus(
        'Não foi possível retomar o monitoramento de localização.',
        StatusTone.error,
      );
    }
  }

  Future<void> _startLocationTracking() async {
    if (_positionSubscription != null) {
      return;
    }

    final locationSettings = _buildLocationSettings();
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) => unawaited(_handlePositionUpdate(position)),
          onError: (_) {
            _setStatus(
              'Falha ao atualizar a localização do aparelho.',
              StatusTone.error,
            );
          },
        );

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

  Future<void> _stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(minutes: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Checking',
          notificationText:
              'Compartilhamento de localização ativo para automação de presença.',
          enableWakeLock: true,
        ),
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  Future<void> _handlePositionUpdate(Position position) async {
    if (_processingLocationUpdate || !_state.locationSharingEnabled) {
      return;
    }
    if (!isLocationAccuracyPreciseEnough(position.accuracy)) {
      return;
    }

    _processingLocationUpdate = true;
    try {
      final positionTimestamp = _resolvePositionTimestamp(position);
      final matchResult = _resolveLocationMatch(position);
      final matchedLocation = matchResult.matchedLocation;
      final matchedAreaLabel = matchedLocation?.automationAreaLabel;
      final nextState = matchedLocation == null
          ? _state.copyWith(
              lastMatchedLocation: null,
              lastLocationUpdateAt: positionTimestamp,
            )
          : _state.copyWith(
              lastMatchedLocation: matchedAreaLabel,
              lastDetectedLocation: matchedLocation.local,
              lastLocationUpdateAt: positionTimestamp,
            );

      _updateAndPersist(nextState, syncAutomation: false);

      if (!_state.hasAnyLocationAutomation) {
        return;
      }

      if (!_state.hasValidChave ||
          !_state.hasApiConfig ||
          _state.isSubmitting) {
        return;
      }

      if (matchedLocation == null) {
        if (!shouldAttemptAutomaticOutOfRangeCheckout(
          lastRecordedAction: _state.lastRecordedAction,
          nearestDistanceMeters: matchResult.nearestWorkplaceDistanceMeters,
          autoCheckOutEnabled: _state.autoCheckOutEnabled,
        )) {
          return;
        }
        await _submitAutomaticOutOfRangeCheckout(
          matchResult.nearestWorkplaceDistanceMeters,
        );
        return;
      }

      if (!shouldAttemptAutomaticLocationEvent(
        location: matchedLocation,
        lastRecordedAction: _state.lastRecordedAction,
        lastCheckInLocation: _state.lastCheckInLocation,
        autoCheckInEnabled: _state.autoCheckInEnabled,
        autoCheckOutEnabled: _state.autoCheckOutEnabled,
      )) {
        return;
      }

      await _submitAutomaticLocationEvent(matchedLocation);
    } finally {
      _processingLocationUpdate = false;
    }
  }

  _LocationMatchResult _resolveLocationMatch(Position position) {
    ManagedLocation? nearestRegularLocation;
    double? nearestRegularDistanceMeters;
    ManagedLocation? nearestCheckoutLocation;
    double? nearestCheckoutDistanceMeters;
    double? nearestWorkplaceDistanceMeters;

    for (final location in _managedLocations) {
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        location.latitude,
        location.longitude,
      );
      if (!location.isCheckoutZone &&
          (nearestWorkplaceDistanceMeters == null ||
              distanceMeters < nearestWorkplaceDistanceMeters)) {
        nearestWorkplaceDistanceMeters = distanceMeters;
      }
      if (distanceMeters > location.toleranceMeters) {
        continue;
      }

      if (location.isCheckoutZone) {
        if (nearestCheckoutDistanceMeters == null ||
            distanceMeters < nearestCheckoutDistanceMeters) {
          nearestCheckoutLocation = location;
          nearestCheckoutDistanceMeters = distanceMeters;
        }
        continue;
      }

      if (nearestRegularDistanceMeters == null ||
          distanceMeters < nearestRegularDistanceMeters) {
        nearestRegularLocation = location;
        nearestRegularDistanceMeters = distanceMeters;
      }
    }

    return _LocationMatchResult(
      matchedLocation: nearestCheckoutLocation ?? nearestRegularLocation,
      nearestWorkplaceDistanceMeters: nearestWorkplaceDistanceMeters,
    );
  }

  Future<void> _submitAutomaticLocationEvent(ManagedLocation location) async {
    try {
      final remoteState = await _apiService.fetchState(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
        chave: _state.chave,
      );
      final nextAction = resolveAutomaticActionForLocation(
        remoteState: remoteState,
        location: location,
        autoCheckInEnabled: _state.autoCheckInEnabled,
        autoCheckOutEnabled: _state.autoCheckOutEnabled,
        lastCheckInLocation: _state.lastCheckInLocation,
      );
      if (nextAction == null) {
        return;
      }

      final resolvedLocal = resolveAutomaticEventLocal(
        action: nextAction,
        location: location,
      );

      final response = await _submit(
        registroForcado: nextAction,
        source: 'location-automation',
        local: resolvedLocal,
      );
      _setStatus(
        '${nextAction.label} automático enviado para $resolvedLocal.',
        StatusTone.success,
      );
      if (response.isEmpty) {
        return;
      }
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao executar a automação por localização.';
      _setStatus(message, StatusTone.error);
    }
  }

  Future<void> _submitAutomaticOutOfRangeCheckout(
    double? nearestDistanceMeters,
  ) async {
    try {
      final remoteState = await _apiService.fetchState(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
        chave: _state.chave,
      );
      final nextAction = resolveAutomaticActionOutOfRange(
        remoteState: remoteState,
        nearestDistanceMeters: nearestDistanceMeters,
        autoCheckOutEnabled: _state.autoCheckOutEnabled,
      );
      if (nextAction == null) {
        return;
      }

      await _submit(
        registroForcado: nextAction,
        source: 'location-automation',
        local: automaticCheckoutLocation,
      );
      _setStatus(
        'Check-Out automático enviado por afastamento das áreas monitoradas.',
        StatusTone.success,
      );
    } catch (error) {
      final message = error is CheckingApiException
          ? error.message
          : 'Falha ao executar o check-out automático por afastamento.';
      _setStatus(message, StatusTone.error);
    }
  }

  @visibleForTesting
  static RegistroType? resolveAutomaticActionForLocation({
    required MobileStateResponse remoteState,
    required ManagedLocation location,
    required bool autoCheckInEnabled,
    required bool autoCheckOutEnabled,
    required String? lastCheckInLocation,
  }) {
    final lastRecordedAction = _resolveLastRecordedAction(remoteState);
    final recordedCheckInLocation = _resolveRecordedCheckInLocation(
      remoteState,
      fallbackLocation: lastCheckInLocation,
    );
    if (!shouldAttemptAutomaticLocationEvent(
      location: location,
      lastRecordedAction: lastRecordedAction,
      lastCheckInLocation: recordedCheckInLocation,
      autoCheckInEnabled: autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled,
    )) {
      return null;
    }
    return location.isCheckoutZone
        ? RegistroType.checkOut
        : RegistroType.checkIn;
  }

  @visibleForTesting
  static bool shouldAttemptAutomaticLocationEvent({
    required ManagedLocation location,
    required RegistroType? lastRecordedAction,
    required String? lastCheckInLocation,
    required bool autoCheckInEnabled,
    required bool autoCheckOutEnabled,
  }) {
    if (location.isCheckoutZone) {
      return autoCheckOutEnabled && lastRecordedAction == RegistroType.checkIn;
    }

    if (!autoCheckInEnabled) {
      return false;
    }
    if (lastRecordedAction != RegistroType.checkIn) {
      return true;
    }
    return !location.matchesLocationName(lastCheckInLocation);
  }

  @visibleForTesting
  static RegistroType? resolveAutomaticActionOutOfRange({
    required MobileStateResponse remoteState,
    required double? nearestDistanceMeters,
    required bool autoCheckOutEnabled,
  }) {
    return shouldAttemptAutomaticOutOfRangeCheckout(
          lastRecordedAction: _resolveLastRecordedAction(remoteState),
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckOutEnabled: autoCheckOutEnabled,
        )
        ? RegistroType.checkOut
        : null;
  }

  @visibleForTesting
  static bool shouldAttemptAutomaticOutOfRangeCheckout({
    required RegistroType? lastRecordedAction,
    required double? nearestDistanceMeters,
    required bool autoCheckOutEnabled,
  }) {
    if (!autoCheckOutEnabled ||
        nearestDistanceMeters == null ||
        nearestDistanceMeters <= outOfRangeCheckoutDistanceMeters) {
      return false;
    }
    return lastRecordedAction == RegistroType.checkIn;
  }

  @visibleForTesting
  static String resolveAutomaticEventLocal({
    required RegistroType action,
    ManagedLocation? location,
  }) {
    if (action == RegistroType.checkOut) {
      if (location != null && location.isCheckoutZone) {
        return location.automationAreaLabel;
      }
      return automaticCheckoutLocation;
    }

    return location?.local ?? automaticCheckoutLocation;
  }

  static DateTime _resolvePositionTimestamp(Position position) {
    return position.timestamp.toLocal();
  }

  @visibleForTesting
  static bool isLocationAccuracyPreciseEnough(double? accuracyMeters) {
    if (accuracyMeters == null || accuracyMeters.isNaN) {
      return false;
    }
    return accuracyMeters <= maxAcceptedLocationAccuracyMeters;
  }

  static RegistroType? _resolveLastRecordedAction(
    MobileStateResponse remoteState,
  ) {
    final lastCheckInAt = remoteState.lastCheckInAt;
    final lastCheckOutAt = remoteState.lastCheckOutAt;
    if (lastCheckInAt == null && lastCheckOutAt == null) {
      return _parseRemoteAction(remoteState.currentAction);
    }
    if (lastCheckInAt != null && lastCheckOutAt == null) {
      return RegistroType.checkIn;
    }
    if (lastCheckInAt == null && lastCheckOutAt != null) {
      return RegistroType.checkOut;
    }
    if (lastCheckInAt!.isAfter(lastCheckOutAt!)) {
      return RegistroType.checkIn;
    }
    if (lastCheckOutAt.isAfter(lastCheckInAt)) {
      return RegistroType.checkOut;
    }
    return _parseRemoteAction(remoteState.currentAction);
  }

  static RegistroType? _parseRemoteAction(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'checkin' => RegistroType.checkIn,
      'checkout' => RegistroType.checkOut,
      _ => null,
    };
  }

  static String? _resolveRecordedCheckInLocation(
    MobileStateResponse remoteState, {
    required String? fallbackLocation,
  }) {
    if (_parseRemoteAction(remoteState.currentAction) == RegistroType.checkIn) {
      final currentLocal = _normalizeOptionalLocationName(
        remoteState.currentLocal,
      );
      if (currentLocal != null) {
        return currentLocal;
      }
    }
    return _normalizeOptionalLocationName(fallbackLocation);
  }

  Future<_LocationPermissionResult> _ensureLocationPermissionGranted({
    required bool interactive,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const _LocationPermissionResult(
        granted: false,
        message: 'Ative o serviço de localização do Android para continuar.',
      );
    }

    var foregroundStatus = await Permission.locationWhenInUse.status;
    if (interactive && !foregroundStatus.isGranted) {
      foregroundStatus = await Permission.locationWhenInUse.request();
    }
    if (!foregroundStatus.isGranted) {
      if (foregroundStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return const _LocationPermissionResult(
        granted: false,
        message:
            'Permita a localização precisa do aplicativo para ativar o monitoramento.',
      );
    }

    var backgroundStatus = await Permission.locationAlways.status;
    if (interactive && !backgroundStatus.isGranted) {
      backgroundStatus = await Permission.locationAlways.request();
    }
    if (!backgroundStatus.isGranted) {
      if (backgroundStatus.isPermanentlyDenied) {
        await openAppSettings();
      }
      return const _LocationPermissionResult(
        granted: false,
        message:
            'Permita o acesso à localização em segundo plano para concluir a ativação.',
      );
    }

    final accuracyStatus = await Geolocator.getLocationAccuracy();
    if (accuracyStatus == LocationAccuracyStatus.reduced) {
      return const _LocationPermissionResult(
        granted: false,
        message:
            'A localização exata precisa ser habilitada nas configurações do sistema.',
      );
    }

    return const _LocationPermissionResult(granted: true, message: '');
  }

  void _applyRemoteState(
    MobileStateResponse response, {
    required String statusMessage,
    required StatusTone tone,
    bool updateStatus = true,
    RegistroType? recentAction,
    String? recentLocal,
  }) {
    final suggestedRegistro = CheckingState.inferSuggestedRegistro(
      lastCheckIn: response.lastCheckInAt,
      lastCheckOut: response.lastCheckOutAt,
      fallback: _state.registro,
    );
    final remoteLastRecordedAction = _resolveLastRecordedAction(response);
    String? nextLastCheckInLocation = _state.lastCheckInLocation;
    if (recentAction == RegistroType.checkIn) {
      nextLastCheckInLocation = _normalizeOptionalLocationName(recentLocal);
    } else if (recentAction == RegistroType.checkOut) {
      nextLastCheckInLocation = null;
    } else if (remoteLastRecordedAction == RegistroType.checkIn) {
      nextLastCheckInLocation = _resolveRecordedCheckInLocation(
        response,
        fallbackLocation: _state.lastCheckInLocation,
      );
    } else if (remoteLastRecordedAction == RegistroType.checkOut) {
      nextLastCheckInLocation = null;
    }

    _updateAndPersist(
      _state.copyWith(
        lastCheckIn: response.lastCheckInAt,
        lastCheckOut: response.lastCheckOutAt,
        lastCheckInLocation: nextLastCheckInLocation,
        registro: suggestedRegistro,
        checkInProjeto: _resolveProjeto(response.projeto) ?? _state.projeto,
        statusMessage: updateStatus ? statusMessage : _state.statusMessage,
        statusTone: updateStatus ? tone : _state.statusTone,
      ),
    );
  }

  void _clearHistoryFields({required bool updateStatus}) {
    _updateAndPersist(
      _state.copyWith(
        lastMatchedLocation: null,
        lastDetectedLocation: null,
        lastLocationUpdateAt: null,
        lastCheckInLocation: null,
        lastCheckIn: null,
        lastCheckOut: null,
        statusMessage: updateStatus
            ? 'Informe a chave do usuário para sincronizar o histórico.'
            : _state.statusMessage,
        statusTone: updateStatus ? StatusTone.warning : _state.statusTone,
      ),
      syncAutomation: false,
    );
  }

  void _restartHistoryAutoRefresh() {
    _stopHistoryAutoRefresh();
    if (!_state.hasValidChave || !_state.hasApiConfig) {
      return;
    }

    _historyRefreshTimer = Timer.periodic(_historyRefreshInterval, (_) {
      if (!_state.hasValidChave ||
          !_state.hasApiConfig ||
          _state.isSubmitting) {
        return;
      }
      unawaited(syncHistory(silent: true, updateStatus: false));
    });
  }

  void _stopHistoryAutoRefresh() {
    _historyRefreshTimer?.cancel();
    _historyRefreshTimer = null;
  }

  ProjetoType? _resolveProjeto(String? value) {
    return switch (value) {
      'P80' => ProjetoType.p80,
      'P82' => ProjetoType.p82,
      'P83' => ProjetoType.p83,
      _ => null,
    };
  }

  String _buildClientEventId({required String prefix}) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '$prefix-$now-$randomPart';
  }

  static String? _normalizeOptionalLocationName(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _updateAndPersist(
    CheckingState nextState, {
    bool syncAutomation = false,
  }) {
    _setState(nextState.copyWith(isLoading: false));
    unawaited(_enqueueStateSave(_state));
    if (_initialized && syncAutomation) {
      unawaited(_syncNativeAutomation());
    }
  }

  Future<void> flushStatePersistence() => _enqueueStateSave(_state);

  @visibleForTesting
  Future<void> waitForPendingStatePersistence() => _pendingStateSave;

  Future<void> _enqueueStateSave(CheckingState stateSnapshot) {
    final saveOperation = _pendingStateSave.then<void>(
      (_) => _storageService.saveState(stateSnapshot),
    );
    _pendingStateSave = saveOperation.then<void>(
      (_) {},
      onError: (error, stackTrace) {},
    );
    return saveOperation;
  }

  String _normalizeKey(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.substring(0, min(4, normalized.length));
  }

  void _setStatus(String message, StatusTone tone) {
    _updateAndPersist(
      _state.copyWith(
        statusMessage: message,
        statusTone: tone,
        isLoading: false,
      ),
    );
  }

  void _setState(CheckingState nextState) {
    _state = nextState;
    notifyListeners();
  }

  bool _canEnableAutomation(String message) {
    if (!_state.hasValidChave) {
      _setStatus(message, StatusTone.warning);
      return false;
    }
    if (!_state.hasApiConfig) {
      _setStatus(message, StatusTone.warning);
      return false;
    }
    return true;
  }

  bool _canEnableLocationAutomation() {
    if (!_state.locationSharingEnabled) {
      _setStatus(
        'Ative o compartilhamento de localização antes de habilitar a automação.',
        StatusTone.warning,
      );
      return false;
    }
    return _canEnableAutomation(
      'Preencha Chave, API HTTPS e chave compartilhada antes de ativar a automação por localização.',
    );
  }

  Future<void> _syncNativeAutomation() async {
    try {
      await _androidBridge.clearSchedules();
    } catch (_) {
      // Falhas de bridge nativa nao devem derrubar a UI.
    }
  }

  @override
  void dispose() {
    _stopHistoryAutoRefresh();
    unawaited(_stopLocationTracking());
    super.dispose();
  }
}

class _LocationPermissionResult {
  const _LocationPermissionResult({
    required this.granted,
    required this.message,
  });

  final bool granted;
  final String message;
}

class _LocationMatchResult {
  const _LocationMatchResult({
    required this.matchedLocation,
    required this.nearestWorkplaceDistanceMeters,
  });

  final ManagedLocation? matchedLocation;
  final double? nearestWorkplaceDistanceMeters;
}
