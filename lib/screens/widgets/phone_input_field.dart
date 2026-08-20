import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/security/input_sanitizer.dart'; // 🔒 Importa tu InputSanitizer

/// Campo de teléfono colombiano: prefijo fijo "🇨🇴 +57" + 10 dígitos + sanitización integrada.
class PhoneInputField extends StatelessWidget {
  const PhoneInputField({
    super.key,
    required this.controller,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Método estático utilitario para obtener el teléfono sanitizado en formato E.164 (+57XXXXXXXXXX)
  /// listo para guardar en Supabase.
  static String? getCleanPhone(String digits) {
    final raw = digits.trim();
    if (raw.isEmpty) return null;
    return InputSanitizer.sanitizePhoneNumber('+57$raw');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      style: theme.textTheme.bodyLarge,
      onChanged: onChanged,
      validator: validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Ingresa tu número de celular';
            }
            if (value.trim().length < 10) {
              return 'El número debe tener 10 dígitos';
            }
            final cleanPhone = getCleanPhone(value);
            if (cleanPhone == null) {
              return 'Número de teléfono no válido';
            }
            return null; // Válido
          },
      decoration: InputDecoration(
        hintText: '300 123 4567',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Center(
            widthFactor: 1,
            child: Text(
              '🇨🇴 +57',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}