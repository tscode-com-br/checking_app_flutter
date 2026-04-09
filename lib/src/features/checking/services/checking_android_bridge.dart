import 'dart:async';

import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CheckingAndroidBridge {
  static const MethodChannel _channel = MethodChannel('checking/android');

  Future<void> initialize({
    required Future<void> Function(String action) onNativeAction,
  }) async {
    if (!_isSupported) {
      return;
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'nativeAction') {
        return null;
      }
      final args =
          (call.arguments as Map<Object?, Object?>?) ??
          const <Object?, Object?>{};
      final action = (args['action'] as String? ?? '').trim();
      if (action.isEmpty) {
        return null;
      }
      await onNativeAction(action);
      return null;
    });

    final pendingAction = await consumePendingNativeAction();
    if (pendingAction != null && pendingAction.isNotEmpty) {
      await onNativeAction(pendingAction);
    }
  }

  Future<String?> consumePendingNativeAction() async {
    if (!_isSupported) {
      return null;
    }
    final result = await _channel.invokeMethod<String>(
      'consumePendingNativeAction',
    );
    final normalized = result?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> syncSchedules(CheckingState state) async {
    if (!_isSupported) {
      return;
    }

    await _channel.invokeMethod<void>('syncSchedules', <String, Object?>{
      'scheduleInEnabled':
          state.hasValidChave && state.hasApiConfig && state.scheduleInEnabled,
      'scheduleInTime': state.scheduleInTime,
      'scheduleOutEnabled':
          state.hasValidChave && state.hasApiConfig && state.scheduleOutEnabled,
      'scheduleOutTime': state.scheduleOutTime,
      'scheduleDays': state.scheduleDays.toList()..sort(),
    });
  }

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
