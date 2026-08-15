import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colombian phone number field: fixed "🇨🇴 +57" prefix + digits-only input.
class PhoneInputField extends StatelessWidget {
  const PhoneInputField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      style: theme.textTheme.bodyLarge,
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
