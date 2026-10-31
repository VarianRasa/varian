import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/domain/workspace_notes_index.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class NotesGraphScreen extends ConsumerStatefulWidget {
  const NotesGraphScreen({super.key});
  @override
  ConsumerState<NotesGraphScreen> createState() => _NotesGraphScreenState();
}

class _NotesGraphScreenState extends ConsumerState<NotesGraphScreen> {
  bool includeUnlinked = true;
  String? focusId;
  String? tag;

  Future<void> _openNote(String noteId) async {
    final state = ref.read(workspaceNotesProvider);
    final accountId = state.accountId;
    if (accountId == null) return;
    final note = state.notes
        .where((item) => item.id == noteId && item.deletedAt == null)
        .firstOrNull;
    if (note == null ||
        (note.projectId == null && note.ownerUserId != accountId)) {
      return;
    }
    await ref
        .read(activeDocumentTabControllerProvider)
        .select(OpenDocumentTab.note(note));
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return;
    }
    context.go('/notes/${Uri.encodeComponent(note.id)}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceNotesProvider);
    final activeNotes = state.notes
        .where((note) => note.deletedAt == null)
        .toList(growable: false);
    final index = WorkspaceNotesIndex(activeNotes);
    final activeFocusId = activeNotes.any((note) => note.id == focusId)
        ? focusId
        : null;
    final activeTag = index.tags.contains(tag) ? tag : null;
    final graph = index.graph(
      focusNoteId: activeFocusId,
      selectedTags: activeTag == null ? const {} : {activeTag},
      includeUnlinked: includeUnlinked,
      limit: 500,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge Graph'),
        actions: [
          TextButton(
            onPressed: () => context.go('/notes'),
            child: const Text('Notes'),
          ),
        ],
      ),
      body: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String?>(
                value: activeTag,
                hint: const Text('All tags'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All tags')),
                  ...index.tags.map(
                    (t) => DropdownMenuItem(value: t, child: Text(t)),
                  ),
                ],
                onChanged: (v) => setState(() => tag = v),
              ),
              DropdownButton<String?>(
                value: activeFocusId,
                hint: const Text('All notes'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All notes')),
                  ...activeNotes.map(
                    (n) => DropdownMenuItem(value: n.id, child: Text(n.title)),
                  ),
                ],
                onChanged: (v) => setState(() => focusId = v),
              ),
              FilterChip(
                label: const Text('Include unlinked'),
                selected: includeUnlinked,
                onSelected: (v) => setState(() => includeUnlinked = v),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Showing ${graph.nodes.length} of ${graph.totalNodeCount} notes${graph.isCapped ? ' (500 node limit)' : ''}',
              key: const ValueKey('graph-count'),
            ),
          ),
          Expanded(
            child: graph.nodes.isEmpty
                ? const Center(child: Text('No notes to graph'))
                : _GraphCanvas(
                    graph: graph,
                    focusedId: activeFocusId,
                    onSelect: _openNote,
                  ),
          ),
        ],
      ),
    );
  }
}

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.graph,
    required this.focusedId,
    required this.onSelect,
  });

  final WorkspaceNotesGraph graph;
  final String? focusedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, 720.0);
        final height = math.max(constraints.maxHeight, 520.0);
        final center = Offset(width / 2, height / 2);
        final radius = math.min(width, height) * 0.43;
        final focusIndex = graph.nodes.indexWhere(
          (note) => note.id == focusedId,
        );
        final positions = <String, Offset>{};
        var orbitIndex = 0;
        final orbitCount = math.max(
          graph.nodes.length - (focusIndex >= 0 ? 1 : 0),
          1,
        );
        for (var index = 0; index < graph.nodes.length; index++) {
          final note = graph.nodes[index];
          if (index == focusIndex) {
            positions[note.id] = center;
            continue;
          }
          final angle = orbitIndex * math.pi * (3 - math.sqrt(5));
          final distance = radius * math.sqrt((orbitIndex + 1) / orbitCount);
          positions[note.id] = Offset(
            center.dx + math.cos(angle) * distance,
            center.dy + math.sin(angle) * distance,
          );
          orbitIndex++;
        }
        final colors = Theme.of(context).colorScheme;
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 2.5,
          constrained: false,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(width, height),
                  painter: _GraphEdgesPainter(
                    positions: positions,
                    edges: graph.edges,
                    color: colors.outlineVariant,
                  ),
                ),
                for (final note in graph.nodes)
                  Positioned(
                    left: positions[note.id]!.dx - 18,
                    top: positions[note.id]!.dy - 18,
                    child: Tooltip(
                      message: note.title,
                      child: IconButton(
                        key: ValueKey('graph-node-${note.id}'),
                        tooltip: note.title,
                        onPressed: () => onSelect(note.id),
                        style: IconButton.styleFrom(
                          backgroundColor: note.id == focusedId
                              ? colors.primaryContainer
                              : colors.surfaceContainerHigh,
                          fixedSize: const Size(36, 36),
                        ),
                        icon: Icon(
                          Icons.circle,
                          size: note.id == focusedId ? 16 : 10,
                          color: note.id == focusedId
                              ? colors.primary
                              : colors.tertiary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GraphEdgesPainter extends CustomPainter {
  const _GraphEdgesPainter({
    required this.positions,
    required this.edges,
    required this.color,
  });

  final Map<String, Offset> positions;
  final List<WorkspaceNotesGraphEdge> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      final from = positions[edge.sourceId];
      final to = positions[edge.targetId];
      if (from != null && to != null) canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.edges != edges ||
      oldDelegate.color != color;
}
