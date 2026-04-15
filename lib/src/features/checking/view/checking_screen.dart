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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CheckingController();
    _controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.flushStatePersistence());
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshAfterEnteringForeground());
      return;
    }

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
                              _Header(onTapGeo: _openLocationAutomationSheet),
                              _HistorySection(state: state),
                              const SizedBox(height: 8),
                              _StatusLabel(state: state),
                              const SizedBox(height: 20),
                              _LabeledField(
                                label: 'Chave Petrobras',
                                child: ChaveInputField(
                                  value: state.chave,
                                  onChanged: _controller.updateChave,
                                  onBlur: _handleChaveInputBlur,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _RadioGroupSelector<RegistroType>(
                                value: state.registro,
                                options: RegistroType.values,
                                labelBuilder: (item) => item.label,
                                onChanged: _controller.updateRegistro,
                              ),
                              const SizedBox(height: 12),
                              _RadioGroupSelector<InformeType>(
                                value: state.informe,
                                options: InformeType.values,
                                labelBuilder: (item) => item.label,
                                onChanged: _controller.updateInforme,
                              ),
                              const SizedBox(height: 12),
                              if (state.registro == RegistroType.checkIn)
                                _RadioGroupSelector<ProjetoType>(
                                  value: state.projeto,
                                  options: ProjetoType.values,
                                  labelBuilder: (item) => item.apiValue,
                                  onChanged: _controller.updateProjeto,
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

  Future<void> _openLocationAutomationSheet() async {
    if (!mounted) return;
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
            final bottomSystemInset = math.max(
              MediaQuery.paddingOf(context).bottom,
              MediaQuery.viewPaddingOf(context).bottom,
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.viewInsetsOf(context).bottom +
                    bottomSystemInset +
                    12,
              ),
              child: _LocationAutomationSheet(
                state: state,
                onClose: () => Navigator.of(sheetContext).maybePop(),
                onLocationSharingChanged: (value) {
                  unawaited(_controller.setLocationSharingEnabled(value));
                },
                onAutomaticCheckingChanged: (value) {
                  unawaited(_controller.setAutomaticCheckInOutEnabled(value));
                },
              ),
            );
          },
        );
      },
    );
  }

  void _handleChaveInputBlur() {
    unawaited(_controller.flushStatePersistence());
  }
}

class ChaveInputField extends StatefulWidget {
  const ChaveInputField({
    required this.value,
    required this.onChanged,
    this.onBlur,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBlur;

  @override
  State<ChaveInputField> createState() => _ChaveInputFieldState();
}

class _ChaveInputFieldState extends State<ChaveInputField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChaveInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus || widget.value == _controller.text) {
      return;
    }
    _setControllerText(widget.value);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLength: 4,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        LengthLimitingTextInputFormatter(4),
      ],
      onTap: _handleTap,
      onTapAlwaysCalled: true,
      decoration: const InputDecoration(
        counterText: '',
        hintText: 'Digite sua chave aqui.',
      ),
    );
  }

  void _handleTextChanged() {
    if (_syncing) {
      return;
    }

    final normalized = _normalizeKey(_controller.text);
    if (normalized != _controller.text) {
      _setControllerText(normalized);
    }
    widget.onChanged(normalized);

    if (normalized.length == 4 && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      widget.onBlur?.call();
    }
  }

  void _handleTap() {
    if (_controller.text.isEmpty) {
      return;
    }

    _setControllerText('');
    widget.onChanged('');
  }

  void _setControllerText(String value) {
    _syncing = true;
    _controller.value = _controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
    _syncing = false;
  }

  String _normalizeKey(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalized.substring(0, math.min(4, normalized.length));
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
  const _Header({required this.onTapGeo});

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
                    icon: Icons.gps_fixed_rounded,
                    onPressed: onTapGeo,
                    semanticLabel: 'Automação por localização',
                    iconColor: AppTheme.primary,
                    iconSize: 22,
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
    this.iconColor = AppTheme.textSoft,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final Color iconColor;
  final double iconSize;

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
            side: _groupOutlineBorderSide(),
            shape: RoundedRectangleBorder(
              borderRadius: _groupOutlineBorderRadius(),
            ),
          ),
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }
}

class _LocationAutomationSheet extends StatelessWidget {
  const _LocationAutomationSheet({
    required this.state,
    required this.onClose,
    required this.onLocationSharingChanged,
    required this.onAutomaticCheckingChanged,
  });

  final CheckingState state;
  final VoidCallback onClose;
  final ValueChanged<bool>? onLocationSharingChanged;
  final ValueChanged<bool>? onAutomaticCheckingChanged;

  @override
  Widget build(BuildContext context) {
    final lastUpdateText = state.lastLocationUpdateAt == null
        ? '--'
        : DateFormat('dd-MM-yyyy HH:mm:ss').format(state.lastLocationUpdateAt!);
    final locationUpdateIntervalText =
        CheckingController.describeLocationUpdateInterval(
          referenceTime: DateTime.now(),
        );
    final capturedLocation = state.lastDetectedLocation?.trim();

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                'Automação por Localização',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              _SwitchRow(
                label: 'Busca por Localização:',
                value: state.locationSharingEnabled,
                onChanged:
                    CheckingController.isLocationSharingToggleInteractive(
                      state: state,
                    )
                    ? onLocationSharingChanged
                    : null,
              ),
              const SizedBox(height: 12),
              _SwitchRow(
                label: 'Check-in/Check-out Automáticos:',
                value: CheckingController.isAutomaticCheckingEnabledInUi(
                  state: state,
                ),
                isBusy: state.isAutomaticCheckingUpdating,
                onChanged:
                    CheckingController.isAutomaticCheckingToggleInteractive(
                      state: state,
                    )
                    ? onAutomaticCheckingChanged
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Última Atualização:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lastUpdateText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Atualizações:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationUpdateIntervalText,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _CapturedLocationCard(locationName: capturedLocation),
              const SizedBox(height: 16),
              _DangerCloseButton(onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerCloseButton extends StatelessWidget {
  const _DangerCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: AppTheme.error,
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.error),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Fechar'),
    );
  }
}

class _CapturedLocationCard extends StatelessWidget {
  const _CapturedLocationCard({required this.locationName});

  final String? locationName;

  @override
  Widget build(BuildContext context) {
    final hasLocation = locationName != null && locationName!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _groupOutlineDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Local Capturado',
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasLocation ? locationName! : '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: hasLocation ? AppTheme.success : AppTheme.textSoft,
            ),
          ),
        ],
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
    return DecoratedBox(
      decoration: _groupOutlineDecoration(),
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
        const groupPadding = 8.0;
        final availableWidth = math.max(
          0.0,
          constraints.maxWidth - (groupPadding * 2),
        );
        final itemWidth =
            ((availableWidth - (spacing * (options.length - 1))) /
                    options.length)
                .clamp(0, double.infinity)
                .toDouble();

        return DecoratedBox(
          decoration: _groupOutlineDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(groupPadding),
            child: RadioGroup<T>(
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
            ),
          ),
        );
      },
    );
  }
}

BorderRadius _groupOutlineBorderRadius() {
  return BorderRadius.circular(12);
}

BorderSide _groupOutlineBorderSide() {
  return BorderSide(color: AppTheme.border.withValues(alpha: 0.72), width: 0.9);
}

BoxDecoration _groupOutlineDecoration() {
  return BoxDecoration(
    color: AppTheme.surface,
    borderRadius: _groupOutlineBorderRadius(),
    border: Border.fromBorderSide(_groupOutlineBorderSide()),
  );
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
    this.isBusy = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isBusy;

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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isBusy
              ? const SizedBox(
                  key: ValueKey('switch-loading'),
                  width: 30,
                  height: 30,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppTheme.primary,
                    ),
                  ),
                )
              : Switch(
                  key: ValueKey<bool>(value),
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AppTheme.primary,
                ),
        ),
      ],
    );
  }
}
