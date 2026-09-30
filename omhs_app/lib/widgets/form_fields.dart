import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// Rounded, filled form fields used on the profile and setup screens.

InputDecoration _decoration(BuildContext context, String label,
    {String? suffix, bool invalid = false}) {
  final c = context.omhs;
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: 1.4),
      );
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    filled: true,
    fillColor: c.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: TextStyle(color: c.muted, fontSize: 13),
    floatingLabelStyle: TextStyle(color: invalid ? c.danger : c.primary),
    suffixStyle: mono(12, weight: FontWeight.w400, color: c.muted),
    enabledBorder: border(invalid ? c.danger : Colors.transparent),
    focusedBorder: border(invalid ? c.danger : c.primary),
  );
}

/// Text field in the app style; [invalid] outlines it in red.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.suffix,
    this.keyboard = TextInputType.name,
    this.allow,
    this.invalid = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? suffix;
  final TextInputType keyboard;

  /// Characters the field accepts; anything when null.
  final RegExp? allow;
  final bool invalid;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        textInputAction: TextInputAction.done,
        keyboardType: keyboard,
        inputFormatters:
            allow == null ? null : [FilteringTextInputFormatter.allow(allow!)],
        style: TextStyle(
          fontSize: 15,
          color: context.omhs.text,
          fontFamily: keyboard == TextInputType.name ? null : kMonoFont,
        ),
        decoration:
            _decoration(context, label, suffix: suffix, invalid: invalid),
      );
}

/// Looks like a field, opens a picker when tapped.
class AppTapField extends StatelessWidget {
  const AppTapField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: _decoration(context, label).copyWith(
          suffixIcon: Icon(icon, size: 20, color: c.muted),
        ),
        child: value == null
            ? null
            : Text(value!, style: TextStyle(fontSize: 15, color: c.text)),
      ),
    );
  }
}
