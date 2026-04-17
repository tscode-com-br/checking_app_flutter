import 'dart:convert';

import 'package:checking/src/features/checking/models/managed_location.dart';
import 'package:checking/src/features/checking/checking_preset_config.dart';
import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:checking/src/features/checking/models/mobile_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CheckingApiException implements Exception {
  const CheckingApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CheckingStorageService {
  static const _prefsKey = 'checking_flutter_state_v1';
  static const _secureApiSharedKey = 'checking_flutter_api_shared_key';
  static const _prefsApiSharedKeyBackup =
      'checking_flutter_api_shared_key_backup_v1';
  static const _initialAndroidSetupPromptedKey =
      'checking_flutter_initial_android_setup_prompted_v1';

  const CheckingStorageService({
    this.secureStorageEnabled = true,
    this.secureStorage = const FlutterSecureStorage(),
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
    Future<void> Function(String key)? secureDelete,
  }) : _secureRead = secureRead,
       _secureWrite = secureWrite,
       _secureDelete = secureDelete;

  const CheckingStorageService.backgroundSafe({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    Future<String?> Function(String key)? secureRead,
    Future<void> Function(String key, String value)? secureWrite,
    Future<void> Function(String key)? secureDelete,
  }) : this(
         secureStorageEnabled: false,
         secureStorage: secureStorage,
         secureRead: secureRead,
         secureWrite: secureWrite,
         secureDelete: secureDelete,
       );

  final bool secureStorageEnabled;
  final FlutterSecureStorage secureStorage;
  final Future<String?> Function(String key)? _secureRead;
  final Future<void> Function(String key, String value)? _secureWrite;
  final Future<void> Function(String key)? _secureDelete;

  Future<CheckingState> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final secureKey = secureStorageEnabled
        ? (await _readSecureValue(_secureApiSharedKey)).trim()
        : '';
    final prefsBackupKey = (prefs.getString(_prefsApiSharedKeyBackup) ?? '')
        .trim();
    if (secureStorageEnabled &&
        secureKey.isNotEmpty &&
        secureKey != prefsBackupKey) {
      await prefs.setString(_prefsApiSharedKeyBackup, secureKey);
    }
    final resolvedSharedKey = secureKey.isNotEmpty
        ? secureKey
        : prefsBackupKey.isNotEmpty
        ? prefsBackupKey
        : CheckingPresetConfig.apiSharedKey;
    if (raw == null || raw.isEmpty) {
      return CheckingState.initial().copyWith(
        apiSharedKey: resolvedSharedKey,
        isLoading: false,
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException(
          'Persisted checking state must be a JSON object.',
        );
      }

      final parsed = Map<String, dynamic>.from(decoded);
      final restoredState = CheckingState.fromJson(parsed);
      return restoredState.copyWith(
        chave: CheckingState.sanitizeChave(restoredState.chave),
        apiBaseUrl: restoredState.apiBaseUrl.trim().isNotEmpty
            ? restoredState.apiBaseUrl
            : CheckingPresetConfig.apiBaseUrl,
        apiSharedKey: resolvedSharedKey,
        isLoading: false,
      );
    } catch (_) {
      return CheckingState.initial().copyWith(
        apiSharedKey: resolvedSharedKey,
        isLoading: false,
      );
    }
  }

  Future<void> saveState(CheckingState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));

    final secureValue = state.apiSharedKey.trim();
    if (secureValue.isEmpty) {
      await prefs.remove(_prefsApiSharedKeyBackup);
      if (!secureStorageEnabled) {
        return;
      }
      await _deleteSecureValue(_secureApiSharedKey);
    } else {
      await prefs.setString(_prefsApiSharedKeyBackup, secureValue);
      if (!secureStorageEnabled) {
        return;
      }
      await _writeSecureValue(_secureApiSharedKey, secureValue);
    }
  }

  Future<String> _readSecureValue(String key) async {
    try {
      final secureRead = _secureRead;
      final value = secureRead != null
          ? await secureRead(key)
          : await secureStorage.read(key: key);
      return (value ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _writeSecureValue(String key, String value) async {
    try {
      final secureWrite = _secureWrite;
      if (secureWrite != null) {
        await secureWrite(key, value);
        return;
      }
      await secureStorage.write(key: key, value: value);
    } catch (_) {
      // A cópia em SharedPreferences mantém o serviço de background funcional.
    }
  }

  Future<void> _deleteSecureValue(String key) async {
    try {
      final secureDelete = _secureDelete;
      if (secureDelete != null) {
        await secureDelete(key);
        return;
      }
      await secureStorage.delete(key: key);
    } catch (_) {
      // A limpeza em SharedPreferences já evita estado inconsistente.
    }
  }

  Future<bool> hasPromptedInitialAndroidSetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_initialAndroidSetupPromptedKey) ?? false;
  }

  Future<void> markInitialAndroidSetupPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_initialAndroidSetupPromptedKey, true);
  }
}

class CheckingApiService {
  CheckingApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MobileStateResponse> fetchState({
    required String baseUrl,
    required String sharedKey,
    required String chave,
  }) async {
    final candidates = _candidateBaseUrls(baseUrl);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final response = await _client.get(
          Uri.parse(
            '$candidate/api/mobile/state?chave=${Uri.encodeQueryComponent(chave)}',
          ),
          headers: _headers(sharedKey),
        );

        final payload = _decode(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CheckingApiException(_extractMessage(payload, response));
        }
        return MobileStateResponse.fromJson(payload);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is CheckingApiException) {
      throw lastError;
    }
    throw const CheckingApiException('Falha ao consultar a API.');
  }

  Future<MobileSubmitResponse> submitEvent({
    required String baseUrl,
    required String sharedKey,
    required String chave,
    required String projeto,
    required String action,
    required String informe,
    required String clientEventId,
    required DateTime eventTime,
    String? local,
  }) async {
    final candidates = _candidateBaseUrls(baseUrl);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final requestPayload = <String, dynamic>{
          'chave': chave,
          'projeto': projeto,
          'action': action,
          'informe': informe,
          'client_event_id': clientEventId,
          'event_time': eventTime.toUtc().toIso8601String(),
        };
        if (local != null && local.trim().isNotEmpty) {
          requestPayload['local'] = local.trim();
        }
        final response = await _client.post(
          Uri.parse('$candidate/api/mobile/events/forms-submit'),
          headers: _headers(sharedKey),
          body: jsonEncode(requestPayload),
        );

        final payload = _decode(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CheckingApiException(_extractMessage(payload, response));
        }
        return MobileSubmitResponse.fromJson(payload);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is CheckingApiException) {
      throw lastError;
    }
    throw const CheckingApiException('Falha ao enviar evento pela API.');
  }

  Future<LocationCatalogResponse> fetchLocations({
    required String baseUrl,
    required String sharedKey,
  }) async {
    final candidates = _candidateBaseUrls(baseUrl);
    Object? lastError;

    for (final candidate in candidates) {
      try {
        final response = await _client.get(
          Uri.parse('$candidate/api/mobile/locations'),
          headers: _headers(sharedKey),
        );

        final payload = _decode(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CheckingApiException(_extractMessage(payload, response));
        }
        return LocationCatalogResponse.fromJson(payload);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is CheckingApiException) {
      throw lastError;
    }
    throw const CheckingApiException(
      'Falha ao atualizar as localizações do aplicativo.',
    );
  }

  Map<String, String> _headers(String sharedKey) {
    return <String, String>{
      'Content-Type': 'application/json',
      'x-mobile-shared-key': sharedKey.trim(),
    };
  }

  String _normalizeAndValidateBaseUrl(String rawBaseUrl) {
    final normalized = rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const CheckingApiException('Informe a URL base da API.');
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const CheckingApiException('A URL base da API é inválida.');
    }
    if (uri.scheme != 'https') {
      throw const CheckingApiException('A URL da API deve usar HTTPS.');
    }
    return normalized;
  }

  List<String> _candidateBaseUrls(String rawBaseUrl) {
    final primary = _normalizeAndValidateBaseUrl(rawBaseUrl);
    final candidates = <String>[primary];

    for (final fallback in CheckingPresetConfig.apiBaseUrlFallbacks) {
      final normalizedFallback = fallback.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalizedFallback.isEmpty ||
          candidates.contains(normalizedFallback)) {
        continue;
      }
      final uri = Uri.tryParse(normalizedFallback);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        continue;
      }
      if (uri.scheme != 'https') {
        continue;
      }
      candidates.add(normalizedFallback);
    }

    return candidates;
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'message': decoded.toString()};
    } catch (_) {
      return <String, dynamic>{'message': _fallbackHttpMessage(response)};
    }
  }

  String _extractMessage(Map<String, dynamic> payload, http.Response response) {
    final detail = payload['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail;
    }

    final message = payload['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }

    return _fallbackHttpMessage(response);
  }

  String _fallbackHttpMessage(http.Response response) {
    return switch (response.statusCode) {
      502 => 'API indisponível no momento (502 Bad Gateway).',
      503 => 'API indisponível no momento (503 Service Unavailable).',
      504 => 'API não respondeu a tempo (504 Gateway Timeout).',
      _ => 'Erro ${response.statusCode} ao acessar a API.',
    };
  }
}
