import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:checking/src/core/theme/app_theme.dart';
import 'package:checking/src/features/checking/controller/checking_controller.dart';
import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:checking/src/features/checking/services/checking_android_bridge.dart';
import 'package:checking/src/features/checking/services/checking_background_service.dart';
import 'package:checking/src/features/checking/services/checking_location_logic.dart';
import 'package:checking/src/features/checking/services/checking_services.dart';
import 'package:checking/src/features/checking/services/location_catalog_service.dart';
import 'package:checking/src/features/checking/view/checking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('builds checking theme', () {
    final theme = AppTheme.build();

    expect(theme.colorScheme.primary, const Color(0xFF007AFF));
  });

  test('suggests check-out when last check-in is newer', () {
    final registro = CheckingState.inferSuggestedRegistro(
      lastCheckIn: DateTime(2026, 4, 9, 8),
      lastCheckOut: DateTime(2026, 4, 8, 18),
    );

    expect(registro, RegistroType.checkOut);
  });

  test('suggests check-in when last check-out is newer', () {
    final registro = CheckingState.inferSuggestedRegistro(
      lastCheckIn: DateTime(2026, 4, 8, 8),
      lastCheckOut: DateTime(2026, 4, 9, 18),
    );

    expect(registro, RegistroType.checkIn);
  });

  test('preserves persisted keys including HR70', () {
    expect(CheckingState.sanitizeChave('HR70'), 'HR70');
    expect(CheckingState.sanitizeChave('AB12'), 'AB12');

    final restored = CheckingState.fromJson({'chave': 'HR70'});

    expect(restored.chave, 'HR70');
  });

  test('restores separated location search and automatic check flags', () {
    final restored = CheckingState.fromJson({
      'chave': 'AB12',
      'locationSharingEnabled': true,
      'autoCheckInEnabled': false,
      'autoCheckOutEnabled': false,
    });

    expect(restored.locationSharingEnabled, isTrue);
    expect(restored.autoCheckInEnabled, isFalse);
    expect(restored.autoCheckOutEnabled, isFalse);
    expect(restored.automaticCheckInOutEnabled, isFalse);
  });

  test('restores configurable schedule settings', () {
    final restored = CheckingState.fromJson({
      'locationUpdateIntervalSeconds': 45 * 60,
      'nightUpdatesDisabled': true,
      'nightPeriodStartMinutes': 23 * 60,
      'nightPeriodEndMinutes': 5 * 60,
      'oemBackgroundSetupEnabled': true,
    });

    expect(restored.locationUpdateIntervalSeconds, 45 * 60);
    expect(restored.nightUpdatesDisabled, isTrue);
    expect(restored.nightPeriodStartMinutes, 23 * 60);
    expect(restored.nightPeriodEndMinutes, 5 * 60);
    expect(restored.oemBackgroundSetupEnabled, isTrue);
  });

  test('keeps legacy automation behavior when split flags are absent', () {
    final restored = CheckingState.fromJson({
      'chave': 'AB12',
      'locationSharingEnabled': true,
    });

    expect(restored.locationSharingEnabled, isTrue);
    expect(restored.autoCheckInEnabled, isTrue);
    expect(restored.autoCheckOutEnabled, isTrue);
    expect(restored.automaticCheckInOutEnabled, isTrue);
  });

  test('forces automatic check flags off when location search is off', () {
    final restored = CheckingState.fromJson({
      'chave': 'AB12',
      'locationSharingEnabled': false,
      'autoCheckInEnabled': true,
      'autoCheckOutEnabled': true,
    });

    expect(restored.locationSharingEnabled, isFalse);
    expect(restored.autoCheckInEnabled, isFalse);
    expect(restored.autoCheckOutEnabled, isFalse);
    expect(restored.automaticCheckInOutEnabled, isFalse);
  });

  test(
    'location sharing toggle stays disabled until Android setup is ready',
    () {
      final blockedState = CheckingState.initial().copyWith(
        canEnableLocationSharing: false,
        locationSharingEnabled: false,
      );
      final enabledState = blockedState.copyWith(
        canEnableLocationSharing: true,
      );
      final alreadyEnabledState = blockedState.copyWith(
        locationSharingEnabled: true,
      );

      expect(
        CheckingController.isLocationSharingToggleInteractive(
          state: blockedState,
        ),
        isFalse,
      );
      expect(
        CheckingController.isLocationSharingToggleInteractive(
          state: enabledState,
        ),
        isTrue,
      );
      expect(
        CheckingController.isLocationSharingToggleInteractive(
          state: alreadyEnabledState,
        ),
        isTrue,
      );
    },
  );

  test('does not persist last check-in and last check-out timestamps', () {
    final state = CheckingState.initial().copyWith(
      lastDetectedLocation: 'Portaria Principal',
      lastLocationUpdateAt: DateTime.utc(2026, 4, 10, 7, 45, 30),
      locationFetchHistory: <LocationFetchEntry>[
        LocationFetchEntry(
          timestamp: DateTime.utc(2026, 4, 10, 7, 45, 30),
          latitude: 1.249494,
          longitude: 103.614345,
        ),
        LocationFetchEntry(
          timestamp: DateTime.utc(2026, 4, 10, 7, 30, 0),
          latitude: 1.25129,
          longitude: 103.613386,
        ),
      ],
      lastCheckInLocation: 'Escritório Principal',
      lastCheckIn: DateTime(2026, 4, 9, 8),
      lastCheckOut: DateTime(2026, 4, 9, 18),
    );

    final json = state.toJson();

    expect(json.containsKey('lastCheckIn'), isFalse);
    expect(json.containsKey('lastCheckOut'), isFalse);
    expect(json['lastDetectedLocation'], 'Portaria Principal');
    expect(json['lastLocationUpdateAt'], '2026-04-10T07:45:30.000Z');
    expect(json['locationFetchHistory'], <Map<String, Object?>>[
      <String, Object?>{
        'timestamp': '2026-04-10T07:45:30.000Z',
        'latitude': 1.249494,
        'longitude': 103.614345,
      },
      <String, Object?>{
        'timestamp': '2026-04-10T07:30:00.000Z',
        'latitude': 1.25129,
        'longitude': 103.613386,
      },
    ]);
    expect(json['lastCheckInLocation'], 'Escritório Principal');
  });

  test('restores persisted location fetch history', () {
    final restored = CheckingState.fromJson({
      'chave': 'AB12',
      'locationFetchHistory': <Map<String, Object?>>[
        <String, Object?>{
          'timestamp': '2026-04-10T07:45:30.000Z',
          'latitude': 1.249494,
          'longitude': 103.614345,
        },
        <String, Object?>{
          'timestamp': '2026-04-10T07:30:00.000Z',
          'latitude': 1.25129,
          'longitude': 103.613386,
        },
      ],
    });

    expect(restored.locationFetchHistory, hasLength(2));
    expect(
      restored.locationFetchHistory.first.timestamp.toUtc().toIso8601String(),
      '2026-04-10T07:45:30.000Z',
    );
    expect(restored.locationFetchHistory.first.latitude, 1.249494);
    expect(restored.locationFetchHistory.first.longitude, 103.614345);
  });

  test(
    'falls back to the prefs backup when secure storage read fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'checking_flutter_state_v1': jsonEncode(const <String, Object?>{}),
        'checking_flutter_api_shared_key_backup_v1': 'prefs-backup-key',
      });

      final storageService = CheckingStorageService(
        secureRead: (_) async => throw Exception('secure read failed'),
      );

      final restored = await storageService.loadState();

      expect(restored.apiSharedKey, 'prefs-backup-key');
    },
  );

  test(
    'mirrors the secure storage key into the prefs backup on load',
    () async {
      SharedPreferences.setMockInitialValues({});

      final storageService = CheckingStorageService(
        secureRead: (_) async => 'secure-storage-key',
      );

      final restored = await storageService.loadState();
      final prefs = await SharedPreferences.getInstance();

      expect(restored.apiSharedKey, 'secure-storage-key');
      expect(
        prefs.getString('checking_flutter_api_shared_key_backup_v1'),
        'secure-storage-key',
      );
    },
  );

  test(
    'background-safe storage loads prefs backup without touching secure storage',
    () async {
      SharedPreferences.setMockInitialValues({
        'checking_flutter_api_shared_key_backup_v1': 'prefs-backup-key',
      });
      var secureReadCalled = false;

      final storageService = CheckingStorageService.backgroundSafe(
        secureRead: (_) async {
          secureReadCalled = true;
          return 'secure-storage-key';
        },
      );

      final restored = await storageService.loadState();

      expect(restored.apiSharedKey, 'prefs-backup-key');
      expect(secureReadCalled, isFalse);
    },
  );

  test(
    'falls back to the initial state when persisted json is malformed',
    () async {
      SharedPreferences.setMockInitialValues({
        'checking_flutter_state_v1': '{invalid-json',
        'checking_flutter_api_shared_key_backup_v1': 'prefs-backup-key',
      });

      final storageService = const CheckingStorageService();
      final restored = await storageService.loadState();

      expect(restored.chave, isEmpty);
      expect(restored.locationSharingEnabled, isFalse);
      expect(restored.apiSharedKey, 'prefs-backup-key');
    },
  );

  test('keeps the prefs backup when secure storage write fails', () async {
    SharedPreferences.setMockInitialValues({});

    final storageService = CheckingStorageService(
      secureWrite: (unusedKey, unusedValue) async =>
          throw Exception('secure write failed'),
    );

    await storageService.saveState(
      CheckingState.initial().copyWith(apiSharedKey: 'persisted-mobile-key'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('checking_flutter_api_shared_key_backup_v1'),
      'persisted-mobile-key',
    );
  });

  test(
    'background-safe storage writes prefs backup without touching secure storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      var secureWriteCalled = false;
      var secureDeleteCalled = false;

      final storageService = CheckingStorageService.backgroundSafe(
        secureWrite: (unusedKey, unusedValue) async {
          secureWriteCalled = true;
        },
        secureDelete: (unusedKey) async {
          secureDeleteCalled = true;
        },
      );

      await storageService.saveState(
        CheckingState.initial().copyWith(apiSharedKey: 'persisted-mobile-key'),
      );

      var prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('checking_flutter_api_shared_key_backup_v1'),
        'persisted-mobile-key',
      );
      expect(secureWriteCalled, isFalse);

      await storageService.saveState(
        CheckingState.initial().copyWith(apiSharedKey: ''),
      );

      prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('checking_flutter_api_shared_key_backup_v1'),
        isNull,
      );
      expect(secureDeleteCalled, isFalse);
    },
  );

  test(
    'deduplicates persisted location fetch history for the same gps fix',
    () {
      final restored = CheckingState.fromJson({
        'chave': 'AB12',
        'locationFetchHistory': <Map<String, Object?>>[
          <String, Object?>{
            'timestamp': '2026-04-10T07:45:30.100Z',
            'latitude': 1.249494,
            'longitude': 103.614345,
          },
          <String, Object?>{
            'timestamp': '2026-04-10T07:45:30.800Z',
            'latitude': 1.249494,
            'longitude': 103.614345,
          },
          <String, Object?>{
            'timestamp': '2026-04-10T07:30:00.000Z',
            'latitude': 1.25129,
            'longitude': 103.613386,
          },
        ],
      });

      expect(restored.locationFetchHistory, hasLength(2));
      expect(
        restored.locationFetchHistory.first.timestamp.toUtc().toIso8601String(),
        '2026-04-10T07:45:30.100Z',
      );
    },
  );

  test(
    'restores legacy persisted location fetch history without coordinates',
    () {
      final restored = CheckingState.fromJson({
        'chave': 'AB12',
        'locationFetchHistory': <String>['2026-04-10T07:45:30.000Z'],
      });

      expect(restored.locationFetchHistory, hasLength(1));
      expect(restored.locationFetchHistory.first.latitude, isNull);
      expect(restored.locationFetchHistory.first.longitude, isNull);
    },
  );

  test(
    'ignores previously persisted last check-in and last check-out values',
    () {
      final restored = CheckingState.fromJson({
        'chave': 'AB12',
        'registro': 'checkIn',
        'lastCheckIn': '2026-04-09T08:00:00Z',
        'lastCheckOut': '2026-04-09T18:00:00Z',
      });

      expect(restored.lastCheckIn, isNull);
      expect(restored.lastCheckOut, isNull);
    },
  );

  test('resolves the last recorded action from history timestamps', () {
    final fromCheckIn = CheckingState.initial().copyWith(
      lastCheckIn: DateTime(2026, 4, 10, 8),
      lastCheckOut: DateTime(2026, 4, 9, 18),
    );
    final fromCheckOut = CheckingState.initial().copyWith(
      lastCheckIn: DateTime(2026, 4, 9, 8),
      lastCheckOut: DateTime(2026, 4, 10, 18),
    );

    expect(fromCheckIn.lastRecordedAction, RegistroType.checkIn);
    expect(fromCheckOut.lastRecordedAction, RegistroType.checkOut);
  });

  test('background snapshot history only applies when timestamps exist', () {
    expect(
      CheckingController.shouldApplyHistoryFromSnapshot(
        hasHydratedHistoryForCurrentKey: true,
        snapshotLastCheckIn: null,
        snapshotLastCheckOut: null,
      ),
      isFalse,
    );

    expect(
      CheckingController.shouldApplyHistoryFromSnapshot(
        hasHydratedHistoryForCurrentKey: true,
        snapshotLastCheckIn: DateTime(2026, 4, 15, 6),
        snapshotLastCheckOut: null,
      ),
      isTrue,
    );
  });

  test('identifies checkout zone locations by configured names', () {
    final singleCheckoutLocation = ManagedLocation(
      id: 1,
      local: 'Zona de CheckOut',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );
    final numberedCheckoutLocation = ManagedLocation(
      id: 2,
      local: 'Zona de CheckOut 3',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );
    final regularLocation = ManagedLocation(
      id: 3,
      local: 'Base P80',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );

    expect(singleCheckoutLocation.isCheckoutZone, isTrue);
    expect(numberedCheckoutLocation.isCheckoutZone, isTrue);
    expect(
      singleCheckoutLocation.automationAreaLabel,
      ManagedLocation.checkoutZoneLabel,
    );
    expect(regularLocation.isCheckoutZone, isFalse);
    expect(regularLocation.automationAreaLabel, 'Base P80');
  });

  test('only accepts precise enough location readings for automation', () {
    expect(CheckingController.isLocationAccuracyPreciseEnough(12), isTrue);
    expect(CheckingController.isLocationAccuracyPreciseEnough(30), isTrue);
    expect(CheckingController.isLocationAccuracyPreciseEnough(30.01), isFalse);
    expect(
      CheckingController.isLocationAccuracyPreciseEnough(
        45,
        maxAccuracyMeters: 45,
      ),
      isTrue,
    );
    expect(
      CheckingController.isLocationAccuracyPreciseEnough(
        45.01,
        maxAccuracyMeters: 45,
      ),
      isFalse,
    );
    expect(CheckingController.isLocationAccuracyPreciseEnough(null), isFalse);
  });

  test('parses multiple coordinates and resolves the nearest point', () {
    final location = ManagedLocation.fromApiJson({
      'id': 99,
      'local': 'Base P80',
      'latitude': 1.255936,
      'longitude': 103.611066,
      'coordinates': [
        {'latitude': 1.255936, 'longitude': 103.611066},
        {'latitude': 1.300000, 'longitude': 103.700000},
      ],
      'tolerance_meters': 150,
      'updated_at': '2026-04-11T08:00:00Z',
    });

    expect(location.coordinates, hasLength(2));
    expect(location.latitude, 1.255936);
    expect(location.longitude, 103.611066);

    final distanceNearSecondCoordinate =
        CheckingController.resolveDistanceToLocation(
          location: location,
          latitude: 1.300000,
          longitude: 103.700000,
        );

    expect(distanceNearSecondCoordinate, lessThan(1));
  });

  test(
    'resolves the last detected managed location for immediate automation',
    () {
      final checkoutLocation = ManagedLocation(
        id: 7,
        local: 'Zona de CheckOut 3',
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 15),
      );
      final regularLocation = ManagedLocation(
        id: 8,
        local: 'Base P80',
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 15),
      );

      final resolved = CheckingController.resolveManagedLocationForLastCapture(
        managedLocations: <ManagedLocation>[regularLocation, checkoutLocation],
        lastMatchedLocation: ManagedLocation.checkoutZoneLabel,
        lastDetectedLocation: 'Zona de CheckOut 3',
      );

      expect(resolved, same(checkoutLocation));
    },
  );

  test('falls back to the last matched area when needed', () {
    final regularLocation = ManagedLocation(
      id: 9,
      local: 'Base P82',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 15),
    );

    final resolved = CheckingController.resolveManagedLocationForLastCapture(
      managedLocations: <ManagedLocation>[regularLocation],
      lastMatchedLocation: 'Base P82',
      lastDetectedLocation: null,
    );

    expect(resolved, same(regularLocation));
  });

  test('parses location catalog settings from api response', () {
    final response = LocationCatalogResponse.fromJson({
      'items': const [],
      'synced_at': '2026-04-12T08:00:00Z',
      'location_accuracy_threshold_meters': 45,
    });

    expect(response.locationAccuracyThresholdMeters, 45);
    expect(response.items, isEmpty);
  });

  test('uses 15-minute location updates during the daytime window', () {
    expect(
      CheckingController.resolveLocationUpdateIntervalSeconds(
        referenceTime: DateTime.utc(2025, 1, 6, 0, 30),
      ),
      15 * 60,
    );
    expect(
      CheckingController.describeLocationUpdateInterval(
        referenceTime: DateTime.utc(2025, 1, 6, 0, 30),
      ),
      '15 min',
    );
  });

  test('suspends background activity inside the configured night period', () {
    final state = CheckingState.initial().copyWith(
      nightUpdatesDisabled: true,
      nightPeriodStartMinutes: 22 * 60,
      nightPeriodEndMinutes: 6 * 60,
    );

    expect(
      CheckingLocationLogic.shouldRunBackgroundActivityNow(
        state: state,
        referenceTime: DateTime(2026, 4, 20, 23, 30),
      ),
      isFalse,
    );
    expect(
      CheckingLocationLogic.shouldRunBackgroundActivityNow(
        state: state,
        referenceTime: DateTime(2026, 4, 20, 9, 0),
      ),
      isTrue,
    );
  });

  test('keeps background tracking active after task removal', () {
    expect(CheckingBackgroundLocationService.stopServiceOnTaskRemoval, isFalse);
    expect(CheckingBackgroundLocationService.allowAutomaticRestart, isTrue);

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:stopWithTask="false"'));
  });

  test(
    'falls back to the cached location catalog when the database is unavailable',
    () async {
      final cachedLocation = ManagedLocation(
        id: 1,
        local: 'Base P80',
        latitude: 1.255936,
        longitude: 103.611066,
        toleranceMeters: 150,
        updatedAt: DateTime(2026, 4, 11, 8),
      );

      SharedPreferences.setMockInitialValues({
        'checking_locations_catalog_cache_v1': jsonEncode(
          <Map<String, Object?>>[cachedLocation.toDatabase()],
        ),
      });

      final service = LocationCatalogService(
        databaseOpener: () async => throw Exception('database unavailable'),
      );

      final restored = await service.loadLocations(preferCache: true);

      expect(restored, hasLength(1));
      expect(restored.first.local, 'Base P80');
      expect(restored.first.latitude, 1.255936);
      expect(restored.first.longitude, 103.611066);
    },
  );

  test('background service only runs when automatic checks are enabled', () {
    final locationOnlyState = CheckingState.initial().copyWith(
      locationSharingEnabled: true,
      autoCheckInEnabled: false,
      autoCheckOutEnabled: false,
    );
    final automaticState = locationOnlyState.copyWith(
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
    );

    expect(
      CheckingBackgroundLocationService.shouldRunForState(locationOnlyState),
      isFalse,
    );
    expect(
      CheckingBackgroundLocationService.shouldRunForState(automaticState),
      isTrue,
    );
    expect(
      CheckingController.shouldRunBackgroundLocationService(
        state: locationOnlyState,
        backgroundServiceSupported: true,
      ),
      isFalse,
    );
    expect(
      CheckingController.shouldRunForegroundLocationStream(
        state: locationOnlyState,
        backgroundServiceSupported: true,
      ),
      isTrue,
    );
    expect(
      CheckingController.shouldRunBackgroundLocationService(
        state: automaticState,
        backgroundServiceSupported: true,
      ),
      isTrue,
    );
    expect(
      CheckingController.shouldRunForegroundLocationStream(
        state: automaticState,
        backgroundServiceSupported: true,
      ),
      isFalse,
    );
  });

  test(
    'background monitoring also depends on Android background and notification permissions',
    () {
      final automaticState = CheckingState.initial().copyWith(
        locationSharingEnabled: true,
        autoCheckInEnabled: true,
        autoCheckOutEnabled: true,
      );

      const readyPermissions = CheckingPermissionSettingsState(
        backgroundAccessEnabled: true,
        notificationsEnabled: true,
        batteryOptimizationIgnored: false,
        isRefreshing: false,
      );
      const missingNotificationPermission = CheckingPermissionSettingsState(
        backgroundAccessEnabled: true,
        notificationsEnabled: false,
        batteryOptimizationIgnored: true,
        isRefreshing: false,
      );

      expect(
        CheckingController.isConfiguredToKeepRunningInBackground(
          state: automaticState,
          permissionSettings: readyPermissions,
          backgroundServiceSupported: true,
        ),
        isTrue,
      );
      expect(
        CheckingController.isConfiguredToKeepRunningInBackground(
          state: automaticState,
          permissionSettings: missingNotificationPermission,
          backgroundServiceSupported: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'permission-backed switches turn off when Android prerequisites are no longer available',
    () {
      final currentState = CheckingState.initial().copyWith(
        canEnableLocationSharing: true,
        locationSharingEnabled: true,
        autoCheckInEnabled: true,
        autoCheckOutEnabled: true,
        oemBackgroundSetupEnabled: true,
        lastMatchedLocation: 'Base P80',
      );

      final reconciledState =
          CheckingController.reconcilePermissionBackedSwitches(
            state: currentState,
            canEnableLocationSharing: false,
          );

      expect(reconciledState.canEnableLocationSharing, isFalse);
      expect(reconciledState.locationSharingEnabled, isFalse);
      expect(reconciledState.oemBackgroundSetupEnabled, isFalse);
      expect(reconciledState.lastMatchedLocation, isNull);
      expect(reconciledState.autoCheckInEnabled, isTrue);
      expect(reconciledState.autoCheckOutEnabled, isTrue);
    },
  );

  test(
    'shows dedicated settings labels for permissions and general adjustments',
    () {
      final screenSource = File(
        'lib/src/features/checking/view/checking_screen.dart',
      ).readAsStringSync();

      expect(screenSource, contains("label: 'Compartilhar Localização:'"));
      expect(screenSource, contains("label: 'Permitir Notificações:'"));
      expect(screenSource, contains("label: 'Sem Restrições de Bateria:'"));
      expect(screenSource, contains("label: 'Ativar Auto-Start:'"));
      expect(
        screenSource,
        contains("label: 'Check-in/Check-out Automáticos:'"),
      );
      expect(screenSource, contains("'Configurações'"));
      expect(screenSource, contains("'Permissões'"));
      expect(screenSource, contains("'Frequência de Atividades'"));
      expect(screenSource, contains('Últimas Localizações'));
      expect(screenSource, contains('Coordenada'));
    },
  );

  test('caps the location fetch history to the newest ten entries', () {
    final timestamps = List<DateTime>.generate(
      12,
      (index) => DateTime.utc(2026, 4, 10, 7, index),
    );

    var history = <LocationFetchEntry>[];
    for (final timestamp in timestamps) {
      history = CheckingLocationLogic.recordLocationFetchHistory(
        history: history,
        timestamp: timestamp,
        latitude: 1.249494,
        longitude: 103.614345,
      );
    }

    expect(history, hasLength(10));
    expect(history.first.timestamp, timestamps.last.toLocal());
    expect(history.last.timestamp, timestamps[2].toLocal());
    expect(history.first.latitude, 1.249494);
    expect(history.first.longitude, 103.614345);
  });

  test('deduplicates repeated gps fixes recorded in the same second', () {
    var history = <LocationFetchEntry>[];

    history = CheckingLocationLogic.recordLocationFetchHistory(
      history: history,
      timestamp: DateTime.utc(2026, 4, 10, 7, 0, 0, 100),
      latitude: 1.249494,
      longitude: 103.614345,
    );
    history = CheckingLocationLogic.recordLocationFetchHistory(
      history: history,
      timestamp: DateTime.utc(2026, 4, 10, 7, 0, 0, 900),
      latitude: 1.249494,
      longitude: 103.614345,
    );
    history = CheckingLocationLogic.recordLocationFetchHistory(
      history: history,
      timestamp: DateTime.utc(2026, 4, 10, 7, 0, 2, 100),
      latitude: 1.249494,
      longitude: 103.614345,
    );

    expect(history, hasLength(2));
    expect(
      history.first.timestamp.toUtc().toIso8601String(),
      '2026-04-10T07:00:02.100Z',
    );
    expect(
      history.last.timestamp.toUtc().toIso8601String(),
      '2026-04-10T07:00:00.900Z',
    );
  });

  test('initializes persisted history during foreground refresh', () async {
    final storageService = _FakeCheckingStorageService(
      initialState: CheckingState.initial().copyWith(
        chave: 'AB12',
        apiBaseUrl: 'https://example.com',
        apiSharedKey: 'shared-key',
      ),
    );
    final apiService = _RecordingCheckingApiService();
    final locationCatalogService = _RecordingLocationCatalogService();
    final controller = CheckingController(
      storageService: storageService,
      apiService: apiService,
      androidBridge: _FakeCheckingAndroidBridge(),
      locationCatalogService: locationCatalogService,
    );

    await controller.initialize();
    await controller.waitForPendingStatePersistence();

    expect(apiService.calls, <String>['fetchState']);
    expect(locationCatalogService.replaceCalls, 0);
    expect(controller.state.lastCheckIn, isNotNull);
    expect(controller.state.lastCheckOut, isNotNull);
    expect(controller.state.statusMessage, 'Atividades atualizadas.');

    controller.dispose();
  });

  test(
    'keeps last check-in and check-out blank until the initial api sync completes',
    () async {
      final storageService = _FakeCheckingStorageService(
        initialState: CheckingState.initial().copyWith(
          chave: 'AB12',
          apiBaseUrl: 'https://example.com',
          apiSharedKey: 'shared-key',
          lastCheckIn: DateTime(2026, 4, 15, 6),
          lastCheckOut: DateTime(2026, 4, 15, 8),
        ),
      );
      final apiService = _DelayedRecordingCheckingApiService();
      final controller = CheckingController(
        storageService: storageService,
        apiService: apiService,
        androidBridge: _FakeCheckingAndroidBridge(),
        locationCatalogService: _RecordingLocationCatalogService(),
      );

      final initializeFuture = controller.initialize();
      await apiService.fetchStateStarted.future;

      expect(controller.state.lastCheckIn, isNull);
      expect(controller.state.lastCheckOut, isNull);
      expect(
        controller.state.statusMessage,
        'Atualização em andamento. Aguarde.',
      );

      apiService.completeFetchState(
        MobileStateResponse(
          found: true,
          chave: 'AB12',
          nome: 'Usuário Teste',
          projeto: 'P80',
          currentAction: 'checkout',
          currentEventTime: DateTime(2026, 4, 15, 8),
          lastCheckInAt: DateTime(2026, 4, 15, 6),
          lastCheckOutAt: DateTime(2026, 4, 15, 8),
        ),
      );

      await initializeFuture;

      expect(controller.state.lastCheckIn, isNotNull);
      expect(controller.state.lastCheckOut, isNotNull);

      controller.dispose();
    },
  );

  test('uses 15-minute location updates during the overnight window', () {
    expect(
      CheckingController.resolveLocationUpdateIntervalSeconds(
        referenceTime: DateTime.utc(2025, 1, 6, 15, 0),
      ),
      15 * 60,
    );
    expect(
      CheckingController.describeLocationUpdateInterval(
        referenceTime: DateTime.utc(2025, 1, 6, 15, 0),
      ),
      '15 min',
    );
  });

  test('manual submissions preserve the selected informe', () {
    final state = CheckingState.initial().copyWith(
      checkInInforme: InformeType.retroativo,
      checkOutInforme: InformeType.retroativo,
    );

    expect(
      CheckingController.resolveInformeForSubmission(
        state: state,
        registro: RegistroType.checkIn,
        source: 'manual',
      ),
      InformeType.retroativo,
    );
    expect(
      CheckingController.resolveInformeForSubmission(
        state: state,
        registro: RegistroType.checkOut,
        source: 'manual',
      ),
      InformeType.retroativo,
    );
  });

  test('location automation submissions always use normal informe', () {
    final state = CheckingState.initial().copyWith(
      checkInInforme: InformeType.retroativo,
      checkOutInforme: InformeType.retroativo,
    );

    expect(
      CheckingController.resolveInformeForSubmission(
        state: state,
        registro: RegistroType.checkIn,
        source: 'location-automation',
      ),
      InformeType.normal,
    );
    expect(
      CheckingController.resolveInformeForSubmission(
        state: state,
        registro: RegistroType.checkOut,
        source: 'location-automation',
      ),
      InformeType.normal,
    );
  });

  test(
    'manual submit does not refresh location tracking when automation is off',
    () {
      final state = CheckingState.initial().copyWith(
        locationSharingEnabled: true,
        autoCheckInEnabled: false,
        autoCheckOutEnabled: false,
      );

      expect(
        CheckingController.shouldRefreshLocationTrackingAfterSubmit(
          state: state,
        ),
        isFalse,
      );
    },
  );

  test('manual submit refreshes location tracking when automation is on', () {
    final state = CheckingState.initial().copyWith(
      locationSharingEnabled: true,
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
    );

    expect(
      CheckingController.shouldRefreshLocationTrackingAfterSubmit(state: state),
      isTrue,
    );
  });

  test(
    'background snapshot cannot re-enable a toggle that the user turned off',
    () {
      expect(
        CheckingController.resolveControlFlagAfterSnapshot(
          currentValue: false,
          snapshotLocationSharingEnabled: true,
        ),
        isFalse,
      );

      expect(
        CheckingController.resolveControlFlagAfterSnapshot(
          currentValue: true,
          snapshotLocationSharingEnabled: false,
        ),
        isFalse,
      );
    },
  );

  test('automatic toggle is disabled and off when location search is off', () {
    final state = CheckingState.initial().copyWith(
      locationSharingEnabled: false,
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
    );

    expect(
      CheckingController.isAutomaticCheckingEnabledInUi(state: state),
      isFalse,
    );
    expect(
      CheckingController.isAutomaticCheckingToggleInteractive(state: state),
      isFalse,
    );
  });

  test('automatic toggle is interactive when location search is on', () {
    final state = CheckingState.initial().copyWith(
      locationSharingEnabled: true,
      autoCheckInEnabled: false,
      autoCheckOutEnabled: false,
    );

    expect(
      CheckingController.isAutomaticCheckingEnabledInUi(state: state),
      isFalse,
    );
    expect(
      CheckingController.isAutomaticCheckingToggleInteractive(state: state),
      isTrue,
    );
  });

  test('automatic toggle is locked while automatic transition is running', () {
    final state = CheckingState.initial().copyWith(
      locationSharingEnabled: true,
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
      isAutomaticCheckingUpdating: true,
    );

    expect(
      CheckingController.isAutomaticCheckingEnabledInUi(state: state),
      isTrue,
    );
    expect(
      CheckingController.isAutomaticCheckingToggleInteractive(state: state),
      isFalse,
    );
  });

  testWidgets(
    'clears the key on tap and dismisses the keyboard after four characters',
    (tester) async {
      final changedValues = <String>[];
      var blurCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChaveInputField(
              value: 'HR70',
              onChanged: changedValues.add,
              onBlur: () => blurCount += 1,
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      final editableField = find.byType(EditableText);

      EditableText editableText() {
        return tester.widget<EditableText>(find.byType(EditableText));
      }

      expect(editableText().controller.text, 'HR70');

      await tester.tap(editableField);
      await tester.pump();

      expect(editableText().controller.text, isEmpty);
      expect(editableText().focusNode.hasFocus, isTrue);
      expect(changedValues.last, isEmpty);

      await tester.enterText(field, 'ab12');
      await tester.pump();

      expect(editableText().controller.text, 'AB12');
      expect(editableText().focusNode.hasFocus, isFalse);
      expect(changedValues.last, 'AB12');
      expect(blurCount, 1);

      await tester.tap(editableField);
      await tester.pump();

      expect(editableText().controller.text, isEmpty);
      expect(editableText().focusNode.hasFocus, isTrue);
      expect(changedValues.last, isEmpty);

      await tester.enterText(field, 'cd34');
      await tester.pump();

      expect(editableText().controller.text, 'CD34');
      expect(editableText().focusNode.hasFocus, isFalse);
      expect(changedValues.last, 'CD34');
      expect(blurCount, 2);
    },
  );

  test('persists the latest chave after rapid consecutive updates', () async {
    final storageService = _DelayedFakeCheckingStorageService();
    final controller = CheckingController(storageService: storageService);

    controller.updateChave('A');
    controller.updateChave('AB');
    controller.updateChave('ABC');

    await controller.waitForPendingStatePersistence();

    expect(storageService.savedStates, isNotEmpty);
    expect(storageService.savedStates.last.chave, 'ABC');
  });

  test('checkout zone only triggers checkout after a previous check-in', () {
    final checkoutLocation = ManagedLocation(
      id: 3,
      local: ManagedLocation.checkoutZoneLabel,
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );

    final fromCheckIn = CheckingController.resolveAutomaticActionForLocation(
      remoteState: MobileStateResponse(
        found: true,
        chave: 'AB12',
        nome: 'Teste',
        projeto: 'P80',
        currentAction: 'checkin',
        currentEventTime: DateTime(2026, 4, 10, 8),
        lastCheckInAt: DateTime(2026, 4, 10, 8),
        lastCheckOutAt: DateTime(2026, 4, 9, 18),
      ),
      location: checkoutLocation,
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
      lastCheckInLocation: 'Base P80',
    );
    final fromCheckOut = CheckingController.resolveAutomaticActionForLocation(
      remoteState: MobileStateResponse(
        found: true,
        chave: 'AB12',
        nome: 'Teste',
        projeto: 'P80',
        currentAction: 'checkout',
        currentEventTime: DateTime(2026, 4, 10, 18),
        lastCheckInAt: DateTime(2026, 4, 10, 8),
        lastCheckOutAt: DateTime(2026, 4, 10, 18),
      ),
      location: checkoutLocation,
      autoCheckInEnabled: true,
      autoCheckOutEnabled: true,
      lastCheckInLocation: 'Base P80',
    );

    expect(fromCheckIn, RegistroType.checkOut);
    expect(fromCheckOut, isNull);
  });

  test(
    'automatic checkout in checkout zone uses Zona de CheckOut as local',
    () {
      final checkoutLocation = ManagedLocation(
        id: 31,
        local: ManagedLocation.checkoutZoneLabel,
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 10),
      );

      final resolvedLocal = CheckingController.resolveAutomaticEventLocal(
        action: RegistroType.checkOut,
        location: checkoutLocation,
      );

      expect(resolvedLocal, ManagedLocation.checkoutZoneLabel);
    },
  );

  test('captured location uses user-facing labels for special cases', () {
    final checkoutLocation = ManagedLocation(
      id: 32,
      local: 'Zona de CheckOut 3',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );

    expect(
      CheckingController.resolveCapturedLocationLabel(
        location: null,
        nearestWorkplaceDistanceMeters: 1500,
      ),
      CheckingController.uncatalogedCapturedLocation,
    );
    expect(
      CheckingController.resolveCapturedLocationLabel(
        location: null,
        nearestWorkplaceDistanceMeters: 2500,
      ),
      'Fora do Ambiente de Trabalho',
    );
    expect(
      CheckingController.resolveCapturedLocationLabel(
        location: checkoutLocation,
      ),
      'Zona de Check-Out',
    );
  });

  test(
    'captured location stays blank only when there is no workplace distance to evaluate',
    () {
      expect(
        CheckingController.resolveCapturedLocationLabel(location: null),
        isNull,
      );
    },
  );

  test(
    'situation 2 does not repeat check-out when the user is already checked out and far from all work areas',
    () {
      final managedLocations = _buildForegroundScenarioLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: 1.322615,
        longitude: 103.663611,
      );

      expect(matchResult.matchedLocation, isNull);
      expect(
        matchResult.nearestWorkplaceDistanceMeters,
        greaterThan(CheckingController.outOfRangeCheckoutDistanceMeters),
      );
      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: matchResult.matchedLocation,
          nearestWorkplaceDistanceMeters:
              matchResult.nearestWorkplaceDistanceMeters,
        ),
        'Fora do Ambiente de Trabalho',
      );
      expect(
        CheckingController.resolveAutomaticActionOutOfRange(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkOut,
          ),
          nearestDistanceMeters: matchResult.nearestWorkplaceDistanceMeters,
          autoCheckOutEnabled: true,
        ),
        isNull,
      );
    },
  );

  test(
    'situation 3 performs automatic check-in when the user re-enters a monitored location after a check-out',
    () {
      final managedLocations = _buildForegroundScenarioLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: 1.249494,
        longitude: 103.614345,
      );
      final matchedLocation = matchResult.matchedLocation;

      expect(matchedLocation?.local, 'Escritório Principal');
      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: matchedLocation,
        ),
        'Escritório Principal',
      );
      expect(
        CheckingController.resolveAutomaticActionForLocation(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkOut,
          ),
          location: matchedLocation!,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
          lastCheckInLocation: null,
        ),
        RegistroType.checkIn,
      );
    },
  );

  test(
    'situation 1 performs automatic check-out in the checkout zone after a prior check-in',
    () {
      final managedLocations = _buildForegroundScenarioLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: 1.266058,
        longitude: 103.614415,
      );
      final matchedLocation = matchResult.matchedLocation;

      expect(matchedLocation?.isCheckoutZone, isTrue);
      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: matchedLocation,
        ),
        'Zona de Check-Out',
      );
      expect(
        CheckingController.resolveAutomaticActionForLocation(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkIn,
            currentLocal: 'Escritório Principal',
          ),
          location: matchedLocation!,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
          lastCheckInLocation: 'Escritório Principal',
        ),
        RegistroType.checkOut,
      );
    },
  );

  test(
    'situation 4 performs a new automatic check-in when the user changes to another monitored location',
    () {
      final managedLocations = _buildForegroundScenarioLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: 1.251290,
        longitude: 103.613386,
      );
      final matchedLocation = matchResult.matchedLocation;

      expect(matchedLocation?.local, 'Em Deslocamento');
      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: matchedLocation,
        ),
        'Em Deslocamento',
      );
      expect(
        CheckingController.resolveAutomaticActionForLocation(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkIn,
            currentLocal: 'Escritório Principal',
          ),
          location: matchedLocation!,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
          lastCheckInLocation: 'Escritório Principal',
        ),
        RegistroType.checkIn,
      );
    },
  );

  test(
    'situation 1 also performs automatic check-out when the user is more than 2 km away from all work areas',
    () {
      final managedLocations = _buildForegroundScenarioLocations();
      final matchResult = CheckingLocationLogic.resolveLocationMatch(
        managedLocations: managedLocations,
        latitude: 1.328550,
        longitude: 103.708420,
      );

      expect(matchResult.matchedLocation, isNull);
      expect(
        matchResult.nearestWorkplaceDistanceMeters,
        greaterThan(CheckingController.outOfRangeCheckoutDistanceMeters),
      );
      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: matchResult.matchedLocation,
          nearestWorkplaceDistanceMeters:
              matchResult.nearestWorkplaceDistanceMeters,
        ),
        'Fora do Ambiente de Trabalho',
      );
      expect(
        CheckingController.resolveAutomaticActionOutOfRange(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkIn,
            currentLocal: 'Escritório Principal',
          ),
          nearestDistanceMeters: matchResult.nearestWorkplaceDistanceMeters,
          autoCheckOutEnabled: true,
        ),
        RegistroType.checkOut,
      );
    },
  );

  test(
    'situation 3 performs automatic check-in near the workplace even without an exact location match',
    () {
      const nearestDistanceMeters = 1500.0;

      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: null,
          nearestWorkplaceDistanceMeters: nearestDistanceMeters,
        ),
        CheckingController.uncatalogedCapturedLocation,
      );
      expect(
        CheckingController.resolveAutomaticActionWithoutLocationMatch(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkOut,
          ),
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
        ),
        RegistroType.checkIn,
      );
      expect(
        CheckingController.resolveAutomaticEventLocal(
          action: RegistroType.checkIn,
        ),
        CheckingController.uncatalogedCapturedLocation,
      );
    },
  );

  test(
    'situation 5 only updates the captured location when the user is near the workplace without an exact match after a prior check-in',
    () {
      const nearestDistanceMeters = 1500.0;

      expect(
        CheckingController.resolveCapturedLocationLabel(
          location: null,
          nearestWorkplaceDistanceMeters: nearestDistanceMeters,
        ),
        CheckingController.uncatalogedCapturedLocation,
      );
      expect(
        CheckingController.resolveAutomaticActionWithoutLocationMatch(
          remoteState: _buildScenarioRemoteState(
            lastAction: RegistroType.checkIn,
            currentLocal: 'Escritório Principal',
          ),
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
        ),
        isNull,
      );
    },
  );

  test('automatic checkout out of range uses Fora do Local de Trabalho', () {
    final resolvedLocal = CheckingController.resolveAutomaticEventLocal(
      action: RegistroType.checkOut,
    );

    expect(resolvedLocal, CheckingController.automaticCheckoutLocation);
  });

  test('regular locations do not repeat check-in in the same location', () {
    final regularLocation = ManagedLocation(
      id: 4,
      local: 'Base P82',
      latitude: 1,
      longitude: 1,
      toleranceMeters: 200,
      updatedAt: DateTime(2026, 4, 10),
    );

    final repeatedCheckIn =
        CheckingController.resolveAutomaticActionForLocation(
          remoteState: MobileStateResponse(
            found: true,
            chave: 'CD34',
            nome: 'Teste',
            projeto: 'P82',
            currentAction: 'checkin',
            currentEventTime: DateTime(2026, 4, 10, 8),
            lastCheckInAt: DateTime(2026, 4, 10, 8),
            lastCheckOutAt: DateTime(2026, 4, 9, 18),
          ),
          location: regularLocation,
          autoCheckInEnabled: true,
          autoCheckOutEnabled: true,
          lastCheckInLocation: 'Base P82',
        );

    expect(repeatedCheckIn, isNull);
  });

  test(
    'regular locations trigger a new check-in when the location changes',
    () {
      final regularLocation = ManagedLocation(
        id: 5,
        local: 'Unidade P80',
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 10),
      );

      final fromCheckOut = CheckingController.resolveAutomaticActionForLocation(
        remoteState: MobileStateResponse(
          found: true,
          chave: 'CD34',
          nome: 'Teste',
          projeto: 'P82',
          currentAction: 'checkout',
          currentEventTime: DateTime(2026, 4, 10, 18),
          lastCheckInAt: DateTime(2026, 4, 10, 8),
          lastCheckOutAt: DateTime(2026, 4, 10, 18),
        ),
        location: regularLocation,
        autoCheckInEnabled: true,
        autoCheckOutEnabled: true,
        lastCheckInLocation: null,
      );
      final fromDifferentCheckIn =
          CheckingController.resolveAutomaticActionForLocation(
            remoteState: MobileStateResponse(
              found: true,
              chave: 'CD34',
              nome: 'Teste',
              projeto: 'P82',
              currentAction: 'checkin',
              currentEventTime: DateTime(2026, 4, 10, 8),
              lastCheckInAt: DateTime(2026, 4, 10, 8),
              lastCheckOutAt: DateTime(2026, 4, 9, 18),
            ),
            location: regularLocation,
            autoCheckInEnabled: true,
            autoCheckOutEnabled: true,
            lastCheckInLocation: 'Escritório Principal',
          );

      expect(fromCheckOut, RegistroType.checkIn);
      expect(fromDifferentCheckIn, RegistroType.checkIn);
    },
  );

  test(
    'regular locations reconcile using the current location returned by the API',
    () {
      final regularLocation = ManagedLocation(
        id: 6,
        local: 'Base P82',
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 10),
      );

      final action = CheckingController.resolveAutomaticActionForLocation(
        remoteState: MobileStateResponse(
          found: true,
          chave: 'GH78',
          nome: 'Teste',
          projeto: 'P82',
          currentAction: 'checkin',
          currentEventTime: DateTime(2026, 4, 10, 8),
          currentLocal: 'Base P80',
          lastCheckInAt: DateTime(2026, 4, 10, 8),
          lastCheckOutAt: DateTime(2026, 4, 9, 18),
        ),
        location: regularLocation,
        autoCheckInEnabled: true,
        autoCheckOutEnabled: true,
        lastCheckInLocation: 'Base P82',
      );

      expect(action, RegistroType.checkIn);
    },
  );

  test(
    'regular locations do not trigger automatic events when automation is off',
    () {
      final regularLocation = ManagedLocation(
        id: 10,
        local: 'Base P80',
        latitude: 1,
        longitude: 1,
        toleranceMeters: 200,
        updatedAt: DateTime(2026, 4, 15),
      );

      final action = CheckingController.resolveAutomaticActionForLocation(
        remoteState: MobileStateResponse(
          found: true,
          chave: 'ZZ99',
          nome: 'Teste',
          projeto: 'P80',
          currentAction: 'checkout',
          currentEventTime: DateTime(2026, 4, 15, 18),
          lastCheckInAt: DateTime(2026, 4, 15, 8),
          lastCheckOutAt: DateTime(2026, 4, 15, 18),
        ),
        location: regularLocation,
        autoCheckInEnabled: false,
        autoCheckOutEnabled: false,
        lastCheckInLocation: null,
      );

      expect(action, isNull);
    },
  );

  test('out-of-range checkout only happens beyond 2 km after a check-in', () {
    final farFromAllLocations =
        CheckingController.resolveAutomaticActionOutOfRange(
          remoteState: MobileStateResponse(
            found: true,
            chave: 'EF56',
            nome: 'Teste',
            projeto: 'P83',
            currentAction: 'checkin',
            currentEventTime: DateTime(2026, 4, 10, 8),
            lastCheckInAt: DateTime(2026, 4, 10, 8),
            lastCheckOutAt: DateTime(2026, 4, 9, 18),
          ),
          nearestDistanceMeters: 2100,
          autoCheckOutEnabled: true,
        );
    final stillNearLocations =
        CheckingController.resolveAutomaticActionOutOfRange(
          remoteState: MobileStateResponse(
            found: true,
            chave: 'EF56',
            nome: 'Teste',
            projeto: 'P83',
            currentAction: 'checkin',
            currentEventTime: DateTime(2026, 4, 10, 8),
            lastCheckInAt: DateTime(2026, 4, 10, 8),
            lastCheckOutAt: DateTime(2026, 4, 9, 18),
          ),
          nearestDistanceMeters: 1950,
          autoCheckOutEnabled: true,
        );
    final alreadyCheckedOut =
        CheckingController.resolveAutomaticActionOutOfRange(
          remoteState: MobileStateResponse(
            found: true,
            chave: 'EF56',
            nome: 'Teste',
            projeto: 'P83',
            currentAction: 'checkout',
            currentEventTime: DateTime(2026, 4, 10, 18),
            lastCheckInAt: DateTime(2026, 4, 10, 8),
            lastCheckOutAt: DateTime(2026, 4, 10, 18),
          ),
          nearestDistanceMeters: 2100,
          autoCheckOutEnabled: true,
        );

    expect(farFromAllLocations, RegistroType.checkOut);
    expect(stillNearLocations, isNull);
    expect(alreadyCheckedOut, isNull);
  });

  test(
    'out-of-range checkout does not happen when automatic checkout is off',
    () {
      final action = CheckingController.resolveAutomaticActionOutOfRange(
        remoteState: MobileStateResponse(
          found: true,
          chave: 'EF56',
          nome: 'Teste',
          projeto: 'P83',
          currentAction: 'checkin',
          currentEventTime: DateTime(2026, 4, 10, 8),
          lastCheckInAt: DateTime(2026, 4, 10, 8),
          lastCheckOutAt: DateTime(2026, 4, 9, 18),
        ),
        nearestDistanceMeters: 2100,
        autoCheckOutEnabled: false,
      );

      expect(action, isNull);
    },
  );
}

class _DelayedFakeCheckingStorageService extends CheckingStorageService {
  final List<CheckingState> savedStates = <CheckingState>[];
  int _saveCount = 0;

  @override
  Future<CheckingState> loadState() async {
    return CheckingState.initial();
  }

  @override
  Future<void> saveState(CheckingState state) async {
    _saveCount += 1;
    if (_saveCount == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    savedStates.add(state);
  }
}

List<ManagedLocation> _buildForegroundScenarioLocations() {
  final updatedAt = DateTime(2026, 4, 15, 7, 0);
  return <ManagedLocation>[
    ManagedLocation(
      id: 200,
      local: 'Escritório Principal',
      latitude: 1.249494,
      longitude: 103.614345,
      toleranceMeters: 150,
      updatedAt: updatedAt,
    ),
    ManagedLocation(
      id: 201,
      local: 'Em Deslocamento',
      latitude: 1.25129,
      longitude: 103.613386,
      toleranceMeters: 150,
      updatedAt: updatedAt,
    ),
    ManagedLocation(
      id: 202,
      local: 'Zona de CheckOut',
      latitude: 1.266058,
      longitude: 103.614415,
      toleranceMeters: 150,
      updatedAt: updatedAt,
    ),
  ];
}

MobileStateResponse _buildScenarioRemoteState({
  required RegistroType lastAction,
  String? currentLocal,
}) {
  switch (lastAction) {
    case RegistroType.checkIn:
      return MobileStateResponse(
        found: true,
        chave: 'HR70',
        nome: 'Usuário Teste',
        projeto: 'P80',
        currentAction: 'checkin',
        currentEventTime: DateTime(2026, 4, 14, 18),
        currentLocal: currentLocal,
        lastCheckInAt: DateTime(2026, 4, 14, 18),
        lastCheckOutAt: DateTime(2026, 4, 13, 18),
      );
    case RegistroType.checkOut:
      return MobileStateResponse(
        found: true,
        chave: 'HR70',
        nome: 'Usuário Teste',
        projeto: 'P80',
        currentAction: 'checkout',
        currentEventTime: DateTime(2026, 4, 14, 18),
        currentLocal: currentLocal,
        lastCheckInAt: DateTime(2026, 4, 14, 7),
        lastCheckOutAt: DateTime(2026, 4, 14, 18),
      );
  }
}

class _FakeCheckingStorageService extends CheckingStorageService {
  _FakeCheckingStorageService({required this.initialState});

  final CheckingState initialState;
  final List<CheckingState> savedStates = <CheckingState>[];
  bool promptedInitialAndroidSetup = true;

  @override
  Future<CheckingState> loadState() async {
    return initialState;
  }

  @override
  Future<void> saveState(CheckingState state) async {
    savedStates.add(state);
  }

  @override
  Future<bool> hasPromptedInitialAndroidSetup() async {
    return promptedInitialAndroidSetup;
  }

  @override
  Future<void> markInitialAndroidSetupPrompted() async {
    promptedInitialAndroidSetup = true;
  }
}

class _RecordingCheckingApiService extends CheckingApiService {
  final List<String> calls = <String>[];

  @override
  Future<MobileStateResponse> fetchState({
    required String baseUrl,
    required String sharedKey,
    required String chave,
  }) async {
    calls.add('fetchState');
    return MobileStateResponse(
      found: true,
      chave: chave,
      nome: 'Usuário Teste',
      projeto: 'P80',
      currentAction: 'checkout',
      currentEventTime: DateTime(2026, 4, 15, 8),
      lastCheckInAt: DateTime(2026, 4, 15, 6),
      lastCheckOutAt: DateTime(2026, 4, 15, 8),
    );
  }

  @override
  Future<LocationCatalogResponse> fetchLocations({
    required String baseUrl,
    required String sharedKey,
  }) async {
    calls.add('fetchLocations');
    return LocationCatalogResponse(
      items: const <ManagedLocation>[],
      syncedAt: DateTime(2026, 4, 15, 8),
      locationAccuracyThresholdMeters: 30,
    );
  }
}

class _DelayedRecordingCheckingApiService extends _RecordingCheckingApiService {
  final Completer<void> fetchStateStarted = Completer<void>();
  final Completer<MobileStateResponse> _fetchStateResponse =
      Completer<MobileStateResponse>();

  @override
  Future<MobileStateResponse> fetchState({
    required String baseUrl,
    required String sharedKey,
    required String chave,
  }) async {
    calls.add('fetchState');
    if (!fetchStateStarted.isCompleted) {
      fetchStateStarted.complete();
    }
    return _fetchStateResponse.future;
  }

  void completeFetchState(MobileStateResponse response) {
    if (!_fetchStateResponse.isCompleted) {
      _fetchStateResponse.complete(response);
    }
  }
}

class _FakeCheckingAndroidBridge extends CheckingAndroidBridge {
  @override
  bool get isSupported => false;

  @override
  Future<void> initialize({
    required Future<void> Function(String action) onNativeAction,
  }) async {}

  @override
  Future<void> clearSchedules() async {}
}

class _RecordingLocationCatalogService extends LocationCatalogService {
  int replaceCalls = 0;

  @override
  Future<List<ManagedLocation>> loadLocations({
    bool preferCache = false,
  }) async {
    return const <ManagedLocation>[];
  }

  @override
  Future<void> replaceLocations(List<ManagedLocation> items) async {
    replaceCalls += 1;
  }
}
