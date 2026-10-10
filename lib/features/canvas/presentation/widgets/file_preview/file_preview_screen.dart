import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/document_preview_parser.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_type.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'transient_file_source_resolver.dart';

const _maxTextBytes = 1024 * 1024;
const _renderedTextChunkBytes = 4 * 1024;

class FilePreviewScreen extends StatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.payload,
    required this.previewType,
    this.sourceResolver = const TransientFileSourceResolver(),
    this.openExternal,
  });

  final FilePayload payload;
  final FilePreviewType previewType;
  final TransientFileSourceResolver sourceResolver;
  final Future<bool> Function(Uint8List bytes, String fileName)? openExternal;

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  Uint8List? _bytes;
  String? _text;
  DocumentPreview? _document;
  String? _error;
  bool _loading = true;
  bool _textTruncated = false;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.previewType == FilePreviewType.external ||
        widget.previewType == FilePreviewType.audio ||
        widget.previewType == FilePreviewType.video) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final hasDirectByteSource =
        widget.payload.artifactReference?.trim().isNotEmpty == true ||
        widget.payload.base64Data?.trim().isNotEmpty == true ||
        widget.payload.storagePath?.trim().isNotEmpty == true ||
        widget.payload.localPath?.trim().isNotEmpty == true;
    if (widget.previewType == FilePreviewType.image && !hasDirectByteSource) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final bytes = await widget.sourceResolver.resolveBytes(
      widget.payload,
      maxBytes: maxTransientFileBytes,
    );
    if (bytes == null) {
      // A query-free public image may still be rendered by Image.network when
      // the test/runtime HTTP client cannot prefetch it. Signed/query-bearing
      // URLs never reach this fallback because publicUri rejects them.
      if (widget.previewType != FilePreviewType.image || _remoteUri == null) {
        _error = 'No usable file source was found.';
      }
    } else {
      _bytes = bytes;
      if (widget.previewType == FilePreviewType.text) {
        _textTruncated = bytes.length > _maxTextBytes;
        _text = utf8.decode(
          bytes.sublist(0, bytes.length.clamp(0, _maxTextBytes)),
          allowMalformed: true,
        );
      } else if (widget.previewType == FilePreviewType.document) {
        try {
          _document = parseDocumentPreview(
            bytes,
            normalizedFileExtension(widget.payload),
          );
        } catch (_) {
          _error = 'The document could not be previewed inside the app.';
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Uri? get _remoteUri =>
      widget.sourceResolver.publicUri(widget.payload.remoteUrl);

  bool get _hasSource => widget.sourceResolver.hasSource(widget.payload);

  Future<void> _openExternal() async {
    try {
      final bytes =
          _bytes ?? await widget.sourceResolver.resolveBytes(widget.payload);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No usable file bytes were found.');
      }
      if (widget.openExternal != null) {
        if (!await widget.openExternal!(bytes, widget.payload.fileName)) {
          throw StateError('External application rejected the file.');
        }
        return;
      }
      final outcome = await ExportFileSaver().save(
        fileName: widget.payload.fileName,
        bytes: bytes,
        mimeType: 'application/octet-stream',
        dialogTitle: 'Save file',
      );
      if (outcome != ExportSaveOutcome.saved) {
        throw StateError('No external application could save this file.');
      }
    } catch (_) {
      if (mounted) {
        showUiToast(
          context,
          'The file could not be opened externally.',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiPageScaffold(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.payload.fileName, overflow: TextOverflow.ellipsis),
          Text(
            '${widget.payload.fileExtension.toUpperCase()} • ${widget.payload.fileSizeText}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: widget.previewType == FilePreviewType.text && _text != null
          ? [
              UiIconButton(
                icon: Icons.search,
                tooltip: 'Search text',
                onPressed: () => setState(() => _searching = !_searching),
              ),
              UiIconButton(
                icon: Icons.copy,
                tooltip: 'Copy text',
                onPressed: () => Clipboard.setData(ClipboardData(text: _text!)),
              ),
            ]
          : const [],
      child: _loading
          ? const Center(
              child: UiProgressIndicator(
                semanticsLabel: 'Loading file preview',
              ),
            )
          : _error != null || !_hasSource
          ? _Fallback(
              message: _error ?? 'No usable file source was found.',
              onOpen: _hasSource ? _openExternal : null,
            )
          : _buildPreview(),
    );
  }

  Widget _buildPreview() => switch (widget.previewType) {
    FilePreviewType.image => _buildImage(),
    FilePreviewType.text => _buildText(),
    FilePreviewType.audio => _AudioPreview(
      payload: widget.payload,
      remoteUri: _remoteUri,
      sourceResolver: widget.sourceResolver,
      onOpen: _openExternal,
    ),
    FilePreviewType.video => _VideoPreview(
      payload: widget.payload,
      remoteUri: _remoteUri,
      sourceResolver: widget.sourceResolver,
      onOpen: _openExternal,
    ),
    FilePreviewType.html => _HtmlPreview(
      remoteUri: _remoteUri,
      bytes: _bytes,
      onOpen: _openExternal,
    ),
    FilePreviewType.document => _buildDocument(),
    FilePreviewType.pdf ||
    FilePreviewType.external => _Fallback(onOpen: _openExternal),
  };

  Widget _buildImage() {
    final image = _bytes != null
        ? Image.memory(
            _bytes!,
            semanticLabel: widget.payload.fileName,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _PreviewError(onOpen: _openExternal),
          )
        : Image.network(
            _remoteUri.toString(),
            semanticLabel: widget.payload.fileName,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _PreviewError(onOpen: _openExternal),
          );
    return Center(
      child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: image),
    );
  }

  Widget _buildDocument() {
    final sections = _document?.sections ?? const <String>[];
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: AppResponsive.pagePadding(context),
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, index) => SelectableText(
              sections[index],
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: AppResponsive.pagePadding(context),
            child: UiButton(
              onPressed: _openExternal,
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.open_in_new),
              child: const Text('OPEN EXTERNALLY'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildText() {
    final text = _text ?? '';
    final matches =
        _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());
    return Column(
      children: [
        if (_searching)
          Padding(
            padding: AppResponsive.pagePadding(context),
            child: UiTextField(
              autofocus: true,
              hint: 'Find in file',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        if (_textTruncated)
          Padding(
            padding: AppResponsive.pagePadding(context),
            child: UiAlert(
              title: 'Preview limited',
              description: 'Preview limited to the first 1 MB.',
              icon: Icons.info_outline,
              variant: UiAlertVariant.info,
              trailing: UiButton(
                onPressed: _openExternal,
                variant: UiButtonVariant.outline,
                child: const Text('OPEN FULL FILE'),
              ),
            ),
          ),
        Expanded(
          child: matches
              ? _buildMatchedText(text)
              : SingleChildScrollView(
                  padding: AppResponsive.pagePadding(context),
                  child: SelectableText(
                    'No matches found.',
                    style: TextStyle(fontFamily: 'monospace', height: 1.45),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMatchedText(String text) {
    if (text.length <= _renderedTextChunkBytes) {
      return SingleChildScrollView(
        padding: AppResponsive.pagePadding(context),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', height: 1.45),
        ),
      );
    }
    final chunkCount =
        (text.length + _renderedTextChunkBytes - 1) ~/ _renderedTextChunkBytes;
    return ListView.builder(
      padding: AppResponsive.pagePadding(context),
      itemCount: chunkCount,
      itemBuilder: (context, index) {
        final start = index * _renderedTextChunkBytes;
        final end = (start + _renderedTextChunkBytes).clamp(0, text.length);
        return SelectableText(
          text.substring(start, end),
          style: const TextStyle(fontFamily: 'monospace', height: 1.45),
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    this.message = 'This file type cannot be previewed safely.',
    this.onOpen,
  });

  final String message;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Center(
      child: Padding(
        padding: AppResponsive.pagePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 56,
              color: tokens.textMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Preview unavailable',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onOpen != null) ...[
              const SizedBox(height: AppSpacing.xl),
              UiButton(
                onPressed: onOpen,
                variant: UiButtonVariant.primary,
                prefix: const Icon(Icons.open_in_new),
                child: const Text('OPEN EXTERNALLY'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) =>
      _Fallback(message: 'The preview could not be rendered.', onOpen: onOpen);
}

class _AudioPreview extends StatefulWidget {
  const _AudioPreview({
    required this.payload,
    required this.remoteUri,
    required this.sourceResolver,
    required this.onOpen,
  });

  final FilePayload payload;
  final Uri? remoteUri;
  final TransientFileSourceResolver sourceResolver;
  final VoidCallback onOpen;

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      if (mounted) {
        setState(
          () => _error = 'Audio preview is unavailable on this platform.',
        );
      }
      return;
    }
    try {
      final bytes = await widget.sourceResolver.resolveBytes(widget.payload);
      if (bytes != null && bytes.isNotEmpty) {
        await _player.setAudioSource(
          AudioSource.uri(
            UriData.fromBytes(
              bytes,
              mimeType: 'audio/${widget.payload.fileExtension}',
            ).uri,
          ),
        );
      } else if (widget.remoteUri != null) {
        await _player.setUrl(widget.remoteUri.toString());
      } else {
        throw StateError('No supported audio source.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'The audio could not be loaded.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sliderWidth =
        (MediaQuery.sizeOf(context).width -
                AppResponsive.pagePadding(context).horizontal)
            .clamp(0.0, 240.0)
            .toDouble();
    if (_error != null) {
      return _Fallback(message: _error!, onOpen: widget.onOpen);
    }
    return Center(
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, state) {
          final playing = state.data?.playing ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audiotrack, size: 64),
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, position) {
                  final duration = _player.duration ?? Duration.zero;
                  final durationMs = duration.inMilliseconds;
                  final positionMs = position.data?.inMilliseconds ?? 0;
                  final normalized = durationMs <= 0
                      ? 0.0
                      : (positionMs / durationMs).clamp(0.0, 1.0);
                  return UiSlider(
                    semanticsLabel: 'Audio position',
                    value: normalized,
                    onChanged: (value) => _player.seek(
                      Duration(milliseconds: (value * durationMs).round()),
                    ),
                  );
                },
              ),
              UiIconButton(
                icon: playing ? Icons.pause_circle : Icons.play_circle,
                tooltip: playing ? 'Pause' : 'Play',
                size: UiButtonSize.lg,
                onPressed: playing ? _player.pause : _player.play,
              ),
              StreamBuilder<double>(
                stream: _player.volumeStream,
                builder: (context, volume) => SizedBox(
                  width: sliderWidth,
                  child: UiSlider(
                    semanticsLabel: 'Audio volume',
                    value: (volume.data ?? 1).clamp(0.0, 1.0),
                    onChanged: _player.setVolume,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.payload,
    required this.remoteUri,
    required this.sourceResolver,
    required this.onOpen,
  });

  final FilePayload payload;
  final Uri? remoteUri;
  final TransientFileSourceResolver sourceResolver;
  final VoidCallback onOpen;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      if (mounted) {
        setState(
          () => _error = 'Video preview is unavailable on this platform.',
        );
      }
      return;
    }
    try {
      final bytes = await widget.sourceResolver.resolveBytes(widget.payload);
      final controller = bytes != null && bytes.isNotEmpty
          ? VideoPlayerController.contentUri(
              Uri.dataFromBytes(
                bytes,
                mimeType: 'video/${widget.payload.fileExtension}',
              ),
            )
          : widget.remoteUri != null
          ? VideoPlayerController.networkUrl(widget.remoteUri!)
          : null;
      if (controller == null) throw StateError('No supported video source.');
      _controller = controller;
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'The video could not be loaded.');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliderWidth =
        (MediaQuery.sizeOf(context).width -
                AppResponsive.pagePadding(context).horizontal)
            .clamp(0.0, 180.0)
            .toDouble();
    if (_error != null) {
      return _Fallback(message: _error!, onOpen: widget.onOpen);
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: UiProgressIndicator(semanticsLabel: 'Loading video preview'),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiIconButton(
              icon: controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
              onPressed: () async {
                controller.value.isPlaying
                    ? await controller.pause()
                    : await controller.play();
                if (mounted) setState(() {});
              },
            ),
            const Icon(Icons.volume_down),
            SizedBox(
              width: sliderWidth,
              child: UiSlider(
                semanticsLabel: 'Video volume',
                value: controller.value.volume.clamp(0.0, 1.0),
                onChanged: (value) async {
                  await controller.setVolume(value);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HtmlPreview extends StatefulWidget {
  const _HtmlPreview({
    required this.remoteUri,
    required this.bytes,
    required this.onOpen,
  });

  final Uri? remoteUri;
  final Uint8List? bytes;
  final VoidCallback onOpen;

  @override
  State<_HtmlPreview> createState() => _HtmlPreviewState();
}

class _HtmlPreviewState extends State<_HtmlPreview> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final supportsWebView =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!kIsWeb && supportsWebView) {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              return uri != null &&
                      uri.query.isEmpty &&
                      uri.fragment.isEmpty &&
                      (uri.scheme == 'http' || uri.scheme == 'https')
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
          ),
        );
      final bytes = widget.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        controller.loadHtmlString(utf8.decode(bytes, allowMalformed: true));
      } else if (widget.remoteUri != null) {
        controller.loadRequest(widget.remoteUri!);
      } else {
        return;
      }
      _controller = controller;
    }
  }

  @override
  Widget build(BuildContext context) => _controller != null
      ? WebViewWidget(controller: _controller!)
      : _Fallback(
          message: widget.remoteUri == null
              ? 'Local HTML is not executed inside the app.'
              : 'HTML preview opens in your browser on this platform.',
          onOpen: widget.remoteUri == null ? null : widget.onOpen,
        );
}
