import 'dart:async';
import 'dart:math' as math;

import 'package:checking/src/core/theme/app_theme.dart';
import 'package:checking/src/features/checking/controller/checking_controller.dart';
import 'package:checking/src/features/checking/models/checking_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CheckingScreen extends StatefulWidget {
  const CheckingScreen({super.key});

  @override
  State<CheckingScreen> createState() => _CheckingScreenState();
}

class _CheckingScreenState extends State<CheckingScreen>
    with WidgetsBindingObserver {
  late final CheckingController _controller;
  late final TextEditingController _chaveController;
  late final FocusNode _chaveFocusNode;
  bool _syncingTextFields = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CheckingController()..addListener(_syncTextFields);
    _chaveController = TextEditingController();
    _chaveFocusNode = FocusNode();
    _chaveFocusNode.addListener(_handleChaveFocusChanged);

    _chaveController.addListener(() {
      if (_syncingTextFields) return;
      final normalized = _normalizeKey(_chaveController.text);
      if (normalized != _chaveController.text) {
        _replaceControllerText(_chaveController, normalized);
      }
      _controller.updateChave(normalized);
    });
    _controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chaveFocusNode.removeListener(_handleChaveFocusChanged);
    unawaited(_controller.flushStatePersistence());
    _controller.removeListener(_syncTextFields);
    _controller.dispose();
    _chaveController.dispose();
    _chaveFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.flushStatePersistence());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final state = _controller.state;
            final bottomPadding = math.max(
              36.0,
              MediaQuery.paddingOf(context).bottom + 28,
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, bottomPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _TopLogo(),
                              const SizedBox(height: 20),
                              _Header(
                                hasSchedule: state.hasAnySchedule,
                                onTapSettings: _controller.toggleSettingsPanel,
                                onTapGeo: _openLocationAutomationSheet,
                              ),
                              if (state.settingsPanelOpen)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 24),
                                  child: _SettingsPanel(
                                    state: state,
                                    onClose: _controller.toggleSettingsPanel,
                                    onScheduleInChanged:
                                        _controller.setScheduleInEnabled,
                                    onScheduleOutChanged:
                                        _controller.setScheduleOutEnabled,
                                    onScheduleDayChanged:
                                        _controller.setScheduleDay,
                                    onSyncNow: _handleSyncNow,
                                    onPickScheduleInTime: () => _pickTime(
                                      state.scheduleInTime,
                                      _controller.setScheduleInTime,
                                    ),
                                    onPickScheduleOutTime: () => _pickTime(
                                      state.scheduleOutTime,
                                      _controller.setScheduleOutTime,
                                    ),
                                  ),
                                ),
                              _HistorySection(state: state),
                              const SizedBox(height: 8),
                              _StatusLabel(state: state),
                              const SizedBox(height: 20),
                              _LabeledField(
                                label: 'Chave Petrobras',
                                child: TextField(
                                  controller: _chaveController,
                                  focusNode: _chaveFocusNode,
                                  maxLength: 4,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z0-9]'),
                                    ),
                                    LengthLimitingTextInputFormatter(4),
                                  ],
                                  decoration: const InputDecoration(
                                    counterText: '',
                                    hintText: 'SRGE',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LabeledField(
                                label: 'Ação',
                                child: _RadioGroupSelector<RegistroType>(
                                  value: state.registro,
                                  options: RegistroType.values,
                                  labelBuilder: (item) => item.label,
                                  onChanged: _controller.updateRegistro,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _LabeledField(
                                label: 'Informe',
                                child: _RadioGroupSelector<InformeType>(
                                  value: state.informe,
                                  options: InformeType.values,
                                  labelBuilder: (item) => item.label,
                                  onChanged: _controller.updateInforme,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (state.registro == RegistroType.checkIn)
                                _LabeledField(
                                  label: 'Projeto',
                                  child: _RadioGroupSelector<ProjetoType>(
                                    value: state.projeto,
                                    options: ProjetoType.values,
                                    labelBuilder: (item) => item.apiValue,
                                    onChanged: _controller.updateProjeto,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: state.isSubmitting ? null : _handleSubmit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        child: state.isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('REGISTRAR'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    try {
      final message = await _controller.submitCurrent();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _handleSyncNow() async {
    try {
      final message = await _controller.syncHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openLocationAutomationSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final state = _controller.state;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.viewInsetsOf(context).bottom + 12,
              ),
              child: _LocationAutomationSheet(
                state: state,
                onClose: () => Navigator.of(sheetContext).maybePop(),
                onLocationSharingChanged: (value) {
                  unawaited(_controller.setLocationSharingEnabled(value));
                },
                onAutoCheckInChanged: (value) {
                  unawaited(_controller.setAutoCheckInEnabled(value));
                },
                onAutoCheckOutChanged: (value) {
                  unawaited(_controller.setAutoCheckOutEnabled(value));
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickTime(
    String currentValue,
    ValueChanged<String> onChanged,
  ) async {
    final parsed = _parseTime(currentValue);
    final picked = await showTimePicker(context: context, initialTime: parsed);
    if (picked == null) return;
    onChanged(_formatTime(picked));
  }

  void _syncTextFields() {
    if (!mounted) return;
    final state = _controller.state;
    _syncingTextFields = true;
    _replaceControllerText(
      _chaveController,
      state.chave,
      focusNode: _chaveFocusNode,
    );
    _syncingTextFields = false;
  }

  void _handleChaveFocusChanged() {
    if (!_chaveFocusNode.hasFocus) {
      unawaited(_controller.flushStatePersistence());
    }
  }

  void _replaceControllerText(
    TextEditingController controller,
    String nextValue, {
    FocusNode? focusNode,
  }) {
    if (controller.text == nextValue) return;
    if (focusNode?.hasFocus ?? false) return;
    controller.value = controller.value.copyWith(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
      composing: TextRange.empty,
    );
  }

  String _normalizeKey(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.substring(0, math.min(4, normalized.length));
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 7, minute: 45);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: int.tryParse(parts[1]) ?? 45,
    );
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _TopLogo extends StatelessWidget {
  const _TopLogo();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * 0.82,
              maxHeight: 90,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ColoredBox(
                color: Colors.white,
                child: Image.asset('assets/app_icon.png', fit: BoxFit.none),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hasSchedule,
    required this.onTapSettings,
    required this.onTapGeo,
  });

  final bool hasSchedule;
  final VoidCallback onTapSettings;
  final VoidCallback onTapGeo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Checking',
                  style: textTheme.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  _HeaderIconButton(
                    icon: hasSchedule
                        ? Icons.event_available_outlined
                        : Icons.event_busy_outlined,
                    onPressed: onTapSettings,
                    semanticLabel: 'Abrir agendamento',
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.location_on_outlined,
                    onPressed: onTapGeo,
                    semanticLabel: 'Localização',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'TBY - Autodeclaração de Presença.',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: AppTheme.surface,
            side: const BorderSide(color: AppTheme.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Icon(icon, color: AppTheme.textSoft, size: 20),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.state,
    required this.onClose,
    required this.onScheduleInChanged,
    required this.onScheduleOutChanged,
    required this.onScheduleDayChanged,
    required this.onSyncNow,
    required this.onPickScheduleInTime,
    required this.onPickScheduleOutTime,
  });

  final CheckingState state;
  final VoidCallback onClose;
  final ValueChanged<bool> onScheduleInChanged;
  final ValueChanged<bool> onScheduleOutChanged;
  final void Function(int day, bool selected) onScheduleDayChanged;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onPickScheduleInTime;
  final Future<void> Function() onPickScheduleOutTime;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agendamento',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text('Dias da semana', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(7, (index) {
              const labels = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
              final selected = state.scheduleDays.contains(index);
              return FilterChip(
                label: Text(labels[index]),
                selected: selected,
                onSelected: (value) => onScheduleDayChanged(index, value),
                selectedColor: AppTheme.primary,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.textSoft,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: const Color(0xFFEBEBEB),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          _SwitchRow(
            label: 'Agendar Check-In',
            value: state.scheduleInEnabled,
            onChanged: onScheduleInChanged,
          ),
          const SizedBox(height: 8),
          _TimeButton(
            label: 'Horário da notificação (Check-In)',
            value: state.scheduleInTime,
            onTap: onPickScheduleInTime,
          ),
          const SizedBox(height: 8),
          _PreviewCard(
            title: 'Dados usados no Check-In',
            lines: [
              'Chave: ${state.chave.isEmpty ? '--' : state.chave}',
              'Informe: ${state.informeFor(RegistroType.checkIn).label}',
              'Projeto: ${state.projeto.apiValue}',
            ],
          ),
          const SizedBox(height: 16),
          _SwitchRow(
            label: 'Agendar Check-Out',
            value: state.scheduleOutEnabled,
            onChanged: onScheduleOutChanged,
          ),
          const SizedBox(height: 8),
          _TimeButton(
            label: 'Horário da notificação (Check-Out)',
            value: state.scheduleOutTime,
            onTap: onPickScheduleOutTime,
          ),
          const SizedBox(height: 8),
          _PreviewCard(
            title: 'Dados usados no Check-Out',
            lines: [
              'Chave: ${state.chave.isEmpty ? '--' : state.chave}',
              'Informe: ${state.informeFor(RegistroType.checkOut).label}',
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          Text(
            'Integração com a API',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppTheme.textMain),
          ),
          const SizedBox(height: 12),
          _PreviewCard(
            title: 'Configuração interna do aplicativo',
            lines: [
              'API já configurada no aplicativo.',
              'Endpoint principal: ${state.apiBaseUrl}',
              'A chave compartilhada não precisa ser informada pelo usuário.',
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A sincronização do último Check-In e Check-Out usa a configuração embutida do aplicativo.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textSoft),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: state.isSyncing ? null : () => onSyncNow(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: state.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sincronizar agora'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onClose,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              side: const BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

class _LocationAutomationSheet extends StatelessWidget {
  const _LocationAutomationSheet({
    required this.state,
    required this.onClose,
    required this.onLocationSharingChanged,
    required this.onAutoCheckInChanged,
    required this.onAutoCheckOutChanged,
  });

  final CheckingState state;
  final VoidCallback onClose;
  final ValueChanged<bool>? onLocationSharingChanged;
  final ValueChanged<bool>? onAutoCheckInChanged;
  final ValueChanged<bool>? onAutoCheckOutChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Automatização por Localização',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _SwitchRow(
              label: 'Compartilhar Localização',
              value: state.locationSharingEnabled,
              onChanged: state.isLocationUpdating
                  ? null
                  : onLocationSharingChanged,
            ),
            const SizedBox(height: 8),
            _SwitchRow(
              label: 'Check-In Automático',
              value: state.autoCheckInEnabled,
              onChanged:
                  !state.locationSharingEnabled || state.isLocationUpdating
                  ? null
                  : onAutoCheckInChanged,
            ),
            const SizedBox(height: 8),
            _SwitchRow(
              label: 'Check-Out Automático',
              value: state.autoCheckOutEnabled,
              onChanged:
                  !state.locationSharingEnabled || state.isLocationUpdating
                  ? null
                  : onAutoCheckOutChanged,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.state});

  final CheckingState state;

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd/MM/yyyy');
    final timeFormatter = DateFormat('HH:mm:ss');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _HistoryItem(
                label: 'Último Check-In',
                value: state.lastCheckIn == null
                    ? ''
                    : '${dateFormatter.format(state.lastCheckIn!)}\n${timeFormatter.format(state.lastCheckIn!)}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HistoryItem(
                label: 'Último Check-Out',
                value: state.lastCheckOut == null
                    ? ''
                    : '${dateFormatter.format(state.lastCheckOut!)}\n${timeFormatter.format(state.lastCheckOut!)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSoft,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMain,
          ),
          softWrap: true,
        ),
      ],
    );
  }
}

class _RadioGroupSelector<T> extends StatelessWidget {
  const _RadioGroupSelector({
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth =
            ((constraints.maxWidth - (spacing * (options.length - 1))) /
                    options.length)
                .clamp(0, double.infinity)
                .toDouble();

        return RadioGroup<T>(
          groupValue: value,
          onChanged: (nextValue) {
            if (nextValue != null) {
              onChanged(nextValue);
            }
          },
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final option in options)
                SizedBox(
                  width: itemWidth,
                  child: _RadioOptionTile<T>(
                    value: option,
                    selected: option == value,
                    label: labelBuilder(option),
                    onTap: () => onChanged(option),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RadioOptionTile<T> extends StatelessWidget {
  const _RadioOptionTile({
    required this.value,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final T value;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Radio<T>(
              value: value,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppTheme.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textMain,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.state});

  final CheckingState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state.statusTone) {
      StatusTone.success => AppTheme.success,
      StatusTone.warning => AppTheme.warning,
      StatusTone.error => AppTheme.error,
      StatusTone.neutral => AppTheme.textSoft,
    };

    return AnimatedOpacity(
      opacity: state.statusMessage.isEmpty ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      child: Text(
        state.statusMessage,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        child,
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textMain),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.primary,
        ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        InkWell(
          onTap: () => onTap(),
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: AppTheme.textMain),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 2),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                line,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSoft),
              ),
            ),
        ],
      ),
    );
  }
}
