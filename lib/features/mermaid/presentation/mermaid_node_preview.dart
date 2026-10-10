import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/theme.dart';
import '../../../domain/models/node_payload.dart';
import '../data/mermaid_renderer.dart';
import '../domain/mermaid_renderer.dart';
import '../domain/mermaid_svg_sanitizer.dart';

/// Displays a Mermaid source node without giving the SVG any pointer input.
///
/// The canvas owns selection and movement. This widget owns only render state,
/// safe cache validation, and a passive accessible preview.
class MermaidNodePreview extends StatefulWidget {
  final MermaidPayload payload;
  final MermaidRenderer? renderer;
  final ValueChanged<MermaidPayload>? onRenderStateChanged;

  const MermaidNodePreview({
    required this.payload,
    this.renderer,
    this.onRenderStateChanged,
    super.key,
  });

  @override
  State<MermaidNodePreview> createState() => _MermaidNodePreviewState();
}

class _MermaidNodePreviewState extends State<MermaidNodePreview> {
  late MermaidRenderer _renderer;
  String? _svg;
  MermaidDiagnostic? _diagnostic;
  bool _loading = false;
  int _requestToken = 0;
  String? _renderSignature;

  @override
  void initState() {
    super.initState();
    _renderer = widget.renderer ?? createPlatformMermaidRenderer();
    _svg = _safeCachedSvg(widget.payload, _renderer);
    _diagnostic = widget.payload.lastError;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startRender();
    });
  }

  @override
  void didUpdateWidget(covariant MermaidNodePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.renderer != oldWidget.renderer) {
      _renderer = widget.renderer ?? createPlatformMermaidRenderer();
    }

    final nextSignature = _signature(widget.payload);
    if (nextSignature != _renderSignature) {
      _svg = _safeCachedSvg(widget.payload, _renderer);
      _diagnostic = widget.payload.lastError;
      _startRender();
    }
  }

  @override
  void dispose() {
    _requestToken++;
    super.dispose();
  }

  void _startRender() {
    final payload = widget.payload;
    final signature = _signature(payload);
    if (_renderSignature == signature) return;
    _renderSignature = signature;
    final requestToken = ++_requestToken;

    if (mounted) {
      setState(() {
        _loading = true;
        _diagnostic = null;
      });
    }

    unawaited(_render(payload, signature, requestToken));
  }

  Future<void> _render(
    MermaidPayload payload,
    String signature,
    int requestToken,
  ) async {
    MermaidRenderResult result;
    try {
      result = await _renderer
          .render(payload.source, config: _renderConfig(payload))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      result = MermaidRenderResult.failure(
        rendererDiagnostic(
          'RENDER_TIMEOUT',
          'Mermaid rendering took too long and was stopped.',
        ),
      );
    } catch (_) {
      result = MermaidRenderResult.failure(
        rendererDiagnostic(
          'RENDER_ERROR',
          'The Mermaid diagram could not be rendered.',
        ),
      );
    }

    if (!mounted || requestToken != _requestToken) return;
    if (_signature(widget.payload) != signature) return;

    String? safeSvg;
    var diagnostic = result.diagnostic;
    if (result.svg != null && diagnostic == null) {
      try {
        safeSvg = MermaidSvgSanitizer.normalizeForFlutter(result.svg!);
      } on MermaidSvgSecurityException catch (error) {
        diagnostic = rendererDiagnostic(
          error.code,
          'Mermaid renderer returned unsafe SVG output.',
        );
      }
    }

    final nextPayload = payload.copyWith(
      diagramType: safeSvg == null ? payload.diagramType : result.diagramType,
      cachedSvg: safeSvg,
      cachedSvgRevision: safeSvg == null ? null : payload.sourceRevision,
      cachedSvgConfigKey: safeSvg == null
          ? null
          : _renderConfig(payload).cacheKey,
      rendererVersion: safeSvg == null ? null : _renderer.rendererVersion,
      lastError: diagnostic,
    );

    setState(() {
      _svg = safeSvg;
      _diagnostic = diagnostic;
      _loading = false;
    });
    widget.onRenderStateChanged?.call(nextPayload);
  }

  static String? _safeCachedSvg(
    MermaidPayload payload,
    MermaidRenderer renderer,
  ) {
    final cached = payload.cachedSvg;
    if (cached == null || cached.isEmpty) return null;
    final config = _renderConfig(payload);
    if (payload.cachedSvgRevision != payload.sourceRevision ||
        payload.cachedSvgConfigKey != config.cacheKey ||
        (renderer.rendererVersion != null &&
            payload.rendererVersion != renderer.rendererVersion)) {
      return null;
    }
    try {
      return MermaidSvgSanitizer.normalizeForFlutter(cached);
    } on MermaidSvgSecurityException {
      return null;
    }
  }

  static MermaidRenderConfig _renderConfig(MermaidPayload payload) =>
      MermaidRenderConfig(
        theme: payload.theme,
        direction: payload.direction,
        overrides: payload.config,
      );

  String _signature(MermaidPayload payload) => Object.hash(
    payload.source,
    payload.sourceRevision,
    payload.theme.value,
    payload.direction?.value,
    jsonEncode(MermaidRenderConfig(overrides: payload.config).safeOverrides),
    _renderer.rendererVersion,
  ).toString();

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final diagramType = widget.payload.diagramType == 'unknown'
        ? 'diagram'
        : widget.payload.diagramType;
    final hasSvg = _svg != null && _svg!.isNotEmpty;
    final semanticLabel = 'Mermaid $diagramType diagram';

    return Semantics(
      container: true,
      label: semanticLabel,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border.all(color: tokens.panelBorder),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasSvg)
                SvgPicture.string(
                  _svg!,
                  key: ValueKey(
                    '${widget.payload.sourceRevision}-${widget.payload.theme.value}-${_svg.hashCode}',
                  ),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  semanticsLabel: semanticLabel,
                  errorBuilder: (context, error, stackTrace) => _StatusMessage(
                    icon: Icons.broken_image_outlined,
                    message: 'Mermaid preview could not be displayed.',
                    color: tokens.warning,
                  ),
                )
              else
                _StatusMessage(
                  key: const ValueKey('mermaid-preview-status'),
                  icon: _diagnostic == null
                      ? Icons.account_tree_outlined
                      : Icons.warning_amber_rounded,
                  message: _statusMessage,
                  color: _diagnostic == null ? tokens.textMuted : tokens.danger,
                ),
              if (_loading)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.panel.withValues(alpha: 0.94),
                      border: Border(
                        top: BorderSide(color: tokens.panelBorder),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        hasSvg
                            ? 'Updating preview…'
                            : 'Rendering Mermaid diagram…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusMessage {
    final diagnostic = _diagnostic;
    if (diagnostic == null) return 'Rendering Mermaid diagram…';
    if (diagnostic.code == 'RENDERER_UNAVAILABLE') {
      return 'Mermaid preview is unavailable on this platform.';
    }
    if (diagnostic.code.contains('PARSE') ||
        diagnostic.code.contains('SOURCE')) {
      return diagnostic.message;
    }
    return diagnostic.message.isEmpty
        ? 'Mermaid preview could not be rendered.'
        : diagnostic.message;
  }
}

class _StatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _StatusMessage({
    required this.icon,
    required this.message,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: color),
          ),
        ],
      ),
    ),
  );
}
