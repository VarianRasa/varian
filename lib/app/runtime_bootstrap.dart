import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/state/auth_provider.dart';

import 'theme.dart';
import 'widgets/ui_primitives.dart';
import 'localization/app_localizations.dart';
import 'supabase_bootstrap.dart';

/// A safe root-level error surface for failures that occur before the normal
/// app shell can render. Flutter's default error widget includes exception
/// details, which may contain callback credentials or provider URLs.
class BootstrapFatalErrorSurface extends StatelessWidget {
  final FlutterErrorDetails? details;

  const BootstrapFatalErrorSurface({this.details, super.key});

  static String messageFor(
    FlutterErrorDetails details, {
    String languageCode = 'en',
  }) => languageCode.toLowerCase().startsWith('id')
      ? 'Muat ulang aplikasi untuk mencoba lagi. Pekerjaan lokal Anda tetap tersimpan.'
      : 'Reload the app to try again. Your local work is preserved.';

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: copy.fatalBootstrapTitle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 40,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      copy.fatalBootstrapTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      copy.fatalBootstrapDescription,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the local application shell usable while optional runtime services
/// finish initializing. Cloud readiness is visible but never gates local work.
class RuntimeBootstrap extends ConsumerStatefulWidget {
  final Future<void> initialization;
  final Widget child;
  final SupabaseBootstrapController? bootstrap;

  const RuntimeBootstrap({
    required this.initialization,
    required this.child,
    this.bootstrap,
    super.key,
  });

  @override
  ConsumerState<RuntimeBootstrap> createState() => _RuntimeBootstrapState();
}

class _RuntimeBootstrapState extends ConsumerState<RuntimeBootstrap> {
  Future<void>? _boundInitialization;
  VoidCallback? _bootstrapListener;
  bool _initializationFailed = false;
  bool _bootstrapBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _bindInitialization();
    _bindBootstrap();
  }

  @override
  void didUpdateWidget(covariant RuntimeBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialization, widget.initialization)) {
      _bindInitialization();
    }
    if (!identical(oldWidget.bootstrap, widget.bootstrap)) {
      _unbindBootstrap(oldWidget.bootstrap);
      _bindBootstrap();
    }
  }

  void _bindBootstrap() {
    final bootstrap = widget.bootstrap;
    if (bootstrap == null) return;
    _bootstrapListener = () {
      if (!mounted) return;
      setState(() => _bootstrapBannerDismissed = false);
      _invalidateRuntimeProviders();
    };
    bootstrap.addListener(_bootstrapListener!);
  }

  void _unbindBootstrap(SupabaseBootstrapController? bootstrap) {
    final listener = _bootstrapListener;
    if (bootstrap != null && listener != null) {
      bootstrap.removeListener(listener);
    }
    _bootstrapListener = null;
  }

  void _bindInitialization() {
    final initialization = widget.initialization;
    if (identical(_boundInitialization, initialization)) return;
    _boundInitialization = initialization;
    initialization.then(
      (_) {
        if (!mounted) return;
        setState(() {
          _initializationFailed = false;
          _bootstrapBannerDismissed = false;
        });
        _invalidateRuntimeProviders();
      },
      onError: (Object _, StackTrace _) {
        if (!mounted) return;
        setState(() {
          _initializationFailed = true;
          _bootstrapBannerDismissed = false;
        });
        _invalidateRuntimeProviders();
      },
    );
  }

  void _invalidateRuntimeProviders() {
    invalidateAuthProviders(ref);
  }

  Future<void> _retryBootstrap() async {
    final bootstrap = widget.bootstrap;
    if (bootstrap == null) return;
    await bootstrap.retry();
  }

  @override
  void dispose() {
    _unbindBootstrap(widget.bootstrap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.bootstrap;
    final state = bootstrap?.state;
    final bootstrapStillStarting =
        state?.status == SupabaseBootstrapStatus.deferred ||
        state?.status == SupabaseBootstrapStatus.initializing;
    final visibleState =
        _initializationFailed && (state == null || bootstrapStillStarting)
        ? const SupabaseBootstrapState(
            status: SupabaseBootstrapStatus.unavailable,
            diagnostic: 'Cloud services are unavailable right now.',
          )
        : state;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (visibleState != null &&
            visibleState.status != SupabaseBootstrapStatus.ready &&
            visibleState.status != SupabaseBootstrapStatus.deferred &&
            !_bootstrapBannerDismissed)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: _BootstrapStatusBanner(
              state: visibleState,
              onRetry: visibleState.canRetry ? _retryBootstrap : null,
              onDismiss: () => setState(() => _bootstrapBannerDismissed = true),
            ),
          ),
      ],
    );
  }
}

class _BootstrapStatusBanner extends StatelessWidget {
  final SupabaseBootstrapState state;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  const _BootstrapStatusBanner({
    required this.state,
    required this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    final tokens = context.appTokens;
    final isError =
        state.status == SupabaseBootstrapStatus.unavailable ||
        state.status == SupabaseBootstrapStatus.notConfigured;
    final color = isError ? tokens.danger : tokens.accent;
    final label = switch (state.status) {
      SupabaseBootstrapStatus.deferred => copy.bootstrapDeferred,
      SupabaseBootstrapStatus.initializing => copy.bootstrapConnecting,
      SupabaseBootstrapStatus.ready => '',
      SupabaseBootstrapStatus.unavailable => copy.bootstrapUnavailable,
      SupabaseBootstrapStatus.notConfigured => copy.bootstrapNotConfigured,
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: label,
      child: UiSurface(
        color: Color.alphaBlend(color.withValues(alpha: 0.08), tokens.panel),
        borderColor: color.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        borderWidth: AppBorder.thin,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.cloud_off_outlined : Icons.cloud_queue_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(color: tokens.text),
              ),
            ),
            if (onRetry != null)
              UiButton(
                onPressed: onRetry,
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.xs,
                child: Text(copy.retry),
              ),
            UiButton(
              key: const ValueKey('dismiss-bootstrap-status'),
              onPressed: onDismiss,
              variant: UiButtonVariant.ghost,
              size: UiButtonSize.xs,
              semanticsLabel: copy.dismiss,
              iconOnly: true,
              child: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
