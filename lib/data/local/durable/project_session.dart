import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/document.dart';
import '../../artifacts/artifact_store_bundle.dart';
import '../../artifacts/transient_artifact_hydrator.dart';
import '../../remote/supabase_sync_provider.dart';
import '../../../features/canvas/domain/canvas_navigation.dart';
import 'durable_project_store.dart';

final durableProjectStoreProvider = Provider<DurableProjectStore>((ref) {
  final store = DurableProjectStore();
  ref.onDispose(() => unawaited(store.close()));
  return store;
});

// Project sessions are held by long-lived controllers and services through
// ref.read. Keep the family container-owned instead of auto-disposing it after
// the read-only access frame; those owners fence their own project lifecycle.
// Project sessions are lightweight project-scoped handles over the
// container-owned durable store. They remain alive until the container is
// disposed so in-flight autosave operations cannot be invalidated by a
// transient route/widget read.
final projectSessionProvider = Provider.family<ProjectSession, String>((
  ref,
  projectId,
) {
  final sync = ref.watch(supabaseSyncServiceProvider);
  final artifactStores = ref.watch(artifactStoreBundleProvider);
  final session = ProjectSession(
    projectId: projectId,
    store: ref.watch(durableProjectStoreProvider),
    artifactHydrator: TransientArtifactHydrator(
      imageArtifactStore: artifactStores.imageArtifactStore,
      fileArtifactStore: artifactStores.fileArtifactStore,
      mediaArtifactStore: artifactStores.mediaArtifactStore,
      videoArtifactStore: artifactStores.videoArtifactStore,
      model3DArtifactStore: artifactStores.model3DArtifactStore,
      storageByteReader: sync.readPrivateStorageBytes,
    ),
    accountIdReader: () => sync.currentUserId,
  );
  ref.onDispose(session.dispose);
  return session;
});

final class ProjectSession {
  ProjectSession({
    required this.projectId,
    required this.store,
    TransientArtifactHydrator? artifactHydrator,
    ArtifactStoreBundle? artifactStoreBundle,
    this.accountIdReader,
  }) : artifactHydrator =
           artifactHydrator ??
           TransientArtifactHydrator(
             imageArtifactStore: artifactStoreBundle?.imageArtifactStore,
             fileArtifactStore: artifactStoreBundle?.fileArtifactStore,
             mediaArtifactStore: artifactStoreBundle?.mediaArtifactStore,
             videoArtifactStore: artifactStoreBundle?.videoArtifactStore,
             model3DArtifactStore: artifactStoreBundle?.model3DArtifactStore,
           ) {
    if (projectId.trim().isEmpty || projectId != projectId.trim()) {
      throw ArgumentError.value(projectId, 'projectId');
    }
  }

  final String projectId;
  final DurableProjectStore store;
  final TransientArtifactHydrator artifactHydrator;
  final String? Function()? accountIdReader;
  int _generation = 0;
  bool _disposed = false;

  int get generation => _generation;
  bool get isDisposed => _disposed;

  Future<CanvasDocument?> loadDocument() async {
    _ensureActive();
    final generation = _generation;
    final document = await store.loadCanvasDocument(projectId);
    if (!_isCurrent(generation) || document == null) return null;
    final hydrated = await artifactHydrator.hydrate(
      document,
      projectId: projectId,
      accountId: accountIdReader?.call(),
    );
    if (!_isCurrent(generation)) return null;
    return hydrated;
  }

  Future<void> saveDocument(
    CanvasDocument document, {
    CanvasNavigationState? navigation,
  }) async {
    _ensureActive();
    if (document.projectId != projectId) {
      throw StateError(
        'Project session $projectId rejected document ${document.projectId}.',
      );
    }
    final generation = _generation;
    await store.saveCanvasDocument(document, navigation: navigation);
    if (!_isCurrent(generation)) {
      throw StateError('Project session changed while saving $projectId.');
    }
  }

  Future<String?> loadRecoveryPayload() async {
    _ensureActive();
    return store.readRecovery(projectId);
  }

  void switchGeneration() {
    _ensureActive();
    _generation++;
  }

  void dispose() {
    _generation++;
    _disposed = true;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _ensureActive() {
    if (_disposed) {
      throw StateError('Project session $projectId is disposed.');
    }
  }
}
