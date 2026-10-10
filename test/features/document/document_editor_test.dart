import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/rich_text.dart';
import 'package:varian/features/document/utils/quill_document_adapter.dart';

void main() {
  group('QuillDocumentAdapter', () {
    test('converts legacy rich text blocks into Quill Delta', () {
      final payload = DocumentPayload(
        title: 'Project brief',
        blocks: const [
          RichTextBlock(
            type: RichTextBlockType.heading,
            spans: [RichTextSpan(text: 'Overview', bold: true)],
          ),
          RichTextBlock(
            type: RichTextBlockType.bullet,
            spans: [RichTextSpan(text: 'First item', italic: true)],
          ),
        ],
      );

      final operations = QuillDocumentAdapter.toQuillDocument(
        payload,
      ).toDelta().toJson();

      expect(operations[0]['insert'], 'Overview');
      expect(operations[0]['attributes']['bold'], true);
      expect(operations[1]['attributes']['header'], 1);
      expect(operations[3]['attributes']['list'], 'bullet');
    });

    test('preserves Delta formatting and produces canvas preview blocks', () {
      final document = quill.Document.fromJson([
        {
          'insert': 'Architecture',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {
          'insert': 'Reference',
          'attributes': {
            'italic': true,
            'underline': true,
            'color': '#F97316',
            'link': 'https://example.com',
          },
        },
        {
          'insert': '\n',
          'attributes': {'blockquote': true},
        },
      ]);

      final payload = QuillDocumentAdapter.fromQuillDocument(
        title: 'Design notes',
        document: document,
      );

      expect(payload.title, 'Design notes');
      expect(payload.blocks[0].type, RichTextBlockType.heading);
      expect(payload.blocks[0].spans.first.bold, true);
      expect(payload.blocks[1].type, RichTextBlockType.quote);
      expect(payload.blocks[1].spans.first.italic, true);
      expect(payload.blocks[1].spans.first.underline, true);
      expect(payload.blocks[1].spans.first.linkUrl, 'https://example.com');
      expect(payload.blocks[1].spans.first.color, const Color(0xFFF97316));
      expect(jsonDecode(payload.deltaJson!), document.toDelta().toJson());
    });

    test('DocumentPayload JSON remains backward compatible', () {
      final legacy = DocumentPayload.fromJson({
        'title': 'Legacy',
        'blocks': [
          {
            'type': 'paragraph',
            'spans': [
              {'text': 'Old document'},
            ],
          },
        ],
      });

      expect(legacy.deltaJson, isNull);
      expect(legacy.blocks.single.plainText, 'Old document');
      expect(legacy.paperPresetId, 'a4');
      expect(legacy.isLandscape, false);
      expect(legacy.themeId, 'default_light');
      expect(legacy.hasShadow, true);
      expect(
        QuillDocumentAdapter.toQuillDocument(legacy).toPlainText(),
        'Old document\n',
      );
    });
  });
}
