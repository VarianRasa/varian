import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/pdf_annotation.dart' as annotation;
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_annotation_coordinates.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_annotation_layer.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_search_bar.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_sidebar.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

enum PdfViewMode { singlePage, continuous }

enum PdfToolMode { hand, select, drawPen, drawHighlighter, addNote }

enum _PdfHeaderAction { search, presentation, external, toggleTheme }

class _ZoomInIntent extends Intent {
  const _ZoomInIntent();
}

class _ZoomOutIntent extends Intent {
  const _ZoomOutIntent();
}

class _ZoomResetIntent extends Intent {
  const _ZoomResetIntent();
}

class _NextPageIntent extends Intent {
  const _NextPageIntent();
}

class _PrevPageIntent extends Intent {
  const _PrevPageIntent();
}

class _ToggleSearchIntent extends Intent {
  const _ToggleSearchIntent();
}

class _ToggleFullscreenIntent extends Intent {
  const _ToggleFullscreenIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class PdfViewerScreen extends StatefulWidget {
  final FilePayload payload;
  final TransientFileSourceResolver sourceResolver;
  final ValueChanged<PdfAnnotationData>? onAnnotationsChanged;

  const PdfViewerScreen({
    super.key,
    required this.payload,
    this.sourceResolver = const TransientFileSourceResolver(),
    this.onAnnotationsChanged,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfViewerController _pdfController;
  late final PdfTextSearcher _textSearcher;

  int _currentPage = 1;
  int _pageCount = 1;
  double _zoomLevel = 1.0;
  bool _isDarkTheme = true;
  Uint8List? _pdfBytes;
  String? _errorMessage;
  bool _isLoading = true;

  // Acrobat Suite State
  bool _isSidebarOpen = false;
  PdfSidebarTab _activeSidebarTab = PdfSidebarTab.thumbnails;
  bool _isSearchOpen = false;
  bool _isFullscreen = false;
  PdfViewMode _viewMode = PdfViewMode.singlePage;
  PdfToolMode _toolMode = PdfToolMode.hand;
  int _rotationQuarterTurns = 0; // 0, 1 (90°), 2 (180°), 3 (270°)

  List<PdfOutlineNode>? _outlineNodes;
  List<PdfPage> _pages = const [];
  List<PdfTextRanges> _selectedTextRanges = const [];
  late PdfAnnotationData _annotations;
  int? _activeStrokePage;
  final List<Offset> _activeStrokePoints = [];

  final Color _activePenColor = const Color(0xFFEF4444);
  final double _activeStrokeWidth = 3.0;

  AppTokens get _tokens => _isDarkTheme ? AppTokens.dark : AppTokens.light;

  @override
  void initState() {
    super.initState();
    _annotations = widget.payload.pdfAnnotations;
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onControllerMatrixChanged);
    _textSearcher = PdfTextSearcher(_pdfController);
    _loadBytes();
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onControllerMatrixChanged);
    _textSearcher.dispose();
    super.dispose();
  }

  void _updateAnnotations(PdfAnnotationData value) {
    setState(() => _annotations = value);
    widget.onAnnotationsChanged?.call(value);
  }

  void _onControllerMatrixChanged() {
    if (_pdfController.isReady && mounted) {
      final currentZoom = _pdfController.currentZoom;
      if ((currentZoom - _zoomLevel).abs() > 0.02) {
        setState(() {
          _zoomLevel = currentZoom;
        });
      }
    }
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

  Future<void> _savePdfExternally() async {
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

  void _goToPage(int page) {
    if (page < 1 || page > _pageCount) return;
    setState(() {
      _currentPage = page;
    });
    if (_pdfController.isReady) {
      _pdfController.goToPage(pageNumber: page);
    }
  }

  void _zoomIn() {
    if (_pdfController.isReady) {
      final nextZoom = _pdfController.getNextZoom(loop: false);
      _pdfController.setZoom(_pdfController.centerPosition, nextZoom);
    }
  }

  void _zoomOut() {
    if (_pdfController.isReady) {
      final prevZoom = _pdfController.getPreviousZoom(loop: false);
      _pdfController.setZoom(_pdfController.centerPosition, prevZoom);
    }
  }

  void _resetZoom() {
    if (_pdfController.isReady) {
      _pdfController.setZoom(_pdfController.centerPosition, 1.0);
    }
  }

  void _rotateClockwise() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchOpen = !_isSearchOpen;
      if (!_isSearchOpen) {
        _textSearcher.resetTextSearch();
      }
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  void _showJumpToPageDialog() {
    final textController = TextEditingController(text: '$_currentPage');
    showUiDialog(
      context: context,
      builder: (dialogCtx) => UiDialog(
        semanticsLabel: 'Go to PDF page',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Go to Page', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Enter page number (1 to $_pageCount):',
                style: style.bodyTextStyle,
              ),
              const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
              UiTextField(
                controller: textController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                hint: '1 - $_pageCount',
                onSubmitted: (value) {
                  final page = int.tryParse(value);
                  if (page != null && page >= 1 && page <= _pageCount) {
                    Navigator.of(dialogCtx).pop();
                    _goToPage(page);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () {
                      final page = int.tryParse(textController.text);
                      if (page != null && page >= 1 && page <= _pageCount) {
                        Navigator.of(dialogCtx).pop();
                        _goToPage(page);
                      }
                    },
                    child: const Text('Go'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAddNote(Offset globalPos) {
    final documentPoint = _pdfController.globalToDocument(globalPos);
    if (documentPoint == null) return;
    final placement = locatePdfPage(
      documentPoint,
      _pdfController.layout.pageLayouts,
    );
    if (placement == null) return;

    final noteTextController = TextEditingController();
    showUiDialog(
      context: context,
      builder: (dialogCtx) => UiDialog(
        semanticsLabel: 'Add PDF sticky note',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sticky_note_2_rounded, color: _tokens.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Add Sticky Note (Page ${placement.pageNumber})',
                      style: style.titleTextStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              UiTextField(
                controller: noteTextController,
                autofocus: true,
                minLines: 4,
                maxLines: 4,
                hint: 'Type your comment or note here...',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () {
                      if (noteTextController.text.trim().isNotEmpty) {
                        final newNote = PdfStickyNote(
                          id: const Uuid().v4(),
                          pageNumber: placement.pageNumber,
                          relativePosition: placement.relativePosition,
                          text: noteTextController.text.trim(),
                          color: _tokens.accent,
                          createdAt: DateTime.now(),
                        );
                        _updateAnnotations(
                          _annotations.copyWith(
                            stickyNotes: [..._annotations.stickyNotes, newNote],
                          ),
                        );
                        setState(() => _toolMode = PdfToolMode.hand);
                      }
                      Navigator.of(dialogCtx).pop();
                    },
                    child: const Text('Save Note'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddTextCommentDialog() {
    if (_selectedTextRanges.isEmpty) return;
    final selections = List<PdfTextRanges>.of(_selectedTextRanges);
    final controller = TextEditingController();
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Add PDF text comment',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Comment', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 4,
                hint: 'Comment on selected text…',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () {
                      final comment = controller.text.trim();
                      if (comment.isEmpty) return;
                      final anchors = <annotation.PdfPageAnchor>[];
                      for (final selection in selections) {
                        final page = _pages[selection.pageNumber - 1];
                        final rect = selection.bounds.toRect(
                          page: page,
                          scaledPageSize: Size(page.width, page.height),
                        );
                        anchors.add(
                          annotation.PdfPageAnchor(
                            pageNumber: selection.pageNumber,
                            relativeRects: [
                              Rect.fromLTWH(
                                rect.left / page.width,
                                rect.top / page.height,
                                rect.width / page.width,
                                rect.height / page.height,
                              ),
                            ],
                          ),
                        );
                      }
                      final now = DateTime.now();
                      final textComment = PdfTextComment(
                        id: const Uuid().v4(),
                        quote: selections.map((item) => item.text).join('\n'),
                        comment: comment,
                        anchors: anchors,
                        createdAt: now,
                        updatedAt: now,
                      );
                      _updateAnnotations(
                        _annotations.copyWith(
                          textComments: [
                            ..._annotations.textComments,
                            textComment,
                          ],
                        ),
                      );
                      setState(() => _selectedTextRanges = const []);
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('Save Comment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTextCommentDialog(PdfTextComment comment) {
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'PDF text comment',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text Comment', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text(
                '“${comment.quote}”',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _tokens.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(comment.comment, style: style.bodyTextStyle),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () {
                      _updateAnnotations(
                        _annotations.copyWith(
                          textComments: _annotations.textComments
                              .where((item) => item.id != comment.id)
                              .toList(),
                        ),
                      );
                      Navigator.pop(dialogContext);
                    },
                    variant: UiButtonVariant.destructive,
                    prefix: const Icon(Icons.delete_outline),
                    child: const Text('Delete'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showViewNoteDialog(PdfStickyNote note) {
    showUiDialog(
      context: context,
      builder: (dialogCtx) => UiDialog(
        semanticsLabel: 'PDF sticky note',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sticky_note_2_rounded, color: _tokens.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Note on Page ${note.pageNumber}',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete note',
                    variant: UiButtonVariant.destructive,
                    onPressed: () {
                      _updateAnnotations(
                        _annotations.copyWith(
                          stickyNotes: _annotations.stickyNotes
                              .where((item) => item.id != note.id)
                              .toList(),
                        ),
                      );
                      Navigator.of(dialogCtx).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(note.text, style: style.bodyTextStyle),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  variant: UiButtonVariant.ghost,
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: true,
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.equal):
            const _ZoomInIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.equal):
            const _ZoomInIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.minus):
            const _ZoomOutIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.minus):
            const _ZoomOutIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit0):
            const _ZoomResetIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.digit0):
            const _ZoomResetIntent(),
        if (!_isSearchOpen)
          LogicalKeySet(LogicalKeyboardKey.arrowRight): const _NextPageIntent(),
        if (!_isSearchOpen)
          LogicalKeySet(LogicalKeyboardKey.arrowLeft): const _PrevPageIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _ToggleSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
            const _ToggleSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.f11): const _ToggleFullscreenIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const _EscapeIntent(),
      },
      actions: <Type, Action<Intent>>{
        _ZoomInIntent: CallbackAction<_ZoomInIntent>(
          onInvoke: (_) => _zoomIn(),
        ),
        _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(
          onInvoke: (_) => _zoomOut(),
        ),
        _ZoomResetIntent: CallbackAction<_ZoomResetIntent>(
          onInvoke: (_) => _resetZoom(),
        ),
        _NextPageIntent: CallbackAction<_NextPageIntent>(
          onInvoke: (_) => _goToPage(_currentPage + 1),
        ),
        _PrevPageIntent: CallbackAction<_PrevPageIntent>(
          onInvoke: (_) => _goToPage(_currentPage - 1),
        ),
        _ToggleSearchIntent: CallbackAction<_ToggleSearchIntent>(
          onInvoke: (_) => _toggleSearch(),
        ),
        _ToggleFullscreenIntent: CallbackAction<_ToggleFullscreenIntent>(
          onInvoke: (_) => _toggleFullscreen(),
        ),
        _EscapeIntent: CallbackAction<_EscapeIntent>(
          onInvoke: (_) {
            if (_isSearchOpen) {
              _toggleSearch();
            } else if (_isFullscreen) {
              _toggleFullscreen();
            }
            return null;
          },
        ),
      },
      child: AppThemeScope(
        data: AppTheme.materialThemeFor(_tokens),
        child: Scaffold(
          backgroundColor: _tokens.canvas,
          appBar: _isFullscreen
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: _buildHeader(),
                ),
          body: Stack(
            children: [
              Column(
                children: [
                  if (!_isFullscreen)
                    SizedBox(
                      width: double.infinity,
                      child: _buildAcrobatToolbar(),
                    ),
                  Expanded(
                    child: Row(
                      children: [
                        // Collapsible Sidebar (Thumbnails, Bookmarks, Annotations)
                        if (_isSidebarOpen && !_isFullscreen)
                          PdfSidebar(
                            pdfController: _pdfController,
                            activeTab: _activeSidebarTab,
                            onTabChanged: (tab) =>
                                setState(() => _activeSidebarTab = tab),
                            outlineNodes: _outlineNodes,
                            stickyNotes: _annotations.stickyNotes,
                            textComments: _annotations.textComments,
                            currentPage: _currentPage,
                            pageCount: _pageCount,
                            isDarkTheme: _isDarkTheme,
                            onClose: () =>
                                setState(() => _isSidebarOpen = false),
                            onPageSelected: (page) => _goToPage(page),
                            onDestSelected: (dest) =>
                                _pdfController.goToDest(dest),
                            onNoteSelected: (note) {
                              _goToPage(note.pageNumber);
                              _showViewNoteDialog(note);
                            },
                            onNoteDeleted: (note) {
                              _updateAnnotations(
                                _annotations.copyWith(
                                  stickyNotes: _annotations.stickyNotes
                                      .where((item) => item.id != note.id)
                                      .toList(),
                                ),
                              );
                            },
                            onTextCommentSelected: (comment) {
                              if (comment.anchors.isNotEmpty) {
                                _goToPage(comment.anchors.first.pageNumber);
                              }
                              _showTextCommentDialog(comment);
                            },
                            onTextCommentDeleted: (comment) {
                              _updateAnnotations(
                                _annotations.copyWith(
                                  textComments: _annotations.textComments
                                      .where((item) => item.id != comment.id)
                                      .toList(),
                                ),
                              );
                            },
                          ),

                        // Main PDF Viewport
                        Expanded(
                          child: Container(
                            color: _tokens.canvasGrid,
                            child: _buildPdfViewerArea(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isFullscreen) _buildBottomStatusBar(),
                ],
              ),

              if (_toolMode == PdfToolMode.select &&
                  _selectedTextRanges.isNotEmpty)
                Positioned(
                  right: AppSpacing.xl,
                  bottom: 52,
                  child: UiButton(
                    onPressed: _showAddTextCommentDialog,
                    prefix: const Icon(Icons.add_comment_outlined),
                    child: const Text('Add Comment'),
                  ),
                ),

              // Floating Search Bar
              if (_isSearchOpen)
                Positioned(
                  top: _isFullscreen ? AppSpacing.md : AppSpacing.sm,
                  left: AppSpacing.page,
                  right: AppSpacing.page,
                  child: PdfSearchBar(
                    textSearcher: _textSearcher,
                    onClose: () => setState(() {
                      _isSearchOpen = false;
                      _textSearcher.resetTextSearch();
                    }),
                    isDarkTheme: _isDarkTheme,
                  ),
                ),

              // Fullscreen Escape Button Overlay
              if (_isFullscreen)
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: UiIconButton(
                    tooltip: 'Exit Fullscreen (Esc / F11)',
                    icon: Icons.fullscreen_exit,
                    variant: UiButtonVariant.outline,
                    onPressed: _toggleFullscreen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tokens = _tokens;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final actions = compact
        ? _buildCompactHeaderActions()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiIconButton(
                tooltip: 'Search Document (Ctrl + F)',
                icon: Icons.search,
                selected: _isSearchOpen,
                onPressed: _toggleSearch,
              ),
              UiIconButton(
                tooltip: 'Presentation Mode (F11)',
                icon: Icons.fullscreen,
                onPressed: _toggleFullscreen,
              ),
              UiIconButton(
                tooltip: 'Open in External Application',
                icon: Icons.open_in_new,
                onPressed: _savePdfExternally,
              ),
              UiIconButton(
                tooltip: _isDarkTheme
                    ? 'Switch to Light Theme'
                    : 'Switch to Dark Theme',
                icon: _isDarkTheme
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                onPressed: () => setState(() => _isDarkTheme = !_isDarkTheme),
              ),
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          bottom: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              UiIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back to Canvas',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + AppSpacing.xxs,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: widget.payload.customBadgeColor ?? tokens.danger,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.payload.fileExtension.toUpperCase().replaceAll(
                    '.',
                    '',
                  ),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: tokens.handle,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.payload.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      '${widget.payload.fileSizeText} • PAGE $_currentPage OF $_pageCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              actions,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeaderActions() => UiMenuButton<_PdfHeaderAction>(
    buttonKey: const ValueKey('pdf-compact-header-actions'),
    tooltip: 'PDF viewer actions',
    icon: Icons.more_vert,
    items: [
      UiMenuAction(
        value: _PdfHeaderAction.search,
        label: 'Search document',
        icon: Icons.search,
        selected: _isSearchOpen,
      ),
      const UiMenuAction(
        value: _PdfHeaderAction.presentation,
        label: 'Presentation mode',
        icon: Icons.fullscreen,
      ),
      const UiMenuAction(
        value: _PdfHeaderAction.external,
        label: 'Open in external application',
        icon: Icons.open_in_new,
      ),
      UiMenuAction(
        value: _PdfHeaderAction.toggleTheme,
        label: _isDarkTheme ? 'Switch to light theme' : 'Switch to dark theme',
        icon: _isDarkTheme
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
    ],
    onSelected: (action) {
      switch (action) {
        case _PdfHeaderAction.search:
          _toggleSearch();
        case _PdfHeaderAction.presentation:
          _toggleFullscreen();
        case _PdfHeaderAction.external:
          _savePdfExternally();
        case _PdfHeaderAction.toggleTheme:
          setState(() => _isDarkTheme = !_isDarkTheme);
      }
    },
  );

  Widget _buildAcrobatToolbar() {
    final tokens = _tokens;

    return Container(
      height: AppControlSize.minimumHitTarget + AppBorder.thin,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        border: Border(
          bottom: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: SingleChildScrollView(
        key: const ValueKey('pdf-acrobat-toolbar-scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          key: const ValueKey('pdf-acrobat-toolbar-content'),
          children: [
            // Sidebar Toggle
            UiIconButton(
              tooltip: _isSidebarOpen
                  ? 'Hide Navigation Panel'
                  : 'Show Navigation Panel (Thumbnails & Outline)',
              icon: _isSidebarOpen ? Icons.menu_open : Icons.menu,
              selected: _isSidebarOpen,
              onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
            ),
            _buildToolbarDivider(),

            // Cursor Tool Selection (Hand vs Text Select vs Annotations)
            _buildToolIconButton(
              tool: PdfToolMode.hand,
              icon: Icons.pan_tool_outlined,
              tooltip: 'Hand Tool (Pan / Scroll)',
            ),
            _buildToolIconButton(
              tool: PdfToolMode.select,
              icon: Icons.text_fields_rounded,
              tooltip: 'Text Selection Tool (Copy Text)',
            ),
            _buildToolIconButton(
              tool: PdfToolMode.drawPen,
              icon: Icons.edit_outlined,
              tooltip: 'Pen Draw Tool',
            ),
            _buildToolIconButton(
              tool: PdfToolMode.drawHighlighter,
              icon: Icons.highlight_alt_rounded,
              tooltip: 'Highlighter Tool',
            ),
            _buildToolIconButton(
              tool: PdfToolMode.addNote,
              icon: Icons.note_add_outlined,
              tooltip: 'Sticky Note Tool (Click on page to place note)',
            ),
            if (_annotations.strokes.isNotEmpty) ...[
              UiIconButton(
                tooltip: 'Clear Drawings',
                icon: Icons.layers_clear_outlined,
                onPressed: () => _updateAnnotations(
                  _annotations.copyWith(strokes: const []),
                ),
              ),
            ],

            _buildToolbarDivider(),

            // Page Navigation Controls
            UiIconButton(
              tooltip: 'Previous Page (←)',
              icon: Icons.chevron_left,
              onPressed: _currentPage > 1
                  ? () => _goToPage(_currentPage - 1)
                  : null,
            ),
            SizedBox(
              height: AppControlSize.minimumHitTarget + AppBorder.thin,
              child: GestureDetector(
                key: const ValueKey('pdf-page-jump-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _showJumpToPageDialog,
                child: Semantics(
                  button: true,
                  label: 'Go to page $_currentPage of $_pageCount',
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + AppSpacing.xxs,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.panel,
                        borderRadius: BorderRadius.circular(
                          tokens.controlRadius,
                        ),
                        border: Border.all(
                          color: tokens.panelBorder,
                          width: AppBorder.thin,
                        ),
                      ),
                      child: Text(
                        'Page $_currentPage / $_pageCount',
                        style: Theme.of(context).textTheme.labelMedium!
                            .copyWith(
                              fontWeight: FontWeight.bold,
                              color: tokens.text,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            UiIconButton(
              tooltip: 'Next Page (→)',
              icon: Icons.chevron_right,
              onPressed: _currentPage < _pageCount
                  ? () => _goToPage(_currentPage + 1)
                  : null,
            ),

            _buildToolbarDivider(),

            // Zoom Controls
            UiIconButton(
              tooltip: 'Zoom Out (Ctrl -)',
              icon: Icons.remove,
              onPressed: _zoomOut,
            ),
            SizedBox(
              height: AppControlSize.minimumHitTarget + AppBorder.thin,
              child: GestureDetector(
                key: const ValueKey('pdf-zoom-reset-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _resetZoom,
                child: Semantics(
                  button: true,
                  label: 'Reset zoom',
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.panel,
                        borderRadius: BorderRadius.circular(
                          tokens.controlRadius,
                        ),
                        border: Border.all(
                          color: tokens.panelBorder,
                          width: AppBorder.thin,
                        ),
                      ),
                      child: Text(
                        '${(_zoomLevel * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          fontWeight: FontWeight.bold,
                          color: tokens.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            UiIconButton(
              tooltip: 'Zoom In (Ctrl +)',
              icon: Icons.add,
              onPressed: _zoomIn,
            ),
            const SizedBox(width: AppSpacing.xs),
            UiButton(
              size: UiButtonSize.sm,
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.fit_screen, size: 13),
              onPressed: _resetZoom,
              child: Text(
                'Reset',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),

            _buildToolbarDivider(),

            // Rotate Page
            UiIconButton(
              tooltip: 'Rotate 90° Clockwise',
              icon: Icons.rotate_right_rounded,
              onPressed: _rotateClockwise,
            ),

            // View Mode Toggle (Single Page vs Continuous Scroll)
            UiIconButton(
              tooltip: _viewMode == PdfViewMode.singlePage
                  ? 'Switch to Continuous Scroll View'
                  : 'Switch to Single-Page Document View',
              icon: _viewMode == PdfViewMode.singlePage
                  ? Icons.view_day_outlined
                  : Icons.view_agenda_outlined,
              selected: _viewMode == PdfViewMode.continuous,
              onPressed: () {
                setState(() {
                  _viewMode = _viewMode == PdfViewMode.singlePage
                      ? PdfViewMode.continuous
                      : PdfViewMode.singlePage;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolIconButton({
    required PdfToolMode tool,
    required IconData icon,
    required String tooltip,
  }) => UiIconButton(
    icon: icon,
    tooltip: tooltip,
    selected: _toolMode == tool,
    onPressed: () => setState(() => _toolMode = tool),
  );

  Widget _buildToolbarDivider() {
    return Container(
      height: AppSpacing.pageWide,
      width: AppBorder.thin,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: _tokens.panelBorder,
    );
  }

  Widget _buildPdfViewerArea() => RotatedBox(
    quarterTurns: _rotationQuarterTurns,
    child: Stack(
      children: [
        _buildPdfViewerCore(),
        if (_toolMode == PdfToolMode.addNote)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _handleAddNote(details.globalPosition),
            ),
          ),
        if (_toolMode == PdfToolMode.drawPen ||
            _toolMode == PdfToolMode.drawHighlighter)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) => _startStroke(details.globalPosition),
              onPanUpdate: (details) => _appendStroke(details.globalPosition),
              onPanEnd: (_) => _finishStroke(),
            ),
          ),
      ],
    ),
  );

  void _startStroke(Offset globalPosition) {
    final point = _pdfController.globalToDocument(globalPosition);
    if (point == null) return;
    final placement = locatePdfPage(point, _pdfController.layout.pageLayouts);
    if (placement == null) return;
    setState(() {
      _activeStrokePage = placement.pageNumber;
      _activeStrokePoints
        ..clear()
        ..add(placement.relativePosition);
    });
  }

  void _appendStroke(Offset globalPosition) {
    final page = _activeStrokePage;
    final point = _pdfController.globalToDocument(globalPosition);
    if (page == null || point == null) return;
    final placement = locatePdfPage(point, _pdfController.layout.pageLayouts);
    if (placement?.pageNumber != page) return;
    setState(() => _activeStrokePoints.add(placement!.relativePosition));
  }

  void _finishStroke() {
    final page = _activeStrokePage;
    if (page == null || _activeStrokePoints.isEmpty) return;
    final stroke = PdfStroke(
      id: const Uuid().v4(),
      pageNumber: page,
      relativePoints: List.of(_activeStrokePoints),
      color: _toolMode == PdfToolMode.drawHighlighter
          ? const Color(0xFFFBBF24)
          : _activePenColor,
      strokeWidth: _toolMode == PdfToolMode.drawHighlighter
          ? 16
          : _activeStrokeWidth,
      isHighlighter: _toolMode == PdfToolMode.drawHighlighter,
    );
    _activeStrokePage = null;
    _activeStrokePoints.clear();
    _updateAnnotations(
      _annotations.copyWith(strokes: [..._annotations.strokes, stroke]),
    );
  }

  Widget _buildPdfViewerCore() {
    if (_isLoading) {
      return const Center(
        child: UiProgressIndicator(semanticsLabel: 'Loading PDF'),
      );
    }

    if (_errorMessage != null) {
      final tokens = _tokens;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: tokens.danger, size: 44),
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

    // Document Page Layout for exact single-page isolation with clean centered sheet styling
    PdfPageLayout singlePageLayout(
      List<PdfPage> pages,
      PdfViewerParams params,
    ) {
      final maxWidth = pages.fold(0.0, (w, p) => math.max(w, p.width));
      final maxHeight = pages.fold(0.0, (h, p) => math.max(h, p.height));
      const pageMargin = 40.0;
      final docWidth = maxWidth + pageMargin * 2;
      final docHeight = maxHeight + pageMargin * 2;
      final pageGap = math.max(docWidth * 3.0, 5000.0);

      final pageLayouts = <Rect>[];
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        final x =
            pageMargin +
            (i * (docWidth + pageGap)) +
            (maxWidth - page.width) / 2;
        final y = pageMargin + (maxHeight - page.height) / 2;
        pageLayouts.add(Rect.fromLTWH(x, y, page.width, page.height));
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size(pages.length * (docWidth + pageGap), docHeight),
      );
    }

    final viewerParams = PdfViewerParams(
      backgroundColor: _tokens.canvasGrid,
      margin: 40,
      layoutPages: _viewMode == PdfViewMode.singlePage
          ? singlePageLayout
          : null,
      enableTextSelection: _toolMode == PdfToolMode.select,
      onTextSelectionChange: (selections) {
        if (mounted) setState(() => _selectedTextRanges = selections);
      },
      pagePaintCallbacks: [_textSearcher.pageTextMatchPaintCallback],
      pageOverlaysBuilder: (context, pageRect, page) => [
        Positioned.fill(
          key: ValueKey('pdf-page-overlay-${page.pageNumber}'),
          child: IgnorePointer(
            child: CustomPaint(
              painter: PdfAnnotationPainter(
                strokes: _annotations.strokes
                    .where((stroke) => stroke.pageNumber == page.pageNumber)
                    .toList(),
                pageSize: pageRect.size,
              ),
            ),
          ),
        ),
        ..._annotations.textComments.expand(
          (comment) => comment.anchors
              .where((anchor) => anchor.pageNumber == page.pageNumber)
              .expand(
                (anchor) => anchor.relativeRects.map(
                  (rect) => Positioned(
                    left: rect.left * pageRect.width,
                    top: rect.top * pageRect.height,
                    width: rect.width * pageRect.width,
                    height: rect.height * pageRect.height,
                    child: GestureDetector(
                      onTap: () => _showTextCommentDialog(comment),
                      child: Container(color: const Color(0x66FBBF24)),
                    ),
                  ),
                ),
              ),
        ),
        ..._annotations.stickyNotes
            .where((note) => note.pageNumber == page.pageNumber)
            .map(
              (note) => Positioned(
                key: ValueKey('pdf-note-${note.id}'),
                left: note.relativePosition.dx * pageRect.width - 12,
                top: note.relativePosition.dy * pageRect.height - 12,
                child: GestureDetector(
                  onTap: () => _showViewNoteDialog(note),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _tokens.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sticky_note_2,
                      size: 16,
                      color: _tokens.handle,
                    ),
                  ),
                ),
              ),
            ),
      ],
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: (link) async {
          if (link.url != null) {
            try {
              await launchUrl(link.url!, mode: LaunchMode.externalApplication);
            } catch (_) {}
          } else if (link.dest != null) {
            _pdfController.goToDest(link.dest!);
          }
        },
      ),
      pageDropShadow: const BoxShadow(
        color: Color(0x66000000),
        blurRadius: 28,
        spreadRadius: 2,
        offset: Offset(0, 10),
      ),
      onViewerReady: (document, controller) async {
        try {
          final outline = await document.loadOutline();
          if (mounted) {
            setState(() {
              _pages = document.pages;
              _outlineNodes = outline;
            });
          }
        } catch (_) {}
      },
      onDocumentChanged: (document) {
        if (document != null && mounted) {
          setState(() {
            _pageCount = document.pages.length;
          });
        }
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null && mounted && pageNumber != _currentPage) {
          setState(() {
            _currentPage = pageNumber;
          });
        }
      },
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
          const Center(
            child: UiProgressIndicator(semanticsLabel: 'Loading PDF pages'),
          ),
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        final tokens = _tokens;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  color: tokens.danger,
                  size: 48,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Failed to render PDF in-app.',
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  'The PDF bytes could not be hydrated from the available source.',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                UiButton(
                  prefix: const Icon(Icons.open_in_new, size: 16),
                  onPressed: _savePdfExternally,
                  child: const Text('Open in System App / Browser'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (_pdfBytes != null) {
      return PdfViewer.data(
        _pdfBytes!,
        sourceName: widget.payload.fileName,
        controller: _pdfController,
        params: viewerParams,
      );
    }

    final tokens = _tokens;
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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: tokens.text),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ensure the file has an owned artifact or private Storage reference.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    final viewModeText = _viewMode == PdfViewMode.singlePage
        ? 'SINGLE-PAGE VIEW'
        : 'CONTINUOUS SCROLL VIEW';
    final toolText = _toolMode == PdfToolMode.hand
        ? 'HAND TOOL'
        : _toolMode == PdfToolMode.select
        ? 'TEXT SELECT TOOL'
        : _toolMode == PdfToolMode.drawPen
        ? 'PEN DRAW'
        : _toolMode == PdfToolMode.drawHighlighter
        ? 'HIGHLIGHTER'
        : 'STICKY NOTE';
    final tokens = _tokens;

    return Container(
      constraints: const BoxConstraints(minHeight: AppControlSize.extraSmall),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          top: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                viewModeText,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.textMuted,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + AppSpacing.xxs,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  toolText,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.accent,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'ROTATION ${_rotationQuarterTurns * 90}° • ZOOM ${(_zoomLevel * 100).round()}% • CTRL+F SEARCH',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w600,
              color: tokens.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
