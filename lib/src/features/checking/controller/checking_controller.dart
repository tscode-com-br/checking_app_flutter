import 'dart:async';
import 'dart:math';

import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:checking/src/features/checking/services/checking_android_bridge.dart';
import 'package:checking/src/features/checking/services/checking_background_service.dart';
import 'package:checking/src/features/checking/services/checking_location_logic.dart';
import 'package:checking/src/features/checking/services/checking_services.dart';
import 'package:checking/src/features/checking/services/location_catalog_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class CheckingController extends ChangeNotifier {
  static const double outOfRangeCheckoutDistanceMeters =
      CheckingLocationLogic.outOfRangeCheckoutDistanceMeters;
  static const double defaultLocationAccuracyThresholdMeters =
      CheckingLocationLogic.defaultLocationAccuracyThresholdMeters;
  static const String automaticCheckoutLocation =
      CheckingLocationLogic.automaticCheckoutLocation;

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
  Timer? _locationUpdateIntervalTimer;
  Timer? _locationCaptureTimer;
  StreamSubscription<Position>? _positionSubscription;
  List<ManagedLocation> _managedLocations = const [];
  bool _processingLocationUpdate = false;
  bool _foregroundRefreshInProgress = false;
  Future<void> _pendingStateSave = Future.value();
  bool _hasHydratedHistoryForCurrentKey = false;
  late final CheckingBackgroundLocationListener _backgroundLocationListener =
      _handleBackgroundLocationSnapshot;

  CheckingState get state => _state;
  List<ManagedLocation> get managedLocations =>
      List.unmodifiable(_managedLocations);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (CheckingBackgroundLocationService.isSupported) {
      CheckingBackgroundLocationService.addListener(
        _backgroundLocationListener,
      );
    }
    try {
      _state = _resolveLocationUpdateIntervalState(
        await _storageService.loadState(),
      ).copyWith(lastCheckIn: null, lastCheckOut: null);
      _hasHydratedHistoryForCurrentKey = false;
      _managedLocations = await _locationCatalogService.loadLocations();
      _restartLocationUpdateIntervalBoundaryTimer();
      notifyListeners();
      await _androidBridge.initialize(onNativeAction: _handleNativeAction);
      await _syncNativeAutomation();
      await _runInitialAndroidSetupIfNeeded();
      await refreshAfterEnteringForeground();
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

    _hasHydratedHistoryForCurrentKey = false;

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
    unawaited(_refreshBackgroundLocationService());

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

  void updateApiBaseUrl(String value) {
    _updateAndPersist(
      _state.copyWith(apiBaseUrl: value.trim()),
      syncAutomation: false,
    );
    unawaited(_refreshBackgroundLocationService());
  }

  void updateApiSharedKey(String value) {
    _updateAndPersist(
      _state.copyWith(apiSharedKey: value.trim()),
      syncAutomation: false,
    );
    unawaited(_refreshBackgroundLocationService());
  }

  Future<void> setLocationSharingEnabled(bool value) async {
    if (_state.isLocationUpdating || _state.isAutomaticCheckingUpdating) {
      return;
    }

    if (value && !_state.canEnableLocationSharing) {
      _setStatus(
        'Permita localização precisa, localização em segundo plano e notificações para habilitar a busca por localização.',
        StatusTone.error,
      );
      return;
    }

    if (!value) {
      await _stopLocationTracking();
      _updateAndPersist(
        _state.copyWith(
          locationSharingEnabled: false,
          autoCheckInEnabled: false,
          autoCheckOutEnabled: false,
          lastMatchedLocation: null,
        ),
        syncAutomation: false,
      );
      await flushStatePersistence();
      _setStatus('Busca por localização desativada.', StatusTone.warning);
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
            autoCheckInEnabled: false,
            autoCheckOutEnabled: false,
          ),
        );
        if (permissionResult.message.isNotEmpty) {
          _setStatus(permissionResult.message, StatusTone.error);
        }
        return;
      }

      final backgroundStartResult =
          await CheckingBackgroundLocationService.ensureReadyForStart(
            interactive: true,
          );
      if (!backgroundStartResult.ready) {
        _setState(
          _state.copyWith(
            isLocationUpdating: false,
            locationSharingEnabled: false,
            autoCheckInEnabled: false,
            autoCheckOutEnabled: false,
          ),
        );
        if (backgroundStartResult.blockingMessage.isNotEmpty) {
          _setStatus(backgroundStartResult.blockingMessage, StatusTone.error);
        }
        return;
      }

      if (_managedLocations.isEmpty) {
        await refreshLocationsCatalog(silent: true, updateStatus: false);
      } else {
        await refreshLocationUpdateInterval(
          restartLocationTrackingIfNeeded: false,
        );
      }
      _setState(
        _state.copyWith(
          locationSharingEnabled: true,
          isLocationUpdating: false,
        ),
      );
      await flushStatePersistence();
      await _refreshLocationTrackingNow();
      final oemSetupResult = await _androidBridge.requestOemBackgroundSetup();
      final automaticCheckEnabled = _state.automaticCheckInOutEnabled;
      final statusSegments = <String>[
        if (backgroundStartResult.warningMessage.isNotEmpty)
          backgroundStartResult.warningMessage
        else
          automaticCheckEnabled
              ? 'Busca por localização ativada com check-in/check-out automáticos habilitados.'
              : 'Busca por localização ativada. Sem a automação, a localização será atualizada somente com o aplicativo em uso.',
        if (oemSetupResult.message.isNotEmpty) oemSetupResult.message,
      ];
      final hasWarning =
          backgroundStartResult.warningMessage.isNotEmpty ||
          oemSetupResult.message.isNotEmpty;
      _setStatus(
        statusSegments.join(' '),
        hasWarning ? StatusTone.warning : StatusTone.success,
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          isLocationUpdating: false,
          locationSharingEnabled: false,
        ),
      );
      _setStatus('Falha ao ativar a busca por localização.', StatusTone.error);
    }
  }

  Future<void> setAutomaticCheckInOutEnabled(bool value) async {
    if (_state.isAutomaticCheckingUpdating || _state.isLocationUpdating) {
      return;
    }

    if (_state.automaticCheckInOutEnabled == value) {
      return;
    }

    if (!_state.locationSharingEnabled) {
      _updateAndPersist(
        _state.copyWith(autoCheckInEnabled: false, autoCheckOutEnabled: false),
        syncAutomation: false,
      );
      await flushStatePersistence();
      _setStatus(
        'Ative a busca por localização para habilitar o check-in/check-out automático.',
        StatusTone.warning,
      );
      return;
    }

    _setState(_state.copyWith(isAutomaticCheckingUpdating: true));
    try {
      final nextState = _state.copyWith(
        autoCheckInEnabled: value,
        autoCheckOutEnabled: value,
        isAutomaticCheckingUpdating: true,
      );
      _updateAndPersist(nextState, syncAutomation: false);
      await flushStatePersistence();

      var appliedImmediateAutomation = false;
      if (value) {
        if (_managedLocations.isEmpty && _state.hasApiConfig) {
          await refreshLocationsCatalog(silent: true, updateStatus: false);
        }
        appliedImmediateAutomation =
            await _applyAutomationFromLastKnownLocationIfNeeded();
        if (!appliedImmediateAutomation) {
          final previousLastCheckIn = _state.lastCheckIn;
          final previousLastCheckOut = _state.lastCheckOut;
          await _captureCurrentPositionNow();
          appliedImmediateAutomation =
              previousLastCheckIn != _state.lastCheckIn ||
              previousLastCheckOut != _state.lastCheckOut;
        }
        await _restartLocationTracking();
      } else {
        await _restartLocationTracking();
      }

      if (value) {
        if (!appliedImmediateAutomation) {
          _setStatus(
            _state.locationSharingEnabled
                ? 'Check-in/Check-out automáticos ativados.'
                : 'Check-in/Check-out automáticos ativados. Ative a busca por localização para iniciar o monitoramento.',
            StatusTone.success,
          );
        }
        return;
      }

      _setStatus(
        _state.locationSharingEnabled
            ? 'Check-in/Check-out automáticos desativados. A busca por localização continuará ativa somente com o aplicativo em uso.'
            : 'Check-in/Check-out automáticos desativados.',
        StatusTone.warning,
      );
    } finally {
      _setState(_state.copyWith(isAutomaticCheckingUpdating: false));
    }
  }

  Future<void> setAutoCheckInEnabled(bool value) async {
    await setAutomaticCheckInOutEnabled(value);
  }

  Future<void> setAutoCheckOutEnabled(bool value) async {
    await setAutomaticCheckInOutEnabled(value);
  }

  Future<void> refreshLocationSharingAvailability({
    bool interactive = false,
    bool updateStatus = false,
  }) async {
    await _refreshLocationSharingAvailability(
      interactive: interactive,
      updateStatus: updateStatus,
    );
  }

  Future<void> refreshAfterEnteringForeground() async {
    if (_foregroundRefreshInProgress) {
      return;
    }

    _foregroundRefreshInProgress = true;
    _hasHydratedHistoryForCurrentKey = false;
    _setState(
      _state.copyWith(
        lastMatchedLocation: null,
        lastDetectedLocation: null,
        lastLocationUpdateAt: null,
        lastCheckInLocation: null,
        lastCheckIn: null,
        lastCheckOut: null,
        statusMessage: 'Atualização em andamento. Aguarde.',
        statusTone: StatusTone.warning,
        isLoading: false,
      ),
    );

    try {
      if (_state.locationSharingEnabled) {
        await _stopLocationTracking();
      }

      await _refreshLocationSharingAvailability(
        interactive: false,
        updateStatus: false,
      );

      if (!_state.hasValidChave || !_state.hasApiConfig) {
        _stopHistoryAutoRefresh();
        _clearHistoryFields(updateStatus: true);
        return;
      }

      try {
        await syncHistory(silent: false, updateStatus: false);
      } catch (error) {
        final message = error is CheckingApiException
            ? error.message
            : 'Falha ao consultar a API.';
        _setStatus(message, StatusTone.error);
        return;
      }
      _restartHistoryAutoRefresh();

      if (!_state.locationSharingEnabled) {
        _setState(
          _state.copyWith(
            lastMatchedLocation: null,
            lastDetectedLocation: null,
            lastLocationUpdateAt: null,
          ),
        );
        _setStatus('Atividades atualizadas.', StatusTone.success);
        return;
      }

      await refreshLocationUpdateInterval(
        restartLocationTrackingIfNeeded: false,
      );
      await refreshLocationsCatalog(silent: true, updateStatus: false);
      await _captureCurrentPositionNow();
      await _restartLocationTracking(captureImmediately: false);
      _setStatus('Atividades e localização atualizadas.', StatusTone.success);
    } finally {
      _foregroundRefreshInProgress = false;
    }
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
      _hasHydratedHistoryForCurrentKey = true;
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
      final nextState = _resolveLocationUpdateIntervalState(
        _state.copyWith(
          locationAccuracyThresholdMeters:
              response.locationAccuracyThresholdMeters,
        ),
      );
      final isTrackingActive = await _isLocationTrackingActive();
      final shouldRestartLocationTracking =
          _state.locationSharingEnabled &&
          isTrackingActive &&
          _state.locationUpdateIntervalSeconds !=
              nextState.locationUpdateIntervalSeconds;
      _managedLocations = response.items;
      _updateAndPersist(nextState, syncAutomation: false);
      _restartLocationUpdateIntervalBoundaryTimer();
      if (shouldRestartLocationTracking) {
        await _restartLocationTracking();
      } else if (_state.locationSharingEnabled) {
        unawaited(_refreshBackgroundLocationService());
      }
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

  Future<void> refreshLocationUpdateInterval({
    bool restartLocationTrackingIfNeeded = true,
  }) async {
    final previousIntervalSeconds = _state.locationUpdateIntervalSeconds;
    final nextState = _resolveLocationUpdateIntervalState(_state);
    final intervalChanged =
        nextState.locationUpdateIntervalSeconds != previousIntervalSeconds;

    if (intervalChanged) {
      _updateAndPersist(nextState, syncAutomation: false);
    }
    _restartLocationUpdateIntervalBoundaryTimer();

    final isTrackingActive = await _isLocationTrackingActive();
    if (intervalChanged &&
        restartLocationTrackingIfNeeded &&
        _state.locationSharingEnabled &&
        isTrackingActive) {
      await _restartLocationTracking();
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
      final informe = resolveInformeForSubmission(
        state: _state,
        registro: registro,
        source: source,
      );
      final response = await _apiService.submitEvent(
        baseUrl: _state.apiBaseUrl,
        sharedKey: _state.apiSharedKey,
        chave: _state.chave,
        projeto: _state.projetoFor(registro).apiValue,
        action: registro.apiValue,
        informe: informe.name,
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
      if (shouldRefreshLocationTrackingAfterSubmit(state: _state)) {
        unawaited(_refreshBackgroundLocationService());
      }
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

  @visibleForTesting
  static InformeType resolveInformeForSubmission({
    required CheckingState state,
    required RegistroType registro,
    required String source,
  }) {
    if (source == 'location-automation') {
      return InformeType.normal;
    }
    return state.informeFor(registro);
  }

  @visibleForTesting
  static bool shouldRefreshLocationTrackingAfterSubmit({
    required CheckingState state,
  }) {
    return state.locationSharingEnabled && state.hasAnyLocationAutomation;
  }

  @visibleForTesting
  static String? resolveCapturedLocationLabel({
    ManagedLocation? location,
    double? nearestWorkplaceDistanceMeters,
  }) {
    return CheckingLocationLogic.resolveCapturedLocationLabel(
      location: location,
      nearestWorkplaceDistanceMeters: nearestWorkplaceDistanceMeters,
    );
  }

  static bool isLocationSharingToggleInteractive({
    required CheckingState state,
  }) {
    return (state.locationSharingEnabled || state.canEnableLocationSharing) &&
        !state.isLocationUpdating &&
        !state.isAutomaticCheckingUpdating;
  }

  @visibleForTesting
  static bool shouldRunBackgroundLocationService({
    required CheckingState state,
    required bool backgroundServiceSupported,
  }) {
    return backgroundServiceSupported &&
        CheckingBackgroundLocationService.shouldRunForState(state);
  }

  @visibleForTesting
  static bool shouldRunForegroundLocationStream({
    required CheckingState state,
    required bool backgroundServiceSupported,
  }) {
    return state.locationSharingEnabled &&
        !shouldRunBackgroundLocationService(
          state: state,
          backgroundServiceSupported: backgroundServiceSupported,
        );
  }

  @visibleForTesting
  static bool resolveControlFlagAfterSnapshot({
    required bool currentValue,
    required bool snapshotLocationSharingEnabled,
  }) {
    return snapshotLocationSharingEnabled ? currentValue : false;
  }

  static bool isAutomaticCheckingEnabledInUi({required CheckingState state}) {
    return state.locationSharingEnabled && state.automaticCheckInOutEnabled;
  }

  static bool isAutomaticCheckingToggleInteractive({
    required CheckingState state,
  }) {
    return state.locationSharingEnabled &&
        !state.isLocationUpdating &&
        !state.isAutomaticCheckingUpdating;
  }

  @visibleForTesting
  static int resolveLocationUpdateIntervalSeconds({DateTime? referenceTime}) {
    return CheckingLocationLogic.resolveLocationUpdateIntervalSeconds(
      referenceTime: referenceTime,
    );
  }

  static String describeLocationUpdateInterval({DateTime? referenceTime}) {
    return CheckingLocationLogic.describeLocationUpdateInterval(
      referenceTime: referenceTime,
    );
  }

  CheckingState _resolveLocationUpdateIntervalState(
    CheckingState state, {
    DateTime? referenceTime,
  }) {
    return CheckingLocationLogic.resolveLocationUpdateIntervalState(
      state,
      referenceTime: referenceTime,
    );
  }

  Duration _delayUntilNextLocationUpdateIntervalBoundary({
    DateTime? referenceTime,
  }) {
    return CheckingLocationLogic.delayUntilNextLocationUpdateIntervalBoundary(
      referenceTime: referenceTime,
    );
  }

  Future<void> _runInitialAndroidSetupIfNeeded() async {
    if (!_androidBridge.isSupported) {
      _setState(_state.copyWith(canEnableLocationSharing: true));
      return;
    }

    if (await _storageService.hasPromptedInitialAndroidSetup()) {
      return;
    }

    await _refreshLocationSharingAvailability(
      interactive: true,
      updateStatus: true,
    );
    await _storageService.markInitialAndroidSetupPrompted();
  }

  Future<void> _refreshLocationSharingAvailability({
    required bool interactive,
    required bool updateStatus,
  }) async {
    if (!_androidBridge.isSupported) {
      _setState(_state.copyWith(canEnableLocationSharing: true));
      return;
    }

    final permissionResult = await _ensureLocationPermissionGranted(
      interactive: interactive,
    );
    final backgroundStartResult =
        await CheckingBackgroundLocationService.ensureReadyForStart(
          interactive: interactive,
        );
    final canEnableLocationSharing =
        permissionResult.granted && backgroundStartResult.ready;
    final oemSetupResult = interactive && canEnableLocationSharing
        ? await _androidBridge.requestOemBackgroundSetup()
        : CheckingOemBackgroundSetupResult.empty;

    var nextState = _state.copyWith(
      canEnableLocationSharing: canEnableLocationSharing,
      isLocationUpdating: false,
    );
    if (!canEnableLocationSharing && _state.locationSharingEnabled) {
      await _stopLocationTracking();
      nextState = nextState.copyWith(
        locationSharingEnabled: false,
        lastMatchedLocation: null,
      );
      _updateAndPersist(nextState, syncAutomation: false);
      await flushStatePersistence();
    } else {
      _setState(nextState);
    }

    if (!updateStatus) {
      return;
    }

    final statusSegments = <String>[
      if (!permissionResult.granted && permissionResult.message.isNotEmpty)
        permissionResult.message
      else if (!backgroundStartResult.ready &&
          backgroundStartResult.blockingMessage.isNotEmpty)
        backgroundStartResult.blockingMessage
      else if (backgroundStartResult.warningMessage.isEmpty &&
          oemSetupResult.message.isEmpty)
        'Configuração inicial do Android concluída.',
      if (backgroundStartResult.warningMessage.isNotEmpty)
        backgroundStartResult.warningMessage,
      if (oemSetupResult.message.isNotEmpty) oemSetupResult.message,
    ];

    if (statusSegments.isEmpty) {
      return;
    }

    _setStatus(
      statusSegments.join(' '),
      !canEnableLocationSharing
          ? StatusTone.error
          : (backgroundStartResult.warningMessage.isNotEmpty ||
                oemSetupResult.message.isNotEmpty)
          ? StatusTone.warning
          : StatusTone.success,
    );
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

  Future<void> _startLocationTracking({bool captureImmediately = true}) async {
    if (_shouldRunBackgroundLocationService(_state)) {
      _stopLocationCaptureTimer();
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      await _refreshBackgroundLocationService();
      return;
    }

    if (CheckingBackgroundLocationService.isSupported) {
      await CheckingBackgroundLocationService.stop();
    }

    if (_positionSubscription != null) {
      return;
    }

    await refreshLocationUpdateInterval(restartLocationTrackingIfNeeded: false);
    _restartLocationCaptureTimer();
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

    if (captureImmediately) {
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
  }

  Future<void> _refreshLocationTrackingNow() async {
    if (!_state.locationSharingEnabled) {
      return;
    }

    await _captureCurrentPositionNow();

    if (_shouldRunBackgroundLocationService(_state)) {
      _stopLocationCaptureTimer();
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      await _refreshBackgroundLocationService();
      return;
    }

    if (CheckingBackgroundLocationService.isSupported) {
      await CheckingBackgroundLocationService.stop();
    }

    if (_positionSubscription == null) {
      await _startLocationTracking();
    }
  }

  Future<void> _captureCurrentPositionNow() async {
    if (!_state.locationSharingEnabled) {
      return;
    }

    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      await _handlePositionUpdate(currentPosition);
    } catch (_) {
      // O stream ou o serviço em segundo plano continuam tentando as próximas leituras.
    }
  }

  Future<void> _stopLocationTracking() async {
    _stopLocationCaptureTimer();
    if (CheckingBackgroundLocationService.isSupported) {
      await CheckingBackgroundLocationService.stop();
    }
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _restartLocationTracking({
    bool captureImmediately = true,
  }) async {
    await _stopLocationTracking();
    await _startLocationTracking(captureImmediately: captureImmediately);
  }

  void _restartLocationCaptureTimer() {
    _stopLocationCaptureTimer();
    if (!_state.locationSharingEnabled ||
        _shouldRunBackgroundLocationService(_state)) {
      return;
    }

    _locationCaptureTimer = Timer.periodic(
      Duration(seconds: max(1, _state.locationUpdateIntervalSeconds)),
      (_) => unawaited(_captureCurrentPositionNow()),
    );
  }

  void _stopLocationCaptureTimer() {
    _locationCaptureTimer?.cancel();
    _locationCaptureTimer = null;
  }

  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: Duration(
          seconds: max(1, _state.locationUpdateIntervalSeconds),
        ),
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
    if (!isLocationAccuracyPreciseEnough(
      position.accuracy,
      maxAccuracyMeters: _state.locationAccuracyThresholdMeters.toDouble(),
    )) {
      return;
    }

    final positionTimestamp = _resolvePositionTimestamp(position);
    if (CheckingLocationLogic.shouldSkipDuplicateLocationFetch(
      history: _state.locationFetchHistory,
      timestamp: positionTimestamp,
      latitude: position.latitude,
      longitude: position.longitude,
    )) {
      return;
    }

    _processingLocationUpdate = true;
    try {
      final matchResult = _resolveLocationMatch(position);
      final matchedLocation = matchResult.matchedLocation;
      final matchedAreaLabel = matchedLocation?.automationAreaLabel;
      final locationFetchHistory =
          CheckingLocationLogic.recordLocationFetchHistory(
            history: _state.locationFetchHistory,
            timestamp: positionTimestamp,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      final capturedLocationLabel = resolveCapturedLocationLabel(
        location: matchedLocation,
        nearestWorkplaceDistanceMeters:
            matchResult.nearestWorkplaceDistanceMeters,
      );
      final nextState = matchedLocation == null
          ? _state.copyWith(
              lastMatchedLocation: null,
              lastDetectedLocation: capturedLocationLabel,
              lastLocationUpdateAt: positionTimestamp,
              locationFetchHistory: locationFetchHistory,
            )
          : _state.copyWith(
              lastMatchedLocation: matchedAreaLabel,
              lastDetectedLocation: capturedLocationLabel,
              lastLocationUpdateAt: positionTimestamp,
              locationFetchHistory: locationFetchHistory,
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

  Future<bool> _applyAutomationFromLastKnownLocationIfNeeded() async {
    if (!_state.locationSharingEnabled ||
        !_state.hasAnyLocationAutomation ||
        !_state.hasValidChave ||
        !_state.hasApiConfig ||
        _state.isSubmitting) {
      return false;
    }

    final location = resolveManagedLocationForLastCapture(
      managedLocations: _managedLocations,
      lastMatchedLocation: _state.lastMatchedLocation,
      lastDetectedLocation: _state.lastDetectedLocation,
    );
    if (location == null) {
      return false;
    }

    if (!shouldAttemptAutomaticLocationEvent(
      location: location,
      lastRecordedAction: _state.lastRecordedAction,
      lastCheckInLocation: _state.lastCheckInLocation,
      autoCheckInEnabled: _state.autoCheckInEnabled,
      autoCheckOutEnabled: _state.autoCheckOutEnabled,
    )) {
      return false;
    }

    await _submitAutomaticLocationEvent(location);
    return true;
  }

  _LocationMatchResult _resolveLocationMatch(Position position) {
    final matchResult = CheckingLocationLogic.resolveLocationMatch(
      managedLocations: _managedLocations,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    return _LocationMatchResult(
      matchedLocation: matchResult.matchedLocation,
      nearestWorkplaceDistanceMeters:
          matchResult.nearestWorkplaceDistanceMeters,
    );
  }

  @visibleForTesting
  static double resolveDistanceToLocation({
    required ManagedLocation location,
    required double latitude,
    required double longitude,
  }) {
    return CheckingLocationLogic.resolveDistanceToLocation(
      location: location,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @visibleForTesting
  static ManagedLocation? resolveManagedLocationForLastCapture({
    required List<ManagedLocation> managedLocations,
    required String? lastMatchedLocation,
    required String? lastDetectedLocation,
  }) {
    final normalizedDetectedLocation = _normalizeLocationLookup(
      lastDetectedLocation,
    );
    if (normalizedDetectedLocation != null) {
      for (final location in managedLocations) {
        if (_normalizeLocationLookup(location.local) ==
            normalizedDetectedLocation) {
          return location;
        }
      }
    }

    final normalizedMatchedLocation = _normalizeLocationLookup(
      lastMatchedLocation,
    );
    if (normalizedMatchedLocation == null) {
      return null;
    }

    for (final location in managedLocations) {
      if (_normalizeLocationLookup(location.automationAreaLabel) ==
              normalizedMatchedLocation ||
          _normalizeLocationLookup(location.local) ==
              normalizedMatchedLocation) {
        return location;
      }
    }

    return null;
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
    return CheckingLocationLogic.resolveAutomaticActionForLocation(
      remoteState: remoteState,
      location: location,
      autoCheckInEnabled: autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled,
      lastCheckInLocation: lastCheckInLocation,
    );
  }

  @visibleForTesting
  static bool shouldAttemptAutomaticLocationEvent({
    required ManagedLocation location,
    required RegistroType? lastRecordedAction,
    required String? lastCheckInLocation,
    required bool autoCheckInEnabled,
    required bool autoCheckOutEnabled,
  }) {
    return CheckingLocationLogic.shouldAttemptAutomaticLocationEvent(
      location: location,
      lastRecordedAction: lastRecordedAction,
      lastCheckInLocation: lastCheckInLocation,
      autoCheckInEnabled: autoCheckInEnabled,
      autoCheckOutEnabled: autoCheckOutEnabled,
    );
  }

  @visibleForTesting
  static RegistroType? resolveAutomaticActionOutOfRange({
    required MobileStateResponse remoteState,
    required double? nearestDistanceMeters,
    required bool autoCheckOutEnabled,
  }) {
    return CheckingLocationLogic.resolveAutomaticActionOutOfRange(
      remoteState: remoteState,
      nearestDistanceMeters: nearestDistanceMeters,
      autoCheckOutEnabled: autoCheckOutEnabled,
    );
  }

  @visibleForTesting
  static bool shouldAttemptAutomaticOutOfRangeCheckout({
    required RegistroType? lastRecordedAction,
    required double? nearestDistanceMeters,
    required bool autoCheckOutEnabled,
  }) {
    return CheckingLocationLogic.shouldAttemptAutomaticOutOfRangeCheckout(
      lastRecordedAction: lastRecordedAction,
      nearestDistanceMeters: nearestDistanceMeters,
      autoCheckOutEnabled: autoCheckOutEnabled,
    );
  }

  @visibleForTesting
  static bool shouldApplyHistoryFromSnapshot({
    required bool hasHydratedHistoryForCurrentKey,
    required DateTime? snapshotLastCheckIn,
    required DateTime? snapshotLastCheckOut,
  }) {
    return hasHydratedHistoryForCurrentKey &&
        (snapshotLastCheckIn != null || snapshotLastCheckOut != null);
  }

  @visibleForTesting
  static String resolveAutomaticEventLocal({
    required RegistroType action,
    ManagedLocation? location,
  }) {
    return CheckingLocationLogic.resolveAutomaticEventLocal(
      action: action,
      location: location,
    );
  }

  static DateTime _resolvePositionTimestamp(Position position) {
    return CheckingLocationLogic.resolvePositionTimestamp(position);
  }

  @visibleForTesting
  static bool isLocationAccuracyPreciseEnough(
    double? accuracyMeters, {
    double maxAccuracyMeters = defaultLocationAccuracyThresholdMeters,
  }) {
    return CheckingLocationLogic.isLocationAccuracyPreciseEnough(
      accuracyMeters,
      maxAccuracyMeters: maxAccuracyMeters,
    );
  }

  Future<_LocationPermissionResult> _ensureLocationPermissionGranted({
    required bool interactive,
  }) async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && interactive) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    }
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

    var accuracyStatus = await Geolocator.getLocationAccuracy();
    if (accuracyStatus == LocationAccuracyStatus.reduced && interactive) {
      await openAppSettings();
      accuracyStatus = await Geolocator.getLocationAccuracy();
    }
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
    _updateAndPersist(
      CheckingLocationLogic.applyRemoteState(
        currentState: _state,
        response: response,
        statusMessage: statusMessage,
        tone: tone,
        updateStatus: updateStatus,
        recentAction: recentAction,
        recentLocal: recentLocal,
      ),
    );
  }

  void _clearHistoryFields({required bool updateStatus}) {
    _hasHydratedHistoryForCurrentKey = false;
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
          _state.isSubmitting ||
          _foregroundRefreshInProgress ||
          _state.isSyncing) {
        return;
      }
      unawaited(syncHistory(silent: true, updateStatus: false));
    });
  }

  void _stopHistoryAutoRefresh() {
    _historyRefreshTimer?.cancel();
    _historyRefreshTimer = null;
  }

  void _restartLocationUpdateIntervalBoundaryTimer() {
    _stopLocationUpdateIntervalBoundaryTimer();
    _locationUpdateIntervalTimer = Timer(
      _delayUntilNextLocationUpdateIntervalBoundary(),
      () {
        unawaited(refreshLocationUpdateInterval());
      },
    );
  }

  void _stopLocationUpdateIntervalBoundaryTimer() {
    _locationUpdateIntervalTimer?.cancel();
    _locationUpdateIntervalTimer = null;
  }

  Future<bool> _isLocationTrackingActive() async {
    final hasForegroundStream = _positionSubscription != null;
    if (CheckingBackgroundLocationService.isSupported) {
      return hasForegroundStream ||
          await CheckingBackgroundLocationService.isRunning();
    }
    return hasForegroundStream;
  }

  Future<void> _refreshBackgroundLocationService() async {
    if (!CheckingBackgroundLocationService.isSupported) {
      return;
    }

    if (!_shouldRunBackgroundLocationService(_state)) {
      await CheckingBackgroundLocationService.stop();
      return;
    }

    final permissionResult = await _ensureLocationPermissionGranted(
      interactive: false,
    );
    if (!permissionResult.granted) {
      await CheckingBackgroundLocationService.stop();
      return;
    }

    final readiness =
        await CheckingBackgroundLocationService.ensureReadyForStart(
          interactive: false,
        );
    if (!readiness.ready) {
      await CheckingBackgroundLocationService.stop();
      return;
    }

    await flushStatePersistence();
    await CheckingBackgroundLocationService.start();
    await CheckingBackgroundLocationService.requestRefresh();
  }

  bool _shouldRunBackgroundLocationService(CheckingState state) {
    return shouldRunBackgroundLocationService(
      state: state,
      backgroundServiceSupported: CheckingBackgroundLocationService.isSupported,
    );
  }

  void _handleBackgroundLocationSnapshot(
    CheckingBackgroundLocationSnapshot snapshot,
  ) {
    if (_foregroundRefreshInProgress) {
      return;
    }

    if (snapshot.chave != _state.chave) {
      return;
    }

    final nextLocationSharingEnabled = resolveControlFlagAfterSnapshot(
      currentValue: _state.locationSharingEnabled,
      snapshotLocationSharingEnabled: snapshot.locationSharingEnabled,
    );
    final shouldApplySnapshotHistory = shouldApplyHistoryFromSnapshot(
      hasHydratedHistoryForCurrentKey: _hasHydratedHistoryForCurrentKey,
      snapshotLastCheckIn: snapshot.lastCheckIn,
      snapshotLastCheckOut: snapshot.lastCheckOut,
    );
    final hasStatusUpdate = snapshot.statusMessage.isNotEmpty;
    _setState(
      _state.copyWith(
        registro: snapshot.registro,
        checkInProjeto: snapshot.checkInProjeto,
        locationSharingEnabled: nextLocationSharingEnabled,
        autoCheckInEnabled: resolveControlFlagAfterSnapshot(
          currentValue: _state.autoCheckInEnabled,
          snapshotLocationSharingEnabled: snapshot.locationSharingEnabled,
        ),
        autoCheckOutEnabled: resolveControlFlagAfterSnapshot(
          currentValue: _state.autoCheckOutEnabled,
          snapshotLocationSharingEnabled: snapshot.locationSharingEnabled,
        ),
        locationUpdateIntervalSeconds: snapshot.locationUpdateIntervalSeconds,
        locationAccuracyThresholdMeters:
            snapshot.locationAccuracyThresholdMeters,
        lastMatchedLocation: snapshot.lastMatchedLocation,
        lastDetectedLocation: snapshot.lastDetectedLocation,
        lastLocationUpdateAt: snapshot.lastLocationUpdateAt,
        locationFetchHistory: snapshot.locationFetchHistory,
        lastCheckInLocation: shouldApplySnapshotHistory
            ? snapshot.lastCheckInLocation
            : _state.lastCheckInLocation,
        lastCheckIn: shouldApplySnapshotHistory
            ? snapshot.lastCheckIn
            : _state.lastCheckIn,
        lastCheckOut: shouldApplySnapshotHistory
            ? snapshot.lastCheckOut
            : _state.lastCheckOut,
        statusMessage: hasStatusUpdate
            ? snapshot.statusMessage
            : _state.statusMessage,
        statusTone: hasStatusUpdate ? snapshot.statusTone : _state.statusTone,
        isLocationUpdating: false,
      ),
    );
  }

  String _buildClientEventId({required String prefix}) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '$prefix-$now-$randomPart';
  }

  static String? _normalizeLocationLookup(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
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
    _stopLocationUpdateIntervalBoundaryTimer();
    _stopLocationCaptureTimer();
    if (CheckingBackgroundLocationService.isSupported) {
      CheckingBackgroundLocationService.removeListener(
        _backgroundLocationListener,
      );
    }
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
