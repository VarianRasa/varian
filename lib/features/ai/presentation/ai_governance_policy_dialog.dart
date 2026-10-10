import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/ai_governance.dart';

class AIGovernancePolicyDialog extends StatefulWidget {
  final AIGovernancePolicy initialPolicy;
  final Future<void> Function(AIGovernancePolicy policy) onSave;

  const AIGovernancePolicyDialog({
    required this.initialPolicy,
    required this.onSave,
    super.key,
  });

  @override
  State<AIGovernancePolicyDialog> createState() =>
      _AIGovernancePolicyDialogState();
}

class _AIGovernancePolicyDialogState extends State<AIGovernancePolicyDialog> {
  late bool _allowGeneration;
  late bool _allowUnknownProviders;
  late bool _retainPrompt;
  late bool _retainInputArtifacts;
  late bool _retainOutputArtifacts;
  late bool _allowProvenanceExport;
  late TextEditingController _quotaController;
  late TextEditingController _thresholdController;
  late TextEditingController _maxCreditsController;
  late TextEditingController _rateCountController;
  late TextEditingController _rateWindowController;
  late TextEditingController _fallbackController;
  late TextEditingController _retentionController;
  late TextEditingController _newProviderController;
  late TextEditingController _newModelsController;
  late Map<String, AIProviderPolicy> _providers;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final policy = widget.initialPolicy;
    _allowGeneration = policy.allowGeneration;
    _allowUnknownProviders = policy.allowUnknownProviders;
    _retainPrompt = policy.retention.retainPrompt;
    _retainInputArtifacts = policy.retention.retainInputArtifacts;
    _retainOutputArtifacts = policy.retention.retainOutputArtifacts;
    _allowProvenanceExport = policy.retention.allowProvenanceExport;
    _quotaController = TextEditingController(
      text: _numberText(policy.quotaCredits),
    );
    _thresholdController = TextEditingController(
      text: _numberText(policy.budgetAlertThreshold),
    );
    _maxCreditsController = TextEditingController(
      text: policy.maxCreditsPerJob.toString(),
    );
    _rateCountController = TextEditingController(
      text: policy.rateLimitCount.toString(),
    );
    _rateWindowController = TextEditingController(
      text: policy.rateLimitWindow.inSeconds.toString(),
    );
    _fallbackController = TextEditingController(
      text: policy.fallbackProviders.join(', '),
    );
    _retentionController = TextEditingController(
      text: policy.retention.jobRetention.inDays.toString(),
    );
    _newProviderController = TextEditingController();
    _newModelsController = TextEditingController();
    _providers = {...policy.providers};
  }

  @override
  void dispose() {
    _quotaController.dispose();
    _thresholdController.dispose();
    _maxCreditsController.dispose();
    _rateCountController.dispose();
    _rateWindowController.dispose();
    _fallbackController.dispose();
    _retentionController.dispose();
    _newProviderController.dispose();
    _newModelsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quota = double.tryParse(_quotaController.text.trim());
    final threshold = double.tryParse(_thresholdController.text.trim());
    final maxCredits = int.tryParse(_maxCreditsController.text.trim());
    final rateCount = int.tryParse(_rateCountController.text.trim());
    final rateWindow = int.tryParse(_rateWindowController.text.trim());
    final retentionDays = int.tryParse(_retentionController.text.trim());
    if (quota == null ||
        threshold == null ||
        maxCredits == null ||
        rateCount == null ||
        rateWindow == null ||
        retentionDays == null) {
      setState(() => _error = 'All numeric fields must contain valid values.');
      return;
    }
    final policy = AIGovernancePolicy(
      allowGeneration: _allowGeneration,
      allowUnknownProviders: _allowUnknownProviders,
      providers: _providers,
      fallbackProviders: _fallbackController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false),
      quotaCredits: quota,
      budgetAlertThreshold: threshold,
      maxCreditsPerJob: maxCredits,
      rateLimitCount: rateCount,
      rateLimitWindow: Duration(seconds: rateWindow),
      retention: AIDataRetentionPolicy(
        jobRetention: Duration(days: retentionDays),
        retainPrompt: _retainPrompt,
        retainInputArtifacts: _retainInputArtifacts,
        retainOutputArtifacts: _retainOutputArtifacts,
        allowProvenanceExport: _allowProvenanceExport,
      ),
    );
    final errors = policy.validate();
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join(' '));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(policy);
      if (mounted) Navigator.of(context).pop(policy);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'AI policy could not be saved: $error';
      });
    }
  }

  void _addProvider() {
    final provider = _newProviderController.text.trim();
    if (provider.isEmpty) {
      setState(() => _error = 'Provider name is required.');
      return;
    }
    final models = _newModelsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    setState(() {
      _providers[provider] =
          _providers[provider]?.copyWith(allowedModels: models) ??
          AIProviderPolicy(provider: provider, allowedModels: models);
      _newProviderController.clear();
      _newModelsController.clear();
      _error = null;
    });
  }

  String _numberText(num value) {
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    String? helper,
  }) => UiTextField(
    controller: controller,
    enabled: !_busy,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    label: label,
    description: helper,
  );

  Widget _responsiveFields(List<Widget> fields) {
    if (!AppResponsive.isNarrow(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < fields.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: fields[index]),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < fields.length; index++) ...[
          if (index > 0)
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
          fields[index],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 720);
    return UiDialog(
      key: const ValueKey('ai-governance-policy-dialog'),
      semanticsLabel: 'AI governance policy',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxHeight),
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
                      'AI Governance Policy',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close AI governance policy',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UiSwitch(
                        key: const ValueKey('ai-governance-allow-generation'),
                        label: const Text('Allow AI generation'),
                        value: _allowGeneration,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _allowGeneration = value),
                      ),
                      UiSwitch(
                        key: const ValueKey('ai-governance-allow-unknown'),
                        label: const Text(
                          'Allow providers without an explicit policy',
                        ),
                        value: _allowUnknownProviders,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _allowUnknownProviders = value),
                      ),
                      const Divider(),
                      Text(
                        'Quota and rate limits',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _responsiveFields([
                        _numberField(
                          label: 'Quota credits',
                          controller: _quotaController,
                        ),
                        _numberField(
                          label: 'Budget alert threshold',
                          controller: _thresholdController,
                          helper: '0.0 to 1.0',
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
                      _responsiveFields([
                        _numberField(
                          label: 'Max credits per job',
                          controller: _maxCreditsController,
                        ),
                        _numberField(
                          label: 'Requests per window',
                          controller: _rateCountController,
                        ),
                        _numberField(
                          label: 'Window seconds',
                          controller: _rateWindowController,
                        ),
                      ]),
                      const SizedBox(height: AppSpacing.sm + AppSpacing.xs / 2),
                      UiTextField(
                        key: const ValueKey('ai-governance-fallbacks'),
                        controller: _fallbackController,
                        enabled: !_busy,
                        label: 'Fallback providers',
                        description: 'Comma-separated, ordered by preference',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Provider allowlist',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_providers.isEmpty)
                        Text(
                          'No explicit provider policies configured.',
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(color: tokens.textMuted),
                        )
                      else
                        for (final entry in _providers.entries)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: _ProviderPolicyEditor(
                              key: ValueKey('ai-provider-${entry.key}'),
                              policy: entry.value,
                              enabled: !_busy,
                              onChanged: (next) =>
                                  setState(() => _providers[entry.key] = next),
                              onRemove: () =>
                                  setState(() => _providers.remove(entry.key)),
                            ),
                          ),
                      _responsiveFields([
                        UiTextField(
                          key: const ValueKey('ai-governance-new-provider'),
                          controller: _newProviderController,
                          enabled: !_busy,
                          label: 'New provider',
                        ),
                        UiTextField(
                          controller: _newModelsController,
                          enabled: !_busy,
                          label: 'Allowed models',
                          description: 'Comma-separated; empty means all',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: UiButton(
                            onPressed: _busy ? null : _addProvider,
                            prefix: const Icon(Icons.add, size: 16),
                            child: const Text('Add provider'),
                          ),
                        ),
                      ]),
                      const Divider(height: AppSpacing.xl + AppSpacing.xs),
                      Text(
                        'Retention and provenance',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _numberField(
                        label: 'Job retention days',
                        controller: _retentionController,
                      ),
                      UiSwitch(
                        label: const Text('Retain prompts'),
                        value: _retainPrompt,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _retainPrompt = value),
                      ),
                      UiSwitch(
                        label: const Text('Retain input artifacts'),
                        value: _retainInputArtifacts,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _retainInputArtifacts = value),
                      ),
                      UiSwitch(
                        label: const Text('Retain output artifacts'),
                        value: _retainOutputArtifacts,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _retainOutputArtifacts = value),
                      ),
                      UiSwitch(
                        label: const Text('Allow provenance export'),
                        value: _allowProvenanceExport,
                        enabled: !_busy,
                        onChange: (value) =>
                            setState(() => _allowProvenanceExport = value),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  key: const ValueKey('ai-governance-error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: tokens.danger),
                ),
              ],
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
                    key: const ValueKey('ai-governance-save-button'),
                    onPressed: _busy ? null : _save,
                    prefix: const Icon(Icons.save_outlined, size: 16),
                    child: Text(_busy ? 'Saving...' : 'Save policy'),
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

class _ProviderPolicyEditor extends StatefulWidget {
  final AIProviderPolicy policy;
  final bool enabled;
  final ValueChanged<AIProviderPolicy> onChanged;
  final VoidCallback onRemove;

  const _ProviderPolicyEditor({
    required this.policy,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  @override
  State<_ProviderPolicyEditor> createState() => _ProviderPolicyEditorState();
}

class _ProviderPolicyEditorState extends State<_ProviderPolicyEditor> {
  late TextEditingController _modelsController;

  @override
  void initState() {
    super.initState();
    _modelsController = TextEditingController(
      text: widget.policy.allowedModels.join(', '),
    );
  }

  @override
  void didUpdateWidget(covariant _ProviderPolicyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy.provider != widget.policy.provider ||
        oldWidget.policy.allowedModels != widget.policy.allowedModels) {
      _modelsController.text = widget.policy.allowedModels.join(', ');
    }
  }

  @override
  void dispose() {
    _modelsController.dispose();
    super.dispose();
  }

  void _updateModels(String value) {
    final models = value
        .split(',')
        .map((model) => model.trim())
        .where((model) => model.isNotEmpty)
        .toSet();
    widget.onChanged(widget.policy.copyWith(allowedModels: models));
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy;
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  policy.provider,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              UiIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Remove provider policy',
                onPressed: widget.enabled ? widget.onRemove : null,
              ),
            ],
          ),
          UiSwitch(
            label: const Text('Enabled'),
            value: policy.enabled,
            enabled: widget.enabled,
            onChange: (value) =>
                widget.onChanged(policy.copyWith(enabled: value)),
          ),
          UiSwitch(
            label: const Text('Allow experimental models'),
            value: policy.allowExperimental,
            enabled: widget.enabled,
            onChange: (value) =>
                widget.onChanged(policy.copyWith(allowExperimental: value)),
          ),
          UiTextField(
            controller: _modelsController,
            enabled: widget.enabled,
            onChanged: _updateModels,
            label: 'Allowed models',
            description: 'Empty means all models',
          ),
        ],
      ),
    );
  }
}
