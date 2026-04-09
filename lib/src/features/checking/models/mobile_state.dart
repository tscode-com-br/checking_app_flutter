class MobileStateResponse {
  const MobileStateResponse({
    required this.found,
    required this.chave,
    required this.nome,
    required this.projeto,
    required this.currentAction,
    required this.currentEventTime,
    required this.lastCheckInAt,
    required this.lastCheckOutAt,
  });

  factory MobileStateResponse.fromJson(Map<String, dynamic> json) {
    return MobileStateResponse(
      found: json['found'] as bool? ?? false,
      chave: json['chave'] as String? ?? '',
      nome: json['nome'] as String?,
      projeto: json['projeto'] as String?,
      currentAction: json['current_action'] as String?,
      currentEventTime: _parse(json['current_event_time']),
      lastCheckInAt: _parse(json['last_checkin_at']),
      lastCheckOutAt: _parse(json['last_checkout_at']),
    );
  }

  final bool found;
  final String chave;
  final String? nome;
  final String? projeto;
  final String? currentAction;
  final DateTime? currentEventTime;
  final DateTime? lastCheckInAt;
  final DateTime? lastCheckOutAt;

  static DateTime? _parse(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}

class MobileSubmitResponse {
  const MobileSubmitResponse({
    required this.ok,
    required this.duplicate,
    required this.queuedForms,
    required this.message,
    required this.state,
  });

  factory MobileSubmitResponse.fromJson(Map<String, dynamic> json) {
    return MobileSubmitResponse(
      ok: json['ok'] as bool? ?? false,
      duplicate: json['duplicate'] as bool? ?? false,
      queuedForms: json['queued_forms'] as bool? ?? true,
      message: json['message'] as String? ?? 'Operação processada.',
      state: MobileStateResponse.fromJson(json['state'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
    );
  }

  final bool ok;
  final bool duplicate;
  final bool queuedForms;
  final String message;
  final MobileStateResponse state;
}