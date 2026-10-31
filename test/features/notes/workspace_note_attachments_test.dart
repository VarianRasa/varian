import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note_attachments.dart';

void main() {
  group('parseWorkspaceNoteAttachmentEmbeds', () {
    const firstId = '123e4567-e89b-12d3-a456-426614174000';
    const secondId = '223e4567-e89b-12d3-a456-426614174001';

    test('returns valid attachment IDs and source offsets from the body', () {
      const source =
          '---\ntitle: "![[attachment:$firstId]]"\n---\n'
          'Cover ![[attachment:$firstId]] and ![[attachment:$secondId]].';

      final embeds = parseWorkspaceNoteAttachmentEmbeds(source);

      expect(embeds.map((embed) => embed.attachmentId), [firstId, secondId]);
      for (final embed in embeds) {
        expect(
          source.substring(embed.start, embed.end),
          '![[attachment:${embed.attachmentId}]]',
        );
      }
    });

    test('ignores frontmatter, fenced code, and inline code', () {
      const source =
          '---\nasset: ![[attachment:$firstId]]\n---\n'
          '`![[attachment:$firstId]]`\n'
          '```markdown\n![[attachment:$firstId]]\n```\n'
          'Visible: ![[attachment:$secondId]]';

      final embeds = parseWorkspaceNoteAttachmentEmbeds(source);

      expect(embeds.map((embed) => embed.attachmentId), [secondId]);
    });

    test('ignores escaped and malformed references', () {
      const source =
          r'\![[attachment:123e4567-e89b-12d3-a456-426614174000]] '
          '![[attachment:../../private/file.png]] '
          '![[attachment:not-a-uuid]]';

      expect(parseWorkspaceNoteAttachmentEmbeds(source), isEmpty);
    });

    test('does not resolve content inside an unclosed frontmatter block', () {
      const source = '---\nasset: ![[attachment:$firstId]]';

      expect(parseWorkspaceNoteAttachmentEmbeds(source), isEmpty);
    });

    test('returns an immutable result', () {
      const source = '![[attachment:$firstId]]';
      final embeds = parseWorkspaceNoteAttachmentEmbeds(source);

      expect(() => embeds.clear(), throwsUnsupportedError);
    });
  });
}
