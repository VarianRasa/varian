import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/mermaid/presentation/mermaid_node_preview.dart';

const _maxInlineMathBytes = 4096;
const _maxBlockMathBytes = 16 * 1024;
final _blockMathDelimiter = RegExp(r'^ {0,3}\$\$\s*$');

class NotesInlineMathSyntax extends md.InlineSyntax {
  NotesInlineMathSyntax()
    : super(r'\$(?!\$)([^$\n]+)\$(?!\$)', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = match[1]!;
    if (utf8.encode(expression).length > _maxInlineMathBytes) {
      parser.advanceBy(match[0]!.length);
      return false;
    }
    final element = md.Element('notes-inline-math', [md.Text(expression)])
      ..attributes['source'] = match[0]!;
    parser.addNode(element);
    return true;
  }
}

class NotesBlockMathSyntax extends md.BlockSyntax {
  const NotesBlockMathSyntax();

  @override
  RegExp get pattern => _blockMathDelimiter;

  @override
  bool canParse(md.BlockParser parser) {
    if (!pattern.hasMatch(parser.current.content)) return false;
    var sourceBytes = 0;
    var sourceLines = 0;
    for (var ahead = 1; ; ahead++) {
      final line = parser.peek(ahead);
      if (line == null) return false;
      if (pattern.hasMatch(line.content)) {
        return sourceBytes <= _maxBlockMathBytes && sourceLines <= 512;
      }
      sourceBytes += utf8.encode(line.content).length + 1;
      sourceLines++;
      if (sourceBytes > _maxBlockMathBytes || sourceLines > 512) return false;
    }
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];
    while (!parser.isDone && !pattern.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }
    if (parser.isDone) return null;
    parser.advance();
    final expression = lines.join('\n');
    final element = md.Element('notes-block-math', [md.Text(expression)])
      ..attributes['source'] = '\$\$\n$expression\n\$\$';
    return element;
  }
}

class NotesMathElementBuilder extends MarkdownElementBuilder {
  NotesMathElementBuilder.inline() : _display = false;
  NotesMathElementBuilder.block() : _display = true;

  final bool _display;

  @override
  bool isBlockElement() => _display;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression = element.textContent;
    final source = element.attributes['source'] ?? expression;
    return Math.tex(
      expression,
      mathStyle: _display ? MathStyle.display : MathStyle.text,
      textStyle: parentStyle ?? preferredStyle,
      onErrorFallback: (_) => Text(source),
    );
  }
}

class NotesMermaidCodeBlockBuilder extends MarkdownElementBuilder {
  NotesMermaidCodeBlockBuilder();

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    if (code?.attributes['class']?.toLowerCase() != 'language-mermaid') {
      return null;
    }
    return NotesMermaidBlockPreview(source: code!.textContent);
  }
}

class NotesMermaidBlockPreview extends StatefulWidget {
  const NotesMermaidBlockPreview({required this.source, super.key});

  final String source;

  @override
  State<NotesMermaidBlockPreview> createState() =>
      _NotesMermaidBlockPreviewState();
}

class _NotesMermaidBlockPreviewState extends State<NotesMermaidBlockPreview> {
  bool _renderFailed = false;

  @override
  Widget build(BuildContext context) {
    final sourceError = MermaidSourceLimits.validate(widget.source);
    if (_renderFailed || sourceError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sourceError?.message ??
                'Mermaid preview failed. Source is preserved:',
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(child: SelectableText(widget.source)),
          ),
        ],
      );
    }
    return SizedBox(
      height: 220,
      child: MermaidNodePreview(
        payload: MermaidPayload(source: widget.source),
        onRenderStateChanged: (payload) {
          if (payload.cachedSvg == null && mounted) {
            setState(() => _renderFailed = true);
          }
        },
      ),
    );
  }
}

final notesMarkdownElementBuilders = <String, MarkdownElementBuilder>{
  'notes-inline-math': NotesMathElementBuilder.inline(),
  'notes-block-math': NotesMathElementBuilder.block(),
  'pre': NotesMermaidCodeBlockBuilder(),
};
