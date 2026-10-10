import 'package:web/web.dart';

import 'auth_recovery.dart' show AuthCallbackParser;

Uri currentAuthUri() => Uri.tryParse(window.location.href) ?? Uri.base;

Future<void> clearHandledAuthUrlPlatform() async {
  final current = Uri.tryParse(window.location.href);
  if (current == null) return;
  final cleaned = AuthCallbackParser.cleanedUri(current);
  window.history.replaceState(null, '', cleaned.toString());
}
