import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../state/auth_provider.dart';
import '../state/auth_recovery.dart';

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  ConsumerState<UpdatePasswordScreen> createState() =>
      _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirmation = _confirmationController.text;
    final copy = CreativeStudioLocalizations.of(context);
    if (password.length < 8) {
      setState(() {
        _error = copy.authWeakPassword;
        _message = null;
      });
      return;
    }
    if (password != confirmation) {
      setState(() {
        _error = copy.authPasswordsMismatch;
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
      await auth.updatePassword(password);
      final accountId = auth.currentUser?.id;
      if (accountId != null && accountId.isNotEmpty) {
        await AuthReturnPathStore.clear(expectedOwner: accountId);
      }
      if (!mounted) return;
      ref.read(authCallbackCoordinatorProvider.notifier).dismiss();
      setState(() {
        _message = CreativeStudioLocalizations.of(context).authPasswordUpdated;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = AuthService.friendlyErrorFor(
          error,
          Localizations.localeOf(context).languageCode,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final callback = ref.watch(authCallbackCoordinatorProvider);
    final copy = CreativeStudioLocalizations.of(context);
    final callbackMessage = callback.status == AuthCallbackStatus.error
        ? AuthCallback.messageForKind(callback.kind, copy.locale.languageCode)
        : null;
    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.canvas),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: AppResponsive.pagePadding(context),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: AppResponsive.dialogWidth(
                      context,
                      preferred: 460,
                    ),
                  ),
                  child: UiSurface(
                    color: tokens.panelElevated,
                    padding: AppResponsive.dialogPadding(context),
                    borderRadius: BorderRadius.circular(AppRadius.dialog),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.lock_reset_outlined,
                          color: tokens.accent,
                          size: AppControlSize.compact,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          copy.authRecoveryTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge!
                              .copyWith(
                                color: tokens.text,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          callbackMessage ?? copy.authRecoveryHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(color: tokens.textMuted, height: 1.4),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        UiTextField(
                          key: const ValueKey('update-password-field'),
                          controller: _passwordController,
                          label: copy.authNewPassword,
                          hint: copy.authRecoveryMinimum,
                          autofillHints: const [AutofillHints.newPassword],
                          obscureText: true,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        UiTextField(
                          key: const ValueKey('update-password-confirmation'),
                          controller: _confirmationController,
                          label: copy.authConfirmPassword,
                          hint: copy.authRecoveryAgain,
                          autofillHints: const [AutofillHints.newPassword],
                          obscureText: true,
                          enabled: !_busy,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _Notice(text: _error!, danger: true),
                        ],
                        if (_message != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _Notice(text: _message!),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        UiButton(
                          key: const ValueKey('update-password-submit'),
                          onPressed: _busy ? null : _submit,
                          mainAxisSize: MainAxisSize.max,
                          prefix: _busy
                              ? const UiProgressIndicator(
                                  semanticsLabel: 'Updating password',
                                  size: 16,
                                )
                              : const Icon(Icons.check),
                          child: Text(
                            _busy ? copy.authWorking : copy.authUpdatePassword,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        UiButton(
                          onPressed: _busy ? null : () => context.go('/'),
                          variant: UiButtonVariant.ghost,
                          child: Text(copy.authBackLocalWorkspace),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthCallbackErrorScreen extends ConsumerWidget {
  const AuthCallbackErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    final snapshot = ref.watch(authCallbackCoordinatorProvider);
    final localizedCallbackMessage = AuthCallback.messageForKind(
      snapshot.kind,
      copy.locale.languageCode,
    );
    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.canvas),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppResponsive.dialogWidth(context, preferred: 460),
              ),
              child: UiSurface(
                color: tokens.panelElevated,
                padding: AppResponsive.dialogPadding(context),
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.link_off_outlined,
                        color: tokens.warning,
                        size: AppControlSize.compact,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        copy.authCallbackTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        localizedCallbackMessage.isNotEmpty
                            ? localizedCallbackMessage
                            : snapshot.message ?? copy.authCallbackLocalSafe,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: tokens.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      UiButton(
                        key: const ValueKey('auth-callback-request-link'),
                        onPressed: () => context.go('/auth'),
                        prefix: const Icon(Icons.mark_email_read_outlined),
                        child: Text(copy.authCallbackRequestLink),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      UiButton(
                        onPressed: () {
                          ref
                              .read(authCallbackCoordinatorProvider.notifier)
                              .dismiss();
                          context.go('/');
                        },
                        variant: UiButtonVariant.ghost,
                        child: Text(copy.authBackLocalWorkspace),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool danger;

  const _Notice({required this.text, this.danger = false});

  @override
  Widget build(BuildContext context) => UiAlert(
    key: danger ? const ValueKey('update-password-error') : null,
    title: text,
    icon: danger ? Icons.error_outline : Icons.info_outline,
    variant: danger ? UiAlertVariant.destructive : UiAlertVariant.success,
    liveRegion: true,
  );
}
