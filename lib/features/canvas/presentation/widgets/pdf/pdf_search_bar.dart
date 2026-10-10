import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:mix/mix.dart';

class PdfSearchBar extends StatefulWidget {
  final PdfTextSearcher textSearcher;
  final VoidCallback onClose;
  final bool isDarkTheme;

  const PdfSearchBar({
    super.key,
    required this.textSearcher,
    required this.onClose,
    required this.isDarkTheme,
  });

  @override
  State<PdfSearchBar> createState() => _PdfSearchBarState();
}

class _PdfSearchBarState extends State<PdfSearchBar> {
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _caseSensitive = false;

  @override
  void initState() {
    super.initState();
    widget.textSearcher.addListener(_onSearchUpdated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.textSearcher.removeListener(_onSearchUpdated);
    _textEditingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _executeSearch(String query) {
    if (query.trim().isEmpty) {
      widget.textSearcher.resetTextSearch();
      return;
    }
    widget.textSearcher.startTextSearch(
      query,
      caseInsensitive: !_caseSensitive,
      searchImmediately: true,
    );
  }

  void _goToNext() {
    if (widget.textSearcher.hasMatches) {
      widget.textSearcher.goToNextMatch();
    }
  }

  void _goToPrev() {
    if (widget.textSearcher.hasMatches) {
      widget.textSearcher.goToPrevMatch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final searcher = widget.textSearcher;
    final totalMatches = searcher.matches.length;
    final currentIndex = searcher.currentIndex != null && totalMatches > 0
        ? searcher.currentIndex! + 1
        : 0;

    final tokens = widget.isDarkTheme ? AppTokens.dark : AppTokens.light;

    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: Box(
        style: AppStyles.surface
            .color(tokens.panelElevated)
            .borderRadius(
              BorderRadiusGeometryMix.value(
                BorderRadius.circular(AppRadius.control),
              ),
            )
            .borderAll(color: tokens.panelBorder, width: AppBorder.thin)
            .boxShadows([
              BoxShadowMix(
                color: tokens.text.withValues(alpha: 0.2),
                blurRadius: AppElevation.floatingBlur,
                offset: const Offset(0, AppElevation.floatingOffset),
              ),
            ])
            .padding(
              EdgeInsetsGeometryMix.value(
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
            ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = (constraints.maxWidth * 0.36)
                .clamp(96.0, 200.0)
                .toDouble();
            return Row(
              children: [
                Icon(Icons.search, size: 18, color: tokens.textMuted),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: fieldWidth,
                  child: UiTextField(
                    controller: _textEditingController,
                    hint: 'Search document...',
                    onChanged: _executeSearch,
                    onSubmitted: (_) => _goToNext(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('pdf-search-actions-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs + AppSpacing.xxs,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: Text(
                            searcher.isSearching
                                ? 'Searching...'
                                : totalMatches > 0
                                ? '$currentIndex / $totalMatches'
                                : _textEditingController.text.isNotEmpty
                                ? '0 found'
                                : '',
                            style: Theme.of(context).textTheme.labelSmall!
                                .copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textMuted,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        UiButton(
                          onPressed: () {
                            setState(() => _caseSensitive = !_caseSensitive);
                            final query = _textEditingController.text;
                            if (query.trim().isNotEmpty) {
                              widget.textSearcher.resetTextSearch();
                              Future.microtask(() {
                                if (!mounted) return;
                                widget.textSearcher.startTextSearch(
                                  query,
                                  caseInsensitive: !_caseSensitive,
                                  searchImmediately: true,
                                );
                              });
                            }
                          },
                          variant: _caseSensitive
                              ? UiButtonVariant.primary
                              : UiButtonVariant.ghost,
                          size: UiButtonSize.sm,
                          child: const Text('Aa'),
                        ),
                        UiIconButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Previous Match (Shift+Enter)',
                          onPressed: totalMatches > 0 ? _goToPrev : null,
                        ),
                        UiIconButton(
                          icon: Icons.keyboard_arrow_down,
                          tooltip: 'Next Match (Enter)',
                          onPressed: totalMatches > 0 ? _goToNext : null,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        UiIconButton(
                          icon: Icons.close,
                          tooltip: 'Close Search (Esc)',
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
