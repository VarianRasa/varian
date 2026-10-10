import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/rich_text.dart';
import 'package:varian/features/canvas/domain/rich_text_editing.dart';

void main() {
  test('selection formatting splits spans and preserves untouched styles', () {
    const blocks = [
      RichTextBlock(
        spans: [
          RichTextSpan(text: 'Hello ', italic: true),
          RichTextSpan(text: 'world'),
        ],
      ),
    ];

    final result = RichTextEditing.formatSelection(
      text: 'Hello world',
      blocks: blocks,
      selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      format: RichTextFormat.bold,
      enabled: true,
    );

    expect(result.single.spans.map((span) => span.text), ['Hello ', 'world']);
    expect(result.single.spans[0].italic, isTrue);
    expect(result.single.spans[0].bold, isFalse);
    expect(result.single.spans[1].bold, isTrue);
  });

  test('multiline formatting keeps paragraph types and offsets', () {
    const blocks = [
      RichTextBlock(
        type: RichTextBlockType.heading,
        spans: [RichTextSpan(text: 'One')],
      ),
      RichTextBlock(
        type: RichTextBlockType.bullet,
        spans: [RichTextSpan(text: 'Two')],
      ),
    ];
    final result = RichTextEditing.formatSelection(
      text: 'One\nTwo',
      blocks: blocks,
      selection: const TextSelection(baseOffset: 1, extentOffset: 6),
      format: RichTextFormat.underline,
      enabled: true,
    );

    expect(result[0].type, RichTextBlockType.heading);
    expect(result[1].type, RichTextBlockType.bullet);
    expect(result[0].spans.any((span) => span.underline), isTrue);
    expect(result[1].spans.any((span) => span.underline), isTrue);
  });

  test('link selection validates schemes and supports clearing', () {
    final linked = RichTextEditing.setLinkSelection(
      text: 'OpenAI',
      blocks: const [
        RichTextBlock(spans: [RichTextSpan(text: 'OpenAI')]),
      ],
      selection: const TextSelection(baseOffset: 0, extentOffset: 6),
      url: 'https://openai.com',
    );
    expect(linked.single.spans.single.linkUrl, 'https://openai.com');

    final cleared = RichTextEditing.setLinkSelection(
      text: 'OpenAI',
      blocks: linked,
      selection: const TextSelection(baseOffset: 0, extentOffset: 6),
      url: null,
    );
    expect(cleared.single.spans.single.linkUrl, isNull);
    expect(RichTextEditing.normalizeLink('javascript:alert(1)'), isNull);
  });

  test('text payload persists typography and text path metadata', () {
    final payload = TextPayload(
      text: 'Path text',
      fontAxes: const {'wght': 650, 'wdth': 90},
      localeTag: 'id-ID',
      spellCheckEnabled: false,
      textPathNodeId: 'path-1',
      textPathOffset: 18,
      textPathReversed: true,
      textPathAlignment: TextPathAlignment.center,
      wrapMode: TextWrapMode.ellipsis,
    );
    final restored = TextPayload.fromJson(payload.toJson());
    expect(restored.fontAxes, {'wght': 650, 'wdth': 90});
    expect(restored.localeTag, 'id-ID');
    expect(restored.spellCheckEnabled, isFalse);
    expect(restored.textPathNodeId, 'path-1');
    expect(restored.textPathOffset, 18);
    expect(restored.textPathReversed, isTrue);
    expect(restored.textPathAlignment, TextPathAlignment.center);
    expect(restored.wrapMode, TextWrapMode.ellipsis);
  });
}
