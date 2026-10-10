import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

class PdfViewerDialog extends StatefulWidget {
  final FilePayload payload;
  final TransientFileSourceResolver sourceResolver;

  const PdfViewerDialog({
    super.key,
    required this.payload,
    this.sourceResolver = const TransientFileSourceResolver(),
  });

  @override
  State<PdfViewerDialog> createState() => _PdfViewerDialogState();
}

class _PdfViewerDialogState extends State<PdfViewerDialog> {
  late final PdfViewerController _pdfController;
  int _currentPage = 1;
  int _pageCount = 1;
  double _zoomLevel = 1.0;
  bool _isDarkTheme = true;
  bool _isSinglePageMode = true;
  Uint8List? _pdfBytes;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    try {
      _pdfBytes = await widget.sourceResolver.resolveBytes(widget.payload);
    } catch (e) {
      _errorMessage = 'Failed to load PDF bytes: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _isDarkTheme ? AppTokens.dark : AppTokens.light;
    return Theme(
      data: AppTheme.materialThemeFor(tokens),
      child: Dialog.fullscreen(
        backgroundColor: tokens.canvas,
        child: Column(
          children: [
            _buildHeader(context, tokens),
            Divider(height: AppBorder.thin, color: tokens.panelBorder),
            Expanded(child: _buildBody(context, tokens)),
            Divider(height: AppBorder.thin, color: tokens.panelBorder),
            _buildBottomToolbar(context, tokens),
          ],
        ),
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required AppTokens tokens,
  }) => UiIconButton(
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    variant: UiButtonVariant.ghost,
    size: UiButtonSize.sm,
  );

  Widget _textAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required AppTokens tokens,
  }) => UiButton(
    onPressed: onPressed,
    variant: UiButtonVariant.outline,
    size: UiButtonSize.sm,
    prefix: Icon(icon, size: 14),
    child: Text(label),
  );

  Future<void> _openExternal() async {
    final bytes =
        _pdfBytes ?? await widget.sourceResolver.resolveBytes(widget.payload);
    if (bytes == null || bytes.isEmpty) return;
    try {
      await ExportFileSaver().save(
        fileName: widget.payload.fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Save PDF',
      );
    } catch (_) {
      // External saving is a best-effort fallback; keep the viewer open.
    }
  }

  Widget _buildHeader(BuildContext context, AppTokens tokens) {
    final fileDetails = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.payload.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            '${widget.payload.fileSizeText} • PDF Viewer',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
    final actions = [
      _iconAction(
        tooltip: _isSinglePageMode
            ? 'Switch to Continuous Scroll'
            : 'Switch to Single Page Mode',
        icon: _isSinglePageMode
            ? Icons.auto_stories_outlined
            : Icons.view_day_outlined,
        tokens: tokens,
        onPressed: () {
          setState(() => _isSinglePageMode = !_isSinglePageMode);
          if (_pdfController.isReady) {
            _pdfController.goToPage(pageNumber: _currentPage);
          }
        },
      ),
      _iconAction(
        tooltip: 'Open in External Application',
        icon: Icons.open_in_new,
        tokens: tokens,
        onPressed: _openExternal,
      ),
      _iconAction(
        tooltip: _isDarkTheme
            ? 'Switch to Light Theme'
            : 'Switch to Dark Theme',
        icon: _isDarkTheme
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        tokens: tokens,
        onPressed: () => setState(() => _isDarkTheme = !_isDarkTheme),
      ),
      _iconAction(
        tooltip: 'Close',
        icon: Icons.close,
        tokens: tokens,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
    return UiSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: tokens.panel,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.dialog),
      ),
      bordered: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final badge = UiBadge(
            widget.payload.fileExtension.toUpperCase().replaceAll('.', ''),
            variant: UiBadgeVariant.destructive,
          );
          if (constraints.maxWidth < AppBreakpoints.compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    badge,
                    const SizedBox(width: AppSpacing.md),
                    fileDetails,
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  children: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              badge,
              const SizedBox(width: AppSpacing.md),
              fileDetails,
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppTokens tokens) {
    if (_isLoading) {
      return const Center(child: UiProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: tokens.danger, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_pdfBytes != null) {
      return _buildPdfViewer(
        PdfViewer.data(
          _pdfBytes!,
          sourceName: widget.payload.fileName,
          controller: _pdfController,
          params: _pdfParams(tokens),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            color: tokens.textMuted,
            size: 48,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No PDF source data found.',
            style: TextStyle(color: tokens.text),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ensure the file has a stable Storage reference or runtime source.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer(Widget viewer) => viewer;

  PdfViewerParams _pdfParams(AppTokens tokens) => PdfViewerParams(
    backgroundColor: tokens.canvas,
    margin: 16,
    layoutPages: _customPageLayout,
    onDocumentChanged: (document) {
      if (document != null && mounted) {
        setState(() => _pageCount = document.pages.length);
      }
    },
    onPageChanged: (pageNumber) {
      if (pageNumber != null && mounted) {
        setState(() => _currentPage = pageNumber);
      }
    },
    loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
        const Center(child: UiProgressIndicator()),
    errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, color: tokens.danger, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Failed to render PDF in-app.',
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: tokens.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Text(
              'Error: $error',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            _textAction(
              label: 'Open in System App / Browser',
              icon: Icons.open_in_new,
              onPressed: _openExternal,
              tokens: tokens,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildBottomToolbar(BuildContext context, AppTokens tokens) {
    Widget pageControls() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconAction(
          tooltip: 'Previous Page',
          icon: Icons.navigate_before,
          tokens: tokens,
          onPressed: _currentPage > 1
              ? () {
                  final prev = _currentPage - 1;
                  if (_pdfController.isReady) {
                    _pdfController.goToPage(pageNumber: prev);
                  }
                  setState(() => _currentPage = prev);
                }
              : null,
        ),
        Text(
          '$_currentPage / $_pageCount',
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: tokens.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        _iconAction(
          tooltip: 'Next Page',
          icon: Icons.navigate_next,
          tokens: tokens,
          onPressed: _currentPage < _pageCount
              ? () {
                  final next = _currentPage + 1;
                  if (_pdfController.isReady) {
                    _pdfController.goToPage(pageNumber: next);
                  }
                  setState(() => _currentPage = next);
                }
              : null,
        ),
      ],
    );

    Widget zoomControls() => Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      children: [
        _iconAction(
          tooltip: 'Zoom Out',
          icon: Icons.zoom_out,
          tokens: tokens,
          onPressed: () {
            setState(() => _zoomLevel = (_zoomLevel / 1.25).clamp(0.5, 4.0));
            if (_pdfController.isReady) {
              _pdfController.zoomDown(loop: false);
            }
          },
        ),
        Text(
          '${(_zoomLevel * 100).toInt()}%',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        _iconAction(
          tooltip: 'Zoom In',
          icon: Icons.zoom_in,
          tokens: tokens,
          onPressed: () {
            setState(() => _zoomLevel = (_zoomLevel * 1.25).clamp(0.5, 4.0));
            _pdfController.zoomUp(loop: false);
          },
        ),
        _textAction(
          label: 'Reset',
          icon: Icons.fit_screen,
          tokens: tokens,
          onPressed: () {
            setState(() {
              _zoomLevel = 1.0;
              _currentPage = 1;
            });
            if (_pdfController.isReady) {
              _pdfController.goToPage(pageNumber: 1);
            }
          },
        ),
      ],
    );

    return UiSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: tokens.panel,
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadius.dialog),
      ),
      bordered: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AppBreakpoints.compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.center, child: pageControls()),
                Align(alignment: Alignment.centerRight, child: zoomControls()),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [pageControls(), zoomControls()],
          );
        },
      ),
    );
  }

  PdfPageLayout _customPageLayout(List<PdfPage> pages, PdfViewerParams params) {
    if (_isSinglePageMode) {
      final maxWidth = pages.fold(0.0, (w, p) => math.max(w, p.width));
      final maxHeight = pages.fold(0.0, (h, p) => math.max(h, p.height));
      final docWidth = maxWidth + params.margin * 2;
      final docHeight = maxHeight + params.margin * 2;
      final gap = math.max(docWidth * 2.0, 3000.0);
      final pageLayouts = <Rect>[];
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        final x =
            params.margin +
            (i * (docWidth + gap)) +
            (maxWidth - page.width) / 2;
        final y = params.margin + (maxHeight - page.height) / 2;
        pageLayouts.add(Rect.fromLTWH(x, y, page.width, page.height));
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size(pages.length * (docWidth + gap), docHeight),
      );
    }

    final width =
        pages.fold(0.0, (w, p) => math.max(w, p.width)) + params.margin * 2;
    final pageLayouts = <Rect>[];
    var y = params.margin;
    for (final page in pages) {
      final rect = Rect.fromLTWH(
        (width - page.width) / 2,
        y,
        page.width,
        page.height,
      );
      pageLayouts.add(rect);
      y += page.height + params.margin;
    }
    return PdfPageLayout(
      pageLayouts: pageLayouts,
      documentSize: Size(width, y),
    );
  }
}
