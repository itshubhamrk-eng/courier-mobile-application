import 'package:flutter/material.dart';

/// Primary button that disables itself while [onPressed] runs, so a double tap
/// cannot send the same booking, THC, DRS or delivery twice.
class SubmitButton extends StatefulWidget {
  const SubmitButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;

  /// Null disables the button.
  final Future<void> Function()? onPressed;

  @override
  State<SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<SubmitButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Text(widget.label);
    return widget.icon == null || _busy
        ? FilledButton(onPressed: enabled ? _run : null, child: child)
        : FilledButton.icon(onPressed: enabled ? _run : null, icon: Icon(widget.icon), label: child);
  }
}
