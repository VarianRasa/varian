import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/note_template_expansion.dart';

void main() {
  test('expands frontmatter safely and body values as escaped Markdown', () {
    const template = '''---
date: {{date}}
title: {{title}}
aliases: {{aliases}}
---
Hello {{title}}. Aliases: {{aliases}}. Unknown: {{owner}}.''';

    final expanded = expandWorkspaceNoteTemplate(
      template: template,
      localDate: DateTime(2026, 3, 4, 23, 50),
      title: 'Research [Draft] {{date}}',
      aliases: const ['Primary *alias*', 'Docs | Notes'],
    );

    expect(
      expanded,
      '''---
date: 2026-03-04
title: "Research [Draft] {{date}}"
aliases: ["Primary *alias*","Docs | Notes"]
---
Hello Research \\[Draft\\] \\{\\{date\\}\\}. Aliases: Primary \\*alias\\*, Docs \\| Notes. Unknown: {{owner}}.''',
    );
  });

  test('reads string and list aliases from note frontmatter', () {
    expect(
      workspaceNoteTemplateAliases('''---
aliases:
  - Primary name
  - "Short name"
---
Body'''),
      ['Primary name', 'Short name'],
    );
    expect(
      workspaceNoteTemplateAliases('''---
alias: One name
---
Body'''),
      ['One name'],
    );
  });

  test('expands known tokens in Markdown when there is no frontmatter', () {
    expect(
      expandWorkspaceNoteTemplate(
        template: '{{date}} — {{title}} — {{aliases}} — {{unknown}}',
        localDate: DateTime(2026, 3, 4),
        title: 'A [title]',
        aliases: const [],
      ),
      r'2026-03-04 — A \[title\] —  — {{unknown}}',
    );
  });
}
