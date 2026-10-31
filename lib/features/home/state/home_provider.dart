import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/workspace_timestamp.dart';
import 'package:uuid/uuid.dart';
import '../../../data/local/account_scoped_local_storage.dart';
import '../../../data/local/durable/project_session.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../domain/models/document.dart';
import '../../canvas/state/autosave_controller.dart';
import '../../canvas/state/open_document_tabs_provider.dart';

final homeProjectsProvider =
    StateNotifierProvider<
      HomeProjectsNotifier,
      AsyncValue<List<LocalProjectMetadata>>
    >(
      (ref) => HomeProjectsNotifier(
        ref,
        ref.read(localStorageServiceProvider),
        ref.read(openDocumentTabsProvider.notifier),
      ),
    );

final homeProjectStatusProvider = StateProvider<ProjectStatus>(
  (ref) => ProjectStatus.active,
);

final homeProjectAdoptionEligibilityProvider =
    FutureProvider.family<bool, String>((ref, projectId) async {
      final projects = ref.watch(homeProjectsProvider).asData?.value;
      final project = projects
          ?.where((candidate) => candidate.id == projectId)
          .firstOrNull;
      if (project == null ||
          project.cloudDeletionDetached ||
          project.cloudOwnerId != null ||
          project.isCollaborationRoom ||
          project.status == ProjectStatus.trashed) {
        return false;
      }
      return !await ref
          .read(localStorageServiceProvider)
          .requiresAccountScopedCollaborationRejoin(projectId);
    });

class HomeProjectsNotifier
    extends StateNotifier<AsyncValue<List<LocalProjectMetadata>>> {
  final Ref _ref;
  final LocalStorageService _storageService;
  final OpenDocumentTabsNotifier _openDocumentTabs;

  HomeProjectsNotifier(this._ref, this._storageService, this._openDocumentTabs)
    : super(const AsyncValue.loading());

  Future<void> loadProjects() async {
    try {
      var list = await _storageService.getProjects();
      final accountId = _currentAccountId();
      if (accountId != null) {
        try {
          list = await _syncCloudProjectCatalog(list, accountId);
        } catch (error) {
          debugPrint('[HomeProjects] Cloud catalog sync failed: $error');
        }
      }
      // Cloud reconciliation may outlive this initial snapshot. Publish the
      // latest durable local state, including edits made during the fetch.
      list = await _storageService.getProjects();
      final currentAccountId = _currentAccountId();
      list = list
          .where(
            (project) =>
                project.cloudOwnerId == null ||
                project.cloudOwnerId == currentAccountId,
          )
          .toList();
      list = await _renameLegacyUntitledProjects(list, currentAccountId);
      if (_currentAccountId() != currentAccountId) {
        list = await _storageService.getProjects();
        final nowCurrentAccountId = _currentAccountId();
        list = list
            .where(
              (project) =>
                  project.cloudOwnerId == null ||
                  project.cloudOwnerId == nowCurrentAccountId,
            )
            .toList();
      }
      list.sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<LocalProjectMetadata> adoptProjectToCloud(
    String projectId, {
    required String expectedAccountId,
  }) async {
    final accountId = expectedAccountId.trim();
    if (accountId.isEmpty || !_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    final projects = await _storageService.getProjects();
    final project = projects.where((item) => item.id == projectId).firstOrNull;
    if (project == null) throw StateError('Project not found: $projectId');
    if (project.cloudDeletionDetached ||
        (project.cloudOwnerId != null &&
            !(project.cloudOwnerId == accountId &&
                project.cloudMetadataSyncPending)) ||
        project.isCollaborationRoom ||
        project.status == ProjectStatus.trashed ||
        await _storageService.requiresAccountScopedCollaborationRejoin(
          projectId,
        )) {
      throw const SyncException('This project is not eligible for adoption.');
    }
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    final document =
        await _ref.read(projectSessionProvider(projectId)).loadDocument() ??
        await _storageService.loadDocument(projectId);
    if (document == null || document.projectId != projectId) {
      throw const SyncException(
        'A valid local document is required before adoption.',
      );
    }
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    final marked = await _storageService.markCloudAdoptionPending(
      projectId: projectId,
      expectedAccountId: accountId,
      shouldWrite: () => _isAdoptionAccountCurrent(accountId),
    );
    if (!marked) {
      if (!_isAdoptionAccountCurrent(accountId)) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }
      throw const SyncException('This project is not eligible for adoption.');
    }

    final adopted = await _completeExplicitCloudAdoption(
      projectId: projectId,
      accountId: accountId,
      document: document,
    );
    await loadProjects();
    return adopted;
  }

  Future<LocalProjectMetadata> _completeExplicitCloudAdoption({
    required String projectId,
    required String accountId,
    CanvasDocument? document,
  }) async {
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    final project = (await _storageService.getProjects())
        .where((item) => item.id == projectId)
        .firstOrNull;
    if (project == null ||
        project.cloudDeletionDetached ||
        project.cloudAdoptionPendingAccountId != accountId ||
        project.isCollaborationRoom ||
        project.status == ProjectStatus.trashed ||
        (project.cloudOwnerId != null && project.cloudOwnerId != accountId)) {
      throw const SyncException('This project is not eligible for adoption.');
    }
    final localDocument =
        document ??
        await _ref.read(projectSessionProvider(projectId)).loadDocument() ??
        await _storageService.loadDocument(projectId);
    if (localDocument == null || localDocument.projectId != projectId) {
      throw const SyncException(
        'A valid local document is required before adoption.',
      );
    }
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    final sync = _ref.read(supabaseSyncServiceProvider);
    try {
      await sync.adoptDocumentSnapshot(
        localDocument,
        expectedUserId: accountId,
      );
    } catch (_) {
      // Snapshot adoption may have committed before its response was lost.
      // Retry content-aware adoption so a different cloud snapshot still fails closed.
      if (!_isAdoptionAccountCurrent(accountId)) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }
      await sync.adoptDocumentSnapshot(
        localDocument,
        expectedUserId: accountId,
      );
    }
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await sync.verifyProjectOwnership(projectId, expectedUserId: accountId);
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    var latestProject = (await _storageService.getProjects())
        .where((item) => item.id == projectId)
        .firstOrNull;
    LocalProjectMetadata? adopted;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_isAdoptionAccountCurrent(accountId)) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }
      if (latestProject == null ||
          latestProject.cloudDeletionDetached ||
          latestProject.cloudAdoptionPendingAccountId != accountId ||
          latestProject.isCollaborationRoom ||
          latestProject.status == ProjectStatus.trashed ||
          (latestProject.cloudOwnerId != null &&
              latestProject.cloudOwnerId != accountId)) {
        throw const SyncException('This project is not eligible for adoption.');
      }

      // Adoption owns only these cloud fields. Use a revision CAS so local
      // rename, pin, archive, or restore edits made during cloud work survive.
      final candidate = latestProject.copyWith(
        cloudOwnerId: accountId,
        cloudUpdatedAt: localDocument.updatedAt.toUtc(),
        cloudMetadataSyncPending: true,
      );
      final saved = await _storageService
          .saveProjectMetadataIfRevisionUnchanged(
            candidate,
            expectedRevision: latestProject.localMetadataRevision,
            shouldWrite: () => _isAdoptionAccountCurrent(accountId),
          );
      if (saved) {
        adopted = candidate;
        break;
      }

      // A conflict is not proof of ownership. Re-read and revalidate the
      // explicit intent before merging only the adoption fields onto current
      // local metadata. The marker remains intact if this cannot be committed.
      latestProject = (await _storageService.getProjects())
          .where((item) => item.id == projectId)
          .firstOrNull;
    }
    if (adopted == null) {
      throw const SyncException(
        'Project metadata changed during adoption; retry after reviewing it.',
      );
    }
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await sync.verifyProjectOwnership(projectId, expectedUserId: accountId);
    await sync.syncProjectMetadata(adopted, expectedUserId: accountId);
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await sync.verifyProjectOwnership(projectId, expectedUserId: accountId);
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await _storageService.clearCloudMetadataSyncPendingIfUnchanged(
      adopted,
      expectedOwnerId: accountId,
      expectedAdoptionPendingAccountId: accountId,
      shouldWrite: () => _isAdoptionAccountCurrent(accountId),
    );
    return (await _storageService.getProjects())
            .where((item) => item.id == projectId)
            .firstOrNull ??
        adopted;
  }

  Future<List<LocalProjectMetadata>> _syncCloudProjectCatalog(
    List<LocalProjectMetadata> localProjects,
    String accountId,
  ) async {
    final sync = _ref.read(supabaseSyncServiceProvider);
    final snapshotRevisions = {
      for (final project in localProjects)
        project.id: project.localMetadataRevision,
    };
    final cloudProjects = await sync.fetchOwnedProjectMetadata(
      expectedUserId: accountId,
    );
    if (_currentAccountId() != accountId) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    final cloudById = {
      for (final project in cloudProjects) project.id: project,
    };
    final mergedProjects = <LocalProjectMetadata>[];

    for (final listedLocalProject in localProjects) {
      var localProject = (await _storageService.getProjects())
          .where((project) => project.id == listedLocalProject.id)
          .firstOrNull;
      if (localProject == null) continue;
      final cloudProject = cloudById.remove(localProject.id);
      final snapshotRevision = snapshotRevisions[localProject.id];
      if (snapshotRevision != null &&
          localProject.localMetadataRevision != snapshotRevision &&
          !localProject.cloudMetadataSyncPending &&
          localProject.cloudAdoptionPendingAccountId != accountId) {
        // A metadata write started after this catalog request. Keep the whole
        // newer record, including fields that do not live in the cloud catalog.
        mergedProjects.add(localProject);
        continue;
      }
      if (localProject.cloudAdoptionPendingAccountId == accountId) {
        try {
          final recovered = await _completeExplicitCloudAdoption(
            projectId: localProject.id,
            accountId: accountId,
          );
          cloudById.remove(localProject.id);
          mergedProjects.add(recovered);
        } catch (error) {
          if (error is SyncException &&
              error.message ==
                  'The cloud account changed during this action.') {
            rethrow;
          }
          final currentAfterFailure = (await _storageService.getProjects())
              .where((project) => project.id == localProject.id)
              .firstOrNull;
          if (currentAfterFailure != null) {
            mergedProjects.add(currentAfterFailure);
          }
        }
        continue;
      }
      if (localProject.isCollaborationRoom ||
          localProject.cloudOwnerId != accountId) {
        // Matching IDs do not prove that a local-only project was adopted.
        // Keep the local record authoritative until explicit adoption.
        mergedProjects.add(localProject);
        continue;
      }
      if (cloudProject == null) {
        mergedProjects.add(localProject);
        continue;
      }

      // Pending local metadata intent is independent of server/client clock
      // skew. Reconcile it only for this already owner-fenced project.
      if (localProject.cloudMetadataSyncPending) {
        final pending = localProject.copyWith(cloudOwnerId: accountId);
        if (_currentAccountId() != accountId) {
          throw const SyncException(
            'The cloud account changed during this action.',
          );
        }
        try {
          await sync.verifyProjectOwnership(
            pending.id,
            expectedUserId: accountId,
          );
          await sync.syncProjectMetadata(pending, expectedUserId: accountId);
          if (_currentAccountId() != accountId) {
            throw const SyncException(
              'The cloud account changed during this action.',
            );
          }
          await sync.verifyProjectOwnership(
            pending.id,
            expectedUserId: accountId,
          );
          await _storageService.clearCloudMetadataSyncPendingIfUnchanged(
            pending,
            expectedOwnerId: accountId,
          );
          final currentAfterSync = (await _storageService.getProjects())
              .where((project) => project.id == pending.id)
              .firstOrNull;
          cloudById.remove(pending.id);
          mergedProjects.add(
            currentAfterSync ??
                pending.copyWith(cloudMetadataSyncPending: false),
          );
          continue;
        } catch (error) {
          if (error is SyncException &&
              error.message ==
                  'The cloud account changed during this action.') {
            rethrow;
          }
          // The durable local intent remains queued and is retried at refresh.
          // Re-read after the network failure too, since another local edit may
          // have happened while ownership and metadata sync were in flight.
          final currentAfterFailure = (await _storageService.getProjects())
              .where((project) => project.id == pending.id)
              .firstOrNull;
          cloudById.remove(pending.id);
          if (currentAfterFailure != null) {
            mergedProjects.add(currentAfterFailure);
          }
          continue;
        }
      }

      final isLocallyTrashed = localProject.status == ProjectStatus.trashed;
      final cachedProject = cloudProject.copyWith(
        name: isLocallyTrashed ? localProject.name : cloudProject.name,
        updatedAt: isLocallyTrashed
            ? localProject.updatedAt
            : cloudProject.updatedAt,
        cloudMetadataSyncPending: false,
        isPinned: isLocallyTrashed
            ? localProject.isPinned
            : cloudProject.isPinned,
        status: isLocallyTrashed ? localProject.status : cloudProject.status,
        trashedAt: isLocallyTrashed
            ? localProject.trashedAt
            : cloudProject.trashedAt,
        clearTrashedAt: isLocallyTrashed && localProject.trashedAt == null,
        cloudOwnerId: accountId,
        cloudUpdatedAt: cloudProject.cloudUpdatedAt ?? cloudProject.updatedAt,
      );
      final written = await _storageService
          .saveProjectMetadataIfRevisionUnchanged(
            cachedProject,
            expectedRevision:
                snapshotRevision ?? localProject.localMetadataRevision,
            shouldWrite: () => _currentAccountId() == accountId,
          );
      if (!written) {
        final currentAfterConflict = (await _storageService.getProjects())
            .where((project) => project.id == localProject.id)
            .firstOrNull;
        if (currentAfterConflict != null) {
          mergedProjects.add(currentAfterConflict);
        }
        continue;
      }
      if (_currentAccountId() != accountId) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }
      mergedProjects.add(cachedProject);
    }

    for (final cloudProject in cloudById.values) {
      final currentLocalProject = (await _storageService.getProjects())
          .where((project) => project.id == cloudProject.id)
          .firstOrNull;
      if (currentLocalProject != null) {
        mergedProjects.add(currentLocalProject);
        continue;
      }
      final inserted = await _storageService.saveProjectMetadataIfAbsent(
        cloudProject,
        shouldWrite: () => _currentAccountId() == accountId,
      );
      if (inserted) {
        mergedProjects.add(cloudProject);
      } else {
        final currentAfterConflict = (await _storageService.getProjects())
            .where((project) => project.id == cloudProject.id)
            .firstOrNull;
        if (currentAfterConflict != null) {
          mergedProjects.add(currentAfterConflict);
        }
      }
    }
    return mergedProjects;
  }

  Future<List<LocalProjectMetadata>> _renameLegacyUntitledProjects(
    List<LocalProjectMetadata> projects,
    String? accountId,
  ) async {
    var updatedAny = false;
    for (final project in projects) {
      final ownerId = project.cloudOwnerId;
      if (project.name != 'Untitled Doc' ||
          project.isCollaborationRoom ||
          (ownerId != null && ownerId != accountId)) {
        continue;
      }
      final renamed = project.copyWith(
        name: formatWorkspaceTimestamp(project.createdAt),
        cloudMetadataSyncPending: ownerId == null
            ? project.cloudMetadataSyncPending
            : true,
      );
      if (ownerId == null) {
        final saved = await _storageService
            .saveProjectMetadataIfRevisionUnchanged(
              renamed,
              expectedRevision: project.localMetadataRevision,
            );
        updatedAny = updatedAny || saved;
        continue;
      }
      if (accountId == null || !_isAdoptionAccountCurrent(accountId)) continue;
      final pending = renamed.copyWith(cloudMetadataSyncPending: true);
      final saved = await _storageService
          .saveProjectMetadataIfRevisionUnchanged(
            pending,
            expectedRevision: project.localMetadataRevision,
            shouldWrite: () => _isAdoptionAccountCurrent(accountId),
          );
      if (!saved) continue;
      updatedAny = true;
      try {
        await _syncOwnedProjectMetadata(pending);
      } catch (error) {
        debugPrint('[HomeProjects] Legacy title sync failed: $error');
      }
    }
    return updatedAny ? _storageService.getProjects() : projects;
  }

  Future<LocalProjectMetadata> createProject(String name) async {
    final now = DateTime.now();
    final normalizedName = name.trim();
    final meta = LocalProjectMetadata(
      id: const Uuid().v4(),
      name: normalizedName.isEmpty || normalizedName == 'Untitled Doc'
          ? formatWorkspaceTimestamp(now)
          : normalizedName,
      createdAt: now,
      updatedAt: now,
    );
    await _storageService.saveProjectMetadata(meta);
    await loadProjects();
    return meta;
  }

  Future<void> deleteProject(String id) async {
    await _storageService.deleteProject(id);
    await _openDocumentTabs.close(id);
    await loadProjects();
  }

  Future<void> detachDeletedCloudProject({
    required String projectId,
    required String expectedAccountId,
  }) async {
    if (!_isAdoptionAccountCurrent(expectedAccountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final current = (await _storageService.getProjects())
          .where((project) => project.id == projectId)
          .firstOrNull;
      if (current == null) throw StateError('Project not found: $projectId');
      if (current.cloudOwnerId == null) return;
      if (current.cloudOwnerId != expectedAccountId ||
          current.isCollaborationRoom) {
        throw const SyncException('This project is not owned by this account.');
      }
      if (!_isAdoptionAccountCurrent(expectedAccountId)) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }

      final localCopy = current.copyWith(
        clearCloudOwnerId: true,
        clearCloudUpdatedAt: true,
        cloudMetadataSyncPending: false,
        clearCloudAdoptionPendingAccountId: true,
        cloudDeletionDetached: true,
      );
      final saved = await _storageService
          .saveProjectMetadataIfRevisionUnchanged(
            localCopy,
            expectedRevision: current.localMetadataRevision,
            shouldWrite: () => _isAdoptionAccountCurrent(expectedAccountId),
          );
      if (!saved) continue;
      if (!_isAdoptionAccountCurrent(expectedAccountId)) {
        throw const SyncException(
          'The cloud account changed during this action.',
        );
      }
      final latest = (await _storageService.getProjects())
          .where((project) => project.id == projectId)
          .firstOrNull;
      if (latest != null && latest.cloudOwnerId == null) {
        final projects = await _storageService.getProjects();
        final currentAccountId = _currentAccountId();
        final visibleProjects = projects
            .where(
              (project) =>
                  project.cloudOwnerId == null ||
                  project.cloudOwnerId == currentAccountId,
            )
            .toList();
        visibleProjects.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        state = AsyncValue.data(visibleProjects);
      }
      return;
    }
    throw StateError('The local project changed repeatedly during detachment.');
  }

  Future<void> moveProjectsToTrash(Iterable<String> ids) async {
    final projectIds = ids.toSet();
    if (projectIds.isEmpty) return;
    await _storageService.moveProjectsToTrash(projectIds);
    for (final id in projectIds) {
      await _openDocumentTabs.close(id);
    }
    await loadProjects();
  }

  Future<void> togglePinned(String id) async {
    final project = await _findProject(id);
    await _storageService.setProjectPinned(id, !project.isPinned);
    final updated = (await _storageService.getProjects()).firstWhere(
      (candidate) => candidate.id == id,
    );
    _setRenamedProjectState(state.value ?? <LocalProjectMetadata>[], updated);
    await _syncOwnedProjectMetadata(updated);
    await loadProjects();
  }

  Future<void> archiveProject(String id) async {
    await _storageService.archiveProject(id);
    final updated = (await _storageService.getProjects()).firstWhere(
      (candidate) => candidate.id == id,
    );
    _setRenamedProjectState(state.value ?? <LocalProjectMetadata>[], updated);
    await _syncOwnedProjectMetadata(updated);
    await loadProjects();
  }

  Future<void> restoreProject(String id) async {
    await _storageService.restoreProject(id);
    final updated = (await _storageService.getProjects()).firstWhere(
      (candidate) => candidate.id == id,
    );
    _setRenamedProjectState(state.value ?? <LocalProjectMetadata>[], updated);
    await _syncOwnedProjectMetadata(updated);
    await loadProjects();
  }

  Future<void> _syncOwnedProjectMetadata(LocalProjectMetadata metadata) async {
    final ownerId = metadata.cloudOwnerId;
    if (ownerId == null) return;
    if (_currentAccountId() != ownerId || !_isAdoptionAccountCurrent(ownerId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    final pending = metadata.copyWith(cloudMetadataSyncPending: true);
    await _storageService.saveProjectMetadata(
      pending,
      shouldWrite: () => _isAdoptionAccountCurrent(ownerId),
    );
    if (!_isAdoptionAccountCurrent(ownerId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    final sync = _ref.read(supabaseSyncServiceProvider);
    await sync.verifyProjectOwnership(metadata.id, expectedUserId: ownerId);
    await sync.syncProjectMetadata(pending, expectedUserId: ownerId);
    if (!_isAdoptionAccountCurrent(ownerId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await _storageService.clearCloudMetadataSyncPendingIfUnchanged(
      pending,
      expectedOwnerId: ownerId,
    );
  }

  Future<void> purgeProject(String id) => purgeProjects([id]);

  Future<void> purgeProjects(Iterable<String> ids) async {
    final projectIds = ids.toSet();
    if (projectIds.isEmpty) return;
    await _storageService.purgeProjects(projectIds);
    for (final id in projectIds) {
      await _openDocumentTabs.close(id);
    }
    await loadProjects();
  }

  Future<LocalProjectMetadata> duplicateProject(String id) async {
    final duplicate = await _storageService.duplicateProject(id);
    await loadProjects();
    return duplicate;
  }

  String? _currentAccountId() {
    final client = _ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser ?? client?.auth.currentSession?.user;
    return user?.id;
  }

  bool _isAdoptionAccountCurrent(String expectedAccountId) {
    final client = _ref.read(supabaseClientProvider);
    final user = client?.auth.currentUser ?? client?.auth.currentSession?.user;
    return user?.id == expectedAccountId && user?.isAnonymous == false;
  }

  Future<LocalProjectMetadata> rememberCollaborationRoom(
    CanvasRoom room, {
    String? expectedAccountId,
  }) async {
    final accountId = expectedAccountId ?? _currentAccountId();
    if (accountId == null || _currentAccountId() != accountId) {
      throw StateError('Collaboration account changed before room save.');
    }
    final current = state.value ?? await _storageService.getProjects();
    final existing = current
        .where((project) => project.id == room.projectId)
        .firstOrNull;
    if (_currentAccountId() != accountId) {
      throw StateError('Collaboration account changed before room save.');
    }
    final now = DateTime.now();
    final metadata = existing == null
        ? LocalProjectMetadata(
            id: room.projectId,
            name: room.projectName,
            createdAt: room.createdAt ?? now,
            updatedAt: now,
            collaborationRoomCode: room.roomCode,
            collaborationRole: room.role,
            collaborationAccountId: accountId,
            collaborationRoomExpiresAt: room.expiresAt,
          )
        : existing.copyWith(
            updatedAt: now,
            collaborationRoomCode: room.roomCode,
            collaborationRole: room.role,
            collaborationAccountId: accountId,
            collaborationRoomExpiresAt: room.expiresAt,
          );
    await _storageService.saveProjectMetadata(
      metadata,
      shouldWrite: () => _currentAccountId() == accountId,
    );
    if (_currentAccountId() != accountId) {
      await _storageService.clearAccountScopedCollaborationMetadata(
        expectedAccountId: accountId,
      );
      throw StateError('Collaboration account changed during room save.');
    }
    if (_currentAccountId() != accountId) {
      await _storageService.clearAccountScopedCollaborationMetadata(
        expectedAccountId: accountId,
      );
      throw StateError('Collaboration account changed before room cache save.');
    }
    await _storageService.clearAccountScopedCollaborationRejoin(room.projectId);
    if (_currentAccountId() != accountId) {
      await _storageService.clearAccountScopedCollaborationMetadata(
        expectedAccountId: accountId,
      );
      throw StateError('Collaboration account changed before room cache save.');
    }
    try {
      await CollaborationRoomCache.write(room, accountId: accountId);
    } catch (_) {
      // Local project metadata remains the fallback source for room recovery.
    }
    if (_currentAccountId() != accountId) {
      await _storageService.clearAccountScopedCollaborationMetadata(
        expectedAccountId: accountId,
      );
      await CollaborationRoomCache.clear(
        room.projectId,
        expectedAccountId: accountId,
      );
      throw StateError('Collaboration account changed after room cache save.');
    }
    await loadProjects();
    return metadata;
  }

  Future<void> clearCollaborationRoom(
    String projectId, {
    String? expectedAccountId,
  }) async {
    final accountId = expectedAccountId ?? _currentAccountId();
    if (expectedAccountId != null && _currentAccountId() != expectedAccountId) {
      throw StateError('Collaboration account changed before room clear.');
    }
    final current = state.value ?? await _storageService.getProjects();
    final project = current
        .where((candidate) => candidate.id == projectId)
        .firstOrNull;
    if (project == null) return;
    await _storageService.saveProjectMetadata(
      project.copyWith(updatedAt: DateTime.now(), clearCollaborationRoom: true),
      shouldWrite: accountId == null
          ? null
          : () => _currentAccountId() == accountId,
    );
    if (expectedAccountId != null && _currentAccountId() != expectedAccountId) {
      throw StateError('Collaboration account changed during room clear.');
    }
    await loadProjects();
  }

  Future<LocalProjectMetadata> _findProject(String id) async {
    final current = state.value ?? await _storageService.getProjects();
    return current.firstWhere(
      (project) => project.id == id,
      orElse: () => throw StateError('Project not found: $id'),
    );
  }

  Future<void> renameProject(String id, String newName) async {
    final accountId = _currentAccountId();
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(newName, 'newName', 'Title cannot be empty.');
    }

    final current = state.value ?? await _storageService.getProjects();
    final matches = current.where((project) => project.id == id).toList();
    if (matches.isEmpty) {
      throw StateError('Project not found: $id');
    }
    final project = matches.first;
    final updated = project.copyWith(
      name: normalizedName,
      updatedAt: DateTime.now(),
      cloudMetadataSyncPending: project.cloudOwnerId != null
          ? true
          : project.cloudMetadataSyncPending,
    );

    final cloudOwnerId = project.cloudOwnerId;
    if (cloudOwnerId == null) {
      await _storageService.saveProjectMetadata(updated);
      _setRenamedProjectState(current, updated);
      return;
    }

    if (accountId == null ||
        accountId != cloudOwnerId ||
        !_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }

    final sync = _ref.read(supabaseSyncServiceProvider);
    await _storageService.saveProjectMetadata(
      updated,
      shouldWrite: () => _isAdoptionAccountCurrent(accountId),
    );
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    _setRenamedProjectState(current, updated);

    await sync.verifyProjectOwnership(id, expectedUserId: accountId);
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await sync.syncProjectMetadata(updated, expectedUserId: accountId);
    if (!_isAdoptionAccountCurrent(accountId)) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    await _storageService.clearCloudMetadataSyncPendingIfUnchanged(
      updated,
      expectedOwnerId: accountId,
    );
  }

  void _setRenamedProjectState(
    List<LocalProjectMetadata> current,
    LocalProjectMetadata updated,
  ) {
    final projects = current
        .map((project) => project.id == updated.id ? updated : project)
        .toList();
    projects.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    state = AsyncValue.data(projects);
  }
}
