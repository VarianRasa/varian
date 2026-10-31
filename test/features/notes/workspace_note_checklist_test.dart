import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note_checklist.dart';

void main() {
  test('finds Markdown tasks outside frontmatter and fenced code', () {
    const markdown = '''---
example: "- [ ] frontmatter"
---
- [ ] Open
- [x] Done
```text
- [ ] Example
```
1. [X] Third''';

    final tasks = parseWorkspaceTaskCheckboxes(markdown);

    expect(tasks.map((task) => task.checked), [false, true, true]);
    expect(tasks.map((task) => task.markerStart), [
      markdown.indexOf('[ ] Open'),
      markdown.indexOf('[x] Done'),
      markdown.indexOf('[X] Third'),
    ]);
  });

  test('toggles only the selected task marker and preserves source bytes', () {
    const markdown = 'before\r\n- [ ] Keep  spaces\r\n- [x] Finished\r\n';
    final markerStart = markdown.indexOf('[ ]');

    expect(
      toggleWorkspaceTaskCheckbox(markdown, markerStart),
      'before\r\n- [x] Keep  spaces\r\n- [x] Finished\r\n',
    );
    expect(toggleWorkspaceTaskCheckbox(markdown, 0), isNull);
  });

  test('renders task markers as internal interactive checkbox links', () {
    const markdown = '- [ ] review the source';
    final markerStart = markdown.indexOf('[ ]');

    expect(
      renderWorkspaceTaskCheckboxes(markdown),
      '- [☐](varian-task://toggle/$markerStart) review the source',
    );
  });
}
