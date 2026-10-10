import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/local_storage_service.dart';
import '../domain/semantic_index.dart';

final semanticIndexProvider =
    StateNotifierProvider.family<
      SemanticIndexNotifier,
      AsyncValue<SemanticIndex>,
      String
    >(
      (ref, projectId) =>
          SemanticIndexNotifier(LocalStorageService(), projectId),
    );

class SemanticIndexNotifier extends StateNotifier<AsyncValue<SemanticIndex>> {
  final LocalStorageService _storage;
  final String projectId;
  late final Future<void> ready;

  SemanticIndexNotifier(this._storage, this.projectId)
    : super(const AsyncValue.loading()) {
    ready = load();
  }

  Future<void> load() async {
    try {
      state = AsyncValue.data(await _storage.loadSemanticIndex(projectId));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> upsert(SemanticIndexRecord record) async {
    await _update((index) => index.upsert(record));
  }

  Future<void> upsertAll(Iterable<SemanticIndexRecord> records) async {
    await _update((index) => index.upsertAll(records));
  }

  Future<void> remove({required String id, SemanticRecordKind? kind}) async {
    await _update((index) => index.remove(id: id, kind: kind));
  }

  Future<void> replaceAll(Iterable<SemanticIndexRecord> records) async {
    await _update((index) => index.replaceAll(records));
  }

  List<SemanticSearchHit> search(
    String query, {
    SemanticRecordKind? kind,
    int limit = 20,
  }) => state.asData?.value.search(query, kind: kind, limit: limit) ?? const [];

  Future<void> _update(
    SemanticIndex Function(SemanticIndex index) mutate,
  ) async {
    final current = state.asData?.value;
    if (current == null) return;
    final next = mutate(current);
    if (next.toJson().toString() == current.toJson().toString()) return;
    await _storage.saveSemanticIndex(next);
    if (mounted) state = AsyncValue.data(next);
  }
}
