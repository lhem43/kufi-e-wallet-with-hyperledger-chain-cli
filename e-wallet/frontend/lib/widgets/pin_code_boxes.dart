import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class PinCodeBoxes extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final bool enabled;
  final String label;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  const PinCodeBoxes({
    super.key,
    required this.controller,
    this.length = 6,
    this.autofocus = false,
    this.enabled = true,
    this.label = '',
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onCompleted,
  }) : assert(length > 0 && length <= 10);

  @override
  State<PinCodeBoxes> createState() => _PinCodeBoxesState();
}

class _PinCodeBoxesState extends State<PinCodeBoxes> {
  final FocusNode _focusNode = FocusNode();
  String _lastNotifiedValue = '';

  bool get _hasError => (widget.errorText ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _lastNotifiedValue = _sanitize(widget.controller.text);
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
    if (widget.autofocus && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant PinCodeBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastNotifiedValue = _sanitize(widget.controller.text);
    }
    if (oldWidget.enabled && !widget.enabled && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _sanitize(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= widget.length) {
      return digits;
    }
    return digits.substring(0, widget.length);
  }

  void _onControllerChanged() {
    final sanitized = _sanitize(widget.controller.text);
    if (sanitized != widget.controller.text) {
      widget.controller.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
      return;
    }

    if (_lastNotifiedValue == sanitized) {
      return;
    }
    _lastNotifiedValue = sanitized;
    widget.onChanged?.call(sanitized);
    if (sanitized.length == widget.length) {
      widget.onCompleted?.call(sanitized);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _sanitize(widget.controller.text);
    final hasFocus = _focusNode.hasFocus;
    final activeIndex = value.length >= widget.length
        ? widget.length - 1
        : value.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: AppColors.ink700,
                fontWeight: FontWeight.w700,
                fontFamily: 'BeVietnamPro',
              ),
            ),
          ),
        GestureDetector(
          onTap: widget.enabled ? _focusNode.requestFocus : null,
          behavior: HitTestBehavior.opaque,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const maxBoxWidth = 58.0;
              const minBoxWidth = 20.0;
              const minSpacing = 2.0;

              var spacing = 8.0;
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : (widget.length * 48.0) + ((widget.length - 1) * spacing);

              var boxWidth =
                  (maxWidth - ((widget.length - 1) * spacing)) / widget.length;
              if (boxWidth < minBoxWidth && widget.length > 1) {
                final adjustedSpacing =
                    (maxWidth - (minBoxWidth * widget.length)) /
                    (widget.length - 1);
                spacing = math.max(minSpacing, adjustedSpacing);
                boxWidth =
                    (maxWidth - ((widget.length - 1) * spacing)) /
                    widget.length;
              }
              final clampedBoxWidth = boxWidth
                  .clamp(minBoxWidth, maxBoxWidth)
                  .toDouble();

              return Row(
                mainAxisSize: MainAxisSize.max,
                children: List.generate(widget.length, (index) {
                  final isActive =
                      hasFocus && widget.enabled && index == activeIndex;
                  final isFilled = index < value.length;

                  Color borderColor = AppColors.violet200;
                  if (_hasError) {
                    borderColor = AppColors.danger;
                  } else if (isActive) {
                    borderColor = AppColors.momoPink;
                  } else if (isFilled) {
                    borderColor = AppColors.violet300;
                  }

                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == widget.length - 1 ? 0 : spacing,
                    ),
                    child: SizedBox(
                      width: clampedBoxWidth,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: borderColor,
                            width: isActive ? 2 : 1.25,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0x281F1B2D,
                              ).withValues(alpha: isActive ? 0.18 : 0.1),
                              blurRadius: isActive ? 14 : 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: isFilled
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.ink700,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : (isActive
                                    ? Container(
                                        width: 2,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: AppColors.momoPink,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      )
                                    : null),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        SizedBox(
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                enableInteractiveSelection: false,
                showCursor: false,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(
                  fontSize: 1,
                  color: Colors.transparent,
                  height: 1,
                ),
                textInputAction: TextInputAction.done,
              ),
            ),
          ),
        ),
        if (!_hasError && (widget.helperText ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 6),
            child: Text(
              widget.helperText!,
              style: const TextStyle(
                color: AppColors.ink500,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_hasError)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 6),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class PinCodeBoxesFormField extends FormField<String> {
  PinCodeBoxesFormField({
    super.key,
    required TextEditingController controller,
    int length = 6,
    bool autofocus = false,
    bool enabled = true,
    String label = '',
    String? helperText,
    super.validator,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onCompleted,
    AutovalidateMode autovalidateMode = AutovalidateMode.disabled,
  }) : super(
         initialValue: controller.text,
         autovalidateMode: autovalidateMode,
         builder: (state) {
           return PinCodeBoxes(
             controller: controller,
             length: length,
             autofocus: autofocus,
             enabled: enabled,
             label: label,
             helperText: helperText,
             errorText: state.errorText,
             onChanged: (value) {
               state.didChange(value);
               onChanged?.call(value);
             },
             onCompleted: onCompleted,
           );
         },
       );
}
