import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/home/presentation/widgets/backend_settings_dialog.dart';
import '../../link_card/domain/link_url_policy.dart';
import '../../../domain/models/ai_artifact.dart';
import '../../../domain/models/ai_job.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/node.dart';
import '../data/ai_local_image_source.dart';
import '../data/image_artifact_store_types.dart';
import '../../../data/remote/supabase_sync_provider.dart';
import '../../../domain/models/node_payload.dart';
import 'package:varian/features/ai/data/video_media_validation.dart';
import '../state/ai_provider.dart';
import '../data/ai_service.dart';
import '../domain/ai_workflow_contract.dart';
import '../domain/ai_copilot_context.dart';
import 'ai_workflow_dialogs.dart';
import 'ai_governance_policy_dialog.dart';

@visibleForTesting
final aiImageAttachmentPickerProvider =
    Provider<Future<AssetPickerResult?> Function()>(
      (ref) =>
          () => AssetService().pickImage(),
    );

@visibleForTesting
final aiImageAttachmentMaxBytesProvider = Provider<int>(
  (ref) => 20 * 1024 * 1024,
);

List<AICapability> aiCapabilitiesForCategory(AICreativeCategory category) {
  switch (category) {
    case AICreativeCategory.generation:
      return [
        AICapability.textToImage,
        AICapability.sketchToImage,
        AICapability.imageToImage,
        AICapability.referenceToImage,
        AICapability.textTo3D,
        AICapability.imageTo3D,
      ];
    case AICreativeCategory.generativeEditing:
      return [
        AICapability.inpainting,
        AICapability.outpainting,
        AICapability.replaceObject,
        AICapability.removeObject,
        AICapability.addObject,
        AICapability.backgroundReplace,
      ];
    case AICreativeCategory.visualTransformation:
      return [
        AICapability.styleTransfer,
        AICapability.materialTransfer,
        AICapability.relighting,
        AICapability.recolor,
        AICapability.restyle,
      ];
    case AICreativeCategory.enhancement:
      return const [];
    case AICreativeCategory.compositionAI:
      return [
        AICapability.populate,
        AICapability.compositionRemove,
        AICapability.rearrange,
        AICapability.expandScene,
        AICapability.smartCutout,
      ];
    case AICreativeCategory.videoAI:
      return [AICapability.imageToVideo];
    case AICreativeCategory.aiAssistant:
      return [AICapability.understandCanvas, AICapability.understandSelection];
  }
}

AIVariantSet _variantSetForJob(AIJob job) {
  final payload = job.variantSetPayload;
  if (payload != null) {
    try {
      final restored = AIVariantSet.fromJson(payload);
      if (restored.variants.isNotEmpty) return restored;
    } catch (_) {}
  }
  final imageReference = job.resultArtifact?.kind == AIArtifactKind.image
      ? validImageArtifactReference(job.resultArtifact?.reference)
      : null;
  final references = [?imageReference];
  final groupId = job.variantGroupId ?? job.id;
  return AIVariantSet(
    id: groupId,
    variants: [
      for (var index = 0; index < references.length; index++)
        AIOutputVariant(
          id: '$groupId-$index',
          index: index,
          artifactReference: references[index],
          license: job.provenance['license'] as String?,
          metadata: {
            if (job.provider != null) 'provider': job.provider,
            if (job.model != null) 'model': job.model,
          },
        ),
    ],
  );
}

class AIPanel extends ConsumerStatefulWidget {
  final String projectId;
  final void Function(CanvasNode node)? onNodeCreated;
  final bool Function()? canEditCanvas;
  final bool compact;
  final FocusNode? promptFocusNode;

  const AIPanel({
    super.key,
    required this.projectId,
    this.onNodeCreated,
    this.canEditCanvas,
    this.compact = false,
    this.promptFocusNode,
  });

  @override
  ConsumerState<AIPanel> createState() => _AIPanelState();
}

class _AIPanelState extends ConsumerState<AIPanel> {
  final _promptController = TextEditingController();
  _AIImageAttachment? _attachment;
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(aiCreativeEngineProvider);
    _promptController.text = state.prompt;
    unawaited(
      ref
          .read(aiCreativeEngineProvider.notifier)
          .restoreJobHistory(widget.projectId),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiState = ref.watch(aiCreativeEngineProvider);
    ref.watch(selectionProvider);
    ref.watch(documentNodesProvider);
    final notifier = ref.read(aiCreativeEngineProvider.notifier);
    final tokens = context.appTokens;

    if (widget.compact) {
      return MixScope.inherit(
        colors: AppMixTokens.colors(tokens),
        child: _buildCompactComposer(context, aiState, notifier, tokens),
      );
    }

    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: SizedBox(
        width: double.infinity,
        child: Box(
          key: const ValueKey('ai-panel-shell'),
          style: BoxStyler()
              .color(AppMixTokens.panel())
              .borderLeft(color: tokens.panelBorder, width: AppBorder.thin),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: const ValueKey('ai-panel-header'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.page,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tokens.panelBorder,
                          width: AppBorder.thin,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: tokens.accent,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'AI CREATIVE ENGINE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(
                                  color: tokens.text,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                          ),
                        ),
                        const Spacer(),
                        UiIconButton(
                          key: const ValueKey('ai-governance-button'),
                          icon: Icons.admin_panel_settings_outlined,
                          tooltip: 'AI governance policy',
                          onPressed: () async {
                            final service = ref.read(aiServiceProvider);
                            await showUiDialog<void>(
                              context: context,
                              builder: (_) => AIGovernancePolicyDialog(
                                initialPolicy: service.governancePolicy,
                                onSave: (policy) =>
                                    service.saveGovernancePolicy(
                                      projectId: widget.projectId,
                                      policy: policy,
                                    ),
                              ),
                            );
                          },
                        ),
                        Flexible(
                          child: Consumer(
                            builder: (context, ref, _) {
                              final cfg = ref.watch(backendConfigProvider);
                              final isConfigured = cfg.isOpenAiConfigured;
                              final badgeText = isConfigured
                                  ? 'BYOK READY: ${cfg.openAiModel}'
                                  : 'SIMULATION MODE';

                              return Tooltip(
                                message: isConfigured
                                    ? 'BYOK endpoint and credentials are set. Route and model support still depends on the selected AI operation.'
                                    : 'Simulation mode. Click to configure an API key.',
                                child: UiButton(
                                  key: const ValueKey(
                                    'ai-backend-settings-button',
                                  ),
                                  onPressed: () {
                                    showUiDialog(
                                      context: context,
                                      builder: (_) =>
                                          const BackendSettingsDialog(),
                                    );
                                  },
                                  semanticsLabel:
                                      'Open AI backend settings: $badgeText',
                                  mainAxisSize: MainAxisSize.min,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 150,
                                    ),
                                    child: UiBadge(
                                      badgeText,
                                      variant: isConfigured
                                          ? UiBadgeVariant.success
                                          : UiBadgeVariant.warning,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(
                        AppSpacing.md + AppSpacing.xxs,
                      ),
                      children: [
                        Row(
                          children: [
                            Icon(
                              _targetIcon(aiState.activeCapability),
                              size: 16,
                              color: tokens.accent,
                            ),
                            const SizedBox(
                              width: AppSpacing.xs + AppSpacing.xxs,
                            ),
                            Expanded(
                              child: Text(
                                _targetLabel(aiState.activeCapability),
                                style: Theme.of(context).textTheme.titleSmall!
                                    .copyWith(
                                      color: tokens.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            UiIconButton(
                              icon: Icons.tune_outlined,
                              tooltip: _showOptions
                                  ? 'Hide options'
                                  : 'Show options',
                              onPressed: () =>
                                  setState(() => _showOptions = !_showOptions),
                            ),
                          ],
                        ),
                        if (_showOptions) ...[
                          const SizedBox(height: AppSpacing.sm),
                          if (aiState.activeCategory !=
                              AICreativeCategory.aiAssistant)
                            _buildOutputModeDropdown(aiState, notifier),
                          if (aiState.activeCategory !=
                              AICreativeCategory.aiAssistant) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _buildCapabilityDropdown(aiState, notifier),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          _buildTargetOptions(aiState, notifier),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _buildComposer(aiState, notifier),
                        const SizedBox(height: AppSpacing.lg),
                        Divider(
                          height: AppBorder.thin,
                          color: tokens.panelBorder,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const UiSectionHeader(title: 'TELEMETRY & RESULTS'),
                        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                        _buildJobHistory(
                          aiState.jobs,
                          isProcessing: aiState.isProcessing,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactComposer(
    BuildContext context,
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
    AppTokens tokens,
  ) {
    final hasCompatibleProvider = _hasCompatibleProvider(
      state.activeCapability,
      state,
    );
    final requiresImage = _requiresImageSource(state.activeCapability);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final providerTooltip = hasCompatibleProvider
            ? 'Compatible AI provider ready'
            : _providerRequirement(state.activeCapability, state);

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: constraints.maxHeight * 0.58,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              child: UiCard(
                key: const ValueKey('ai-prompt-composer'),
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_attachment != null || requiresImage) ...[
                      _attachment != null
                          ? _attachmentChip(tokens)
                          : _selectedSourceChip(tokens),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    LayoutBuilder(
                      builder: (context, rowConstraints) {
                        final narrowComposer = rowConstraints.maxWidth < 380;
                        final controls = <Widget>[
                          if (!isNarrow)
                            Tooltip(
                              message: providerTooltip,
                              child: UiBadge(
                                hasCompatibleProvider ? 'READY' : 'SETUP',
                                variant: hasCompatibleProvider
                                    ? UiBadgeVariant.success
                                    : UiBadgeVariant.warning,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          UiIconButton(
                            key: const ValueKey(
                              'ai-composer-provider-settings',
                            ),
                            icon: Icons.key_outlined,
                            tooltip: 'AI provider settings',
                            size: UiButtonSize.xs,
                            color: hasCompatibleProvider
                                ? null
                                : tokens.warning,
                            onPressed: () {
                              showUiDialog(
                                context: context,
                                builder: (_) => const BackendSettingsDialog(),
                              );
                            },
                          ),
                          UiIconButton(
                            key: const ValueKey('ai-composer-options'),
                            icon: Icons.tune_outlined,
                            tooltip: _showOptions
                                ? 'Hide AI options'
                                : 'Show AI options',
                            size: UiButtonSize.xs,
                            selected: _showOptions,
                            onPressed: () =>
                                setState(() => _showOptions = !_showOptions),
                          ),
                        ];
                        return narrowComposer
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildComposer(
                                    state,
                                    notifier,
                                    compact: true,
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: controls,
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: _buildComposer(
                                      state,
                                      notifier,
                                      compact: true,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  ...controls,
                                ],
                              );
                      },
                    ),
                    if (_showOptions) ...[
                      const SizedBox(height: AppSpacing.xs),
                      if (state.activeCategory !=
                          AICreativeCategory.aiAssistant) ...[
                        _buildOutputModeDropdown(state, notifier),
                        const SizedBox(height: AppSpacing.xs),
                        _buildCapabilityDropdown(state, notifier),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      _buildTargetOptions(state, notifier),
                      const SizedBox(height: AppSpacing.xs),
                      UiButton(
                        key: const ValueKey('ai-composer-governance-settings'),
                        onPressed: () async {
                          final service = ref.read(aiServiceProvider);
                          await showUiDialog<void>(
                            context: context,
                            builder: (_) => AIGovernancePolicyDialog(
                              initialPolicy: service.governancePolicy,
                              onSave: (policy) => service.saveGovernancePolicy(
                                projectId: widget.projectId,
                                policy: policy,
                              ),
                            ),
                          );
                        },
                        prefix: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 16,
                        ),
                        child: const Text('AI governance policy'),
                      ),
                    ],
                    if (state.activeCapability == AICapability.imageToVideo)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Video generation requires a source image and a configured video provider.',
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                      ),
                    if (_attachmentError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      UiAlert(
                        title: 'Image attachment issue',
                        description: _attachmentError!,
                        icon: Icons.error_outline,
                        variant: UiAlertVariant.destructive,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _targetLabel(AICapability capability) => switch (capability) {
    AICapability.textToImage => 'Image',
    AICapability.sketchToImage => 'Sketch to image',
    AICapability.imageToImage => 'Edit image',
    AICapability.referenceToImage => 'Reference to image',
    AICapability.textTo3D || AICapability.imageTo3D => '3D model',
    AICapability.imageToVideo => 'Video',
    AICapability.understandCanvas ||
    AICapability.understandSelection ||
    AICapability.summarizeNotes => 'Assistant',
    _ => _capabilityLabel(capability),
  };

  IconData _targetIcon(AICapability capability) => switch (capability) {
    AICapability.imageToVideo => Icons.movie_outlined,
    AICapability.textTo3D ||
    AICapability.imageTo3D => Icons.view_in_ar_outlined,
    AICapability.understandCanvas ||
    AICapability.understandSelection ||
    AICapability.summarizeNotes => Icons.chat_bubble_outline,
    AICapability.textToImage => Icons.image_outlined,
    _ => Icons.edit_outlined,
  };

  Widget _buildTargetOptions(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    if (_isThreeDCapability(state.activeCapability)) {
      return _buildThreeDParams(state, notifier);
    }
    if (state.activeCapability == AICapability.imageToVideo) {
      return _buildVideoAIParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.generation) {
      return _buildGenerationParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.generativeEditing) {
      return _buildGenerativeEditingParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.visualTransformation) {
      return _buildTransformParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.compositionAI) {
      return _buildCompositionParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.videoAI) {
      return _buildVideoAIParams(state, notifier);
    }
    if (state.activeCategory == AICreativeCategory.aiAssistant) {
      return _buildAssistantParams(state, notifier);
    }
    return const SizedBox.shrink();
  }

  Widget _buildComposer(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier, {
    bool compact = false,
  }) {
    final tokens = context.appTokens;
    final isAssistant = state.activeCategory == AICreativeCategory.aiAssistant;
    final requiresImage = _requiresImageSource(state.activeCapability);
    final capability = state.activeCapability;
    final hasCompatibleProvider = _hasCompatibleProvider(capability, state);

    final promptField = UiTextField(
      key: compact ? const ValueKey('ai-prompt-field') : null,
      controller: _promptController,
      focusNode: compact ? widget.promptFocusNode : null,
      minLines: compact ? 1 : 2,
      maxLines: compact ? 4 : 5,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textAlignVertical: compact ? TextAlignVertical.top : null,
      onChanged: notifier.setPrompt,
      hint: compact
          ? isAssistant
                ? 'Ask about canvas...'
                : 'Describe your idea...'
          : isAssistant
          ? 'Ask anything about this canvas...'
          : _getPromptHint(state.activeCapability),
      prefix: compact
          ? Tooltip(
              message: _targetLabel(capability),
              child: Icon(
                _targetIcon(capability),
                size: 16,
                color: tokens.accent,
              ),
            )
          : null,
    );
    final targetMenuButton = UiMenuButton<_AIComposerAction>(
      buttonKey: const ValueKey('ai-generation-target'),
      icon: Icons.add,
      tooltip: 'Add or choose output',
      items: [
        const UiMenuAction(
          value: _AIComposerAction.image,
          label: 'Create image',
          icon: Icons.image_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.editImage,
          label: 'Edit image',
          icon: Icons.edit_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.sketchToImage,
          label: 'Sketch to image',
          icon: Icons.draw_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.referenceToImage,
          label: 'Reference to image',
          icon: Icons.collections_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.video,
          label: 'Create video',
          icon: Icons.movie_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.model3d,
          label: 'Create 3D model',
          icon: Icons.view_in_ar_outlined,
        ),
        const UiMenuAction(
          value: _AIComposerAction.assistant,
          label: 'Ask about canvas',
          icon: Icons.chat_bubble_outline,
        ),
        UiMenuAction(
          value: _AIComposerAction.uploadImage,
          label: 'Upload image',
          icon: Icons.upload_file_outlined,
          enabled: !state.isProcessing,
        ),
        UiMenuAction(
          value: _AIComposerAction.useCanvasImage,
          label: 'Use selected canvas image',
          icon: Icons.dashboard_outlined,
          enabled: !state.isProcessing,
        ),
        UiMenuAction(
          value: _AIComposerAction.removeAttachment,
          label: 'Remove uploaded image',
          icon: Icons.close,
          enabled: _attachment != null,
        ),
      ],
      onSelected: (action) => _selectComposerAction(action, notifier),
    );
    final sendLabel = state.isProcessing
        ? 'Working...'
        : isAssistant
        ? 'Ask'
        : 'Generate';
    final sendIcon = isAssistant ? Icons.arrow_upward : Icons.auto_awesome;
    final sendButton = Tooltip(
      message: sendLabel,
      child: UiButton(
        key: const ValueKey('ai-composer-send'),
        onPressed: state.isProcessing
            ? null
            : () => _submitPrompt(state, notifier),
        size: compact ? UiButtonSize.xs : UiButtonSize.sm,
        iconOnly: compact,
        semanticsLabel: compact ? sendLabel : null,
        prefix: compact
            ? null
            : state.isProcessing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: UiProgressIndicator(),
              )
            : Icon(sendIcon, size: 15),
        child: compact
            ? state.isProcessing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: UiProgressIndicator(),
                    )
                  : Icon(sendIcon, size: 15)
            : Text(sendLabel),
      ),
    );

    if (compact) {
      return UiSurface(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        color: tokens.panelElevated,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            targetMenuButton,
            const SizedBox(width: AppSpacing.xxs),
            Expanded(child: promptField),
            const SizedBox(width: AppSpacing.xxs),
            sendButton,
          ],
        ),
      );
    }

    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      color: tokens.panelElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_attachment != null) ...[
            _attachmentChip(tokens),
            const SizedBox(height: AppSpacing.sm),
          ] else if (requiresImage) ...[
            _selectedSourceChip(tokens),
            const SizedBox(height: AppSpacing.sm),
          ],
          promptField,
          if (!hasCompatibleProvider) ...[
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            if (compact)
              Tooltip(
                message: _providerRequirement(capability, state),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: tokens.warning, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Provider required',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              UiAlert(
                title: 'Provider required',
                description: _providerRequirement(capability, state),
                icon: Icons.info_outline,
                variant: UiAlertVariant.warning,
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              targetMenuButton,
              if (requiresImage && _attachment == null)
                Text(
                  _hasSelectedImageSource()
                      ? 'Using selected canvas image'
                      : 'Add an image or select one on canvas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
              sendButton,
            ],
          ),
          if (state.activeCapability == AICapability.imageToVideo) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Video generation currently requires a source image and a configured video provider.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
            ),
          ],
          if (_attachmentError != null) ...[
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            UiAlert(
              title: 'Image attachment issue',
              description: _attachmentError!,
              icon: Icons.error_outline,
              variant: UiAlertVariant.destructive,
            ),
          ],
        ],
      ),
    );
  }

  String? _attachmentError;

  void _selectComposerAction(
    _AIComposerAction action,
    AICreativeEngineNotifier notifier,
  ) {
    switch (action) {
      case _AIComposerAction.image:
        notifier.setCapability(AICapability.textToImage);
      case _AIComposerAction.editImage:
        notifier.setCapability(AICapability.imageToImage);
      case _AIComposerAction.sketchToImage:
        notifier.setCapability(AICapability.sketchToImage);
      case _AIComposerAction.referenceToImage:
        notifier.setCapability(AICapability.referenceToImage);
      case _AIComposerAction.video:
        notifier.setCapability(AICapability.imageToVideo);
      case _AIComposerAction.model3d:
        notifier.setCapability(
          _attachment != null || _hasSelectedImageSource()
              ? AICapability.imageTo3D
              : AICapability.textTo3D,
        );
      case _AIComposerAction.assistant:
        notifier.setCapability(AICapability.understandCanvas);
      case _AIComposerAction.uploadImage:
        unawaited(_pickAttachment(notifier));
      case _AIComposerAction.useCanvasImage:
        setState(() {
          _attachment = null;
          _attachmentError = null;
        });
        if (!_hasSelectedImageSource()) {
          showUiToast(
            context,
            'Select an image or image LinkCard on canvas first.',
          );
        }
      case _AIComposerAction.removeAttachment:
        setState(() {
          _attachment = null;
          _attachmentError = null;
        });
    }
  }

  Widget _attachmentChip(AppTokens tokens) => UiSurface(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    color: tokens.panel,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: 14, color: tokens.accent),
        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(_attachment!.name, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: AppSpacing.xs),
        UiIconButton(
          icon: Icons.close,
          tooltip: 'Remove attachment',
          size: UiButtonSize.sm,
          onPressed: () => setState(() {
            _attachment = null;
            _attachmentError = null;
          }),
        ),
      ],
    ),
  );

  Widget _selectedSourceChip(AppTokens tokens) {
    final selectedNode = _selectedImageNode();
    return UiSurface(
      key: const ValueKey('ai-canvas-source-chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      color: tokens.panel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 14, color: tokens.accent),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              selectedNode?.name ??
                  (selectedNode == null
                      ? 'No canvas image selected'
                      : 'Selected canvas image'),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ),
          if (selectedNode != null) ...[
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            UiIconButton(
              icon: Icons.close,
              tooltip: 'Clear canvas image selection',
              size: UiButtonSize.sm,
              onPressed: () => ref.read(selectionProvider.notifier).clear(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAttachment(AICreativeEngineNotifier notifier) async {
    setState(() => _attachmentError = null);
    try {
      final picker = ref.read(aiImageAttachmentPickerProvider);
      final result = await picker();
      if (!mounted || result == null) return;
      final bytes = result.bytes;
      final maxBytes = ref.read(aiImageAttachmentMaxBytesProvider);
      if (bytes == null || bytes.isEmpty) {
        setState(() => _attachmentError = 'Could not read the selected image.');
        return;
      }
      if (bytes.length > maxBytes) {
        setState(
          () => _attachmentError =
              'Image exceeds the ${maxBytes ~/ (1024 * 1024)} MB limit.',
        );
        return;
      }
      if (!isValidImageBytes(bytes)) {
        setState(
          () => _attachmentError = 'Choose a valid PNG, JPEG, or WebP image.',
        );
        return;
      }
      final mimeType = _mimeTypeForBytes(bytes);
      final currentCapability = ref
          .read(aiCreativeEngineProvider)
          .activeCapability;
      final inferredCapability = switch (currentCapability) {
        AICapability.textToImage => AICapability.imageToImage,
        AICapability.textTo3D => AICapability.imageTo3D,
        _ => null,
      };
      setState(() {
        _attachment = _AIImageAttachment(
          name: result.name,
          bytes: Uint8List.fromList(bytes),
          mimeType: mimeType,
        );
        _attachmentError = null;
      });
      if (inferredCapability != null) {
        notifier.setCapability(inferredCapability);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _attachmentError = 'Image selection failed. Try again.');
      }
    }
  }

  CanvasNode? _selectedImageNode() {
    final selectedIds = ref.read(selectionProvider);
    return ref
        .read(documentNodesProvider)
        .where(
          (node) =>
              selectedIds.contains(node.id) && _hasReadableImageSource(node),
        )
        .firstOrNull;
  }

  bool _hasSelectedImageSource() => _selectedImageNode() != null;

  bool _hasCompatibleProvider(
    AICapability capability,
    AICreativeEngineState state,
  ) {
    final config = ref.watch(backendConfigProvider);
    return switch (capability) {
      AICapability.textToImage ||
      AICapability.sketchToImage ||
      AICapability.imageToImage ||
      AICapability.referenceToImage ||
      AICapability.inpainting ||
      AICapability.outpainting ||
      AICapability.replaceObject ||
      AICapability.removeObject ||
      AICapability.addObject ||
      AICapability.backgroundReplace ||
      AICapability.styleTransfer ||
      AICapability.materialTransfer ||
      AICapability.relighting ||
      AICapability.recolor ||
      AICapability.restyle ||
      AICapability.populate ||
      AICapability.compositionRemove ||
      AICapability.rearrange ||
      AICapability.expandScene ||
      AICapability.smartCutout => config.isOpenAiConfigured,
      AICapability.imageToVideo => config.isVideoConfigured,
      AICapability.textTo3D || AICapability.imageTo3D =>
        config.isThreeDConfigured &&
            (capability != AICapability.textTo3D ||
                !_threeDProviderNeedsImageGeneration(state) ||
                config.isOpenAiConfigured),
      AICapability.understandCanvas ||
      AICapability.understandSelection ||
      AICapability.summarizeNotes => config.isOpenAiConfigured,
      _ => false,
    };
  }

  bool _threeDProviderNeedsImageGeneration(AICreativeEngineState state) =>
      const {
        'triposr',
        'trellis',
        'fal-trellis2',
        'hunyuan3d',
      }.contains(state.selectedThreeDProvider.trim().toLowerCase());

  String _providerRequirement(
    AICapability capability,
    AICreativeEngineState state,
  ) => switch (capability) {
    AICapability.imageToVideo =>
      'Configure a compatible video provider. Video currently supports image-to-video.',
    AICapability.textTo3D =>
      'Configure a 3D worker/provider${_threeDProviderNeedsImageGeneration(state) ? ' and an image-generation provider' : ''} for text-to-3D.',
    AICapability.imageTo3D =>
      'Configure a 3D worker/provider to convert the selected image.',
    AICapability.understandCanvas ||
    AICapability.understandSelection ||
    AICapability.summarizeNotes =>
      'Configure a chat-compatible BYOK endpoint to ask about the canvas.',
    _ => 'Configure a compatible image provider and model in BYOK settings.',
  };

  bool _requiresImageSource(AICapability capability) => switch (capability) {
    AICapability.sketchToImage ||
    AICapability.imageToImage ||
    AICapability.referenceToImage ||
    AICapability.imageToVideo ||
    AICapability.imageTo3D ||
    AICapability.inpainting ||
    AICapability.outpainting ||
    AICapability.replaceObject ||
    AICapability.removeObject ||
    AICapability.addObject ||
    AICapability.backgroundReplace ||
    AICapability.styleTransfer ||
    AICapability.materialTransfer ||
    AICapability.relighting ||
    AICapability.recolor ||
    AICapability.restyle ||
    AICapability.populate ||
    AICapability.compositionRemove ||
    AICapability.rearrange ||
    AICapability.expandScene ||
    AICapability.smartCutout => true,
    _ => false,
  };

  Future<_SelectedImageSource> _effectiveImageSource() async {
    final attachment = _attachment;
    if (attachment != null) {
      return _SelectedImageSource(
        bytes: attachment.bytes,
        base64: base64Encode(attachment.bytes),
        mimeType: attachment.mimeType,
        byteLength: attachment.bytes.length,
      );
    }
    return _selectedImageSource();
  }

  Future<void> _submitPrompt(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) async {
    notifier.setPrompt(_promptController.text);
    final capability = state.activeCapability;
    if (capability == AICapability.textToImage ||
        capability == AICapability.textTo3D ||
        capability == AICapability.understandCanvas ||
        capability == AICapability.understandSelection ||
        capability == AICapability.summarizeNotes) {
      await notifier.executeSequence(
        projectId: widget.projectId,
        variantOfNodeId: _selectedReplacementNodeId(state),
        copilotContext: _copilotContext(state),
        onNodeCreated: widget.onNodeCreated,
        canEditCanvas: widget.canEditCanvas,
      );
      return;
    }

    final source = await _effectiveImageSource();
    if (!mounted || !context.mounted) return;
    if (!source.hasReadableValue) {
      showUiToast(
        context,
        'Attach an image or select an image node on canvas first.',
        variant: UiToastVariant.error,
      );
      return;
    }
    final outputTarget = capability == AICapability.imageToVideo
        ? NodeType.videoCard
        : capability == AICapability.imageTo3D
        ? NodeType.model3d
        : NodeType.image;
    final sourceNode = source.nodeId == null
        ? null
        : ref
              .read(documentNodesProvider)
              .where((node) => node.id == source.nodeId)
              .firstOrNull;
    final selectedOutputNode = ref
        .read(documentNodesProvider)
        .where(
          (node) =>
              ref.read(selectionProvider).contains(node.id) &&
              node.type == outputTarget,
        )
        .firstOrNull;
    final replaceNodeId = state.outputMode == AIOutputMode.replace
        ? (sourceNode?.type == outputTarget
              ? sourceNode?.id
              : selectedOutputNode?.id)
        : source.nodeId;
    final position =
        source.spawnPosition ??
        (sourceNode == null
            ? null
            : Offset(sourceNode.x + sourceNode.width + 40, sourceNode.y));
    await notifier.executeSequence(
      projectId: widget.projectId,
      copilotContext: _copilotContext(state),
      sourceImageBase64: source.base64,
      sourceImageUrl: source.url,
      sourceImageArtifactReference: source.artifactReference,
      sourceImageStoragePath: source.storagePath,
      sourceImageMimeType: source.mimeType,
      sourceImageByteLength: source.byteLength,
      variantOfNodeId: replaceNodeId,
      spawnCanvasPosition: position,
      onNodeCreated: widget.onNodeCreated,
      canEditCanvas: widget.canEditCanvas,
    );
  }

  String? _selectedReplacementNodeId(AICreativeEngineState state) {
    if (state.outputMode != AIOutputMode.replace) return null;
    final selectedIds = ref.read(selectionProvider);
    final targetType = switch (state.activeCapability) {
      AICapability.textTo3D || AICapability.imageTo3D => NodeType.model3d,
      AICapability.imageToVideo => NodeType.videoCard,
      _ => NodeType.image,
    };
    return ref
        .read(documentNodesProvider)
        .where(
          (node) => selectedIds.contains(node.id) && node.type == targetType,
        )
        .firstOrNull
        ?.id;
  }

  Future<_SelectedImageSource> _selectedImageSource() async {
    final selected = ref.read(selectionProvider);
    CanvasNode? node;
    for (final candidate in ref.read(documentNodesProvider)) {
      if (selected.contains(candidate.id) &&
          _hasReadableImageSource(candidate)) {
        node = candidate;
        break;
      }
    }
    if (node == null) return const _SelectedImageSource.empty();

    final source = await _sourceForNode(node);
    if (!source.hasReadableValue) return const _SelectedImageSource.empty();
    return source.copyWith(
      nodeId: node.id,
      spawnPosition: Offset(node.x + node.width + 40, node.y),
    );
  }

  bool _hasReadableImageSource(CanvasNode node) {
    final payload = node.payload;
    if (payload is ImagePayload) {
      return _hasImageUrl(payload.url) ||
          validImageArtifactReference(payload.imageArtifactReference) != null ||
          _isProjectStoragePath(payload.storagePath) ||
          (!kIsWeb && payload.localPath?.trim().isNotEmpty == true);
    }
    if (payload is LinkPayload) {
      final imageUrl = payload.imageUrl?.trim();
      if (_isDataUri(imageUrl) || _isHttpUrl(imageUrl)) return true;
      return (payload.mediaType == 'image' || isDirectImageUrl(payload.url)) &&
          _isHttpUrl(payload.url);
    }
    return false;
  }

  Future<_SelectedImageSource> _sourceForNode(CanvasNode node) async {
    final payload = node.payload;
    String? value;
    String? localPath;
    if (payload is ImagePayload) {
      final artifactReference = validImageArtifactReference(
        payload.imageArtifactReference,
      );
      if (artifactReference != null) {
        final store = ref.read(imageArtifactStoreProvider);
        final hydrated = await store.hydrate(artifactReference);
        final bytes =
            hydrated?.bytes ??
            (hydrated == null ? null : await store.read(hydrated));
        if (bytes != null && bytes.isNotEmpty) {
          return _SelectedImageSource(
            bytes: bytes,
            artifactReference: artifactReference,
            mimeType: payload.mimeType ?? _mimeTypeForBytes(bytes),
            byteLength: bytes.length,
          );
        }
      }
      final storagePath = payload.storagePath;
      if (_isProjectStoragePath(storagePath)) {
        final sync = ref.read(supabaseSyncServiceProvider);
        final bytes = await sync.readPrivateStorageBytes(
          projectId: widget.projectId,
          path: storagePath!,
          maxBytes: maxImageArtifactBytes,
        );
        if (bytes != null && bytes.isNotEmpty) {
          return _SelectedImageSource(
            bytes: bytes,
            storagePath: storagePath,
            mimeType: payload.mimeType ?? _mimeTypeForBytes(bytes),
            byteLength: bytes.length,
          );
        }
      }
      value = payload.url?.trim();
      localPath = payload.localPath?.trim();
    } else if (payload is LinkPayload) {
      value = payload.imageUrl?.trim();
      if (!_isDataUri(value) && !_isHttpUrl(value)) {
        value = payload.mediaType == 'image' || isDirectImageUrl(payload.url)
            ? payload.url.trim()
            : null;
      }
    }

    if (_isDataUri(value)) {
      final comma = value!.indexOf(',');
      final encoded = comma >= 0 ? value.substring(comma + 1) : value;
      final bytes = Uint8List.fromList(base64Decode(encoded));
      return _SelectedImageSource(
        bytes: bytes,
        base64: encoded,
        mimeType: _mimeTypeFromDataUri(value),
        byteLength: bytes.length,
      );
    }
    if (_isHttpUrl(value)) return _SelectedImageSource(url: value);

    if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      final bytes = await readLocalAIImageBytes(localPath);
      if (bytes != null && bytes.isNotEmpty) {
        return _SelectedImageSource(
          bytes: bytes,
          base64: base64Encode(bytes),
          mimeType: _mimeTypeForBytes(bytes),
          byteLength: bytes.length,
        );
      }
    }
    return const _SelectedImageSource.empty();
  }

  bool _isProjectStoragePath(String? value) =>
      value != null &&
      ref
          .read(supabaseSyncServiceProvider)
          .storageResolver
          .isStoragePath(value, projectId: widget.projectId);

  String _mimeTypeForBytes(Uint8List bytes) {
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  String _mimeTypeFromDataUri(String value) {
    final comma = value.indexOf(',');
    if (comma <= 5) return 'image/png';
    final type = value
        .substring(5, comma)
        .split(';')
        .first
        .trim()
        .toLowerCase();
    return type.startsWith('image/') ? type : 'image/png';
  }

  bool _hasImageUrl(String? value) => _isDataUri(value) || _isHttpUrl(value);

  bool _isDataUri(String? value) =>
      value?.trim().toLowerCase().startsWith('data:image/') ?? false;

  bool _isHttpUrl(String? value) {
    final uri = value == null ? null : Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Widget _buildCapabilityDropdown(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    final capabilities = aiCapabilitiesForCategory(state.activeCategory);
    return UiSelect<AICapability>(
      items: {
        for (final capability in capabilities)
          _capabilityLabel(capability): capability,
      },
      value: state.activeCapability,
      label: 'ADVANCED OPERATION',
      onChanged: (value) {
        if (value != null) notifier.setCapability(value);
      },
    );
  }

  Widget _buildOutputModeDropdown(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) => UiSelect<AIOutputMode>(
    items: const {
      'Insert as new node': AIOutputMode.insert,
      'Replace selected source': AIOutputMode.replace,
    },
    value: state.outputMode,
    label: 'OUTPUT SEMANTICS',
    onChanged: (value) {
      if (value != null) notifier.setOutputMode(value);
    },
  );

  Widget _buildAiSelect<T>({
    required String label,
    required T? value,
    required Iterable<T> values,
    required String Function(T) format,
    required ValueChanged<T> onChanged,
  }) => UiSelect<T>(
    items: {for (final item in values) format(item): item},
    value: value,
    label: label,
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );

  String _capabilityLabel(AICapability cap) {
    switch (cap) {
      case AICapability.textToImage:
        return 'Text → Image (Configured Image Provider)';
      case AICapability.sketchToImage:
        return 'Sketch → Image (Prompted Edit)';
      case AICapability.imageToImage:
        return 'Image → Image (Prompted Edit)';
      case AICapability.imageToVideo:
        return 'Image → Video (Configured Video Provider)';
      case AICapability.referenceToImage:
        return 'Reference → Image (Prompted Edit)';
      case AICapability.textTo3D:
        return 'Text → 3D (Configured Worker)';
      case AICapability.imageTo3D:
        return 'Image → 3D (Configured Worker)';
      case AICapability.inpainting:
        return 'Masked Image Edit';
      case AICapability.outpainting:
        return 'Scene Expansion (Image Edit)';
      case AICapability.replaceObject:
        return 'Replace Object (Image Edit)';
      case AICapability.removeObject:
        return 'Remove Object (Image Edit)';
      case AICapability.addObject:
        return 'Add Object (Image Edit)';
      case AICapability.backgroundReplace:
        return 'Background Edit';
      case AICapability.styleTransfer:
        return 'Style Edit';
      case AICapability.materialTransfer:
        return 'Material Edit';
      case AICapability.relighting:
        return 'Relight by Prompt';
      case AICapability.recolor:
        return 'Recolor by Prompt';
      case AICapability.restyle:
        return 'Restyle by Prompt';
      case AICapability.upscale:
        return 'Upscale (Unsupported)';
      case AICapability.denoise:
        return 'Denoise (Unsupported)';
      case AICapability.sharpen:
        return 'Sharpen (Unsupported)';
      case AICapability.restore:
        return 'Restore (Unsupported)';
      case AICapability.detailEnhancement:
        return 'Detail Enhancement (Unsupported)';
      case AICapability.populate:
        return 'Populate Scene (Image Edit)';
      case AICapability.compositionRemove:
        return 'Remove Clutter (Image Edit)';
      case AICapability.rearrange:
        return 'Recompose Scene (Image Edit)';
      case AICapability.expandScene:
        return 'Expand Scene (Image Edit)';
      case AICapability.smartCutout:
        return 'Cutout (Image Edit)';
      case AICapability.videoFromImage:
        return 'Video Sequence (Unsupported)';
      case AICapability.firstLastFrame:
        return 'Frame Interpolation (Unsupported)';
      case AICapability.cameraMotion:
        return 'Camera Motion (Unsupported)';
      case AICapability.animateObject:
        return 'Object Animation (Unsupported)';
      case AICapability.videoRestyle:
        return 'Video Restyle (Unsupported)';
      case AICapability.understandCanvas:
        return 'Understand Canvas Structure';
      case AICapability.understandSelection:
        return 'Analyze Selection Context';
      case AICapability.callTools:
        return 'Tool Execution (Unsupported)';
      case AICapability.agentGenerate:
        return 'Agent Generation (Unsupported)';
      case AICapability.agentEdit:
        return 'Agent Edit (Unsupported)';
      case AICapability.agentArrange:
        return 'Agent Layout (Unsupported)';
      case AICapability.summarizeNotes:
        return 'Summarize Sticky Notes';
      case AICapability.promptToDiagram:
        return 'Prompt to Diagram (Unsupported)';
    }
  }

  String _getPromptHint(AICapability cap) {
    switch (cap) {
      case AICapability.sketchToImage:
        return 'Transform this sketch into a modernist villa with travertine stone and floor-to-ceiling glass...';
      case AICapability.relighting:
        return 'Golden hour lighting with warm amber sunset glow and long atmospheric shadows...';
      case AICapability.materialTransfer:
        return 'Replace concrete facade with dark cedar timber slats and black matte steel frame...';
      case AICapability.populate:
        return 'Add modern architectural entourage: pedestrians in casual attire and birch trees in perspective...';
      case AICapability.imageToVideo:
        return 'Animate this image with a slow cinematic camera move...';
      case AICapability.textTo3D:
        return 'Generate a clean 3D asset from text, for example: low-poly lounge chair, separated cushions, studio lighting...';
      case AICapability.imageTo3D:
        return 'Convert the selected product/reference image into a clean 3D model with watertight geometry...';
      default:
        return 'Enter prompt specifications (e.g. Modernist pavilion in forest, ultra photorealistic 8k)...';
    }
  }

  Widget _buildGenerationParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    const presets = [
      'Photorealistic Architecture',
      'Clay Model / Conceptual',
      'Atmospheric Watercolor',
      'Cyberpunk Neon Urban',
      'Interior Design Editorial',
      'Minimalist Scandi',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiSelect<String>(
          label: 'STYLE PRESET',
          value: state.selectedStylePreset,
          values: presets,
          format: (value) => value,
          onChanged: notifier.setStylePreset,
        ),
        if (_isThreeDCapability(state.activeCapability)) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildThreeDParams(state, notifier),
        ],
      ],
    );
  }

  bool _isThreeDCapability(AICapability capability) =>
      capability == AICapability.textTo3D ||
      capability == AICapability.imageTo3D;

  Widget _buildThreeDParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    final tokens = context.appTokens;
    const providers = [
      'triposr',
      'trellis',
      'fal-trellis2',
      'hunyuan3d',
      'comfyui',
    ];
    const meshQualities = ['draft', 'balanced', 'high'];
    const textureModes = ['none', 'vertex_color', 'pbr'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiSelect<String>(
          label: '3D PROVIDER',
          value: providers.contains(state.selectedThreeDProvider)
              ? state.selectedThreeDProvider
              : providers.first,
          values: providers,
          format: (value) => value == 'fal-trellis2'
              ? 'FAL TRELLIS2 (METERED)'
              : value.toUpperCase(),
          onChanged: notifier.setThreeDProvider,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildAiSelect<String>(
                label: 'MESH QUALITY',
                value: meshQualities.contains(state.selectedMeshQuality)
                    ? state.selectedMeshQuality
                    : meshQualities[1],
                values: meshQualities,
                format: (value) => value.toUpperCase(),
                onChanged: notifier.setMeshQuality,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildAiSelect<String>(
                label: 'TEXTURE MODE',
                value: textureModes.contains(state.selectedTextureMode)
                    ? state.selectedTextureMode
                    : textureModes.last,
                values: textureModes,
                format: (value) => value.toUpperCase(),
                onChanged: notifier.setTextureMode,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              'Triangle budget',
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
            Expanded(
              child: UiSlider(
                value: ((state.triangleBudget - 25000) / 225000).clamp(
                  0.0,
                  1.0,
                ),
                onChanged: (value) => _deferProviderUpdate(
                  () => notifier.setTriangleBudget(
                    (25000 + value * 225000).round(),
                  ),
                ),
              ),
            ),
            Text(
              '${(state.triangleBudget / 1000).round()}k',
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
        Text(
          state.activeCapability == AICapability.textTo3D
              ? 'Text → 3D memakai provider yang mendukung text input; TripoSR memerlukan reference image.'
              : 'Pilih satu image node di canvas agar worker dapat menjalankan image-to-3D.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.warning),
        ),
      ],
    );
  }

  Widget _buildGenerativeEditingParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    final tokens = context.appTokens;
    final configuredMask = state.maskDocument;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: UiButton(
            variant: UiButtonVariant.ghost,
            prefix: const Icon(Icons.brush_outlined, size: 15),
            onPressed: () async {
              final mask = await showUiDialog<AIMaskDocument>(
                context: context,
                builder: (_) => AIMaskEditorDialog(
                  initialMask:
                      configuredMask ??
                      const AIMaskDocument(
                        width: 512,
                        height: 512,
                        operation: AIMaskOperation.inpaint,
                      ),
                ),
              );
              if (mask != null && mounted) {
                notifier.setMaskDocument(mask);
                showUiToast(
                  context,
                  'Mask ready: ${mask.strokes.length} stroke(s).',
                  variant: UiToastVariant.success,
                );
              }
            },
            child: const Text('Open Mask Editor'),
          ),
        ),
        if (configuredMask != null) ...[
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mask configured · ${configuredMask.operation.name} · ${configuredMask.strokes.length} stroke(s)',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.success),
                ),
              ),
              UiButton(
                variant: UiButtonVariant.ghost,
                onPressed: notifier.clearMaskDocument,
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _deferProviderUpdate(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) update();
    });
  }

  Widget _buildTransformParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    const materials = [
      'Travertine Marble & Glass',
      'Exposed Brutalist Concrete',
      'Charred Shou Sugi Ban Wood',
      'Brushed Champagne Gold & Steel',
    ];

    const relighting = [
      'Golden Hour Sunset',
      'Overcast Diffuse Daylight',
      'Dramatic Studio Softbox',
      'Midnight Blue & Neon Glow',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiSelect<String>(
          label: 'MATERIAL SHADER',
          value: state.selectedMaterial,
          values: materials,
          format: (value) => value,
          onChanged: notifier.setMaterial,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildAiSelect<String>(
          label: 'RELIGHTING PRESET',
          value: state.selectedRelighting,
          values: relighting,
          format: (value) => value,
          onChanged: notifier.setRelighting,
        ),
      ],
    );
  }

  Widget _buildCompositionParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    const entourages = [
      'Modern Architectural Entourage (People & Trees)',
      'Luxury Vehicles & Street Furniture',
      'Lush Tropical Foliage & Plants',
      'Contemporary Office Furniture & Fixtures',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiSelect<String>(
          label: 'ENTOURAGE ASSET PACK',
          value: state.selectedEntourage,
          values: entourages,
          format: (value) => value,
          onChanged: notifier.setEntourage,
        ),
      ],
    );
  }

  Widget _buildVideoAIParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    const motions = [
      'Drone Orbit Flythrough',
      'Smooth Dolly Zoom In',
      'Horizontal Tracking Pan',
      'Slow Pedestal Rise',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAiSelect<String>(
          label: 'CAMERA MOTION TRAJECTORY',
          value: state.selectedCameraMotion,
          values: motions,
          format: (value) => value,
          onChanged: notifier.setCameraMotion,
        ),
      ],
    );
  }

  Map<String, dynamic>? _copilotContext(AICreativeEngineState state) {
    if (state.activeCategory != AICreativeCategory.aiAssistant) return null;
    final snapshot = AICopilotContextSnapshot.fromCanvas(
      projectId: widget.projectId,
      scope: state.selectedCopilotScope,
      allNodes: ref.read(documentNodesProvider),
      assets: ref.read(documentAssetsProvider).items,
      selectedNodeIds: ref.read(selectionProvider),
    );
    return snapshot.toJson();
  }

  Widget _buildAssistantParams(
    AICreativeEngineState state,
    AICreativeEngineNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiAlert(
          title: 'Canvas context is sent to a chat provider.',
          description:
              'Responses are text-only and do not create canvas actions.',
          icon: Icons.hub_outlined,
          variant: UiAlertVariant.info,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildAiSelect<AICopilotContextScope>(
          label: 'COPILOT CONTEXT',
          value: state.selectedCopilotScope,
          values: AICopilotContextScope.values,
          format: (value) => value.label,
          onChanged: notifier.setCopilotScope,
        ),
      ],
    );
  }

  Widget _buildJobHistory(List<AIJob> jobs, {required bool isProcessing}) {
    final tokens = context.appTokens;
    final notifier = ref.read(aiCreativeEngineProvider.notifier);
    if (jobs.isEmpty) {
      return UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No recent telemetry jobs.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return Column(
      children: jobs.take(5).map((job) {
        final isSuccess = job.status == AIJobStatus.completed;
        final isFailed = job.status == AIJobStatus.failed;
        final isRetryable = isFailed && _isThreeDCapability(job.capability);

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: UiSurface(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            borderColor: isFailed
                ? tokens.danger.withValues(alpha: 0.5)
                : tokens.panelBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSuccess
                          ? Icons.check_circle_outline
                          : (isFailed ? Icons.error_outline : Icons.sync),
                      size: 14,
                      color: isSuccess
                          ? tokens.success
                          : (isFailed ? tokens.danger : tokens.accent),
                    ),
                    const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        job.capability.name.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isRetryable)
                      UiIconButton(
                        icon: Icons.refresh,
                        size: UiButtonSize.sm,
                        tooltip: 'Retry 3D generation',
                        onPressed: isProcessing
                            ? null
                            : () => notifier.retryJob(
                                job: job,
                                onNodeCreated: widget.onNodeCreated,
                                canEditCanvas: widget.canEditCanvas,
                              ),
                      ),
                    if (job.status == AIJobStatus.processing)
                      UiIconButton(
                        icon: Icons.stop_circle_outlined,
                        variant: UiButtonVariant.destructive,
                        size: UiButtonSize.sm,
                        tooltip: 'Cancel AI job',
                        onPressed: isProcessing
                            ? () => notifier.cancelJob(job.id)
                            : null,
                      ),
                    if (job.resultImageUrls.length > 1)
                      UiIconButton(
                        icon: Icons.compare_arrows,
                        size: UiButtonSize.sm,
                        tooltip: 'Review AI variants',
                        onPressed: () async {
                          final reviewed = await showUiDialog<AIVariantSet>(
                            context: context,
                            builder: (_) => AIWorkflowReviewDialog(
                              initialVariants: _variantSetForJob(job),
                              provenance: job.provenance.isEmpty
                                  ? null
                                  : AIProvenanceNotice(
                                      provider:
                                          job.provider ?? 'configured provider',
                                      model: job.model,
                                      license:
                                          job.provenance['license'] as String?,
                                    ),
                            ),
                          );
                          if (!mounted || reviewed == null) return;
                          await notifier.saveVariantSet(
                            jobId: job.id,
                            variants: reviewed,
                          );
                        },
                      ),
                    Semantics(
                      key: ValueKey('ai-job-status-${job.id}'),
                      container: true,
                      liveRegion: job.status == AIJobStatus.processing,
                      label:
                          '${job.capability.name} job ${job.status.name}${job.isSimulated ? ', simulated' : ''}',
                      child: ExcludeSemantics(
                        child: UiBadge(
                          isFailed
                              ? 'FAILED'
                              : (job.isSimulated
                                    ? 'SIMULATED'
                                    : job.status.name.toUpperCase()),
                          variant: isFailed
                              ? UiBadgeVariant.destructive
                              : (job.isSimulated
                                    ? UiBadgeVariant.warning
                                    : isSuccess
                                    ? UiBadgeVariant.success
                                    : UiBadgeVariant.info),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  job.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
                if (job.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    job.errorMessage!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.danger, fontSize: 10),
                  ),
                ] else if (job.resultText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    job.resultText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

enum _AIComposerAction {
  image,
  editImage,
  sketchToImage,
  referenceToImage,
  video,
  model3d,
  assistant,
  uploadImage,
  useCanvasImage,
  removeAttachment,
}

class _AIImageAttachment {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const _AIImageAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
}

class _SelectedImageSource {
  final String? nodeId;
  final Uint8List? bytes;
  final String? base64;
  final String? url;
  final String? artifactReference;
  final String? storagePath;
  final String? mimeType;
  final int? byteLength;
  final Offset? spawnPosition;

  const _SelectedImageSource({
    this.nodeId,
    this.bytes,
    this.base64,
    this.url,
    this.artifactReference,
    this.storagePath,
    this.mimeType,
    this.byteLength,
    this.spawnPosition,
  });

  const _SelectedImageSource.empty()
    : nodeId = null,
      bytes = null,
      base64 = null,
      url = null,
      artifactReference = null,
      storagePath = null,
      mimeType = null,
      byteLength = null,
      spawnPosition = null;

  bool get hasReadableValue =>
      bytes?.isNotEmpty == true ||
      base64?.trim().isNotEmpty == true ||
      url?.trim().isNotEmpty == true;

  _SelectedImageSource copyWith({
    String? nodeId,
    Uint8List? bytes,
    String? base64,
    String? url,
    String? artifactReference,
    String? storagePath,
    String? mimeType,
    int? byteLength,
    Offset? spawnPosition,
  }) => _SelectedImageSource(
    nodeId: nodeId ?? this.nodeId,
    bytes: bytes ?? this.bytes,
    base64: base64 ?? this.base64,
    url: url ?? this.url,
    artifactReference: artifactReference ?? this.artifactReference,
    storagePath: storagePath ?? this.storagePath,
    mimeType: mimeType ?? this.mimeType,
    byteLength: byteLength ?? this.byteLength,
    spawnPosition: spawnPosition ?? this.spawnPosition,
  );
}
