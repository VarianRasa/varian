import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/responsive.dart';
import '../../../app/supabase_bootstrap.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../data/remote/supabase_service.dart';
import '../../publishing/domain/published_snapshot.dart';
import '../state/autosave_controller.dart';
import 'canvas_screen.dart';
import 'widgets/canvas_editor_services.dart';

typedef SharedCanvasReader =
    Future<SharedCanvasData> Function({
      required String projectId,
      required String token,
      String? passwordDigest,
    });

final sharedCanvasReaderProvider = Provider<SharedCanvasReader?>((ref) => null);

class SecureShareScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String token;
  final bool embedRequested;
  final SharedCanvasReader? reader;
  final SupabaseBootstrapController? bootstrap;

  const SecureShareScreen({
    super.key,
    required this.projectId,
    required this.token,
    this.embedRequested = false,
    this.reader,
    this.bootstrap,
  });

  @override
  ConsumerState<SecureShareScreen> createState() => _SecureShareScreenState();
}

class _SecureShareScreenState extends ConsumerState<SecureShareScreen> {
  SharedCanvasData? _shared;
  bool _loading = true;
  bool _requiresPassword = false;
  bool _passwordRejected = false;
  String? _passwordSnapshotId;
  String? _passwordErrorMessage;
  String? _errorMessage;
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadWithPassword();
  }

  Future<void> _loadWithPassword({String? passwordDigest}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final bootstrap =
          widget.bootstrap ??
          (widget.reader == null ? defaultSupabaseBootstrap : null);
      if (bootstrap != null) {
        await bootstrap.ensureReady(explicit: true);
      }
      final reader = widget.reader;
      final shared = reader != null
          ? await reader(
              projectId: widget.projectId,
              token: widget.token,
              passwordDigest: passwordDigest,
            )
          : await ref
                .read(supabaseSyncServiceProvider)
                .readSharedCanvas(
                  projectId: widget.projectId,
                  token: widget.token,
                  passwordDigest: passwordDigest,
                );
      if (!mounted) return;
      setState(() {
        _shared = shared;
        _loading = false;
        _requiresPassword = false;
        _passwordRejected = false;
        _passwordSnapshotId = null;
        _passwordErrorMessage = null;
      });
    } on SharedCanvasPasswordRequired catch (error) {
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _shared = null;
        _loading = false;
        _requiresPassword = true;
        _passwordRejected = error.rejected;
        _passwordSnapshotId = error.snapshotId;
        _passwordErrorMessage = error.rejected
            ? 'Incorrect password. Try again.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _requiresPassword = false;
        _passwordSnapshotId = null;
        _errorMessage = error is SyncException
            ? error.message
            : 'The canvas share link could not be opened.';
      });
    }
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _passwordRejected = false;
        _passwordErrorMessage = 'Password is required.';
      });
      return;
    }
    final snapshotId = _passwordSnapshotId;
    if (snapshotId == null || snapshotId.isEmpty) return;
    await _loadWithPassword(
      passwordDigest: PublishedSnapshot.passwordDigestFor(snapshotId, password),
    );
  }

  String _passwordTitle() =>
      _passwordRejected ? 'Incorrect password' : 'Password-protected canvas';

  String _passwordDescription() => _passwordRejected
      ? 'The password is incorrect. Enter it again to open this published snapshot.'
      : 'Enter the password provided by the canvas owner.';

  Widget _buildPasswordGate(BuildContext context) {
    final tokens = context.appTokens;
    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: AppResponsive.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: UiSurface(
                padding: EdgeInsets.all(
                  AppResponsive.isCompact(context)
                      ? AppSpacing.pageWide
                      : AppSpacing.xl,
                ),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_outline, size: 40, color: tokens.accent),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        _passwordTitle(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall!
                            .copyWith(
                              color: tokens.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _passwordDescription(),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.pageWide),
                      UiTextField(
                        key: const ValueKey('secure-share-password'),
                        controller: _passwordController,
                        label: 'Password',
                        prefix: const Icon(Icons.password_outlined),
                        autofocus: true,
                        obscureText: true,
                        enabled: !_loading,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) {
                          if (!_loading) unawaited(_submitPassword());
                        },
                      ),
                      if (_passwordErrorMessage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _passwordErrorMessage!,
                          style: TextStyle(color: tokens.danger),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      UiButton(
                        key: const ValueKey('secure-share-password-submit'),
                        onPressed: _loading ? null : _submitPassword,
                        mainAxisSize: MainAxisSize.max,
                        prefix: _loading
                            ? const UiProgressIndicator(
                                semanticsLabel: 'Opening shared canvas',
                                size: 18,
                              )
                            : const Icon(Icons.lock_open_outlined),
                        child: const Text('Open canvas'),
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

  Widget _buildError(BuildContext context, {String? message}) {
    final tokens = context.appTokens;
    final resolvedMessage =
        message ??
        _errorMessage ??
        'This canvas share link is invalid, expired, or revoked.';
    return UiPageScaffold(
      title: const SizedBox.shrink(),
      showHeader: false,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: AppResponsive.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: UiSurface(
                padding: AppResponsive.dialogPadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.link_off_outlined,
                      size: 40,
                      color: tokens.accent,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      resolvedMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokens.text),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    UiButton(
                      key: const ValueKey('secure-share-retry'),
                      onPressed: _loading ? null : _load,
                      prefix: const Icon(Icons.refresh, size: 16),
                      child: const Text('Try again'),
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

  Widget _buildWatermark(SharedCanvasData shared) {
    if (!shared.watermarkEnabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Transform.rotate(
          angle: -0.35,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.dialog),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Text(
                'PUBLISHED PREVIEW',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _shared == null && !_requiresPassword) {
      return const UiPageScaffold(
        title: SizedBox.shrink(),
        showHeader: false,
        child: UiLoadingState(label: 'Loading shared canvas'),
      );
    }
    final shared = _shared;
    if (shared == null) {
      if (_requiresPassword) return _buildPasswordGate(context);
      return _buildError(context);
    }
    if (widget.embedRequested && !shared.embedEnabled) {
      return _buildError(
        context,
        message: 'Embedding is disabled for this published snapshot.',
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CanvasScreen(
          projectId: shared.document.projectId,
          projectName: 'Shared Canvas Document',
          readOnly: true,
          services: CanvasEditorServices.sharedReadOnly.copyWith(
            enableExport: shared.canExport,
          ),
          initialDocument: shared.document,
          initialComments: shared.comments,
        ),
        _buildWatermark(shared),
      ],
    );
  }
}
