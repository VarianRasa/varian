import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../data/meeting_configuration.dart';
import '../domain/meeting_errors.dart';
import '../domain/meeting_models.dart';
import '../state/meeting_controller.dart';

final _meetingIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class PreJoinScreen extends ConsumerStatefulWidget {
  const PreJoinScreen({
    required this.meetingId,
    required this.projectId,
    super.key,
  });

  final String meetingId;
  final String projectId;

  @override
  ConsumerState<PreJoinScreen> createState() => _PreJoinScreenState();
}

class _PreJoinScreenState extends ConsumerState<PreJoinScreen> {
  MeetingErrorCode? _errorCode;
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    final meetingId = widget.meetingId.trim();
    final projectId = widget.projectId.trim();
    final configuration = ref.watch(meetingConfigurationProvider);

    final validationError = _validate(
      meetingId: meetingId,
      projectId: projectId,
      configuration: configuration,
    );
    if (validationError != null) {
      return _UnavailableView(code: validationError);
    }

    final tokens = context.appTokens;
    final state = ref.watch(meetingControllerProvider(projectId));
    final controller = ref.read(meetingControllerProvider(projectId).notifier);
    final status = state.status;
    final errorCode = _errorCode ?? state.errorCode;
    final connected =
        status == MeetingStatus.connected &&
        errorCode == null &&
        state.meetingId == meetingId;
    return UiPageScaffold(
      title: const Text('Join video meeting'),
      child: SingleChildScrollView(
        padding: AppResponsive.pagePadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: UiSurface(
              padding: EdgeInsets.all(
                AppResponsive.isCompact(context)
                    ? AppSpacing.md
                    : AppSpacing.xl,
              ),
              child: Semantics(
                container: true,
                label: 'Video meeting pre-join',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.video_call_outlined, color: tokens.accent),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Ready to join?',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        UiBadge(
                          connected ? 'Connected' : 'Ready',
                          variant: connected
                              ? UiBadgeVariant.success
                              : UiBadgeVariant.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      status == MeetingStatus.connected
                          ? 'You are connected to this meeting.'
                          : 'Check your access before joining. Your camera and microphone stay off until you join.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
                    ),
                    if (errorCode != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      UiAlert(
                        key: const Key('meeting-error'),
                        title: 'Unable to join meeting',
                        description: MeetingErrorMessage.forCode(errorCode),
                        icon: Icons.error_outline,
                        variant: UiAlertVariant.destructive,
                        liveRegion: true,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    UiButton(
                      key: connected
                          ? const Key('meeting-open-stage-button')
                          : const Key('meeting-join-button'),
                      onPressed: _joining
                          ? null
                          : connected
                          ? () => context.push(
                              '/meeting/${Uri.encodeComponent(meetingId)}/stage?projectId=${Uri.encodeQueryComponent(projectId)}',
                            )
                          : () => _join(controller, meetingId),
                      mainAxisSize: MainAxisSize.max,
                      prefix: _joining
                          ? const UiProgressIndicator(
                              semanticsLabel: 'Joining meeting',
                              size: 16,
                            )
                          : Icon(
                              connected
                                  ? Icons.meeting_room_outlined
                                  : Icons.video_call_outlined,
                              size: 16,
                            ),
                      child: Text(
                        _joining
                            ? 'Joining…'
                            : connected
                            ? 'Open stage'
                            : 'Join meeting',
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

  Future<void> _join(MeetingController controller, String meetingId) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _errorCode = null;
    });
    try {
      await controller.join(meetingId: meetingId);
      if (!mounted) return;
      setState(() {
        _joining = false;
      });
    } on MeetingControllerException catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _errorCode = error.code;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _errorCode = MeetingErrorCode.providerUnavailable;
      });
    }
  }

  MeetingErrorCode? _validate({
    required String meetingId,
    required String projectId,
    required MeetingConfiguration configuration,
  }) {
    if (!_meetingIdPattern.hasMatch(meetingId)) {
      return MeetingErrorCode.unavailable;
    }
    if (!_validProjectId(projectId)) {
      return MeetingErrorCode.unavailable;
    }
    if (!configuration.isAvailable) {
      return MeetingErrorCode.unavailable;
    }
    return null;
  }

  static bool _validProjectId(String value) =>
      value.isNotEmpty &&
      !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.code});

  final MeetingErrorCode code;
  @override
  Widget build(BuildContext context) {
    return UiPageScaffold(
      title: const Text('Video meeting unavailable'),
      child: Center(
        child: Padding(
          padding: AppResponsive.pagePadding(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: UiAlert(
              key: const Key('meeting-unavailable'),
              title: 'Video meeting unavailable',
              description: MeetingErrorMessage.forCode(code),
              icon: Icons.error_outline,
              variant: UiAlertVariant.destructive,
              liveRegion: true,
            ),
          ),
        ),
      ),
    );
  }
}
