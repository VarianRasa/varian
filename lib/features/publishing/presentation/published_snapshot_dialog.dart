import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/document.dart';
import '../domain/published_snapshot.dart';

typedef PublishedSnapshotCallback =
    Future<String?> Function(PublishedSnapshot snapshot);

class PublishedSnapshotDialog extends StatefulWidget {
  final CanvasDocument document;
  final String publishedBy;
  final PublishedSnapshot? existingSnapshot;
  final PublishedSnapshotCallback onPublish;

  const PublishedSnapshotDialog({
    required this.document,
    required this.publishedBy,
    required this.onPublish,
    this.existingSnapshot,
    super.key,
  });

  @override
  State<PublishedSnapshotDialog> createState() =>
      _PublishedSnapshotDialogState();
}

class _PublishedSnapshotDialogState extends State<PublishedSnapshotDialog> {
  late PublishedAccess _access;
  late PublishedDownloadPolicy _downloadPolicy;
  late String _expiry;
  late bool _embedEnabled;
  late bool _watermarkEnabled;
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  PublishedSnapshot? _published;
  String? _shareLink;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSnapshot;
    _access = existing?.access ?? PublishedAccess.link;
    _downloadPolicy =
        existing?.downloadPolicy ?? PublishedDownloadPolicy.allowed;
    _expiry = _expiryValue(existing?.expiresAt);
    _embedEnabled = existing?.embedEnabled ?? false;
    _watermarkEnabled = existing?.watermarkEnabled ?? false;
  }

  String? get _embedLink {
    final link = _shareLink;
    if (link == null || link.isEmpty || !_embedEnabled) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'embed': '1'})
        .toString();
  }

  Future<void> _copyEmbedLink() async {
    final link = _embedLink;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      showUiToast(
        context,
        'Embed link copied.',
        variant: UiToastVariant.success,
      );
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  String _expiryValue(DateTime? expiresAt) {
    if (expiresAt == null) return 'never';
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining <= const Duration(hours: 2)) return '1h';
    if (remaining <= const Duration(days: 2)) return '1d';
    return '7d';
  }

  DateTime? _expiresAt() => switch (_expiry) {
    '1h' => DateTime.now().add(const Duration(hours: 1)),
    '1d' => DateTime.now().add(const Duration(days: 1)),
    '7d' => DateTime.now().add(const Duration(days: 7)),
    _ => null,
  };

  String _accessLabel(PublishedAccess value) => switch (value) {
    PublishedAccess.link => 'Anyone with the link',
    PublishedAccess.password => 'Password protected',
    PublishedAccess.private => 'Private / unpublished to viewers',
  };

  String _downloadLabel(PublishedDownloadPolicy value) => switch (value) {
    PublishedDownloadPolicy.allowed => 'Downloads allowed',
    PublishedDownloadPolicy.disabled => 'Downloads disabled',
    PublishedDownloadPolicy.exportOnly => 'Export only',
  };

  Future<void> _publish() async {
    final password = _passwordController.text.trim();
    if (_access == PublishedAccess.password && password.isEmpty) {
      setState(() => _error = 'Password is required for protected snapshots.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final snapshot = PublishedSnapshot.publish(
      widget.document,
      publishedBy: widget.publishedBy,
      version: (widget.existingSnapshot?.version ?? 0) + 1,
      expiresAt: _expiresAt(),
      access: _access,
      downloadPolicy: _downloadPolicy,
      embedEnabled: _embedEnabled,
      watermarkEnabled: _watermarkEnabled,
      password: password.isEmpty ? null : password,
    );

    try {
      final shareLink = await widget.onPublish(snapshot);
      if (!mounted) return;
      setState(() {
        _published = snapshot;
        _shareLink = shareLink;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Publish failed: $error';
      });
    }
  }

  Future<void> _copyLink() async {
    final link = _shareLink;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      showUiToast(
        context,
        'Share link copied.',
        variant: UiToastVariant.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final published = _published;
    final embedLink = _embedLink;
    final tokens = context.appTokens;
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 620);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 680);
    return UiDialog(
      key: const ValueKey('published-snapshot-dialog'),
      semanticsLabel: 'Publish immutable snapshot',
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
                      'Publish Snapshot',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close publish snapshot',
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
                      Text(
                        'Freeze the current canvas as an immutable version. Future edits do not change this snapshot.',
                        style: style.bodyTextStyle,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      UiSelect<PublishedAccess>(
                        key: const ValueKey('published-access'),
                        label: 'Access',
                        items: {
                          for (final value in PublishedAccess.values)
                            _accessLabel(value): value,
                        },
                        value: _access,
                        enabled: !_busy,
                        onChanged: (value) {
                          if (value != null) setState(() => _access = value);
                        },
                      ),
                      if (_access == PublishedAccess.password) ...[
                        const SizedBox(height: AppSpacing.md),
                        UiTextField(
                          key: const ValueKey('published-password'),
                          controller: _passwordController,
                          label: 'Password',
                          prefix: const Icon(Icons.lock_outline),
                          obscureText: true,
                          enabled: !_busy,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      UiSelect<String>(
                        key: const ValueKey('published-expiry'),
                        label: 'Expiry',
                        items: const {
                          'Never': 'never',
                          '1 hour': '1h',
                          '1 day': '1d',
                          '7 days': '7d',
                        },
                        value: _expiry,
                        enabled: !_busy,
                        onChanged: (value) {
                          if (value != null) setState(() => _expiry = value);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      UiSelect<PublishedDownloadPolicy>(
                        key: const ValueKey('published-download-policy'),
                        label: 'Download policy',
                        items: {
                          for (final value in PublishedDownloadPolicy.values)
                            _downloadLabel(value): value,
                        },
                        value: _downloadPolicy,
                        enabled: !_busy,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _downloadPolicy = value);
                          }
                        },
                      ),
                      UiSwitch(
                        key: const ValueKey('published-embed'),
                        label: const Text('Allow embed'),
                        value: _embedEnabled,
                        onChange: _busy
                            ? null
                            : (value) => setState(() => _embedEnabled = value),
                      ),
                      UiSwitch(
                        key: const ValueKey('published-watermark'),
                        label: const Text('Show watermark'),
                        value: _watermarkEnabled,
                        onChange: _busy
                            ? null
                            : (value) =>
                                  setState(() => _watermarkEnabled = value),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tokens.danger),
                          ),
                        ),
                      ],
                      if (published != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        UiSurface(
                          color: tokens.panelElevated,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Published v${published.version}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                published.access == PublishedAccess.private
                                    ? 'Private snapshot saved. No viewer link was created.'
                                    : _shareLink == null
                                    ? 'Snapshot saved locally. Sign in and configure Supabase to create a viewer link.'
                                    : 'Viewer link points to this immutable snapshot.',
                                style: style.bodyTextStyle,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              SelectableText(
                                'Content hash: ${published.contentHash}',
                              ),
                              if (_shareLink != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                SelectableText(_shareLink!),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: UiButton(
                                    onPressed: _copyLink,
                                    variant: UiButtonVariant.ghost,
                                    prefix: const Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                    ),
                                    child: const Text('Copy link'),
                                  ),
                                ),
                              ],
                              if (embedLink != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Embed URL',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                SelectableText(embedLink),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: UiButton(
                                    key: const ValueKey('copy-embed-link'),
                                    onPressed: _copyEmbedLink,
                                    variant: UiButtonVariant.ghost,
                                    prefix: const Icon(
                                      Icons.code_outlined,
                                      size: 16,
                                    ),
                                    child: const Text('Copy embed link'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
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
                    child: const Text('Close'),
                  ),
                  UiButton(
                    key: const ValueKey('publish-snapshot-button'),
                    onPressed: _busy ? null : _publish,
                    prefix: _busy
                        ? const UiProgressIndicator(
                            semanticsLabel: 'Publishing snapshot',
                            size: 16,
                          )
                        : const Icon(Icons.publish_outlined, size: 16),
                    child: Text(
                      published == null ? 'Publish' : 'Publish new version',
                    ),
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
