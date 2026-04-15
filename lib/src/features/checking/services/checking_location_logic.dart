import 'dart:math';

import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:geolocator/geolocator.dart';

class CheckingLocationMatchResult {
  const CheckingLocationMatchResult({
    required this.matchedLocation,
    required this.nearestWorkplaceDistanceMeters,
  });

  final ManagedLocation? matchedLocation;
  final double? nearestWorkplaceDistanceMeters;
}

class CheckingLocationLogic {
  static const double outOfRangeCheckoutDistanceMeters = 2000;
  static const double defaultLocationAccuracyThresholdMeters = 30;
  static const String automaticCheckoutLocation = 'Fora do Local de Trabalho';
  static const String outsideWorkplaceCapturedLocation =
      'Fora do Ambiente de Trabalho';
  static const String checkoutZoneCapturedLocation = 'Zona de Check-Out';
  static const Duration singaporeUtcOffset = Duration(hours: 8);
  static const int daytimeLocationUpdateIntervalSeconds = 15 * 60;
  static const int overnightLocationUpdateIntervalSeconds = 60 * 60;
  static const int daytimeLocationUpdateStartHour = 6;
  static const int overnightLocationUpdateStartHour = 22;

  static int resolveLocationUpdateIntervalSeconds({DateTime? referenceTime}) {
    final reference = _toSingaporeTime(referenceTime ?? DateTime.now());
    return _isDaytimeLocationUpdateWindow(reference)
        ? daytimeLocationUpdateIntervalSeconds
        : overnightLocationUpdateIntervalSeconds;
  }

  static String describeLocationUpdateInterval({DateTime? referenceTime}) {
    return resolveLocationUpdateIntervalSeconds(referenceTime: referenceTime) ==
            daytimeLocationUpdateIntervalSeconds
        ? '15 min'
        : '1 hora';
  }

  static CheckingState resolveLocationUpdateIntervalState(
    CheckingState state, {
    DateTime? referenceTime,
  }) {
    final resolvedIntervalSeconds = resolveLocationUpdateIntervalSeconds(
      referenceTime: referenceTime,
    );
    if (resolvedIntervalSeconds == state.locationUpdateIntervalSeconds) {
      return state;
    }

    return state.copyWith(
      locationUpdateIntervalSeconds: resolvedIntervalSeconds,
    );
  }

  static Duration delayUntilNextLocationUpdateIntervalBoundary({
    DateTime? referenceTime,
  }) {
    final referenceUtc = (referenceTime ?? DateTime.now()).toUtc();
    final referenceSgt = _toSingaporeTime(referenceUtc);
    final nextBoundarySgt = referenceSgt.hour < daytimeLocationUpdateStartHour
        ? DateTime.utc(
            referenceSgt.year,
            referenceSgt.month,
            referenceSgt.day,
            daytimeLocationUpdateStartHour,
          )
        : referenceSgt.hour < overnightLocationUpdateStartHour
        ? DateTime.utc(
            referenceSgt.year,
            referenceSgt.month,
            referenceSgt.day,
            overnightLocationUpdateStartHour,
          )
        : DateTime.utc(
            referenceSgt.year,
            referenceSgt.month,
            referenceSgt.day + 1,
            daytimeLocationUpdateStartHour,
          );
    final nextBoundaryUtc = nextBoundarySgt.subtract(singaporeUtcOffset);
    final delay = nextBoundaryUtc.difference(referenceUtc);
    return delay.isNegative || delay == Duration.zero
        ? const Duration(seconds: 1)
        : delay;
  }

  static double resolveDistanceToLocation({
    required ManagedLocation location,
    required double latitude,
    required double longitude,
  }) {
    return location.coordinates
        .map(
          (coordinate) => Geolocator.distanceBetween(
            latitude,
            longitude,
            coordinate.latitude,
            coordinate.longitude,
          ),
        )
        .reduce(min);
  }

  static CheckingLocationMatchResult resolveLocationMatch({
    required List<ManagedLocation> managedLocations,
    required double latitude,
    required double longitude,
  }) {
    ManagedLocation? nearestRegularLocation;
    double? nearestRegularDistanceMeters;
    ManagedLocation? nearestCheckoutLocation;
    double? nearestCheckoutDistanceMeters;
    double? nearestWorkplaceDistanceMeters;

    for (final location in managedLocations) {
      final distanceMeters = resolveDistanceToLocation(
        location: location,
        latitude: latitude,
        longitude: longitude,
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

    return CheckingLocationMatchResult(
      matchedLocation: nearestCheckoutLocation ?? nearestRegularLocation,
      nearestWorkplaceDistanceMeters: nearestWorkplaceDistanceMeters,
    );
  }

  static RegistroType? resolveAutomaticActionForLocation({
    required MobileStateResponse remoteState,
    required ManagedLocation location,
    required bool autoCheckInEnabled,
    required bool autoCheckOutEnabled,
    required String? lastCheckInLocation,
  }) {
    final lastRecordedAction = resolveLastRecordedAction(remoteState);
    final recordedCheckInLocation = resolveRecordedCheckInLocation(
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

  static RegistroType? resolveAutomaticActionOutOfRange({
    required MobileStateResponse remoteState,
    required double? nearestDistanceMeters,
    required bool autoCheckOutEnabled,
  }) {
    return shouldAttemptAutomaticOutOfRangeCheckout(
          lastRecordedAction: resolveLastRecordedAction(remoteState),
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckOutEnabled: autoCheckOutEnabled,
        )
        ? RegistroType.checkOut
        : null;
  }

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

  static String? resolveCapturedLocationLabel({
    ManagedLocation? location,
    double? nearestWorkplaceDistanceMeters,
  }) {
    if (location == null) {
      if (nearestWorkplaceDistanceMeters != null &&
          nearestWorkplaceDistanceMeters > outOfRangeCheckoutDistanceMeters) {
        return outsideWorkplaceCapturedLocation;
      }
      return null;
    }
    if (location.isCheckoutZone) {
      return checkoutZoneCapturedLocation;
    }
    return location.local;
  }

  static bool isLocationAccuracyPreciseEnough(
    double? accuracyMeters, {
    double maxAccuracyMeters = defaultLocationAccuracyThresholdMeters,
  }) {
    if (accuracyMeters == null || accuracyMeters.isNaN) {
      return false;
    }
    return accuracyMeters <= maxAccuracyMeters;
  }

  static RegistroType? resolveLastRecordedAction(
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

  static String? resolveRecordedCheckInLocation(
    MobileStateResponse remoteState, {
    required String? fallbackLocation,
  }) {
    if (_parseRemoteAction(remoteState.currentAction) == RegistroType.checkIn) {
      final currentLocal = normalizeOptionalLocationName(
        remoteState.currentLocal,
      );
      if (currentLocal != null) {
        return currentLocal;
      }
    }
    return normalizeOptionalLocationName(fallbackLocation);
  }

  static CheckingState applyRemoteState({
    required CheckingState currentState,
    required MobileStateResponse response,
    required String statusMessage,
    required StatusTone tone,
    bool updateStatus = true,
    RegistroType? recentAction,
    String? recentLocal,
  }) {
    final suggestedRegistro = CheckingState.inferSuggestedRegistro(
      lastCheckIn: response.lastCheckInAt,
      lastCheckOut: response.lastCheckOutAt,
      fallback: currentState.registro,
    );
    final remoteLastRecordedAction = resolveLastRecordedAction(response);
    String? nextLastCheckInLocation = currentState.lastCheckInLocation;
    if (recentAction == RegistroType.checkIn) {
      nextLastCheckInLocation = normalizeOptionalLocationName(recentLocal);
    } else if (recentAction == RegistroType.checkOut) {
      nextLastCheckInLocation = null;
    } else if (remoteLastRecordedAction == RegistroType.checkIn) {
      nextLastCheckInLocation = resolveRecordedCheckInLocation(
        response,
        fallbackLocation: currentState.lastCheckInLocation,
      );
    } else if (remoteLastRecordedAction == RegistroType.checkOut) {
      nextLastCheckInLocation = null;
    }

    return currentState.copyWith(
      lastCheckIn: response.lastCheckInAt,
      lastCheckOut: response.lastCheckOutAt,
      lastCheckInLocation: nextLastCheckInLocation,
      registro: suggestedRegistro,
      checkInProjeto: resolveProjeto(response.projeto) ?? currentState.projeto,
      statusMessage: updateStatus ? statusMessage : currentState.statusMessage,
      statusTone: updateStatus ? tone : currentState.statusTone,
    );
  }

  static ProjetoType? resolveProjeto(String? value) {
    return switch (value) {
      'P80' => ProjetoType.p80,
      'P82' => ProjetoType.p82,
      'P83' => ProjetoType.p83,
      _ => null,
    };
  }

  static DateTime resolvePositionTimestamp(Position position) {
    return position.timestamp.toLocal();
  }

  static String? normalizeOptionalLocationName(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static DateTime _toSingaporeTime(DateTime referenceTime) {
    return referenceTime.toUtc().add(singaporeUtcOffset);
  }

  static bool _isDaytimeLocationUpdateWindow(DateTime singaporeTime) {
    return singaporeTime.hour >= daytimeLocationUpdateStartHour &&
        singaporeTime.hour < overnightLocationUpdateStartHour;
  }

  static RegistroType? _parseRemoteAction(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'checkin' => RegistroType.checkIn,
      'checkout' => RegistroType.checkOut,
      _ => null,
    };
  }
}
