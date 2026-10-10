import 'dart:async';

import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/presentation/data/supabase_presenter_remote_transport.dart';
import 'package:varian/features/presentation/domain/remote_presenter_control.dart';

class PresenterRemoteConnection {
  final PresenterRemoteSession session;
  final SupabasePresenterRemoteTransport transport;

  const PresenterRemoteConnection({
    required this.session,
    required this.transport,
  });
}

Future<PresenterRemoteConnection?> showPresenterRemoteHostDialog({
  required BuildContext context,
  required SupabaseClient? client,
  required SupabaseSyncService syncService,
}) => showUiDialog<PresenterRemoteConnection>(
  context: context,
  builder: (_) =>
      PresenterRemoteHostDialog(client: client, syncService: syncService),
);

Future<void> showPresenterRemoteControllerDialog({
  required BuildContext context,
  required String projectId,
  required SupabaseClient? client,
  required SupabaseSyncService syncService,
}) async {
  await showUiDialog<void>(
    context: context,
    builder: (_) => PresenterRemoteControllerDialog(
      projectId: projectId,
      client: client,
      syncService: syncService,
    ),
  );
}

class PresenterRemoteHostDialog extends StatefulWidget {
  final SupabaseClient? client;
  final SupabaseSyncService syncService;

  const PresenterRemoteHostDialog({
    required this.client,
    required this.syncService,
    super.key,
  });

  @override
  State<PresenterRemoteHostDialog> createState() =>
      _PresenterRemoteHostDialogState();
}

class _PresenterRemoteHostDialogState extends State<PresenterRemoteHostDialog> {
  final _sessionIdController = TextEditingController();
  PresenterRemoteSession? _session;
  bool _busy = false;
  String? _error;

  User? get _user =>
      widget.client?.auth.currentUser ??
      widget.client?.auth.currentSession?.user;

  @override
  void dispose() {
    _sessionIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final sessionId = _sessionIdController.text.trim();
    if (sessionId.isEmpty) {
      setState(() => _error = 'Masukkan Session ID presenter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.syncService.getPresenterRemoteSession(
        sessionId,
      );
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _grantConsent() async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final granted = await widget.syncService.grantPresenterRemoteConsent(
        session.sessionId,
      );
      if (!mounted) return;
      setState(() => _session = granted);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final session = _session;
    final user = _user;
    if (session == null || user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final transport = SupabasePresenterRemoteTransport(
      widget.client,
      syncService: widget.syncService,
    );
    try {
      await transport.join(session: session, localActorId: user.id);
      if (!mounted) {
        await transport.dispose();
        return;
      }
      Navigator.of(
        context,
      ).pop(PresenterRemoteConnection(session: session, transport: transport));
    } catch (error) {
      await transport.dispose();
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final user = _user;
    final session = _session;
    final canGrant = session != null && user?.id == session.presenterId;
    final canConnect =
        session?.consentGranted == true &&
        session?.isActive(DateTime.now().toUtc()) == true &&
        user != null;
    return _RemoteDialogShell(
      title: 'Presenter Remote',
      icon: Icons.slideshow_outlined,
      children: [
        Text(
          'Hubungkan layar ini sebagai presenter. Controller harus membuat session terlebih dahulu.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
        UiTextField(
          controller: _sessionIdController,
          label: 'Session ID',
          hint: 'UUID session dari controller',
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _loadSession(),
        ),
        const SizedBox(height: AppSpacing.md),
        UiButton(
          onPressed: _busy ? null : _loadSession,
          mainAxisSize: MainAxisSize.max,
          prefix: const Icon(Icons.refresh, size: 16),
          child: const Text('Load session'),
        ),
        if (session != null) ...[
          const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project: ${session.projectId}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Role: ${session.role.name} • Expiry: ${session.expiresAt.toLocal()}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  session.consentGranted
                      ? 'Consent granted. Session siap dipakai.'
                      : 'Menunggu consent presenter.',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: session.consentGranted
                        ? tokens.success
                        : tokens.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (canGrant && !session.consentGranted)
            UiButton(
              onPressed: _busy ? null : _grantConsent,
              mainAxisSize: MainAxisSize.max,
              prefix: const Icon(Icons.verified_user_outlined, size: 16),
              child: const Text('Grant consent'),
            ),
          if (!canGrant && !session.consentGranted)
            Text(
              'Login dengan akun presenter untuk memberikan consent.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
          if (canConnect)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: UiButton(
                onPressed: _busy ? null : _connect,
                mainAxisSize: MainAxisSize.max,
                prefix: const Icon(Icons.link, size: 16),
                child: const Text('Connect presenter'),
              ),
            ),
        ],
        if (user == null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              'Login diperlukan untuk menerima remote command.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.warning),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.danger),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        UiButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          variant: UiButtonVariant.outline,
          mainAxisSize: MainAxisSize.max,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class PresenterRemoteControllerDialog extends StatefulWidget {
  final String projectId;
  final SupabaseClient? client;
  final SupabaseSyncService syncService;

  const PresenterRemoteControllerDialog({
    required this.projectId,
    required this.client,
    required this.syncService,
    super.key,
  });

  @override
  State<PresenterRemoteControllerDialog> createState() =>
      _PresenterRemoteControllerDialogState();
}

class _PresenterRemoteControllerDialogState
    extends State<PresenterRemoteControllerDialog> {
  final _presenterIdController = TextEditingController();
  final _sessionIdController = TextEditingController();
  PresenterRemoteRole _role = PresenterRemoteRole.presenter;
  PresenterRemoteSession? _session;
  SupabasePresenterRemoteTransport? _transport;
  bool _busy = false;
  String? _error;

  User? get _user =>
      widget.client?.auth.currentUser ??
      widget.client?.auth.currentSession?.user;

  bool get _connected => _transport?.isConnected == true;

  @override
  void dispose() {
    _presenterIdController.dispose();
    _sessionIdController.dispose();
    unawaited(_transport?.dispose());
    super.dispose();
  }

  Future<void> _createSession() async {
    final presenterId = _presenterIdController.text.trim();
    if (presenterId.isEmpty) {
      setState(() => _error = 'Masukkan user ID presenter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.syncService.createPresenterRemoteSession(
        projectId: widget.projectId,
        presenterId: presenterId,
        role: _role,
      );
      if (!mounted) return;
      _sessionIdController.text = session.sessionId;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSession() async {
    final sessionId = _sessionIdController.text.trim();
    if (sessionId.isEmpty) {
      setState(() => _error = 'Masukkan Session ID presenter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.syncService.getPresenterRemoteSession(
        sessionId,
      );
      if (!mounted) return;
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final session = _session;
    final user = _user;
    if (session == null || user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final transport = SupabasePresenterRemoteTransport(
      widget.client,
      syncService: widget.syncService,
    );
    try {
      await transport.join(session: session, localActorId: user.id);
      if (!mounted) {
        await transport.dispose();
        return;
      }
      await _transport?.dispose();
      setState(() => _transport = transport);
    } catch (error) {
      await transport.dispose();
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(PresenterRemoteAction action, {int? frameIndex}) async {
    final session = _session;
    final user = _user;
    final transport = _transport;
    if (session == null || user == null || transport == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await transport.send(
        PresenterRemoteCommand(
          commandId: const Uuid().v4(),
          sessionId: session.sessionId,
          action: action,
          frameIndex: frameIndex,
          createdAt: DateTime.now().toUtc(),
          actorId: user.id,
          projectId: session.projectId,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _remoteErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final session = _session;
    final user = _user;
    return _RemoteDialogShell(
      title: 'Remote Presenter Controller',
      icon: Icons.settings_remote_outlined,
      children: [
        Text(
          'Buat session, bagikan ID ke presenter, lalu tunggu consent sebelum mengirim command.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
        UiTextField(
          controller: _presenterIdController,
          label: 'Presenter user ID',
          hint: 'UUID akun presenter',
          enabled: !_busy && session == null,
        ),
        if (session == null) ...[
          const SizedBox(height: AppSpacing.md),
          UiSelect<PresenterRemoteRole>(
            value: _role,
            label: 'Control role',
            items: const {
              'Presenter': PresenterRemoteRole.presenter,
              'Owner': PresenterRemoteRole.owner,
            },
            enabled: !_busy,
            onChanged: (value) {
              if (!_busy && value != null) setState(() => _role = value);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          UiButton(
            onPressed: _busy || user == null ? null : _createSession,
            mainAxisSize: MainAxisSize.max,
            prefix: const Icon(Icons.add_link, size: 16),
            child: const Text('Create session'),
          ),
        ],
        const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
        UiTextField(
          controller: _sessionIdController,
          label: 'Session ID',
          hint: 'UUID session',
          enabled: !_busy,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: UiButton(
                onPressed: _busy ? null : _loadSession,
                prefix: const Icon(Icons.refresh, size: 16),
                child: const Text('Refresh'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: UiButton(
                onPressed: _busy || session == null || user == null
                    ? null
                    : _connect,
                prefix: const Icon(Icons.link, size: 16),
                child: const Text('Connect'),
              ),
            ),
          ],
        ),
        if (session != null) ...[
          const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SelectableText(
              'Session: ${session.sessionId}\n'
              'Consent: ${session.consentGranted ? 'granted' : 'pending'}\n'
              'Expires: ${session.expiresAt.toLocal()}',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: session.consentGranted ? tokens.success : tokens.warning,
              ),
            ),
          ),
          if (_connected) ...[
            const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _commandButton(
                  icon: Icons.arrow_back,
                  label: 'Previous',
                  action: PresenterRemoteAction.previous,
                ),
                _commandButton(
                  icon: Icons.arrow_forward,
                  label: 'Next',
                  action: PresenterRemoteAction.next,
                ),
                _commandButton(
                  icon: Icons.pause,
                  label: 'Pause',
                  action: PresenterRemoteAction.pause,
                ),
                _commandButton(
                  icon: Icons.play_arrow,
                  label: 'Resume',
                  action: PresenterRemoteAction.resume,
                ),
                _commandButton(
                  icon: Icons.stop,
                  label: 'Stop',
                  action: PresenterRemoteAction.stop,
                ),
              ],
            ),
          ],
        ],
        if (user == null)
          Text(
            'Login diperlukan untuk membuat atau mengontrol session.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.warning),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.danger),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        UiButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          variant: UiButtonVariant.outline,
          mainAxisSize: MainAxisSize.max,
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _commandButton({
    required IconData icon,
    required String label,
    required PresenterRemoteAction action,
  }) => UiButton(
    onPressed: _busy ? null : () => _send(action),
    prefix: Icon(icon, size: 15),
    child: Text(label),
  );
}

class _RemoteDialogShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _RemoteDialogShell({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 520);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: UiSurface(
        padding: AppResponsive.dialogPadding(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 42, color: tokens.accent),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  color: tokens.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

String _remoteErrorMessage(Object error) {
  if (error is SyncException) return error.message;
  if (error is FormatException) return error.message;
  return 'Presenter remote operation failed.';
}
