import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Labelled square-cornered field from the mock-ups. [obscure] adds the
/// show/hide eye; [trailingLabel] sits on the label row (e.g. "¿Olvidaste…?").
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.trailingLabel,
    this.onSubmitted,
    this.enabled = true,
    this.inputFormatters,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.style,
    this.prefixText,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? trailingLabel;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final TextAlign textAlign;
  final TextStyle? style;

  /// Fixed text before the value (e.g. "C-" in front of a serial number).
  final String? prefixText;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: AppRadius.medium,
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                widget.label.toUpperCase(),
                style: AppTheme.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.trailingLabel != null) ...[
              const SizedBox(width: 12),
              Flexible(child: widget.trailingLabel!),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: _hidden,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: widget.onSubmitted,
          inputFormatters: widget.inputFormatters,
          maxLength: widget.maxLength,
          textAlign: widget.textAlign,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: widget.style ?? const TextStyle(fontSize: 17, color: AppColors.ink),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixText: widget.prefixText,
            prefixStyle: widget.style ?? const TextStyle(fontSize: 17, color: AppColors.ink),
            hintStyle: const TextStyle(fontSize: 17, color: AppColors.hint),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            enabledBorder: _border(AppColors.border),
            disabledBorder: _border(AppColors.border),
            focusedBorder: _border(AppColors.blue, 1.5),
            errorBorder: _border(AppColors.error),
            focusedErrorBorder: _border(AppColors.error, 1.5),
            errorStyle: const TextStyle(fontSize: 13, color: AppColors.error),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
                    icon: Icon(
                      _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.muted,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
