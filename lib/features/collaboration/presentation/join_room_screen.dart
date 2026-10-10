import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/responsive.dart';
import '../../../app/supabase_bootstrap.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../data/remote/backend_config.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../domain/models/collaboration.dart';
import '../../canvas/state/autosave_controller.dart';
import '../../home/state/home_provider.dart';

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({this.initialRoomCode, super.key});

  final String? initialRoomCode;

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  late final TextEditingController _roomCodeController;
  late final TextEditingController _displayNameController;
  late final String _generatedDisplayName;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    final initialRoomCode = (widget.initialRoomCode ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    _roomCodeController = TextEditingController(
      text: initialRoomCode.length > 6
          ? initialRoomCode.substring(0, 6)
          : initialRoomCode,
    );
    final client = ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser ?? client?.auth.currentSession?.user;
    _generatedDisplayName = CollaborationDisplayNameGenerator.resolve(
      stableId: user?.id ?? 'local-device',
      preferredName: '',
    );
    _displayNameController = TextEditingController(text: _generatedDisplayName);
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _joinRoom() async {
    if (_joining) return;
    final roomCode = _roomCodeController.text.trim();
    final copy = CreativeStudioLocalizations.of(context);
    if (!CanvasRoom.isValidRoomCode(roomCode)) {
      showUiToast(context, copy.authInvalidRoom, variant: UiToastVariant.error);
      return;
    }

    setState(() => _joining = true);
    try {
      var client = ref.read(supabaseClientProvider);
      final bootstrapStatus = defaultSupabaseBootstrap.state.status;
      if (client == null &&
          (bootstrapStatus == SupabaseBootstrapStatus.deferred ||
              bootstrapStatus == SupabaseBootstrapStatus.initializing)) {
        await defaultSupabaseBootstrap.ensureReady(explicit: true);
        if (!mounted) return;
        client = ref.read(supabaseClientProvider);
      }
      final user =
          client?.auth.currentUser ?? client?.auth.currentSession?.user;
      if (user == null) {
        if (mounted) {
          final returnPath = Uri(
            path: '/join',
            queryParameters: {'roomId': roomCode},
          ).toString();
          context.go(
            Uri(
              path: '/auth',
              queryParameters: {'returnTo': returnPath},
            ).toString(),
          );
        }
        return;
      }

      await ref.read(backendConfigReadyProvider.future);
      if (!mounted) return;
      final currentConfig = ref.read(backendConfigProvider);
      if (_displayNameController.text.trim() == _generatedDisplayName &&
          currentConfig.currentUserName.trim().isNotEmpty &&
          currentConfig.currentUserName.trim() != 'Architect') {
        _displayNameController.text = currentConfig.currentUserName;
      }
      final displayName = CollaborationDisplayNameGenerator.validate(
        _displayNameController.text,
      );
      final expectedAccountId = user.id;
      await ref
          .read(backendConfigProvider.notifier)
          .saveConfig(currentConfig.copyWith(currentUserName: displayName));
      final currentAfterConfig = ref.read(supabaseClientProvider);
      final accountAfterConfig =
          currentAfterConfig?.auth.currentUser?.id ??
          currentAfterConfig?.auth.currentSession?.user.id;
      if (accountAfterConfig != expectedAccountId) {
        throw StateError('Collaboration account changed before room join.');
      }
      final room = await ref
          .read(supabaseSyncServiceProvider)
          .joinCollaborationRoom(
            roomCode: roomCode,
            displayName: displayName,
            expectedUserId: expectedAccountId,
          );
      final currentAfterJoin = ref.read(supabaseClientProvider);
      final accountAfterJoin =
          currentAfterJoin?.auth.currentUser?.id ??
          currentAfterJoin?.auth.currentSession?.user.id;
      if (accountAfterJoin != expectedAccountId) {
        throw StateError('Collaboration account changed after room join.');
      }
      await ref
          .read(homeProjectsProvider.notifier)
          .rememberCollaborationRoom(
            room,
            expectedAccountId: expectedAccountId,
          );
      if (!mounted) return;
      context.go(
        Uri(
          path: '/project/${Uri.encodeComponent(room.projectId)}',
          queryParameters: {
            'role': CollaborationRole.fromWire(room.role).wireName,
          },
        ).toString(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _joining = false);
      final message = copy.authRoomUnavailable;
      showUiToast(context, message, variant: UiToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    final client = ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser ?? client?.auth.currentSession?.user;
    return UiPageScaffold(
      title: Text(copy.authJoinTitle),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: copy.close,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: AppResponsive.pagePadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: UiSurface(
                padding: EdgeInsets.all(
                  AppResponsive.isCompact(context)
                      ? AppSpacing.page
                      : AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 48,
                      color: tokens.accent,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      copy.authJoinWorkspace,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall!
                          .copyWith(
                            color: tokens.text,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      copy.authJoinDescription,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    UiTextField(
                      controller: _roomCodeController,
                      label: copy.authRoomId,
                      hint: copy.authRoomHint,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textAlign: TextAlign.center,
                      onSubmitted: (_) => _joinRoom(),
                      enabled: !_joining,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    UiTextField(
                      controller: _displayNameController,
                      label: copy.authDisplayName,
                      hint: copy.authDisplayNameHint,
                      description: copy.authDisplayNameDescription,
                      enabled: !_joining,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [LengthLimitingTextInputFormatter(32)],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (user == null)
                      Text(
                        copy.authLoginRequired,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    UiButton(
                      onPressed: _joining ? null : _joinRoom,
                      mainAxisSize: MainAxisSize.max,
                      prefix: _joining
                          ? const UiProgressIndicator(
                              semanticsLabel: 'Joining room',
                              size: 16,
                            )
                          : const Icon(Icons.login_outlined),
                      child: Text(
                        user == null ? copy.authLoginToJoin : copy.authJoinRoom,
                      ),
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
