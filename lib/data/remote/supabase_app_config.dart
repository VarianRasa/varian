import 'package:flutter/foundation.dart';

/// Public Supabase connection settings supplied by the app publisher at build
/// time. Never put a service-role key or a user password in these values.
class SupabaseAppConfig {
  const SupabaseAppConfig._();

  // These values are intentionally public client defaults. Supabase publishable
  // keys are protected by RLS, while service-role keys must never ship here.
  static const _defaultUrl = 'https://jnpxpylzzskaukgwhuzg.supabase.co';
  static const _defaultPublishableKey =
      'sb_publishable_fJBXPqePIUuveNl2POVLCw_7dLztK5G';

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultUrl,
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: _defaultPublishableKey,
    ),
  );
  static const authRedirectUrl = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
  );
  static const allowRuntimeConfiguration = bool.fromEnvironment(
    'ALLOW_RUNTIME_SUPABASE_CONFIG',
    defaultValue: false,
  );
  static const assetLibraryProviderProxyEnabled = bool.fromEnvironment(
    'ASSET_LIBRARY_PROVIDER_PROXY',
    defaultValue: false,
  );
  static const assetLibraryProviderProxyUrl = String.fromEnvironment(
    'ASSET_LIBRARY_PROVIDER_URL',
  );

  static Uri? get assetLibraryProviderBaseUri {
    final configured = assetLibraryProviderProxyUrl.trim();
    if (configured.isNotEmpty) {
      if (_hasUnsafeUrlCharacters(assetLibraryProviderProxyUrl)) return null;
      final uri = Uri.tryParse(configured);
      if (uri != null &&
          uri.scheme.toLowerCase() == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          uri.port == 443 &&
          uri.query.isEmpty &&
          uri.fragment.isEmpty) {
        final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
        return uri.replace(path: path);
      }
      return null;
    }
    if (!assetLibraryProviderProxyEnabled || !isConfigured) return null;
    if (_hasUnsafeUrlCharacters(url)) return null;
    final base = url.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/functions/v1/asset-library/');
    return uri?.scheme.toLowerCase() == 'https' &&
            uri?.host.isNotEmpty == true &&
            uri?.userInfo.isEmpty == true &&
            uri?.port == 443 &&
            uri?.query.isEmpty == true &&
            uri?.fragment.isEmpty == true
        ? uri
        : null;
  }

  static bool _hasUnsafeUrlCharacters(String value) =>
      value.codeUnits.any((code) => code <= 0x20 || code == 0x7f);

  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  static String? get oauthRedirectUrl {
    final configured = authRedirectUrl.trim();
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return origin == 'null' || origin.isEmpty ? null : origin;
    }
    return 'io.canvascreative://auth/callback';
  }
}
