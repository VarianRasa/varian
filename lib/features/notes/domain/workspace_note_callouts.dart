import 'note_markdown_metadata.dart';
import 'workspace_note_links.dart';

final _calloutHeader = RegExp(
  r'^ {0,3}(>[ \t]*)\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-])?(?:[ \t]+(.*))?[ \t]*$',
);
final _blockquoteLine = RegExp(r'^ {0,3}>');

String renderWorkspaceCallouts(
  String markdown, {
  Map<int, bool> collapsedCallouts = const {},
}) {
  final lines = markdown.split('\n');
  final lineOffsets = <int>[];
  var offset = 0;
  for (final line in lines) {
    lineOffsets.add(offset);
    offset += line.length + 1;
  }
  final metadata = parseNoteMarkdownMetadata(markdown);
  final bodyOffset = markdown.length - metadata.body.length;
  final codeMask = workspaceMarkdownCodeContextMask(markdown);
  final renderedLines = <String>[];
  var lineIndex = 0;

  while (lineIndex < lines.length) {
    final rawLine = lines[lineIndex];
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    final lineOffset = lineOffsets[lineIndex];
    final match = _calloutHeader.firstMatch(line);
    final isCode = codeMask
        .skip(lineOffset)
        .take(line.length)
        .any((isCode) => isCode);
    if (lineOffset < bodyOffset || match == null || isCode) {
      renderedLines.add(rawLine);
      lineIndex++;
      continue;
    }

    final collapsed = collapsedCallouts[lineOffset] ?? match.group(3) == '-';
    final type = match.group(2)!.toUpperCase();
    final label = '$type ${collapsed ? '▸' : '▾'}';
    final title = match.group(4)?.trim();
    final carriageReturn = rawLine.endsWith('\r') ? '\r' : '';
    renderedLines.add(
      '${match.group(1)}[$label](varian-callout://toggle/$lineOffset/${collapsed ? 1 : 0})'
      '${title == null || title.isEmpty ? '' : ' $title'}$carriageReturn',
    );

    if (collapsed) {
      var nextLine = lineIndex + 1;
      while (nextLine < lines.length) {
        final continuation = lines[nextLine].endsWith('\r')
            ? lines[nextLine].substring(0, lines[nextLine].length - 1)
            : lines[nextLine];
        if (!_blockquoteLine.hasMatch(continuation)) break;
        nextLine++;
      }
      if (nextLine > lineIndex + 1) {
        renderedLines.add('${match.group(1)}…$carriageReturn');
        lineIndex = nextLine;
        continue;
      }
    }

    lineIndex++;
  }

  return renderedLines.join('\n');
}
