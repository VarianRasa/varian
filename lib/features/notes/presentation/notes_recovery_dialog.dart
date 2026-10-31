import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/notes_key_manager.dart';

class NotesRecoveryDialog extends StatefulWidget {
  const NotesRecoveryDialog({
    required this.accountId,
    required this.manager,
    required this.persistKey,
    required this.persistEnvelope,
    this.envelope,
    super.key,
  });

  final String accountId;
  final NotesKeyManager manager;
  final NotesKeyEnvelope? envelope;
  final Future<void> Function(Uint8List key) persistKey;
  final Future<void> Function(NotesKeyEnvelope envelope) persistEnvelope;

  @override
  State<NotesRecoveryDialog> createState() => _NotesRecoveryDialogState();
}

class _NotesRecoveryDialogState extends State<NotesRecoveryDialog> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _isSetup => widget.envelope == null;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final passphrase = _passphrase.text;
    if (_isSetup && passphrase != _confirmation.text) {
      setState(() => _error = 'Passphrases do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = _isSetup
          ? await _setup(passphrase)
          : await widget.manager.unlockEnvelope(
              accountId: widget.accountId,
              passphrase: passphrase,
              envelope: widget.envelope!,
            );
      await widget.persistKey(key);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on NotesKeyException {
      if (mounted) setState(() => _error = 'Recovery passphrase is invalid.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Notes recovery is unavailable.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _setup(String passphrase) async {
    final created = await widget.manager.createAccountKey(
      accountId: widget.accountId,
      passphrase: passphrase,
    );
    await widget.persistEnvelope(created.envelope);
    return created.key;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_isSetup ? 'Set up Notes recovery' : 'Unlock Notes'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _isSetup
              ? 'Choose a recovery passphrase. Without it or this device key, encrypted offline Notes cannot be recovered.'
              : 'Enter your recovery passphrase to unlock encrypted Notes on this device.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passphrase,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Recovery passphrase'),
        ),
        if (_isSetup)
          TextField(
            controller: _confirmation,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm passphrase'),
          ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? 'Working…'
              : _isSetup
              ? 'Set up'
              : 'Unlock',
        ),
      ),
    ],
  );
}
