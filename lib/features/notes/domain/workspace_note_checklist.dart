import 'note_markdown_metadata.dart';
import 'workspace_note_links.dart';

class WorkspaceTaskCheckbox {
  const WorkspaceTaskCheckbox({
    required this.markerStart,
    required this.checked,
  });

  final int markerStart;
  final bool checked;
}

List<WorkspaceTaskCheckbox> parseWorkspaceTaskCheckboxes(String markdown) {
  final metadata = parseNoteMarkdownMetadata(markdown);
  final bodyOffset = markdown.length - metadata.body.length;
  final codeMask = workspaceMarkdownCodeContextMask(markdown);
  final tasks = <WorkspaceTaskCheckbox>[];
  final taskPattern = RegExp(r'^ {0,3}(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\]');
  var lineOffset = bodyOffset;
  for (final rawLine in metadata.body.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    final match = taskPattern.firstMatch(line);
    final hasTaskTextSeparator =
        match != null &&
        (match.end == line.length ||
            line[match.end] == ' ' ||
            line[match.end] == '\t');
    if (match != null && hasTaskTextSeparator) {
      final markerStart =
          lineOffset + match.start + match.group(0)!.indexOf('[');
      final markerEnd = markerStart + 3;
      if (!codeMask
          .skip(markerStart)
          .take(markerEnd - markerStart)
          .any((isCode) => isCode)) {
        tasks.add(
          WorkspaceTaskCheckbox(
            markerStart: markerStart,
            checked: match.group(1)!.toLowerCase() == 'x',
          ),
        );
      }
    }
    lineOffset += rawLine.length + 1;
  }
  return List.unmodifiable(tasks);
}

String? toggleWorkspaceTaskCheckbox(String markdown, int markerStart) {
  final task = parseWorkspaceTaskCheckboxes(
    markdown,
  ).where((candidate) => candidate.markerStart == markerStart).firstOrNull;
  if (task == null) return null;
  return markdown.replaceRange(
    markerStart + 1,
    markerStart + 2,
    task.checked ? ' ' : 'x',
  );
}

String renderWorkspaceTaskCheckboxes(String markdown) {
  final tasks = parseWorkspaceTaskCheckboxes(markdown);
  var rendered = markdown;
  for (final task in tasks.reversed) {
    final icon = task.checked ? '☑' : '☐';
    rendered = rendered.replaceRange(
      task.markerStart,
      task.markerStart + 3,
      '[$icon](varian-task://toggle/${task.markerStart})',
    );
  }
  return rendered;
}
