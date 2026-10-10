import 'package:flutter/services.dart';

import '../../../domain/models/rich_text.dart';

enum RichTextFormat { bold, italic, underline, strikethrough }

class RichTextEditing {
  const RichTextEditing._();

  static List<RichTextBlock> normalizeBlocks(
    String text, {
    List<RichTextBlock>? blocks,
  }) {
    final lines = text.split('\n');
    final result = <RichTextBlock>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final existing = blocks != null && index < blocks.length
          ? blocks[index]
          : null;
      if (existing != null && existing.plainText == line) {
        result.add(existing);
        continue;
      }
      final template = existing?.spans.isNotEmpty == true
          ? existing!.spans.first
          : const RichTextSpan(text: '');
      result.add(
        (existing ?? const RichTextBlock()).copyWith(
          spans: [template.copyWith(text: line)],
        ),
      );
    }
    return result;
  }

  static List<RichTextBlock> replaceBlockText(
    List<RichTextBlock> blocks,
    int index,
    String text,
  ) {
    if (index < 0 || index >= blocks.length) return List.of(blocks);
    final current = blocks[index];
    final template = current.spans.isNotEmpty
        ? current.spans.first
        : const RichTextSpan(text: '');
    final result = List<RichTextBlock>.from(blocks);
    result[index] = current.copyWith(spans: [template.copyWith(text: text)]);
    return result;
  }

  static List<RichTextBlock> formatSelection({
    required String text,
    required List<RichTextBlock>? blocks,
    required TextSelection selection,
    required RichTextFormat format,
    bool? enabled,
  }) {
    final normalized = normalizeBlocks(text, blocks: blocks);
    if (!_hasTextSelection(text, selection)) return normalized;

    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final result = <RichTextBlock>[];
    var offset = 0;
    for (final block in normalized) {
      final line = block.plainText;
      final lineStart = offset;
      final lineEnd = lineStart + line.length;
      if (start < lineEnd && end > lineStart) {
        result.add(
          _formatBlock(
            block,
            start: (start - lineStart).clamp(0, line.length),
            end: (end - lineStart).clamp(0, line.length),
            format: format,
            enabled: enabled,
          ),
        );
      } else {
        result.add(block);
      }
      offset = lineEnd + 1;
    }
    return result;
  }

  static List<RichTextBlock> setLinkSelection({
    required String text,
    required List<RichTextBlock>? blocks,
    required TextSelection selection,
    required String? url,
  }) {
    final normalizedUrl = normalizeLink(url);
    final normalized = normalizeBlocks(text, blocks: blocks);
    if (!_hasTextSelection(text, selection)) return normalized;

    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final result = <RichTextBlock>[];
    var offset = 0;
    for (final block in normalized) {
      final line = block.plainText;
      final lineStart = offset;
      final lineEnd = lineStart + line.length;
      if (start < lineEnd && end > lineStart) {
        result.add(
          _formatBlock(
            block,
            start: (start - lineStart).clamp(0, line.length),
            end: (end - lineStart).clamp(0, line.length),
            linkUrl: normalizedUrl,
            linkProvided: true,
          ),
        );
      } else {
        result.add(block);
      }
      offset = lineEnd + 1;
    }
    return result;
  }

  static String? normalizeLink(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty && uri.scheme != 'mailto') return null;
    const allowedSchemes = {'http', 'https', 'mailto'};
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) return null;
    return value;
  }

  static bool _hasTextSelection(String text, TextSelection selection) {
    if (text.isEmpty || !selection.isValid || selection.isCollapsed) {
      return false;
    }
    return selection.start >= 0 &&
        selection.end >= 0 &&
        selection.start <= text.length &&
        selection.end <= text.length;
  }

  static RichTextBlock _formatBlock(
    RichTextBlock block, {
    required int start,
    required int end,
    RichTextFormat? format,
    bool? enabled,
    String? linkUrl,
    bool linkProvided = false,
  }) {
    final safeStart = start.clamp(0, block.plainText.length);
    final safeEnd = end.clamp(safeStart, block.plainText.length);
    if (safeStart == safeEnd) return block;

    final spans = <RichTextSpan>[];
    var cursor = 0;
    for (final span
        in block.spans.isEmpty ? const [RichTextSpan(text: '')] : block.spans) {
      final spanStart = cursor;
      final spanEnd = spanStart + span.text.length;
      final overlapStart = safeStart.clamp(spanStart, spanEnd);
      final overlapEnd = safeEnd.clamp(spanStart, spanEnd);
      if (overlapStart > spanStart) {
        spans.add(
          span.copyWith(text: span.text.substring(0, overlapStart - spanStart)),
        );
      }
      if (overlapEnd > overlapStart) {
        var selected = span.copyWith(
          text: span.text.substring(
            overlapStart - spanStart,
            overlapEnd - spanStart,
          ),
        );
        if (format != null) {
          selected = _applyFormat(selected, format, enabled);
        }
        if (linkProvided) selected = selected.copyWith(linkUrl: linkUrl);
        spans.add(selected);
      }
      if (overlapEnd < spanEnd) {
        spans.add(
          span.copyWith(text: span.text.substring(overlapEnd - spanStart)),
        );
      }
      cursor = spanEnd;
    }
    return block.copyWith(spans: _mergeAdjacent(spans));
  }

  static RichTextSpan _applyFormat(
    RichTextSpan span,
    RichTextFormat format,
    bool? enabled,
  ) {
    switch (format) {
      case RichTextFormat.bold:
        return span.copyWith(bold: enabled ?? !span.bold);
      case RichTextFormat.italic:
        return span.copyWith(italic: enabled ?? !span.italic);
      case RichTextFormat.underline:
        return span.copyWith(underline: enabled ?? !span.underline);
      case RichTextFormat.strikethrough:
        return span.copyWith(strikethrough: enabled ?? !span.strikethrough);
    }
  }

  static List<RichTextSpan> _mergeAdjacent(List<RichTextSpan> spans) {
    final result = <RichTextSpan>[];
    for (final span in spans) {
      if (span.text.isEmpty && spans.length > 1) continue;
      if (result.isNotEmpty && _sameStyle(result.last, span)) {
        result[result.length - 1] = result.last.copyWith(
          text: result.last.text + span.text,
        );
      } else {
        result.add(span);
      }
    }
    return result.isEmpty ? [const RichTextSpan(text: '')] : result;
  }

  static bool _sameStyle(RichTextSpan first, RichTextSpan second) {
    if (first.bold != second.bold ||
        first.italic != second.italic ||
        first.underline != second.underline ||
        first.strikethrough != second.strikethrough ||
        first.color != second.color ||
        first.highlight != second.highlight ||
        first.linkUrl != second.linkUrl ||
        first.fontFamily != second.fontFamily ||
        first.fontSize != second.fontSize ||
        first.fontWeight != second.fontWeight) {
      return false;
    }
    if (first.fontAxes.length != second.fontAxes.length) return false;
    for (final entry in first.fontAxes.entries) {
      if (second.fontAxes[entry.key] != entry.value) return false;
    }
    return true;
  }
}
