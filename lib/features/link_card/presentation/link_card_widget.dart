import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mix/mix.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../data/link_preview_service.dart';
import '../domain/link_url_policy.dart';

class LinkCardWidget extends StatefulWidget {
  final CanvasNode node;
  final bool selected;
  final ValueChanged<String> onSubmitUrl;
  final VoidCallback onRefresh;
  final VoidCallback onOpenInApp;
  final VoidCallback onOpenExternal;
  final ValueChanged<Offset>? onDragDelta;
  final ValueChanged<Offset>? onSecondaryTap;

  const LinkCardWidget({
    super.key,
    required this.node,
    required this.selected,
    required this.onSubmitUrl,
    required this.onRefresh,
    required this.onOpenInApp,
    required this.onOpenExternal,
    this.onDragDelta,
    this.onSecondaryTap,
  });

  @override
  State<LinkCardWidget> createState() => _LinkCardWidgetState();
}

class _LinkCardWidgetState extends State<LinkCardWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final FocusNode _cardFocusNode;
  late final FocusNode _urlFocusNode;
  bool _editing = false;
  String? _error;

  LinkPayload get _payload => widget.node.payload as LinkPayload;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _payload.url);
    _focusNode = FocusNode();
    _cardFocusNode = FocusNode(debugLabel: 'Link card');
    _urlFocusNode = FocusNode(debugLabel: 'Edit link URL');
  }

  @override
  void didUpdateWidget(covariant LinkCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && _controller.text != _payload.url) {
      _controller.text = _payload.url;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _cardFocusNode.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (!widget.selected) return;
    setState(() {
      _editing = true;
      _error = null;
      _controller.text = _payload.url;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _submit() {
    try {
      final url = normalizeLinkUrl(_controller.text).toString();
      setState(() {
        _editing = false;
        _error = null;
      });
      widget.onSubmitUrl(url);
    } on LinkUrlValidationException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _error = null;
      _controller.text = _payload.url;
    });
  }

  KeyEventResult _handleCardKeyEvent(FocusNode node, KeyEvent event) {
    if (node != _cardFocusNode ||
        !_cardFocusNode.hasPrimaryFocus ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onOpenInApp();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleUrlKeyEvent(FocusNode node, KeyEvent event) {
    if (node == _urlFocusNode &&
        _urlFocusNode.hasPrimaryFocus &&
        event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _startEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 128;
        final contentPadding = compactHeight
            ? const EdgeInsets.all(AppSpacing.xxs)
            : const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs);
        final showImage =
            constraints.maxHeight >= 180 && constraints.maxWidth >= 260;
        return MixScope.inherit(
          colors: AppMixTokens.colors(tokens),
          child: Box(
            style: AppStyles.surface
                .color(tokens.panel)
                .borderRadius(
                  BorderRadiusGeometryMix.value(
                    BorderRadius.circular(tokens.panelRadius),
                  ),
                ),
            child: Focus(
              key: const Key('link-card-keyboard-focus'),
              focusNode: _cardFocusNode,
              onKeyEvent: _handleCardKeyEvent,
              child: Semantics(
                container: true,
                focusable: true,
                label: _payload.title.isNotEmpty ? _payload.title : 'Link card',
                hint: 'Press Enter or Space to open. Tab to the URL to edit.',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.panelRadius),
                  child: GestureDetector(
                    onDoubleTap: _editing ? null : widget.onOpenInApp,
                    onSecondaryTapUp: widget.onSecondaryTap == null
                        ? null
                        : (details) =>
                              widget.onSecondaryTap!(details.globalPosition),
                    onPanUpdate: widget.onDragDelta == null
                        ? null
                        : (details) => widget.onDragDelta!(details.delta),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.selected
                              ? tokens.selection
                              : tokens.panelBorder,
                        ),
                        borderRadius: BorderRadius.circular(tokens.panelRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showImage) Expanded(child: _image()),
                          Padding(
                            padding: contentPadding,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (compactHeight)
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: AppControlSize.minimumHitTarget,
                                        height: AppControlSize.minimumHitTarget,
                                        child: Semantics(
                                          label: 'Link actions',
                                          button: true,
                                          child: PopupMenuButton<String>(
                                            key: const Key(
                                              'link-card-compact-actions',
                                            ),
                                            tooltip: 'Link actions',
                                            constraints: const BoxConstraints(
                                              minWidth: 112,
                                            ),
                                            padding: EdgeInsets.zero,
                                            iconSize: 20,
                                            onSelected: (action) {
                                              if (action == 'refresh') {
                                                widget.onRefresh();
                                              } else {
                                                widget.onOpenExternal();
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem(
                                                value: 'refresh',
                                                enabled:
                                                    _payload.url.isNotEmpty,
                                                child: const Text(
                                                  'Refresh preview',
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'external',
                                                enabled:
                                                    _payload.url.isNotEmpty,
                                                child: const Text(
                                                  'Open in browser',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Expanded(child: _url()),
                                    ],
                                  )
                                else ...[
                                  Row(
                                    children: [
                                      _favicon(),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(child: _title()),
                                      UiIconButton(
                                        key: const Key('link-card-refresh'),
                                        onPressed: _payload.url.isEmpty
                                            ? null
                                            : widget.onRefresh,
                                        tooltip: 'Refresh preview',
                                        icon: Icons.refresh,
                                        size: UiButtonSize.lg,
                                      ),
                                      UiIconButton(
                                        key: const Key('link-card-external'),
                                        onPressed: _payload.url.isEmpty
                                            ? null
                                            : widget.onOpenExternal,
                                        tooltip: 'Open in browser',
                                        icon: Icons.open_in_new,
                                        size: UiButtonSize.lg,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  _url(),
                                ],
                                if (_payload.description?.isNotEmpty == true &&
                                    constraints.maxHeight >= 150) ...[
                                  const SizedBox(
                                    height: AppSpacing.xs + AppSpacing.xxs,
                                  ),
                                  Text(
                                    _payload.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                if (_error != null)
                                  Text(
                                    _error!,
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: tokens.danger,
                                      fontSize: 10,
                                    ),
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
            ),
          ),
        );
      },
    );
  }

  Widget _image() {
    final tokens = context.appTokens;
    if (_payload.previewStatus == LinkPreviewStatus.loading) {
      return ColoredBox(
        color: tokens.panelElevated,
        child: const Center(
          child: UiProgressIndicator(semanticsLabel: 'Loading link preview'),
        ),
      );
    }
    final declaredImageUrl = _payload.imageUrl?.trim();
    final imageUrl = declaredImageUrl?.isNotEmpty == true
        ? declaredImageUrl
        : isDirectImageUrl(_payload.url)
        ? _payload.url
        : null;
    if (imageUrl != null) {
      final normalizedImageUrl = normalizeLinkPreviewAssetUri(imageUrl);
      return Image.network(
        normalizedImageUrl?.toString() ?? imageUrl,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => _imageFallback(),
      );
    }
    return _imageFallback();
  }

  Widget _imageFallback() {
    final icon = switch (_payload.mediaType) {
      'video' => Icons.movie,
      'audio' => Icons.audiotrack,
      'pdf' => Icons.picture_as_pdf,
      'image' => Icons.image,
      'file' => Icons.insert_drive_file,
      _ => Icons.language,
    };
    final tokens = context.appTokens;
    return ColoredBox(
      color: tokens.panelElevated,
      child: Center(child: Icon(icon, color: tokens.textMuted, size: 40)),
    );
  }

  Widget _favicon() {
    if (_payload.faviconUrl?.isNotEmpty == true) {
      return Image.network(
        _payload.faviconUrl!,
        width: 18,
        height: 18,
        errorBuilder: (_, _, _) => const Icon(Icons.link, size: 18),
      );
    }
    return Icon(Icons.link, color: context.appTokens.info, size: 18);
  }

  Widget _title() {
    final hostname = Uri.tryParse(_payload.url)?.host ?? '';
    final title = _payload.title.isNotEmpty
        ? _payload.title
        : _payload.siteName?.isNotEmpty == true
        ? _payload.siteName!
        : hostname.isNotEmpty
        ? hostname
        : 'Link Card';
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.appTokens.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _url() {
    if (_editing) {
      return Focus(
        onKeyEvent: (_, event) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _cancel();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppControlSize.minimumHitTarget,
          ),
          child: UiTextField(
            key: const Key('link-card-url-editor'),
            controller: _controller,
            focusNode: _focusNode,
            onSubmitted: (_) => _submit(),
            textInputAction: TextInputAction.done,
            hint: 'https://example.com',
          ),
        ),
      );
    }
    final hostname = Uri.tryParse(_payload.url)?.host;
    final label = _payload.url.isEmpty
        ? 'Double-click untuk memasukkan URL'
        : hostname ?? _payload.url;
    return Focus(
      key: const Key('link-card-url-keyboard-focus'),
      focusNode: _urlFocusNode,
      canRequestFocus: widget.selected,
      skipTraversal: !widget.selected,
      onKeyEvent: _handleUrlKeyEvent,
      child: Semantics(
        button: true,
        enabled: widget.selected,
        label: 'Edit URL: $label',
        hint: 'Press Enter or Space to edit URL.',
        onTap: widget.selected ? _startEditing : null,
        child: GestureDetector(
          key: const Key('link-card-url'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _startEditing,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppControlSize.minimumHitTarget,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _payload.previewStatus == LinkPreviewStatus.error
                      ? context.appTokens.danger
                      : context.appTokens.textMuted,
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
