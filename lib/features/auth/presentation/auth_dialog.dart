import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth_screen.dart';

/// Compatibility entry point for callers that still use the old dialog API.
/// Authentication is now a full page so it works consistently on web and
/// desktop.
Future<void> showAuthDialog(BuildContext context) async {
  await context.push<void>('/auth');
}

@Deprecated('Use AuthScreen through the /auth route instead.')
class AuthDialog extends StatelessWidget {
  const AuthDialog({super.key});

  @override
  Widget build(BuildContext context) => const AuthScreen();
}
