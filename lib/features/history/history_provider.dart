import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/features/history/snapshot_manager.dart';
import 'package:varian/features/canvas/commands/command_replay.dart';

class NodeHistoryEntry {
  final DateTime timestamp;
  final CanvasNode snapshot;

  const NodeHistoryEntry({required this.timestamp, required this.snapshot});
}

class NodeHistoryState {
  final Map<String, List<NodeHistoryEntry>> entriesByNodeId;

  const NodeHistoryState({this.entriesByNodeId = const {}});

  NodeHistoryState copyWith({
    Map<String, List<NodeHistoryEntry>>? entriesByNodeId,
  }) {
    return NodeHistoryState(
      entriesByNodeId: entriesByNodeId ?? this.entriesByNodeId,
    );
  }
}

final nodeHistoryProvider =
    StateNotifierProvider<NodeHistoryNotifier, NodeHistoryState>((ref) {
      return NodeHistoryNotifier();
    });

class NodeHistoryNotifier extends StateNotifier<NodeHistoryState> {
  static const int _maxEntriesPerNode = 50;

  NodeHistoryNotifier() : super(const NodeHistoryState());

  void recordSnapshot(CanvasNode node) {
    final map = Map<String, List<NodeHistoryEntry>>.from(state.entriesByNodeId);
    final list = List<NodeHistoryEntry>.from(map[node.id] ?? const []);
    list.add(
      NodeHistoryEntry(
        timestamp: DateTime.now(),
        snapshot: node.copyWith(payload: node.payload.clone()),
      ),
    );
    if (list.length > _maxEntriesPerNode) {
      list.removeAt(0);
    }
    map[node.id] = list;
    state = NodeHistoryState(entriesByNodeId: map);
  }

  List<NodeHistoryEntry> historyFor(String nodeId) {
    return state.entriesByNodeId[nodeId] ?? const [];
  }

  void clearNode(String nodeId) {
    final map = Map<String, List<NodeHistoryEntry>>.from(state.entriesByNodeId);
    map.remove(nodeId);
    state = NodeHistoryState(entriesByNodeId: map);
  }

  void clear() {
    state = const NodeHistoryState();
  }
}

class BoardHistoryState {
  final List<DocumentSnapshotRecord> snapshots;

  const BoardHistoryState({this.snapshots = const []});

  BoardHistoryState copyWith({List<DocumentSnapshotRecord>? snapshots}) {
    return BoardHistoryState(snapshots: snapshots ?? this.snapshots);
  }
}

final boardHistoryProvider =
    StateNotifierProvider<BoardHistoryNotifier, BoardHistoryState>((ref) {
      return BoardHistoryNotifier();
    });

class BoardHistoryNotifier extends StateNotifier<BoardHistoryState> {
  static const int _maxSnapshots = 20;

  BoardHistoryNotifier() : super(const BoardHistoryState());

  List<DocumentSnapshotRecord> get snapshots => state.snapshots;

  void addSnapshot(CanvasDocument document, {String? description}) {
    final list = List<DocumentSnapshotRecord>.from(state.snapshots);
    list.add(
      DocumentSnapshotRecord(
        id: 'snap_${DateTime.now().microsecondsSinceEpoch}',
        description: description ?? 'Autosave snapshot',
        timestamp: DateTime.now(),
        document: document,
      ),
    );
    if (list.length > _maxSnapshots) {
      list.removeAt(0);
    }
    state = BoardHistoryState(snapshots: list);
  }

  void clear() {
    state = const BoardHistoryState();
  }
}

final persistedVersionsProvider =
    StateNotifierProvider.family<
      PersistedVersionsNotifier,
      AsyncValue<List<DocumentSnapshotRecord>>,
      String
    >((ref, projectId) {
      return PersistedVersionsNotifier(
        LocalStorageService(),
        projectId,
        ref.watch(durableProjectStoreProvider),
      );
    });

final persistedAutoCheckpointsProvider =
    StateNotifierProvider.family<
      PersistedAutoCheckpointsNotifier,
      AsyncValue<List<DocumentSnapshotRecord>>,
      String
    >((ref, projectId) {
      return PersistedAutoCheckpointsNotifier(
        LocalStorageService(),
        projectId,
        ref.watch(durableProjectStoreProvider),
      );
    });

class PersistedVersionsNotifier
    extends StateNotifier<AsyncValue<List<DocumentSnapshotRecord>>> {
  final LocalStorageService _storage;
  final String projectId;
  final DurableProjectStore _durableStore;

  PersistedVersionsNotifier(this._storage, this.projectId, this._durableStore)
    : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final durable = await _durableStore.loadHistory(projectId);
      state = AsyncValue.data(
        durable.isNotEmpty ? durable : await _storage.loadVersions(projectId),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<DocumentSnapshotRecord> save(
    CanvasDocument document, {
    required String description,
    CommandReplayLog? commandReplay,
  }) async {
    final current = await _durableStore.loadHistory(projectId);
    final record = DocumentSnapshotRecord(
      id: 'version_${DateTime.now().microsecondsSinceEpoch}',
      description: description.trim(),
      timestamp: DateTime.now(),
      document: document.copyWith(projectId: projectId),
      commandReplay: commandReplay,
    );
    final bounded = [...current, record];
    if (bounded.length > LocalStorageService.maxVersions) {
      bounded.removeRange(0, bounded.length - LocalStorageService.maxVersions);
    }
    await _durableStore.saveHistory(projectId, bounded);
    await load();
    return record;
  }

  Future<void> delete(String versionId) async {
    final remaining = (await _durableStore.loadHistory(
      projectId,
    )).where((version) => version.id != versionId).toList(growable: false);
    if (remaining.isEmpty) {
      await _durableStore.clearHistory(projectId);
    } else {
      await _durableStore.saveHistory(projectId, remaining);
    }
    await load();
  }
}

class PersistedAutoCheckpointsNotifier
    extends StateNotifier<AsyncValue<List<DocumentSnapshotRecord>>> {
  final LocalStorageService _storage;
  final String projectId;
  final DurableProjectStore _durableStore;

  PersistedAutoCheckpointsNotifier(
    this._storage,
    this.projectId,
    this._durableStore,
  ) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final durable = await _durableStore.loadAutoCheckpoints(projectId);
      state = AsyncValue.data(
        durable.isNotEmpty
            ? durable
            : await _storage.loadAutoCheckpoints(projectId),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<DocumentSnapshotRecord?> save(
    CanvasDocument document, {
    CommandReplayLog? commandReplay,
  }) async {
    final current = await _durableStore.loadAutoCheckpoints(projectId);
    final candidate = DocumentSnapshotRecord(
      id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
      description: 'Autosave checkpoint',
      timestamp: DateTime.now(),
      document: document.copyWith(projectId: projectId),
      commandReplay: commandReplay,
    );
    final record =
        current.isNotEmpty &&
            current.last.document.toPersistenceJson().toString() ==
                candidate.document.toPersistenceJson().toString()
        ? null
        : candidate;
    if (record != null) {
      final bounded = [...current, record];
      if (bounded.length > LocalStorageService.maxVersions) {
        bounded.removeRange(
          0,
          bounded.length - LocalStorageService.maxVersions,
        );
      }
      await _durableStore.saveAutoCheckpoints(projectId, bounded);
    }
    await load();
    return record;
  }

  Future<void> clear() async {
    await _durableStore.clearAutoCheckpoints(projectId);
    await load();
  }
}
