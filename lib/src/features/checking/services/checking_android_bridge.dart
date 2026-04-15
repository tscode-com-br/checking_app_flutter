import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CheckingOemBackgroundSetupResult {
  const CheckingOemBackgroundSetupResult({
    required this.openedSettings,
    required this.message,
  });

  static const empty = CheckingOemBackgroundSetupResult(
    openedSettings: false,
    message: '',
  );

  factory CheckingOemBackgroundSetupResult.fromMap(
    Map<Object?, Object?>? values,
  ) {
    if (values == null) {
      return empty;
    }

    final map = Map<Object?, Object?>.from(values);
    return CheckingOemBackgroundSetupResult(
      openedSettings: map['openedSettings'] as bool? ?? false,
      message: (map['message'] as String? ?? '').trim(),
    );
  }

  final bool openedSettings;
  final String message;
}

class CheckingAndroidBridge {
  static const MethodChannel _channel = MethodChannel('checking/android');

  bool get isSupported => _isSupported;

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

  Future<void> clearSchedules() async {
    if (!_isSupported) {
      return;
    }

    await _channel.invokeMethod<void>('clearSchedules');
  }

  Future<CheckingOemBackgroundSetupResult> requestOemBackgroundSetup() async {
    if (!_isSupported) {
      return CheckingOemBackgroundSetupResult.empty;
    }

    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'requestOemBackgroundSetup',
      );
      return CheckingOemBackgroundSetupResult.fromMap(result);
    } on MissingPluginException {
      return CheckingOemBackgroundSetupResult.empty;
    } on PlatformException {
      return CheckingOemBackgroundSetupResult.empty;
    }
  }

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
