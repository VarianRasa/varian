import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note_callouts.dart';

void main() {
  test('renders callouts, honors fold markers, and skips code examples', () {
    const markdown = '''---
example: ignored
---
> [!warning]- Careful
> hidden body

> [!note] Details
> visible body
```markdown
> [!tip] Example
```
''';
    final warningOffset = markdown.indexOf('> [!warning]');
    final noteOffset = markdown.indexOf('> [!note]');

    final rendered = renderWorkspaceCallouts(markdown);

    expect(
      rendered,
      contains('[WARNING ▸](varian-callout://toggle/$warningOffset/1) Careful'),
    );
    expect(rendered, isNot(contains('> hidden body')));
    expect(
      rendered,
      contains('[NOTE ▾](varian-callout://toggle/$noteOffset/0) Details'),
    );
    expect(rendered, contains('> visible body'));
    expect(rendered, contains('> [!tip] Example'));
  });

  test(
    'can expand a callout that starts collapsed without changing source',
    () {
      const markdown = '> [!tip]- Next steps\n> retained content';
      final markerOffset = markdown.indexOf('> [!tip]');

      final rendered = renderWorkspaceCallouts(
        markdown,
        collapsedCallouts: {markerOffset: false},
      );

      expect(
        rendered,
        contains('[TIP ▾](varian-callout://toggle/$markerOffset/0)'),
      );
      expect(rendered, contains('> retained content'));
      expect(markdown, '> [!tip]- Next steps\n> retained content');
    },
  );
}
