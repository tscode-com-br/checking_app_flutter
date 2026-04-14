import 'package:checking/src/core/theme/app_theme.dart';
import 'package:checking/src/features/checking/controller/checking_controller.dart';
import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:checking/src/features/checking/services/checking_services.dart';
import 'package:checking/src/features/checking/view/checking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('does not persist last check-in and last check-out timestamps', () {
    final state = CheckingState.initial().copyWith(
      lastDetectedLocation: 'Portaria Principal',
      lastLocationUpdateAt: DateTime.utc(2026, 4, 10, 7, 45, 30),
      lastCheckInLocation: 'Escritório Principal',
      lastCheckIn: DateTime(2026, 4, 9, 8),
      lastCheckOut: DateTime(2026, 4, 9, 18),
    );

    final json = state.toJson();

    expect(json.containsKey('lastCheckIn'), isFalse);
    expect(json.containsKey('lastCheckOut'), isFalse);
    expect(json['lastDetectedLocation'], 'Portaria Principal');
    expect(json['lastLocationUpdateAt'], '2026-04-10T07:45:30.000Z');
    expect(json['lastCheckInLocation'], 'Escritório Principal');
  });

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

  test('parses location catalog settings from api response', () {
    final response = LocationCatalogResponse.fromJson({
      'items': const [],
      'synced_at': '2026-04-12T08:00:00Z',
      'location_accuracy_threshold_meters': 45,
    });

    expect(response.locationAccuracyThresholdMeters, 45);
    expect(response.items, isEmpty);
  });

  test('uses 16-minute location updates during the daytime window', () {
    expect(
      CheckingController.resolveLocationUpdateIntervalSeconds(
        referenceTime: DateTime.utc(2025, 1, 6, 0, 30),
      ),
      16 * 60,
    );
    expect(
      CheckingController.describeLocationUpdateInterval(
        referenceTime: DateTime.utc(2025, 1, 6, 0, 30),
      ),
      '16 min',
    );
  });

  test('uses hourly location updates during the overnight window', () {
    expect(
      CheckingController.resolveLocationUpdateIntervalSeconds(
        referenceTime: DateTime.utc(2025, 1, 6, 15, 0),
      ),
      60 * 60,
    );
    expect(
      CheckingController.describeLocationUpdateInterval(
        referenceTime: DateTime.utc(2025, 1, 6, 15, 0),
      ),
      '1 hora',
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
