import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/responsive.dart';
import '../../../app/supabase_bootstrap.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../app/widgets/varian_logo.dart';
import 'auth_template_showcase.dart';
import '../state/auth_provider.dart';
import '../state/auth_recovery.dart';

class _EmbeddedAuthGridPainter extends CustomPainter {
  final Color color;

  const _EmbeddedAuthGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    const spacing = 24.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EmbeddedAuthGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

enum _AuthMode { signIn, signUp, reset }

class AuthScreen extends ConsumerStatefulWidget {
  final PasswordResetCooldown? resetCooldown;
  final String? returnPath;
  final bool embedded;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onClose;

  const AuthScreen({
    this.resetCooldown,
    this.returnPath,
    this.embedded = false,
    this.onAuthenticated,
    this.onClose,
    super.key,
  });

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;
  String? _message;
  late final PasswordResetCooldown _resetCooldown;
  Timer? _cooldownTimer;
  Duration _cooldownRemaining = Duration.zero;

  bool get _needsPassword => _mode != _AuthMode.reset;
  bool get _isConfigured => ref.read(authServiceProvider).canAttempt;

  String get _title => switch (_mode) {
    _AuthMode.signIn => CreativeStudioLocalizations.of(context).authSignInTitle,
    _AuthMode.signUp => CreativeStudioLocalizations.of(context).authSignUpTitle,
    _AuthMode.reset => CreativeStudioLocalizations.of(context).authResetTitle,
  };

  String get _actionLabel => switch (_mode) {
    _AuthMode.signIn => CreativeStudioLocalizations.of(
      context,
    ).authSignInAction,
    _AuthMode.signUp => CreativeStudioLocalizations.of(
      context,
    ).authSignUpAction,
    _AuthMode.reset => CreativeStudioLocalizations.of(context).authResetAction,
  };

  String get _googleLabel => _mode == _AuthMode.signUp
      ? CreativeStudioLocalizations.of(context).authGoogleSignUp
      : CreativeStudioLocalizations.of(context).authGoogleSignIn;

  String get _configurationMessage =>
      CreativeStudioLocalizations.of(context).authUnavailable;

  @override
  void initState() {
    super.initState();
    _resetCooldown =
        widget.resetCooldown ?? ref.read(passwordResetCooldownProvider);
    _cooldownRemaining = _resetCooldown.remainingAt(DateTime.now());
    if (_cooldownRemaining > Duration.zero) _scheduleCooldownTicker();
    if (widget.returnPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resumeProtectedReturn());
      });
    }
  }

  Future<void> _resumeProtectedReturn() async {
    final status = defaultSupabaseBootstrap.state.status;
    if (status == SupabaseBootstrapStatus.deferred ||
        status == SupabaseBootstrapStatus.initializing) {
      await defaultSupabaseBootstrap.ensureReady(explicit: true);
    }
    if (!mounted) return;
    final client = ref.read(supabaseClientProvider);
    final session = client?.auth.currentSession;
    if (session == null) return;
    if (widget.embedded) {
      widget.onAuthenticated?.call();
      return;
    }
    final returnPath = await _consumeReturnPathAfterAuth(
      accountId: session.user.id,
    );
    if (mounted) context.go(returnPath ?? '/');
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _passwordVisible = false;
      _error = null;
      _message = null;
      _passwordController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emailFocusNode.requestFocus();
    });
  }

  String? _validate() {
    final email = _emailController.text.trim();
    final copy = CreativeStudioLocalizations.of(context);
    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return copy.authInvalidEmail;
    }
    if (_needsPassword && _passwordController.text.length < 8) {
      return copy.authWeakPassword;
    }
    return null;
  }

  String get _cooldownLabel {
    final seconds = _cooldownRemaining.inSeconds.ceil();
    if (seconds <= 0) return _actionLabel;
    return CreativeStudioLocalizations.of(context).isIndonesian
        ? 'COBA LAGI DALAM ${seconds}d'
        : 'TRY AGAIN IN ${seconds}s';
  }

  void _scheduleCooldownTicker() {
    _cooldownTimer?.cancel();
    void tick() {
      final remaining = _resetCooldown.remainingAt(DateTime.now());
      if (mounted) {
        setState(() => _cooldownRemaining = remaining);
      } else {
        _cooldownRemaining = remaining;
      }
      if (remaining <= Duration.zero) _cooldownTimer?.cancel();
    }

    tick();
    if (_cooldownRemaining > Duration.zero) {
      _cooldownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => tick(),
      );
    }
  }

  void _startResetCooldown({Duration? retryAfter}) {
    _resetCooldown.tryStart(retryAfter: retryAfter);
    _scheduleCooldownTicker();
  }

  Future<String?> _returnPath() async {
    final path = AuthCallbackParser.safeLocalPath(widget.returnPath);
    await AuthReturnPathStore.save(
      path,
      ownerAccountId: ref.read(authServiceProvider).currentUser?.id,
    );
    return path;
  }

  Future<String?> _consumeReturnPathAfterAuth({String? accountId}) async {
    final explicitPath = AuthCallbackParser.safeLocalPath(widget.returnPath);
    if (explicitPath != null) {
      await AuthReturnPathStore.clearIfMatches(
        explicitPath,
        expectedOwner: accountId,
      );
      return explicitPath;
    }
    return AuthReturnPathStore.consume(accountId: accountId);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_mode == _AuthMode.reset && _resetCooldown.isActive) {
      setState(() {
        _cooldownRemaining = _resetCooldown.remainingAt(DateTime.now());
        _error = CreativeStudioLocalizations.of(context).authCooldownWait;
      });
      return;
    }
    final validation = _validate();
    if (validation != null) {
      setState(() {
        _error = validation;
        _message = null;
      });
      return;
    }
    if (!_isConfigured) {
      setState(() {
        _error = _configurationMessage;
        _message = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      if (_mode == _AuthMode.signIn) {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (widget.embedded) {
          if (mounted) widget.onAuthenticated?.call();
        } else {
          final returnPath = await _consumeReturnPathAfterAuth(
            accountId: auth.currentUser?.id,
          );
          if (mounted) context.go(returnPath ?? '/');
        }
      } else if (_mode == _AuthMode.signUp) {
        final hasSession = await auth.signUp(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (!mounted) return;
        if (hasSession) {
          if (widget.embedded) {
            widget.onAuthenticated?.call();
          } else {
            final returnPath = await _consumeReturnPathAfterAuth(
              accountId: auth.currentUser?.id,
            );
            if (mounted) context.go(returnPath ?? '/');
          }
        } else {
          setState(() {
            _message = CreativeStudioLocalizations.of(
              context,
            ).authSignupConfirmation;
          });
        }
      } else {
        final explicitPath = AuthCallbackParser.safeLocalPath(
          widget.returnPath,
        );
        if (explicitPath != null) {
          await AuthReturnPathStore.clearIfMatches(
            explicitPath,
            expectedOwner: auth.currentUser?.id,
          );
        }
        await auth.sendPasswordReset(_emailController.text);
        if (!mounted) return;
        _startResetCooldown();
        setState(() {
          _message = CreativeStudioLocalizations.of(context).authResetSent;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = AuthService.friendlyErrorFor(
          error,
          Localizations.localeOf(context).languageCode,
        );
        if (_mode == _AuthMode.reset &&
            AuthService.friendlyError(error) ==
                'Too many attempts. Try again in a moment.') {
          _startResetCooldown(retryAfter: AuthService.retryAfter(error));
        }
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_busy || !_isConfigured) {
      if (!_isConfigured) {
        setState(() => _error = _configurationMessage);
      }
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    String? savedPath;
    try {
      savedPath = await _returnPath();
      final launched = await ref.read(authServiceProvider).signInWithGoogle();
      if (!launched) {
        await AuthReturnPathStore.clearIfMatches(savedPath);
      }
      if (!launched && mounted) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).authBrowserLoginFailed;
        });
      }
    } catch (error) {
      await AuthReturnPathStore.clearIfMatches(savedPath);
      if (mounted) {
        setState(
          () => _error = AuthService.friendlyErrorFor(
            error,
            Localizations.localeOf(context).languageCode,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (widget.embedded) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.panel,
          gradient: RadialGradient(
            center: const Alignment(0.72, -0.82),
            radius: 1.25,
            colors: [
              Color.alphaBlend(
                tokens.accent.withValues(alpha: 0.045),
                tokens.panel,
              ),
              tokens.panel,
            ],
          ),
        ),
        child: CustomPaint(
          key: const ValueKey('auth-embedded-background-grid'),
          painter: _EmbeddedAuthGridPainter(color: tokens.canvasGrid),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 320;
                final horizontalPadding = compact
                    ? AppSpacing.sm
                    : AppSpacing.md;
                final verticalPadding = constraints.maxHeight < 420
                    ? AppSpacing.sm
                    : AppSpacing.md;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - verticalPadding * 2)
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                    ),
                    child: _buildAuthCard(
                      context,
                      compact: true,
                      embedded: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.canvas),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < AppBreakpoints.medium;
              final pagePadding = AppResponsive.pagePadding(context);
              final contentMinHeight =
                  (constraints.maxHeight - pagePadding.vertical)
                      .clamp(0.0, double.infinity)
                      .toDouble();
              return SingleChildScrollView(
                padding: pagePadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: contentMinHeight),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildMinimalBrandHeader(context),
                                const SizedBox(height: AppSpacing.xl),
                                _buildAuthCard(context),
                                const SizedBox(height: AppSpacing.xl),
                                _buildCanvasIntro(context, compact: true),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _buildCanvasIntro(
                                    context,
                                    minimal: true,
                                  ),
                                ),
                                const SizedBox(width: 64),
                                SizedBox(
                                  width: AppResponsive.dialogWidth(
                                    context,
                                    preferred: 420,
                                  ),
                                  child: _buildAuthCard(context),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalBrandHeader(BuildContext context) {
    final tokens = context.appTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final brand = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VarianBrandMark(size: 28),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Varian',
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: tokens.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        final appTitle = Text(
          CreativeStudioLocalizations.of(context).appTitle,
          maxLines: stacked ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              brand,
              const SizedBox(height: AppSpacing.xs),
              SizedBox(width: constraints.maxWidth, child: appTitle),
            ],
          );
        }

        return Row(
          children: [
            brand,
            const Spacer(),
            Flexible(child: appTitle),
          ],
        );
      },
    );
  }

  Widget _buildCanvasIntro(
    BuildContext context, {
    bool compact = false,
    bool minimal = false,
  }) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          const VarianBrandMark(size: 34),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (!compact) ...[
          Text(
            copy.authIntroLabel,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            copy.authIntroHeadline,
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              copy.authIntroDescription,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: tokens.textMuted,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ] else ...[
          Text(
            copy.authIntroHeadline,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            minimal ? copy.authIntroDescription : copy.authIntroLabel,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: tokens.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AuthTemplateShowcase(
          compact: compact,
          key: const ValueKey('auth-template-showcase'),
        ),
      ],
    );
  }

  Widget _buildAuthCard(
    BuildContext context, {
    bool compact = false,
    bool embedded = false,
  }) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    final auth = ref.watch(authServiceProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sectionGap = embedded ? AppSpacing.sm : AppSpacing.md;
    final content = AutofillGroup(
      child: AnimatedSize(
        duration: reduceMotion
            ? const Duration(milliseconds: 1)
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? const Duration(milliseconds: 1)
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _title,
                      key: ValueKey(_mode),
                      style:
                          (compact
                                  ? Theme.of(context).textTheme.titleSmall!
                                  : Theme.of(context).textTheme.bodyLarge!)
                              .copyWith(
                                color: tokens.text,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                  ),
                ),
                if (!embedded)
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: copy.authBackToCanvas,
                    onPressed: _busy ? null : () => context.go('/'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? const Duration(milliseconds: 1)
                  : const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                _mode == _AuthMode.signUp
                    ? copy.authCardSignUpHint
                    : copy.authCardSignInHint,
                key: ValueKey('hint-$_mode'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
            ),
            SizedBox(height: sectionGap),
            if (!auth.canAttempt) ...[
              _buildNotice(
                context,
                icon: Icons.lock_outline,
                text: _configurationMessage,
              ),
              SizedBox(height: embedded ? sectionGap : AppSpacing.lg),
            ],
            UiButton(
              onPressed: _busy || !auth.canAttempt ? null : _continueWithGoogle,
              variant: UiButtonVariant.outline,
              mainAxisSize: MainAxisSize.max,
              prefix: const Icon(Icons.account_circle_outlined),
              child: Text(_googleLabel),
            ),
            SizedBox(height: sectionGap),
            Row(
              children: [
                Expanded(child: Divider(color: tokens.panelBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(
                    copy.authOrEmail,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tokens.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: tokens.panelBorder)),
              ],
            ),
            SizedBox(height: sectionGap),
            UiTextField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              label: copy.authEmail,
              hint: copy.authEmailHint,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: _needsPassword
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofocus: true,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) {
                if (_needsPassword) {
                  _passwordFocusNode.requestFocus();
                } else {
                  _submit();
                }
              },
            ),
            if (_needsPassword) ...[
              const SizedBox(height: AppSpacing.sm),
              UiTextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                label: copy.authPassword,
                hint: copy.authPasswordMinimum,
                autofillHints: const [AutofillHints.password],
                obscureText: !_passwordVisible,
                textInputAction: TextInputAction.done,
                suffix: IconButton(
                  key: const ValueKey('auth-password-visibility'),
                  tooltip: _passwordVisible
                      ? copy.authHidePassword
                      : copy.authShowPassword,
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_mode == _AuthMode.signIn) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: _busy ? null : () => _setMode(_AuthMode.reset),
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                  child: Text(copy.authForgotPassword),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildNotice(
                context,
                icon: Icons.error_outline,
                text: _error!,
                danger: true,
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildNotice(
                context,
                icon: Icons.mark_email_read_outlined,
                text: _message!,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            UiButton(
              // Keep the email action enabled while cloud is unavailable so
              // local validation stays actionable and no network request is
              // attempted for incomplete input. _submit gates cloud work
              // only after the local checks pass.
              onPressed:
                  _busy || (_mode == _AuthMode.reset && _resetCooldown.isActive)
                  ? null
                  : _submit,
              mainAxisSize: MainAxisSize.max,
              prefix: _busy
                  ? const UiProgressIndicator(
                      semanticsLabel: 'Working',
                      size: 16,
                    )
                  : Icon(
                      _mode == _AuthMode.reset
                          ? Icons.mark_email_read_outlined
                          : Icons.arrow_forward,
                    ),
              child: Text(_busy ? copy.authWorking : _cooldownLabel),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              key: const ValueKey('auth-footer'),
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              children: [
                Text(
                  _mode == _AuthMode.signUp
                      ? copy.authAlreadyAccount
                      : copy.authNewToWorkspace,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                UiButton(
                  onPressed: _busy
                      ? null
                      : () => _setMode(
                          _mode == _AuthMode.signUp
                              ? _AuthMode.signIn
                              : _AuthMode.signUp,
                        ),
                  variant: UiButtonVariant.ghost,
                  size: UiButtonSize.sm,
                  child: Text(
                    _mode == _AuthMode.signUp
                        ? copy.authSignInAction
                        : copy.authSignUpAction,
                  ),
                ),
              ],
            ),
            if (_mode == _AuthMode.reset) ...[
              const SizedBox(height: AppSpacing.xs),
              UiButton(
                onPressed: _busy ? null : () => _setMode(_AuthMode.signIn),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                child: Text(copy.authBackToSignIn),
              ),
            ],
          ],
        ),
      ),
    );
    final surface = embedded
        ? Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < AppBreakpoints.compact
                  ? AppSpacing.sm
                  : AppSpacing.md,
            ),
            child: content,
          )
        : UiSurface(
            color: tokens.panelElevated,
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < AppBreakpoints.compact
                  ? AppSpacing.lg
                  : AppSpacing.xl,
            ),
            borderRadius: BorderRadius.circular(AppRadius.panel),
            child: content,
          );
    return TweenAnimationBuilder<double>(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
      child: surface,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * 10),
          child: child,
        ),
      ),
    );
  }

  Widget _buildNotice(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool danger = false,
  }) {
    return UiAlert(
      key: danger ? const ValueKey('auth-error') : null,
      title: text,
      icon: icon,
      variant: danger ? UiAlertVariant.destructive : UiAlertVariant.info,
      liveRegion: true,
    );
  }
}
