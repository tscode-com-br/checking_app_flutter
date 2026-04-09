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

  const CheckingStorageService({
    this.secureStorage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage secureStorage;

  Future<CheckingState> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final secureKey = (await secureStorage.read(key: _secureApiSharedKey) ?? '')
        .trim();
    final resolvedSharedKey = secureKey.isNotEmpty
        ? secureKey
        : CheckingPresetConfig.apiSharedKey;
    if (raw == null || raw.isEmpty) {
      return CheckingState.initial().copyWith(
        apiSharedKey: resolvedSharedKey,
        isLoading: false,
      );
    }

    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    final restoredState = CheckingState.fromJson(parsed);
    return restoredState.copyWith(
      chave: CheckingState.sanitizeChave(restoredState.chave),
      apiBaseUrl: restoredState.apiBaseUrl.trim().isNotEmpty
          ? restoredState.apiBaseUrl
          : CheckingPresetConfig.apiBaseUrl,
      apiSharedKey: resolvedSharedKey,
      isLoading: false,
    );
  }

  Future<void> saveState(CheckingState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));

    final secureValue = state.apiSharedKey.trim();
    if (secureValue.isEmpty) {
      await secureStorage.delete(key: _secureApiSharedKey);
    } else {
      await secureStorage.write(key: _secureApiSharedKey, value: secureValue);
    }
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
