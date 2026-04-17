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
  static const int maxLocationFetchHistoryEntries =
      LocationFetchEntry.maxStoredEntries;
  static const int minLocationUpdateIntervalMinutes = 15;
  static const int maxLocationUpdateIntervalMinutes = 60;
  static const int defaultLocationUpdateIntervalSeconds = 15 * 60;
  static const int defaultNightPeriodStartMinutes = 22 * 60;
  static const int defaultNightPeriodEndMinutes = 6 * 60;
  static const Duration singaporeUtcOffset = Duration(hours: 8);
  static const int postCheckoutNightModeResumeMinutes = 6 * 60;
  static const String automaticCheckoutLocation = 'Fora do Local de Trabalho';
  static const String outsideWorkplaceCapturedLocation =
      'Fora do Ambiente de Trabalho';
  static const String checkoutZoneCapturedLocation = 'Zona de Check-Out';
  static const String uncatalogedCapturedLocation =
      'Localização não Cadastrada';
  static const String postCheckoutNightModeStatusMessage =
      'Modo noturno após check-out ativo até 06:00 do dia seguinte, no horário de Singapura.';

  static int resolveLocationUpdateIntervalSeconds({
    int? configuredIntervalSeconds,
    DateTime? referenceTime,
  }) {
    return normalizeLocationUpdateIntervalSeconds(
      configuredIntervalSeconds ?? defaultLocationUpdateIntervalSeconds,
    );
  }

  static String describeLocationUpdateInterval({
    int? configuredIntervalSeconds,
    DateTime? referenceTime,
  }) {
    final intervalSeconds = resolveLocationUpdateIntervalSeconds(
      configuredIntervalSeconds: configuredIntervalSeconds,
      referenceTime: referenceTime,
    );
    return '${intervalSeconds ~/ 60} min';
  }

  static CheckingState resolveLocationUpdateIntervalState(
    CheckingState state, {
    DateTime? referenceTime,
  }) {
    final resolvedIntervalSeconds = resolveLocationUpdateIntervalSeconds(
      configuredIntervalSeconds: state.locationUpdateIntervalSeconds,
      referenceTime: referenceTime,
    );
    final normalizedNightPeriodStartMinutes = normalizeMinutesOfDay(
      state.nightPeriodStartMinutes,
      fallbackMinutes: defaultNightPeriodStartMinutes,
    );
    final normalizedNightPeriodEndMinutes = normalizeMinutesOfDay(
      state.nightPeriodEndMinutes,
      fallbackMinutes: defaultNightPeriodEndMinutes,
    );
    final normalizedNightModeAfterCheckoutUntil =
        normalizeNightModeAfterCheckoutUntil(
          state: state,
          referenceTime: referenceTime,
        );
    if (resolvedIntervalSeconds == state.locationUpdateIntervalSeconds &&
        normalizedNightPeriodStartMinutes == state.nightPeriodStartMinutes &&
        normalizedNightPeriodEndMinutes == state.nightPeriodEndMinutes &&
        normalizedNightModeAfterCheckoutUntil ==
            state.nightModeAfterCheckoutUntil) {
      return state;
    }

    return state.copyWith(
      locationUpdateIntervalSeconds: resolvedIntervalSeconds,
      nightPeriodStartMinutes: normalizedNightPeriodStartMinutes,
      nightPeriodEndMinutes: normalizedNightPeriodEndMinutes,
      nightModeAfterCheckoutUntil: normalizedNightModeAfterCheckoutUntil,
    );
  }

  static Duration delayUntilNextLocationUpdateIntervalBoundary({
    required CheckingState state,
    DateTime? referenceTime,
  }) {
    final normalizedNightModeAfterCheckoutUntil =
        normalizeNightModeAfterCheckoutUntil(
          state: state,
          referenceTime: referenceTime,
        );
    if (normalizedNightModeAfterCheckoutUntil != null) {
      final now = referenceTime ?? DateTime.now();
      final delay = normalizedNightModeAfterCheckoutUntil.difference(now);
      if (delay <= Duration.zero) {
        return const Duration(minutes: 1);
      }
      return delay;
    }

    if (state.nightModeAfterCheckoutEnabled) {
      return const Duration(days: 1);
    }

    if (!state.nightUpdatesDisabled ||
        state.nightPeriodStartMinutes == state.nightPeriodEndMinutes) {
      return const Duration(days: 1);
    }

    final now = referenceTime ?? DateTime.now();
    final nextBoundary = resolveNextNightPeriodBoundary(
      referenceTime: now,
      startMinutes: state.nightPeriodStartMinutes,
      endMinutes: state.nightPeriodEndMinutes,
    );
    if (nextBoundary == null) {
      return const Duration(days: 1);
    }

    final delay = nextBoundary.difference(now);
    if (delay <= Duration.zero) {
      return const Duration(minutes: 1);
    }
    return delay;
  }

  static int normalizeLocationUpdateIntervalSeconds(int seconds) {
    final normalizedMinutes = ((seconds / 60).round()).clamp(
      minLocationUpdateIntervalMinutes,
      maxLocationUpdateIntervalMinutes,
    );
    return normalizedMinutes * 60;
  }

  static int normalizeMinutesOfDay(
    int minutes, {
    required int fallbackMinutes,
  }) {
    const minutesPerDay = 24 * 60;
    final normalized = minutes % minutesPerDay;
    return normalized < 0 ? normalized + minutesPerDay : normalized;
  }

  static bool isNightPeriodActive({
    required CheckingState state,
    DateTime? referenceTime,
  }) {
    if (state.nightModeAfterCheckoutEnabled) {
      return false;
    }

    if (!state.nightUpdatesDisabled ||
        state.nightPeriodStartMinutes == state.nightPeriodEndMinutes) {
      return false;
    }

    final now = referenceTime ?? DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = normalizeMinutesOfDay(
      state.nightPeriodStartMinutes,
      fallbackMinutes: defaultNightPeriodStartMinutes,
    );
    final endMinutes = normalizeMinutesOfDay(
      state.nightPeriodEndMinutes,
      fallbackMinutes: defaultNightPeriodEndMinutes,
    );
    if (startMinutes < endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }

  static DateTime? resolveNextNightPeriodBoundary({
    required DateTime referenceTime,
    required int startMinutes,
    required int endMinutes,
  }) {
    final normalizedStartMinutes = normalizeMinutesOfDay(
      startMinutes,
      fallbackMinutes: defaultNightPeriodStartMinutes,
    );
    final normalizedEndMinutes = normalizeMinutesOfDay(
      endMinutes,
      fallbackMinutes: defaultNightPeriodEndMinutes,
    );
    if (normalizedStartMinutes == normalizedEndMinutes) {
      return null;
    }

    final today = DateTime(
      referenceTime.year,
      referenceTime.month,
      referenceTime.day,
    );
    final currentMinutes = referenceTime.hour * 60 + referenceTime.minute;
    final startToday = today.add(Duration(minutes: normalizedStartMinutes));
    final endToday = today.add(Duration(minutes: normalizedEndMinutes));
    final spansMidnight = normalizedStartMinutes > normalizedEndMinutes;
    if (!spansMidnight) {
      return currentMinutes < normalizedStartMinutes
          ? startToday
          : currentMinutes < normalizedEndMinutes
          ? endToday
          : startToday.add(const Duration(days: 1));
    }

    if (currentMinutes >= normalizedStartMinutes) {
      return endToday.add(const Duration(days: 1));
    }
    if (currentMinutes < normalizedEndMinutes) {
      return endToday;
    }
    return startToday;
  }

  static bool shouldRunBackgroundActivityNow({
    required CheckingState state,
    DateTime? referenceTime,
  }) {
    if (isNightModeAfterCheckoutActive(
      state: state,
      referenceTime: referenceTime,
    )) {
      return false;
    }

    if (state.nightModeAfterCheckoutEnabled) {
      return true;
    }

    return !isNightPeriodActive(state: state, referenceTime: referenceTime);
  }

  static DateTime resolveNightModeAfterCheckoutUntil({
    required DateTime checkoutTime,
  }) {
    final checkoutTimeInSingapore = checkoutTime.toUtc().add(
      singaporeUtcOffset,
    );
    final nextDayAtSixInSingapore = DateTime.utc(
      checkoutTimeInSingapore.year,
      checkoutTimeInSingapore.month,
      checkoutTimeInSingapore.day,
    ).add(const Duration(days: 1, hours: 6));
    return nextDayAtSixInSingapore.subtract(singaporeUtcOffset).toLocal();
  }

  static DateTime? normalizeNightModeAfterCheckoutUntil({
    required CheckingState state,
    DateTime? referenceTime,
  }) {
    if (!state.nightModeAfterCheckoutEnabled) {
      return null;
    }

    final nightModeAfterCheckoutUntil = state.nightModeAfterCheckoutUntil;
    if (nightModeAfterCheckoutUntil == null) {
      return null;
    }

    final now = referenceTime ?? DateTime.now();
    if (!nightModeAfterCheckoutUntil.isAfter(now)) {
      return null;
    }
    return nightModeAfterCheckoutUntil;
  }

  static bool isNightModeAfterCheckoutActive({
    required CheckingState state,
    DateTime? referenceTime,
  }) {
    return normalizeNightModeAfterCheckoutUntil(
          state: state,
          referenceTime: referenceTime,
        ) !=
        null;
  }

  static DateTime? resolveNightModeAfterCheckoutUntilForAction({
    required CheckingState currentState,
    required RegistroType? effectiveLastAction,
    required DateTime? lastCheckOut,
    DateTime? referenceTime,
  }) {
    if (!currentState.nightModeAfterCheckoutEnabled) {
      return null;
    }

    final now = referenceTime ?? DateTime.now();
    if (effectiveLastAction == RegistroType.checkOut && lastCheckOut != null) {
      final nightModeAfterCheckoutUntil = resolveNightModeAfterCheckoutUntil(
        checkoutTime: lastCheckOut,
      );
      return nightModeAfterCheckoutUntil.isAfter(now)
          ? nightModeAfterCheckoutUntil
          : null;
    }

    if (effectiveLastAction == RegistroType.checkIn) {
      return null;
    }

    final existingNightModeAfterCheckoutUntil =
        currentState.nightModeAfterCheckoutUntil;
    if (existingNightModeAfterCheckoutUntil == null ||
        !existingNightModeAfterCheckoutUntil.isAfter(now)) {
      return null;
    }
    return existingNightModeAfterCheckoutUntil;
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

  static RegistroType? resolveAutomaticActionWithoutLocationMatch({
    required MobileStateResponse remoteState,
    required double? nearestDistanceMeters,
    required bool autoCheckInEnabled,
    required bool autoCheckOutEnabled,
  }) {
    final outOfRangeAction = resolveAutomaticActionOutOfRange(
      remoteState: remoteState,
      nearestDistanceMeters: nearestDistanceMeters,
      autoCheckOutEnabled: autoCheckOutEnabled,
    );
    if (outOfRangeAction != null) {
      return outOfRangeAction;
    }

    return shouldAttemptAutomaticNearbyWorkplaceCheckIn(
          lastRecordedAction: resolveLastRecordedAction(remoteState),
          nearestDistanceMeters: nearestDistanceMeters,
          autoCheckInEnabled: autoCheckInEnabled,
        )
        ? RegistroType.checkIn
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

  static bool shouldAttemptAutomaticNearbyWorkplaceCheckIn({
    required RegistroType? lastRecordedAction,
    required double? nearestDistanceMeters,
    required bool autoCheckInEnabled,
  }) {
    if (!autoCheckInEnabled ||
        nearestDistanceMeters == null ||
        nearestDistanceMeters > outOfRangeCheckoutDistanceMeters) {
      return false;
    }
    return lastRecordedAction != RegistroType.checkIn;
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

    return location?.local ?? uncatalogedCapturedLocation;
  }

  static String? resolveCapturedLocationLabel({
    ManagedLocation? location,
    double? nearestWorkplaceDistanceMeters,
  }) {
    if (location == null) {
      if (nearestWorkplaceDistanceMeters == null) {
        return null;
      }
      if (nearestWorkplaceDistanceMeters > outOfRangeCheckoutDistanceMeters) {
        return outsideWorkplaceCapturedLocation;
      }
      return uncatalogedCapturedLocation;
    }
    if (location.isCheckoutZone) {
      return checkoutZoneCapturedLocation;
    }
    return location.local;
  }

  static List<LocationFetchEntry> recordLocationFetchHistory({
    required List<LocationFetchEntry> history,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    int maxEntries = maxLocationFetchHistoryEntries,
  }) {
    final effectiveMaxEntries = max(1, maxEntries);
    return LocationFetchEntry.normalizeHistory(<LocationFetchEntry>[
      LocationFetchEntry(
        timestamp: timestamp.toLocal(),
        latitude: latitude,
        longitude: longitude,
      ),
      ...history,
    ], maxEntries: effectiveMaxEntries);
  }

  static bool shouldSkipDuplicateLocationFetch({
    required List<LocationFetchEntry> history,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
  }) {
    if (history.isEmpty) {
      return false;
    }

    return LocationFetchEntry(
      timestamp: timestamp.toLocal(),
      latitude: latitude,
      longitude: longitude,
    ).isDuplicateOf(history.first);
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
    final nextNightModeAfterCheckoutUntil =
        resolveNightModeAfterCheckoutUntilForAction(
          currentState: currentState,
          effectiveLastAction: recentAction ?? remoteLastRecordedAction,
          lastCheckOut: response.lastCheckOutAt,
        );

    return currentState.copyWith(
      lastCheckIn: response.lastCheckInAt,
      lastCheckOut: response.lastCheckOutAt,
      lastCheckInLocation: nextLastCheckInLocation,
      nightModeAfterCheckoutUntil: nextNightModeAfterCheckoutUntil,
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

  static RegistroType? _parseRemoteAction(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'checkin' => RegistroType.checkIn,
      'checkout' => RegistroType.checkOut,
      _ => null,
    };
  }
}
