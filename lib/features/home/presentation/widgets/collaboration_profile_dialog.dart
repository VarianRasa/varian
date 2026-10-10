import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../data/remote/backend_config.dart';
import '../../../../data/remote/supabase_service.dart';
import '../../../../domain/models/collaboration.dart';
import '../../../collaboration/state/collaboration_session_provider.dart';

Future<void> showCollaborationProfileDialog(
  BuildContext context, {
  String? projectId,
}) async {
  await showUiDialog<void>(
    context: context,
    builder: (_) => CollaborationProfileDialog(projectId: projectId),
  );
}

class CollaborationProfileDialog extends ConsumerStatefulWidget {
  final String? projectId;

  const CollaborationProfileDialog({super.key, this.projectId});

  @override
  ConsumerState<CollaborationProfileDialog> createState() =>
      _CollaborationProfileDialogState();
}

class _CollaborationProfileDialogState
    extends ConsumerState<CollaborationProfileDialog> {
  late final TextEditingController _nameController;
  late final String _initialName;
  late final String _stableId;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final client = ref.read(supabaseClientProvider);
    _stableId =
        client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        'local-device';
    final config = ref.read(backendConfigProvider);
    _initialName = CollaborationDisplayNameGenerator.resolve(
      stableId: _stableId,
      preferredName: config.currentUserName,
    );
    _nameController = TextEditingController(text: _initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _useGeneratedName() {
    setState(() {
      _errorMessage = null;
      _nameController.text = CollaborationDisplayNameGenerator.generate(
        _stableId,
      );
      _nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _nameController.text.length),
      );
    });
  }

  Future<void> _save() async {
    try {
      setState(() {
        _saving = true;
        _errorMessage = null;
      });
      await ref.read(backendConfigReadyProvider.future);
      if (!mounted) return;
      final config = ref.read(backendConfigProvider);
      if (_nameController.text.trim() == _initialName.trim() &&
          config.currentUserName.trim().isNotEmpty &&
          config.currentUserName.trim() != _initialName.trim()) {
        _nameController.text = config.currentUserName;
      }
      final displayName = CollaborationDisplayNameGenerator.validate(
        _nameController.text,
      );
      await ref
          .read(backendConfigProvider.notifier)
          .saveConfig(config.copyWith(currentUserName: displayName));
      final projectId = widget.projectId;
      if (projectId != null && projectId.trim().isNotEmpty) {
        final collaboration = ref.read(
          collaborationSessionProvider(projectId).notifier,
        );
        if (collaboration.isStarted) {
          await collaboration.updateDisplayName(displayName);
        }
      }
      if (!mounted) return;
      showUiToast(context, 'Collaboration name updated.');
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not save collaboration name.');
      debugPrint('[CollaborationProfileDialog] Save failed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 640) - keyboardInset)
            .clamp(0.0, 640.0)
            .toDouble();
    final width = AppResponsive.dialogWidth(context, preferred: 480);
    final generatedName = CollaborationDisplayNameGenerator.generate(_stableId);

    return UiDialog(
      semanticsLabel: 'Collaboration profile',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 480,
        maxHeight: maxHeight,
      ),
      builder: (context, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_circle_outlined, color: tokens.accent),
                      const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          'COLLABORATION PROFILE',
                          style: style.titleTextStyle,
                        ),
                      ),
                      UiIconButton(
                        icon: Icons.close,
                        tooltip: 'Close profile',
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Nama ini terlihat oleh member lain di room. Jika tidak diubah, nama generated akan tetap sama saat login kembali.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  UiTextField(
                    controller: _nameController,
                    label: 'Display name',
                    hint: generatedName,
                    description: '2–32 karakter',
                    autofocus: true,
                    enabled: !_saving,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [LengthLimitingTextInputFormatter(32)],
                    onSubmitted: (_) => _save(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _errorMessage!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: tokens.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: UiButton(
                      onPressed: _saving ? null : _useGeneratedName,
                      variant: UiButtonVariant.ghost,
                      prefix: const Icon(Icons.auto_awesome_outlined),
                      child: const Text('Use generated name'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: _saving ? null : _save,
                        prefix: _saving
                            ? const UiProgressIndicator(
                                semanticsLabel: 'Saving profile',
                                size: 16,
                              )
                            : const Icon(Icons.save_outlined),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
