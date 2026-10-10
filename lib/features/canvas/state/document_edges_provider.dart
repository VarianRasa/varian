import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/connector_edge.dart';

final documentEdgesProvider =
    StateNotifierProvider<DocumentEdgesNotifier, List<CanvasEdge>>((ref) {
      return DocumentEdgesNotifier();
    });

class DocumentEdgesNotifier extends StateNotifier<List<CanvasEdge>> {
  DocumentEdgesNotifier() : super([]);

  void setEdges(List<CanvasEdge> edges) {
    state = edges;
  }

  void addEdge(CanvasEdge edge) {
    state = [...state, edge];
  }

  void removeEdge(String id) {
    removeEdges([id]);
  }

  void removeEdges(Iterable<String> ids) {
    final idsToRemove = ids.toSet();
    if (idsToRemove.isEmpty) return;
    state = state.where((edge) => !idsToRemove.contains(edge.id)).toList();
  }

  void removeEdgesConnectedTo(String nodeId) {
    state = state
        .where((e) => e.sourceNodeId != nodeId && e.targetNodeId != nodeId)
        .toList();
  }

  void updateEdge(CanvasEdge updated) {
    state = [
      for (final edge in state)
        if (edge.id == updated.id) updated else edge,
    ];
  }
}
