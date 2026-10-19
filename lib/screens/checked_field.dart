import 'package:flutter/material.dart';

/// A text field that checks itself. It stays quiet while someone types into
/// it for the first time, says what is wrong once they leave it (or once the
/// form is submitted with [showError]), and from then on updates as they type.
class CheckedField extends StatefulWidget {
  const CheckedField({
    super.key,
    required this.controller,
    required this.label,
    required this.check,
    this.showError = false,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.helperText,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.onLeft,
  });

  final TextEditingController controller;
  final String label;

  /// What is wrong with the current text, or null when it's fine.
  final String? Function(String text) check;

  /// Shows any problem straight away, for example after a submit.
  final bool showError;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? helperText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Called each time the person leaves the field with something in it.
  final ValueChanged<String>? onLeft;

  @override
  State<CheckedField> createState() => _CheckedFieldState();
}

class _CheckedFieldState extends State<CheckedField> {
  final _focus = FocusNode();
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      // Only once there is something to judge: tabbing through an empty
      // field shouldn't scold anyone.
      if (_focus.hasFocus || widget.controller.text.isEmpty) return;
      if (!_left) setState(() => _left = true);
      widget.onLeft?.call(widget.controller.text);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error =
        _left || widget.showError ? widget.check(widget.controller.text) : null;
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      autocorrect: false,
      enableSuggestions: !widget.obscureText,
      onChanged: (text) {
        // Rebuild so a shown error clears or changes as the person types.
        if (_left || widget.showError) setState(() {});
        widget.onChanged?.call(text);
      },
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: error == null ? widget.helperText : null,
        helperMaxLines: 2,
        errorText: error,
        errorMaxLines: 2,
        suffixIcon: widget.suffixIcon,
      ),
    );
  }
}
