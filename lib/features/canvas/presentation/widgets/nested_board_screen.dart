import 'package:flutter/material.dart';

import '../../../../domain/models/node.dart';
import 'nested_board_editor_host.dart';

/// Compatibility route for callers that still construct the old nested screen.
/// The actual editor is hosted by [NestedBoardEditorHost] so all nested boards
/// use the same canvas implementation as the root canvas.
class NestedBoardScreen extends StatelessWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onSave;
  final ValueChanged<CanvasNode>? onSaveAndExit;

  const NestedBoardScreen({
    required this.node,
    required this.onSave,
    this.onSaveAndExit,
    super.key,
  });

  static Future<void> show(
    BuildContext context, {
    required CanvasNode node,
    required ValueChanged<CanvasNode> onUpdate,
  }) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => NestedBoardEditorHost(node: node, onSave: onUpdate),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      NestedBoardEditorHost(node: node, onSave: onSave);
}
