import 'package:flutter/material.dart';

Future<String?> showBackupPassphraseDialog({
  required BuildContext context,
  required String title,
  required String description,
  required bool confirmPassphrase,
  bool requireMinLength = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      return _PassphraseDialog(
        title: title,
        description: description,
        confirmPassphrase: confirmPassphrase,
        requireMinLength: requireMinLength,
      );
    },
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.description,
    required this.confirmPassphrase,
    required this.requireMinLength,
  });

  final String title;
  final String description;
  final bool confirmPassphrase;
  final bool requireMinLength;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscurePassphrase = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final passphrase = _passphraseController.text.trim();
    final confirmation = _confirmController.text.trim();

    if (passphrase.isEmpty) {
      setState(() => _errorText = 'Passphrase cannot be empty.');
      return;
    }

    if (widget.requireMinLength && passphrase.length < 8) {
      setState(() => _errorText = 'Use at least 8 characters.');
      return;
    }

    if (widget.confirmPassphrase && passphrase != confirmation) {
      setState(() => _errorText = 'Passphrases do not match.');
      return;
    }

    Navigator.of(context).pop(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.description),
            const SizedBox(height: 12),
            TextField(
              controller: _passphraseController,
              obscureText: _obscurePassphrase,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                errorText: _errorText,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() => _obscurePassphrase = !_obscurePassphrase);
                  },
                  icon: Icon(
                    _obscurePassphrase
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.confirmPassphrase) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Confirm passphrase',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscureConfirm = !_obscureConfirm);
                    },
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
