import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../auth/state/auth_provider.dart';
import '../../../data/remote/supabase_sync_provider.dart';
import '../../../domain/models/workspace_governance.dart';
import '../domain/plugin_registry.dart';
import '../domain/remote_operability.dart';
import '../domain/usage_billing.dart';
import '../state/workspace_governance_provider.dart';

class WorkspaceGovernanceDialog extends ConsumerStatefulWidget {
  final AccessibilitySettings initialSettings;
  final Future<void> Function(AccessibilitySettings settings) onSave;
  final WorkspaceQuota quota;
  final WorkspaceUsage usage;
  final RetentionPolicy retentionPolicy;
  final List<WorkspaceAuditEvent> auditEvents;
  final WorkspacePolicy initialPolicy;
  final Future<void> Function(WorkspacePolicy policy)? onPolicySave;
  final PluginRegistry? initialPluginRegistry;
  final Future<void> Function(PluginRegistry registry)? onPluginRegistrySave;
  final WorkspaceHealthSnapshot? healthSnapshot;
  final EntitlementSnapshot? entitlement;
  final Future<WorkspaceSupportBundleReceipt> Function()? onSupportBundleSubmit;
  final String? cloudProjectId;
  final String? cloudExpectedUserId;

  const WorkspaceGovernanceDialog({
    required this.initialSettings,
    required this.onSave,
    this.quota = const WorkspaceQuota(),
    this.usage = const WorkspaceUsage(),
    this.retentionPolicy = const RetentionPolicy(),
    this.auditEvents = const [],
    this.initialPolicy = const WorkspacePolicy(),
    this.onPolicySave,
    this.initialPluginRegistry,
    this.onPluginRegistrySave,
    this.healthSnapshot,
    this.entitlement,
    this.onSupportBundleSubmit,
    this.cloudProjectId,
    this.cloudExpectedUserId,
    super.key,
  });

  @override
  ConsumerState<WorkspaceGovernanceDialog> createState() =>
      _WorkspaceGovernanceDialogState();
}

class _WorkspaceGovernanceDialogState
    extends ConsumerState<WorkspaceGovernanceDialog> {
  late AccessibilitySettings _settings;
  late WorkspacePolicy _policy;
  late PluginRegistry _pluginRegistry;
  bool _busy = false;
  bool _supportBundleBusy = false;
  String? _error;
  String? _supportBundleStatus;
  bool _cloudDeletionBusy = false;
  bool _cloudConfirmationOpen = false;
  String? _cloudDeletionMessage;
  int _cloudActionGeneration = 0;
  WorkspaceGovernanceKey? _boundCloudGovernanceKey;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _policy = widget.initialPolicy.copyWith(
      quota: widget.quota,
      retention: widget.retentionPolicy,
    );
    _pluginRegistry = widget.initialPluginRegistry ?? PluginRegistry();
    _boundCloudGovernanceKey = _cloudGovernanceKey;
  }

  @override
  void didUpdateWidget(covariant WorkspaceGovernanceDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _cloudGovernanceKey;
    if (nextKey != _boundCloudGovernanceKey) {
      _boundCloudGovernanceKey = nextKey;
      _cloudActionGeneration++;
      _cloudDeletionBusy = false;
      _cloudConfirmationOpen = false;
      _cloudDeletionMessage = null;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_settings);
      if (widget.onPolicySave != null) await widget.onPolicySave!(_policy);
      if (widget.onPluginRegistrySave != null) {
        await widget.onPluginRegistrySave!(_pluginRegistry);
      }
      if (mounted) Navigator.of(context).pop(_settings);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Settings could not be saved: $error';
      });
    }
  }

  void _update(AccessibilitySettings next) {
    if (_busy) return;
    setState(() => _settings = next);
  }

  void _togglePlugin(PluginRegistration registration) {
    if (_busy) return;
    try {
      if (registration.state == PluginRegistrationState.enabled) {
        _pluginRegistry.disable(registration.manifest.id);
      } else if (registration.state == PluginRegistrationState.disabled) {
        _pluginRegistry.enable(registration.manifest.id);
      }
      setState(() {});
    } catch (error) {
      setState(() => _error = 'Plugin could not be updated: $error');
    }
  }

  String? get _cloudProjectId {
    final projectId = widget.cloudProjectId?.trim();
    return projectId == null || projectId.isEmpty ? null : projectId;
  }

  String? get _cloudExpectedUserId {
    final userId = widget.cloudExpectedUserId?.trim();
    return userId == null || userId.isEmpty ? null : userId;
  }

  WorkspaceGovernanceKey? get _cloudGovernanceKey {
    final projectId = _cloudProjectId;
    final expectedUserId = _cloudExpectedUserId;
    if (projectId == null || expectedUserId == null) return null;
    return WorkspaceGovernanceKey(
      projectId: projectId,
      expectedUserId: expectedUserId,
    );
  }

  Future<bool> _confirmCloudDeletion({required bool cancelRequest}) async {
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => _CloudDeletionConfirmationDialog(
        cancelRequest: cancelRequest,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    return confirmed == true;
  }

  Future<void> _runCloudDeletionAction({required bool cancelRequest}) async {
    final projectId = _cloudProjectId;
    final expectedUserId = _cloudExpectedUserId;
    if (projectId == null ||
        expectedUserId == null ||
        _cloudDeletionBusy ||
        _cloudConfirmationOpen) {
      return;
    }
    final auth = ref.read(authUserProvider);
    final key = WorkspaceGovernanceKey(
      projectId: projectId,
      expectedUserId: expectedUserId,
    );
    final initial = ref.read(workspaceGovernanceProvider(key));
    final governance = initial.governance.valueOrNull;
    final service = ref.read(supabaseSyncServiceProvider);
    final authenticatedUserId = auth.valueOrNull?.id;
    if (governance == null ||
        !governance.eligibility.isOwner ||
        governance.snapshot.projectId != projectId ||
        governance.snapshot.hasPendingDeletionRequest != cancelRequest ||
        service.currentUserId != expectedUserId ||
        authenticatedUserId != expectedUserId) {
      setState(
        () => _cloudDeletionMessage = CreativeStudioLocalizations.of(
          context,
        ).cloudDeletionUnavailable,
      );
      ref.read(workspaceGovernanceProvider(key).notifier).load();
      return;
    }
    final copy = CreativeStudioLocalizations.of(context);
    setState(() {
      _cloudConfirmationOpen = true;
      _cloudDeletionMessage = null;
    });
    final actionGeneration = ++_cloudActionGeneration;
    bool confirmed;
    try {
      confirmed = await _confirmCloudDeletion(cancelRequest: cancelRequest);
    } finally {
      if (mounted) setState(() => _cloudConfirmationOpen = false);
    }
    if (!mounted || actionGeneration != _cloudActionGeneration) return;
    if (!confirmed ||
        _cloudProjectId != projectId ||
        _cloudExpectedUserId != expectedUserId) {
      return;
    }
    final controller = ref.read(workspaceGovernanceProvider(key).notifier);
    if (ref.read(authUserProvider).valueOrNull?.id != expectedUserId ||
        service.currentUserId != expectedUserId) {
      await controller.load();
      if (!mounted) return;
      setState(() => _cloudDeletionMessage = copy.cloudDeletionUnavailable);
      return;
    }
    await controller.load();
    if (!mounted ||
        actionGeneration != _cloudActionGeneration ||
        _cloudProjectId != projectId ||
        _cloudExpectedUserId != expectedUserId ||
        service.currentUserId != expectedUserId) {
      return;
    }
    final current = ref
        .read(workspaceGovernanceProvider(key))
        .governance
        .valueOrNull;
    if (current == null ||
        !current.eligibility.isOwner ||
        current.snapshot.projectId != projectId ||
        current.snapshot.hasPendingDeletionRequest != cancelRequest) {
      if (!mounted) return;
      setState(() => _cloudDeletionMessage = copy.cloudDeletionUnavailable);
      return;
    }

    setState(() {
      _cloudDeletionBusy = true;
      _cloudDeletionMessage = null;
    });
    try {
      final succeeded = cancelRequest
          ? await controller.cancelDeletion()
          : await controller.requestDeletion();
      if (!mounted || actionGeneration != _cloudActionGeneration) return;
      final state = ref.read(workspaceGovernanceProvider(key));
      setState(
        () => _cloudDeletionMessage = succeeded
            ? cancelRequest
                  ? copy.cloudDeletionCancelSuccess
                  : copy.cloudDeletionRequestSuccess
            : state.governance.hasError
            ? copy.cloudDeletionStatusUnavailableAfterAction
            : copy.cloudDeletionActionFailed,
      );
    } catch (_) {
      if (!mounted || actionGeneration != _cloudActionGeneration) return;
      setState(() => _cloudDeletionMessage = copy.cloudDeletionActionFailed);
    } finally {
      if (mounted && actionGeneration == _cloudActionGeneration) {
        setState(() => _cloudDeletionBusy = false);
      }
    }
  }

  Future<void> _submitSupportBundle() async {
    if (_supportBundleBusy || widget.onSupportBundleSubmit == null) return;
    setState(() {
      _supportBundleBusy = true;
      _supportBundleStatus = null;
    });
    try {
      final receipt = await widget.onSupportBundleSubmit!();
      if (!mounted) return;
      setState(() {
        _supportBundleBusy = false;
        _supportBundleStatus =
            'Support bundle ${receipt.status}: ${receipt.operationId}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _supportBundleBusy = false;
        _supportBundleStatus = 'Support bundle failed: $error';
      });
    }
  }

  String _pluginStateLabel(PluginRegistrationState state) => switch (state) {
    PluginRegistrationState.pendingReview => 'Pending review',
    PluginRegistrationState.enabled => 'Enabled',
    PluginRegistrationState.disabled => 'Disabled',
    PluginRegistrationState.blocked => 'Blocked',
  };

  String _entitlementStatusLabel(EntitlementStatus status) => switch (status) {
    EntitlementStatus.active => 'active',
    EntitlementStatus.trialing => 'trialing',
    EntitlementStatus.pastDue => 'past due',
    EntitlementStatus.canceled => 'canceled',
    EntitlementStatus.paused => 'paused',
  };

  Widget _buildCloudDeletionSection(
    WorkspaceGovernanceKey key,
    WorkspaceGovernanceControllerState state, {
    required bool accountMatches,
  }) {
    final copy = CreativeStudioLocalizations.of(context);
    final governance = state.governance.valueOrNull;
    final owner =
        accountMatches &&
        governance?.eligibility.isOwner == true &&
        governance?.snapshot.projectId == key.projectId;
    final pending = governance?.snapshot.hasPendingDeletionRequest == true;
    final timestamp = governance?.snapshot.deletionRequestedAt;
    final statusAvailable = governance != null;
    final canAct =
        owner && statusAvailable && !state.isMutating && !_cloudDeletionBusy;
    final errorMessage = state.governance.hasError
        ? copy.cloudDeletionUnavailable
        : null;

    return UiSurface(
      key: const ValueKey('governance-cloud-deletion'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.cloudDeletionSection,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(copy.cloudDeletionLocalScope),
          const SizedBox(height: AppSpacing.sm),
          if (state.governance.isLoading)
            Semantics(
              liveRegion: true,
              label: copy.cloudDeletionLoading,
              child: const UiProgressIndicator(
                semanticsLabel: 'Loading cloud deletion status',
                size: 20,
              ),
            )
          else if (!accountMatches)
            Semantics(
              liveRegion: true,
              child: Text(copy.cloudDeletionUnavailable),
            )
          else if (!statusAvailable)
            Semantics(
              liveRegion: true,
              child: Text(errorMessage ?? copy.cloudDeletionUnavailable),
            )
          else if (!owner)
            Text(copy.cloudDeletionOwnerOnly)
          else if (pending) ...[
            Text(copy.cloudDeletionPending),
            if (timestamp != null)
              Text('${copy.cloudDeletionUpdatedAt} ${timestamp.toLocal()}'),
          ] else
            Text(copy.cloudDeletionNotRequested),
          if (_cloudDeletionMessage != null) ...[
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Semantics(liveRegion: true, child: Text(_cloudDeletionMessage!)),
          ],
          if (state.governance.hasError && !state.governance.isLoading)
            UiButton(
              key: const ValueKey('governance-cloud-deletion-retry'),
              variant: UiButtonVariant.outline,
              onPressed: _cloudDeletionBusy
                  ? null
                  : () => ref
                        .read(workspaceGovernanceProvider(key).notifier)
                        .load(),
              child: Text(copy.cloudDeletionRetry),
            ),
          if (owner && statusAvailable)
            UiButton(
              key: ValueKey(
                pending
                    ? 'governance-cloud-deletion-cancel'
                    : 'governance-cloud-deletion-request',
              ),
              variant: pending
                  ? UiButtonVariant.outline
                  : UiButtonVariant.destructive,
              onPressed: canAct
                  ? () => _runCloudDeletionAction(cancelRequest: pending)
                  : null,
              prefix: _cloudDeletionBusy || state.isMutating
                  ? const UiProgressIndicator(
                      semanticsLabel: 'Updating cloud deletion status',
                      size: 16,
                    )
                  : Icon(
                      pending ? Icons.undo_outlined : Icons.cloud_off_outlined,
                    ),
              child: Text(
                _cloudDeletionBusy || state.isMutating
                    ? pending
                          ? copy.cloudDeletionCancelling
                          : copy.cloudDeletionRequesting
                    : pending
                    ? copy.cloudDeletionCancelAction
                    : copy.cloudDeletionRequestAction,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloudKey = _cloudGovernanceKey;
    if (cloudKey != _boundCloudGovernanceKey) {
      _boundCloudGovernanceKey = cloudKey;
      _cloudActionGeneration++;
      _cloudDeletionBusy = false;
      _cloudConfirmationOpen = false;
      _cloudDeletionMessage = null;
    }
    final cloudState = cloudKey == null
        ? null
        : ref.watch(workspaceGovernanceProvider(cloudKey));
    final authState = cloudKey == null ? null : ref.watch(authUserProvider);
    final cloudAccountMatches =
        cloudKey != null &&
        authState?.valueOrNull?.id == cloudKey.expectedUserId;
    final usageWithinQuota = widget.usage.within(widget.quota);
    final tokens = context.appTokens;
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 620);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    return UiDialog(
      key: const ValueKey('workspace-governance-dialog'),
      semanticsLabel: 'Workspace governance settings',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Workspace Governance',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close workspace governance',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: Material(
                  type: MaterialType.transparency,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Accessibility and workspace policies are stored locally and can be enforced by a team backend when configured.',
                        ),
                        if (widget.healthSnapshot != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const UiSectionHeader(title: 'BACKEND HEALTH'),
                          const SizedBox(height: AppSpacing.sm),
                          UiSurface(
                            key: const ValueKey('governance-health-status'),
                            color: tokens.panelElevated,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                Icon(
                                  widget.healthSnapshot!.isAvailable
                                      ? Icons.cloud_done_outlined
                                      : Icons.cloud_off_outlined,
                                  color: widget.healthSnapshot!.isAvailable
                                      ? tokens.success
                                      : tokens.danger,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Status: ${widget.healthSnapshot!.status.name}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: tokens.text,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Version ${widget.healthSnapshot!.version} · ${widget.healthSnapshot!.checks.length} checks',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: tokens.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final check in widget.healthSnapshot!.checks)
                            Text(
                              '${check.name}: ${check.status.name} · ${check.message}',
                            ),
                        ],
                        if (widget.entitlement != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          const UiSectionHeader(title: 'BILLING ENTITLEMENT'),
                          const SizedBox(height: AppSpacing.sm),
                          UiSurface(
                            key: const ValueKey(
                              'governance-entitlement-status',
                            ),
                            color: tokens.panelElevated,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                Icon(
                                  widget.entitlement!.status ==
                                              EntitlementStatus.active ||
                                          widget.entitlement!.status ==
                                              EntitlementStatus.trialing
                                      ? Icons.verified_outlined
                                      : Icons.warning_amber_outlined,
                                  color:
                                      widget.entitlement!.status ==
                                              EntitlementStatus.active ||
                                          widget.entitlement!.status ==
                                              EntitlementStatus.trialing
                                      ? tokens.success
                                      : tokens.warning,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.entitlement!.provider} · ${widget.entitlement!.planId}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: tokens.text,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        'Status ${_entitlementStatusLabel(widget.entitlement!.status)} · revision ${widget.entitlement!.revision}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: tokens.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Seats ${widget.entitlement!.limitFor(UsageMetric.seats)} · AI credits ${widget.entitlement!.limitFor(UsageMetric.aiCredits)}',
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        const UiSectionHeader(title: 'ACCESSIBILITY'),
                        UiSwitch(
                          key: const ValueKey('governance-reduced-motion'),
                          label: const Text('Reduce motion'),
                          description: const Text(
                            'Use zero-duration transitions where supported.',
                          ),
                          value: _settings.reducedMotion,
                          onChange: (value) =>
                              _update(_settings.copyWith(reducedMotion: value)),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-high-contrast'),
                          label: const Text('High contrast'),
                          value: _settings.highContrast,
                          onChange: (value) =>
                              _update(_settings.copyWith(highContrast: value)),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-keyboard-only'),
                          label: const Text('Keyboard-only flow'),
                          value: _settings.keyboardOnly,
                          onChange: (value) =>
                              _update(_settings.copyWith(keyboardOnly: value)),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-larger-text'),
                          label: const Text('Larger text'),
                          value: _settings.largerText,
                          onChange: (value) =>
                              _update(_settings.copyWith(largerText: value)),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-focus'),
                          label: const Text('Always show focus'),
                          value: _settings.alwaysShowFocus,
                          onChange: (value) => _update(
                            _settings.copyWith(alwaysShowFocus: value),
                          ),
                        ),
                        Divider(
                          height: AppSpacing.xl,
                          thickness: AppBorder.thin,
                          color: tokens.panelBorder,
                        ),
                        const UiSectionHeader(title: 'WORKSPACE POLICY STATUS'),
                        const SizedBox(height: AppSpacing.sm),
                        UiSwitch(
                          key: const ValueKey('governance-public-sharing'),
                          label: const Text('Allow public sharing'),
                          value: _policy.allowPublicSharing,
                          onChange: _busy
                              ? null
                              : (value) => setState(
                                  () => _policy = _policy.copyWith(
                                    allowPublicSharing: value,
                                  ),
                                ),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-embeds'),
                          label: const Text('Allow embeds'),
                          value: _policy.allowEmbeds,
                          onChange: _busy
                              ? null
                              : (value) => setState(
                                  () => _policy = _policy.copyWith(
                                    allowEmbeds: value,
                                  ),
                                ),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-ai'),
                          label: const Text('Allow AI generation'),
                          value: _policy.allowAiGeneration,
                          onChange: _busy
                              ? null
                              : (value) => setState(
                                  () => _policy = _policy.copyWith(
                                    allowAiGeneration: value,
                                  ),
                                ),
                        ),
                        UiSwitch(
                          key: const ValueKey('governance-data-export'),
                          label: const Text('Allow data export'),
                          value: _policy.allowDataExport,
                          onChange: _busy
                              ? null
                              : (value) => setState(
                                  () => _policy = _policy.copyWith(
                                    allowDataExport: value,
                                  ),
                                ),
                        ),
                        Text('Billing plan: ${_policy.billingPlan}'),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Quota: ${usageWithinQuota ? 'within limits' : 'over configured limits'}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: usageWithinQuota
                                    ? tokens.success
                                    : tokens.danger,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          'Storage ${widget.usage.storageBytes} / ${widget.quota.storageBytes} bytes · Assets ${widget.usage.assetBytes} / ${widget.quota.assetBytes} bytes',
                        ),
                        Text(
                          'Trash retention: ${widget.retentionPolicy.trashRetention.inDays} days · Audit retention: ${widget.retentionPolicy.auditLogRetention.inDays} days',
                        ),
                        Text(
                          'User export: ${widget.retentionPolicy.allowUserExport ? 'allowed' : 'restricted'}',
                        ),
                        if (widget.onSupportBundleSubmit != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          UiButton(
                            key: const ValueKey(
                              'governance-support-bundle-button',
                            ),
                            variant: UiButtonVariant.outline,
                            onPressed: _supportBundleBusy
                                ? null
                                : _submitSupportBundle,
                            prefix: const Icon(
                              Icons.support_agent_outlined,
                              size: 16,
                            ),
                            child: Text(
                              _supportBundleBusy
                                  ? 'Sending support bundle...'
                                  : 'Send redacted support bundle',
                            ),
                          ),
                          if (_supportBundleStatus != null)
                            Semantics(
                              key: const ValueKey(
                                'governance-support-bundle-status',
                              ),
                              liveRegion: true,
                              child: Text(_supportBundleStatus!),
                            ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        const UiSectionHeader(title: 'LOCAL PLUGINS'),
                        const Text(
                          'Plugin permissions are reviewed before enablement. Runtime sandbox enforcement remains local until a production plugin service is connected.',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (_pluginRegistry.registrations.isEmpty)
                          const Text('No plugins registered.')
                        else
                          for (final registration
                              in _pluginRegistry.registrations)
                            UiSurface(
                              key: ValueKey(
                                'governance-plugin-${registration.manifest.id}',
                              ),
                              color: tokens.panelElevated,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          registration.manifest.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: tokens.text,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          '${registration.manifest.id} · v${registration.manifest.version} · ${_pluginStateLabel(registration.state)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: tokens.textMuted,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (registration.state ==
                                          PluginRegistrationState.enabled ||
                                      registration.state ==
                                          PluginRegistrationState.disabled)
                                    UiIconButton(
                                      key: ValueKey(
                                        'governance-plugin-toggle-${registration.manifest.id}',
                                      ),
                                      tooltip:
                                          registration.state ==
                                              PluginRegistrationState.enabled
                                          ? 'Disable plugin'
                                          : 'Enable plugin',
                                      onPressed: _busy
                                          ? null
                                          : () => _togglePlugin(registration),
                                      icon:
                                          registration.state ==
                                              PluginRegistrationState.enabled
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                    ),
                                ],
                              ),
                            ),
                        if (cloudKey != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _buildCloudDeletionSection(
                            cloudKey,
                            cloudState!,
                            accountMatches: cloudAccountMatches,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        const UiSectionHeader(title: 'Recent audit activity'),
                        const SizedBox(height: AppSpacing.sm),
                        if (widget.auditEvents.isEmpty)
                          const Text('No audit events available.')
                        else
                          for (final event in widget.auditEvents.take(8))
                            UiSurface(
                              color: tokens.panelElevated,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${event.operation.isEmpty ? event.action : event.operation} · ${event.result}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: tokens.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    '${event.targetType}:${event.targetId} · ${event.timestamp.toLocal()}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: tokens.textMuted),
                                  ),
                                ],
                              ),
                            ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: tokens.danger),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    key: const ValueKey('governance-save-button'),
                    onPressed: _busy ? null : _save,
                    prefix: _busy
                        ? const UiProgressIndicator(
                            semanticsLabel: 'Saving workspace settings',
                            size: 16,
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    child: Text(_busy ? 'Saving...' : 'Save settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudDeletionConfirmationDialog extends StatelessWidget {
  const _CloudDeletionConfirmationDialog({
    required this.cancelRequest,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool cancelRequest;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    return UiDialog(
      key: const ValueKey('governance-cloud-deletion-confirmation'),
      semanticsLabel: cancelRequest
          ? copy.cloudDeletionCancelConfirmTitle
          : copy.cloudDeletionRequestConfirmTitle,
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 460),
      builder: (dialogContext, style) => Padding(
        padding: AppResponsive.dialogPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              cancelRequest
                  ? copy.cloudDeletionCancelConfirmTitle
                  : copy.cloudDeletionRequestConfirmTitle,
              style: style.titleTextStyle,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              cancelRequest
                  ? copy.cloudDeletionCancelConfirmBody
                  : copy.cloudDeletionRequestConfirmBody,
            ),
            const SizedBox(height: AppSpacing.pageWide),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                UiButton(
                  key: const ValueKey(
                    'governance-cloud-deletion-cancel-confirm',
                  ),
                  variant: UiButtonVariant.ghost,
                  onPressed: onCancel,
                  child: Text(copy.cancel),
                ),
                UiButton(
                  key: const ValueKey(
                    'governance-cloud-deletion-confirm-button',
                  ),
                  variant: UiButtonVariant.destructive,
                  onPressed: onConfirm,
                  child: Text(copy.cloudDeletionConfirmAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
