import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/rich_text.dart';

class QuillDocumentAdapter {
  const QuillDocumentAdapter._();

  static quill.Document toQuillDocument(DocumentPayload payload) {
    final savedDelta = payload.deltaJson;
    if (savedDelta != null) {
      try {
        final json = jsonDecode(savedDelta);
        if (json is List) return quill.Document.fromJson(json);
      } on FormatException {
        // Fall back to the backward-compatible block representation.
      }
    }

    final operations = <Map<String, dynamic>>[];
    for (final block in payload.blocks) {
      for (final span in block.spans) {
        if (span.text.isEmpty) continue;
        final attributes = _inlineAttributes(span);
        operations.add({
          'insert': span.text,
          if (attributes.isNotEmpty) 'attributes': attributes,
        });
      }
      final attributes = _blockAttributes(block.type);
      operations.add({
        'insert': '\n',
        if (attributes.isNotEmpty) 'attributes': attributes,
      });
    }

    if (operations.isEmpty) operations.add({'insert': '\n'});
    return quill.Document.fromJson(operations);
  }

  static DocumentPayload fromQuillDocument({
    required String title,
    required quill.Document document,
  }) {
    final delta = document.toDelta().toJson();
    final blocks = <RichTextBlock>[];
    var spans = <RichTextSpan>[];

    void finishBlock(Map<String, dynamic>? attributes) {
      blocks.add(
        RichTextBlock(
          type: _blockType(attributes),
          spans: List<RichTextSpan>.from(spans),
        ),
      );
      spans = <RichTextSpan>[];
    }

    for (final rawOperation in delta) {
      final operation = Map<String, dynamic>.from(rawOperation);
      final inserted = operation['insert'];
      if (inserted is! String) continue;
      final attributes = operation['attributes'] is Map
          ? Map<String, dynamic>.from(operation['attributes'] as Map)
          : null;
      final parts = inserted.split('\n');

      for (var index = 0; index < parts.length; index++) {
        final text = parts[index];
        if (text.isNotEmpty) {
          spans.add(_spanFromAttributes(text, attributes));
        }
        if (index < parts.length - 1) {
          finishBlock(attributes);
        }
      }
    }

    if (spans.isNotEmpty) {
      finishBlock(null);
    }
    if (blocks.isEmpty) {
      blocks.add(const RichTextBlock(spans: [RichTextSpan(text: '')]));
    }

    return DocumentPayload(
      title: title.trim().isEmpty ? 'Untitled Document' : title.trim(),
      blocks: blocks,
      deltaJson: jsonEncode(delta),
    );
  }

  static Map<String, dynamic> _inlineAttributes(RichTextSpan span) => {
    if (span.bold) 'bold': true,
    if (span.italic) 'italic': true,
    if (span.underline) 'underline': true,
    if (span.strikethrough) 'strike': true,
    if (span.color != null) 'color': _colorToHex(span.color!),
    if (span.highlight != null) 'background': _colorToHex(span.highlight!),
    if (span.linkUrl != null && span.linkUrl!.isNotEmpty) 'link': span.linkUrl,
  };

  static Map<String, dynamic> _blockAttributes(RichTextBlockType type) {
    switch (type) {
      case RichTextBlockType.heading:
        return {'header': 1};
      case RichTextBlockType.bullet:
        return {'list': 'bullet'};
      case RichTextBlockType.numbered:
        return {'list': 'ordered'};
      case RichTextBlockType.quote:
        return {'blockquote': true};
      case RichTextBlockType.code:
        return {'code-block': true};
      case RichTextBlockType.paragraph:
        return const {};
    }
  }

  static RichTextBlockType _blockType(Map<String, dynamic>? attributes) {
    if (attributes == null) return RichTextBlockType.paragraph;
    if (attributes['header'] != null) return RichTextBlockType.heading;
    if (attributes['align'] != null) return RichTextBlockType.paragraph;
    if (attributes['list'] == 'bullet' ||
        attributes['list'] == 'checked' ||
        attributes['list'] == 'unchecked') {
      return RichTextBlockType.bullet;
    }
    if (attributes['list'] == 'ordered') return RichTextBlockType.numbered;
    if (attributes['blockquote'] == true) return RichTextBlockType.quote;
    if (attributes['code-block'] != null) return RichTextBlockType.code;
    return RichTextBlockType.paragraph;
  }

  static RichTextSpan _spanFromAttributes(
    String text,
    Map<String, dynamic>? attributes,
  ) {
    return RichTextSpan(
      text: text,
      bold: attributes?['bold'] == true,
      italic: attributes?['italic'] == true,
      underline: attributes?['underline'] == true,
      strikethrough: attributes?['strike'] == true,
      color: _parseColor(attributes?['color']),
      highlight: _parseColor(attributes?['background']),
      linkUrl: attributes?['link'] as String?,
    );
  }

  static String _colorToHex(Color color) {
    final value = color.toARGB32();
    return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color? _parseColor(dynamic value) {
    if (value is! String) return null;
    final hex = value.replaceFirst('#', '');
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
  }
}
