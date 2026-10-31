import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/supabase_bootstrap.dart';
import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/workspace_timestamp.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../data/local/account_scoped_local_storage.dart';
import '../../../data/local/durable/project_session.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/remote/supabase_service.dart';
import '../../../domain/models/collaboration.dart';
import '../../../domain/models/document.dart';
import '../../../domain/models/design_tokens.dart';
import '../../auth/state/auth_provider.dart';
import '../../canvas/presentation/canvas_screen.dart';
import '../../capture/domain/capture_canvas_handoff.dart';
import '../../canvas/state/autosave_controller.dart';
import '../../canvas/state/design_token_provider.dart';
import '../../canvas/state/document_assets_provider.dart';
import '../../canvas/state/document_edges_provider.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../../canvas/state/open_document_tabs_provider.dart';
import '../../canvas/state/viewport_provider.dart';
import '../../collaboration/state/collaboration_session_provider.dart';
import '../state/home_provider.dart';

/// Owns loading for the canonical `/project/:projectId` route.
///
/// Local metadata and documents are loaded before the editor is built, so a
/// direct route or browser refresh does not depend on an authenticated cloud
/// session. Owner snapshots are read only after server ownership verification;
/// collaboration snapshots are deferred until membership is verified.
class ProjectRouteScreen extends ConsumerStatefulWidget {
  const ProjectRouteScreen({
    required this.projectId,
    this.collaborationRole,
    this.captureHandoff,
    this.editorBuilder,
    super.key,
  });

  final String projectId;
  final CollaborationRole? collaborationRole;
  final CaptureCanvasHandoff? captureHandoff;
  final Widget Function(
    String projectId,
    String projectName,
    CollaborationRole? role,
  )?
  editorBuilder;

  @override
  ConsumerState<ProjectRouteScreen> createState() => _ProjectRouteScreenState();
}

final projectRouteTransitionRecoveryProvider =
    StateProvider.family<ProjectRouteTransitionRecovery?, String>(
      (ref, projectId) => null,
    );

class ProjectRouteTransitionRecovery {
  const ProjectRouteTransitionRecovery({
    required this.document,
    required this.accountId,
  });

  final CanvasDocument document;
  final String? accountId;
}

class _ProjectRouteScreenState extends ConsumerState<ProjectRouteScreen> {
  LocalProjectMetadata? _metadata;
  CanvasDocument? _loadedDocument;
  String? _loadedCloudAccountId;
  String? _loadingCloudAccountId;
  Object? _loadError;
  bool _loading = true;
  bool _requiresCloudAuth = false;
  CanvasDocument? _pendingTransitionDocument;
  bool _authTransitionInFlight = false;
  bool _recoveringTransitionDocument = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProject());
  }

  @override
  void didUpdateWidget(covariant ProjectRouteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.collaborationRole != widget.collaborationRole) {
      unawaited(_flushBeforeReload(oldWidget.projectId));
    }
  }

  Future<void> _flushBeforeReload(String previousProjectId) async {
    if (previousProjectId != widget.projectId) {
      await _prepareProjectSwitch(previousProjectId);
    }
    if (!mounted) return;
    await _loadProject();
  }

  Future<void> _loadProject() async {
    final projectId = widget.projectId.trim();
    final savedRecovery = ref.read(
      projectRouteTransitionRecoveryProvider(projectId),
    );
    if (savedRecovery != null) {
      _pendingTransitionDocument = savedRecovery.document;
    }
    if (_pendingTransitionDocument?.projectId == projectId) {
      if (!mounted) return;
      setState(() {
        _metadata = null;
        _loadedDocument = null;
        _loadedCloudAccountId = null;
        _loadError = const _UnsavedTransitionException();
        _loading = false;
      });
      final currentAccountId =
          ref.read(supabaseClientProvider)?.auth.currentUser?.id ??
          ref.read(supabaseClientProvider)?.auth.currentSession?.user.id;
      if (currentAccountId != null &&
          currentAccountId == savedRecovery?.accountId) {
        unawaited(_recoverTransitionDocument());
      }
      return;
    }
    final generation = ++_loadGeneration;
    final client = ref.read(supabaseClientProvider);
    _loadingCloudAccountId =
        client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        ref.read(authUserProvider).value?.id;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _metadata = null;
        _loadedCloudAccountId = null;
        _requiresCloudAuth = false;
      });
    }

    try {
      final projectId = widget.projectId.trim();
      if (projectId.isEmpty || _hasUnsafeProjectId(projectId)) {
        throw const _ProjectNotFoundException();
      }
      final storage = ref.read(localStorageServiceProvider);
      final durableSession = ref.read(projectSessionProvider(projectId));
      final projects = await storage.getProjects();
      var metadata = projects.cast<LocalProjectMetadata?>().firstWhere(
        (project) => project?.id == projectId,
        orElse: () => null,
      );
      final legacyMetadata = metadata;
      if (legacyMetadata != null &&
          legacyMetadata.name == 'Untitled Doc' &&
          !legacyMetadata.isCollaborationRoom &&
          (legacyMetadata.cloudOwnerId == null ||
              (legacyMetadata.cloudOwnerId == _loadingCloudAccountId &&
                  _cloudAccountIsCurrent(legacyMetadata.cloudOwnerId)))) {
        final renamed = legacyMetadata.copyWith(
          name: formatWorkspaceTimestamp(legacyMetadata.createdAt),
          cloudMetadataSyncPending: legacyMetadata.cloudOwnerId != null
              ? true
              : legacyMetadata.cloudMetadataSyncPending,
        );
        final saved = await storage.saveProjectMetadataIfRevisionUnchanged(
          renamed,
          expectedRevision: legacyMetadata.localMetadataRevision,
          shouldWrite: legacyMetadata.cloudOwnerId == null
              ? null
              : () => _cloudAccountIsCurrent(legacyMetadata.cloudOwnerId),
        );
        if (saved) metadata = renamed;
      }
      if (await storage.requiresAccountScopedCollaborationRejoin(projectId)) {
        throw const _ProjectMembershipRequiredException();
      }
      if (metadata == null) throw const _ProjectNotFoundException();
      CanvasDocument? document;
      final collaborationProject =
          widget.collaborationRole != null ||
          metadata.collaborationRole != null ||
          metadata.isCollaborationRoom;
      final cloudBackedProject = metadata.cloudOwnerId != null;
      final cloudProject = collaborationProject || cloudBackedProject;
      if (generation != _loadGeneration ||
          widget.projectId.trim() != projectId) {
        return;
      }
      _requiresCloudAuth = cloudProject;
      String? expectedCloudAccountId;

      if (cloudProject) {
        final authState = ref.read(authUserProvider);
        if (authState.hasValue && authState.value == null) {
          throw const _ProjectAuthRequiredException();
        }
        expectedCloudAccountId = authState.value?.id;
        var client = ref.read(supabaseClientProvider);
        if (client == null) {
          await defaultSupabaseBootstrap.ensureReady(explicit: true);
          ref.invalidate(supabaseClientProvider);
          client = ref.read(supabaseClientProvider);
        }
        expectedCloudAccountId ??= client?.auth.currentUser?.id;
        expectedCloudAccountId ??= client?.auth.currentSession?.user.id;
        if (client?.auth.currentUser == null ||
            !_cloudAccountIsCurrent(expectedCloudAccountId)) {
          throw const _ProjectAuthRequiredException();
        }

        final sync = ref.read(supabaseSyncServiceProvider);
        if (collaborationProject) {
          final roomCode = metadata.collaborationRoomCode?.trim() ?? '';
          if (!CanvasRoom.isValidRoomCode(roomCode)) {
            throw const _ProjectMembershipRequiredException();
          }
          final room = await sync.joinCollaborationRoom(
            roomCode: roomCode,
            displayName: 'Collaborator',
            expectedUserId: expectedCloudAccountId,
          );
          if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
            throw const _ProjectAuthRequiredException();
          }
          if (room.projectId != projectId) {
            throw const _ProjectMembershipRequiredException();
          }
          metadata = metadata.copyWith(collaborationRole: room.role);
          try {
            document = await _fetchCloudDocument(projectId);
          } catch (_) {
            if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
              throw const _ProjectAuthRequiredException();
            }
            throw const _ProjectUnavailableException();
          }
          if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
            throw const _ProjectAuthRequiredException();
          }
          if (document == null) {
            throw const _ProjectUnavailableException();
          }
        } else if (cloudBackedProject) {
          final ownerAccountId = expectedCloudAccountId;
          if (ownerAccountId == null ||
              metadata.cloudOwnerId != ownerAccountId) {
            throw const _ProjectAuthRequiredException();
          }
          await _verifyCloudProjectOwnership(sync, projectId, ownerAccountId);
          if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
            throw const _ProjectAuthRequiredException();
          }

          // Durable project records are authoritative. SharedPreferences is a
          // compatibility fallback for projects written before the durable
          // store was introduced.
          document = await durableSession.loadDocument();
          document ??= await storage.loadDocument(projectId);
          CanvasDocument? cloudDocument;
          try {
            cloudDocument = await _fetchCloudDocument(
              projectId,
              includeCollaborationSnapshot: false,
            );
            if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
              throw const _ProjectAuthRequiredException();
            }
          } catch (_) {
            if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
              throw const _ProjectAuthRequiredException();
            }
            throw const _ProjectUnavailableException();
          }

          if (document != null && cloudDocument != null) {
            if (!_sameDocumentContent(document, cloudDocument)) {
              throw const _ProjectConflictException();
            }
            // Matching snapshots are equivalent regardless of client clocks.
            // Prefer the cloud copy as the verified canonical read without
            // making a timestamp-based choice between divergent content.
            document = cloudDocument;
          } else if (document == null && cloudDocument != null) {
            if (!_cloudAccountIsCurrent(expectedCloudAccountId)) {
              throw const _ProjectAuthRequiredException();
            }
            document = cloudDocument;
            await storage.saveDocument(cloudDocument);
          } else if (document != null && cloudDocument == null) {
            // A missing cloud snapshot is not proof that a local snapshot is
            // safe to upload; require an explicit adoption flow instead.
            throw const _ProjectConflictException();
          }
        } else {
          throw const _ProjectAuthRequiredException();
        }
      } else {
        // Local-only projects must remain available without cloud setup.
        document = await durableSession.loadDocument();
        document ??= await storage.loadDocument(projectId);
      }
      final resolvedAuth = ref.read(authUserProvider);
      if (_requiresCloudAuth &&
          (resolvedAuth.hasValue && resolvedAuth.value == null ||
              !_cloudAccountIsCurrent(expectedCloudAccountId))) {
        throw const _ProjectAuthRequiredException();
      }
      if (!mounted || generation != _loadGeneration) return;
      _applyDocument(document);
      if (!mounted || generation != _loadGeneration) return;
      _loadedDocument = document;
      setState(() {
        _metadata = metadata;
        _loadedCloudAccountId = expectedCloudAccountId;
        _loadingCloudAccountId = null;
        _loading = false;
      });
    } on _ProjectMembershipRequiredException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } on _ProjectAuthRequiredException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } on _ProjectNotFoundException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } on _ProjectConflictException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } on _ProjectUnavailableException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } on LocalStorageException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = const _ProjectUnavailableException();
        _loading = false;
      });
    }
  }

  Future<void> _verifyCloudProjectOwnership(
    SupabaseSyncService sync,
    String projectId,
    String expectedAccountId,
  ) async {
    try {
      await sync.verifyProjectOwnership(
        projectId,
        expectedUserId: expectedAccountId,
      );
    } on SyncException catch (error) {
      if (!_cloudAccountIsCurrent(expectedAccountId)) {
        throw const _ProjectAuthRequiredException();
      }
      if (error.message == 'The signed-in account does not own this project.') {
        throw const _ProjectAuthRequiredException();
      }
      throw const _ProjectUnavailableException();
    }
  }

  bool _cloudAccountIsCurrent(String? expectedAccountId) {
    if (expectedAccountId == null) return false;
    final client = ref.read(supabaseClientProvider);
    final currentAccountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    return currentAccountId == expectedAccountId;
  }

  Future<CanvasDocument?> _fetchCloudDocument(
    String projectId, {
    bool includeCollaborationSnapshot = true,
  }) async {
    final sync = ref.read(supabaseSyncServiceProvider);
    final snapshot = await sync.fetchDocumentSnapshot(projectId);
    if (snapshot != null) return snapshot;
    if (!includeCollaborationSnapshot) return null;
    return sync.fetchCollaborationSnapshot(projectId);
  }

  bool _sameDocumentContent(CanvasDocument left, CanvasDocument right) {
    Object? canonicalize(Object? value) {
      if (value is Map) {
        final entries = value.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
        return {
          for (final entry in entries)
            entry.key.toString(): canonicalize(entry.value),
        };
      }
      if (value is List) {
        return value.map(canonicalize).toList(growable: false);
      }
      return value;
    }

    Map<String, dynamic> withoutClientTimestamp(CanvasDocument document) {
      final value = Map<String, dynamic>.from(document.toPersistenceJson());
      value.remove('updatedAt');
      final assets = value['assets'];
      if (assets is Map && assets['items'] is List) {
        value['assets'] = Map<String, dynamic>.from(assets)
          ..['items'] = (assets['items'] as List)
              .map((item) {
                if (item is! Map) return item;
                return Map<String, dynamic>.from(item)..remove('updatedAt');
              })
              .toList(growable: false);
      }
      return value;
    }

    return jsonEncode(canonicalize(withoutClientTimestamp(left))) ==
        jsonEncode(canonicalize(withoutClientTimestamp(right)));
  }

  void _applyDocument(CanvasDocument? document) {
    final nodes = ref.read(documentNodesProvider.notifier);
    final edges = ref.read(documentEdgesProvider.notifier);
    final assets = ref.read(documentAssetsProvider.notifier);
    final tokens = ref.read(designTokenSetProvider.notifier);
    final viewport = ref.read(viewportProvider.notifier);
    if (document == null) {
      nodes.setNodes(const []);
      edges.setEdges(const []);
      assets.clear();
      tokens.setSet(const DesignTokenSet());
      viewport.reset();
      return;
    }
    nodes.setNodes(document.nodes);
    edges.setEdges(document.edges);
    assets.setManifest(document.assets);
    tokens.setSet(document.tokens);
    viewport.setPosition(document.viewport.x, document.viewport.y);
    viewport.setZoom(document.viewport.zoom);
  }

  Future<void> _createProject(BuildContext context) async {
    try {
      final metadata = await ref
          .read(homeProjectsProvider.notifier)
          .createProject('Untitled Doc');
      if (!context.mounted) return;
      await _prepareProjectSwitch(widget.projectId);
      if (context.mounted) context.go(_projectPath(metadata.id));
    } catch (_) {
      if (context.mounted) {
        showUiToast(
          context,
          CreativeStudioLocalizations.of(context).projectActionUnavailable,
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _selectProject(BuildContext context, OpenDocumentTab tab) async {
    await _prepareProjectSwitch(widget.projectId);
    if (!context.mounted) return;
    context.go(_projectPath(tab.projectId));
  }

  Future<void> _prepareProjectSwitch(String projectId) async {
    final autosave = ref.read(autosaveControllerProvider);
    await autosave.flushAndDeactivateProject(projectId);

    final collaborationProvider = collaborationSessionProvider(projectId);
    if (!ref.exists(collaborationProvider)) return;
    await ref.read(collaborationProvider.notifier).leave();
  }

  Future<void> _closeProject(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  ) async {
    await _prepareProjectSwitch(tab.projectId);
    await ref.read(openDocumentTabsProvider.notifier).close(tab.projectId);
    if (!active || !context.mounted) return;
    if (replacement == null) {
      context.go('/');
    } else {
      context.go(_projectPath(replacement.projectId));
    }
  }

  Future<void> _handleAuthTransition() async {
    if (_authTransitionInFlight) return;
    _authTransitionInFlight = true;
    final oldAccountId = _loadedCloudAccountId ?? _loadingCloudAccountId;
    var document = _metadata == null
        ? null
        : (_documentFromProviders(widget.projectId) ?? _loadedDocument);
    final autosave = ref.read(autosaveControllerProvider);
    Object? flushFailure;
    try {
      await autosave.flushDurable(deactivateAfterFlush: true);
    } catch (error) {
      flushFailure = error;
      debugPrint(
        '[ProjectRouteScreen] Auth transition durable flush failed: $error',
      );
      document = _documentFromProviders(widget.projectId) ?? document;
      if (document != null) {
        document = document.copyWith(updatedAt: DateTime.now().toUtc());
        _pendingTransitionDocument = document;
        ref
            .read(
              projectRouteTransitionRecoveryProvider(widget.projectId).notifier,
            )
            .state = ProjectRouteTransitionRecovery(
          document: document,
          accountId: oldAccountId,
        );
      }
    }
    if (!mounted) return;
    unawaited(
      ref
          .read(collaborationSessionProvider(widget.projectId).notifier)
          .discardCloudStateOnDispose(),
    );
    ref.invalidate(collaborationSessionProvider(widget.projectId));
    if (flushFailure == null) {
      _applyDocument(null);
      _loadedDocument = null;
    }
    setState(() {
      _metadata = null;
      _loadedCloudAccountId = null;
      _loadError = flushFailure == null
          ? const _ProjectAuthRequiredException()
          : const _UnsavedTransitionException();
      _loading = false;
    });
    _authTransitionInFlight = false;
    if (flushFailure == null) unawaited(_loadProject());
  }

  CanvasDocument? _documentFromProviders(String projectId) {
    final autosave = ref.read(autosaveControllerProvider);
    if (autosave.activeProjectId != projectId) return null;
    try {
      return autosave.currentDocument();
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverTransitionDocument() async {
    final document = _pendingTransitionDocument;
    if (document == null ||
        document.projectId != widget.projectId ||
        _recoveringTransitionDocument) {
      return;
    }
    _recoveringTransitionDocument = true;
    var durableSaved = false;
    final autosave = ref.read(autosaveControllerProvider);
    if (autosave.activeProjectId == document.projectId) {
      try {
        await autosave.flushDurable(deactivateAfterFlush: true);
        durableSaved = true;
      } catch (_) {
        // Fall through to the independent compatibility store.
      }
    } else {
      try {
        await ref
            .read(projectPersistenceSessionProvider(document.projectId))
            .saveDocument(document);
        durableSaved = true;
      } catch (_) {
        // Fall through to the independent compatibility store.
      }
    }

    var fallbackSaved = false;
    try {
      await ref.read(localStorageServiceProvider).saveDocument(document);
      fallbackSaved = true;
    } catch (error) {
      debugPrint(
        '[ProjectRouteScreen] Transition recovery fallback save failed: $error',
      );
    }

    if (!mounted) {
      _recoveringTransitionDocument = false;
      return;
    }
    if (durableSaved || fallbackSaved) {
      _pendingTransitionDocument = null;
      ref
              .read(
                projectRouteTransitionRecoveryProvider(
                  document.projectId,
                ).notifier,
              )
              .state =
          null;
      if (mounted) unawaited(_loadProject());
    } else {
      debugPrint(
        '[ProjectRouteScreen] No local recovery store accepted the transition draft.',
      );
    }
    _recoveringTransitionDocument = false;
  }

  String _projectPath(String projectId, {CollaborationRole? role}) {
    final query = role == null ? null : {'role': role.wireName};
    return Uri(
      path: '/project/${Uri.encodeComponent(projectId)}',
      queryParameters: query,
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<User?>>(authUserProvider, (_, next) {
      if (!_requiresCloudAuth || !next.hasValue) return;
      final observedAccountId = _loadedCloudAccountId ?? _loadingCloudAccountId;
      final accountChanged =
          next.value != null &&
          observedAccountId != null &&
          next.value!.id != observedAccountId;
      if (accountChanged || next.value == null) {
        unawaited(_handleAuthTransition());
      } else if (_pendingTransitionDocument != null &&
          ref
                  .read(
                    projectRouteTransitionRecoveryProvider(widget.projectId),
                  )
                  ?.accountId ==
              next.value?.id) {
        unawaited(_recoverTransitionDocument());
      } else if (_loadError is _ProjectAuthRequiredException) {
        unawaited(_loadProject());
      }
    });
    if (_loading) {
      return UiPageScaffold(
        title: Text(CreativeStudioLocalizations.of(context).projectLoading),
        child: const Center(child: UiLoadingState()),
      );
    }

    final error = _loadError;
    if (error != null) {
      final copy = CreativeStudioLocalizations.of(context);
      final notFound = error is _ProjectNotFoundException;
      final authRequired = error is _ProjectAuthRequiredException;
      final membershipRequired = error is _ProjectMembershipRequiredException;
      final conflict = error is _ProjectConflictException;
      final unsavedTransition = error is _UnsavedTransitionException;
      final title = membershipRequired
          ? copy.projectMembershipRequired
          : authRequired
          ? copy.projectAuthRequired
          : notFound
          ? copy.projectNotFound
          : conflict
          ? 'Project conflict needs review'
          : unsavedTransition
          ? 'Unsaved work needs recovery'
          : copy.projectUnavailable;
      return UiPageScaffold(
        title: Text(title),
        child: Center(
          child: Padding(
            padding: AppResponsive.pagePadding(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: UiSurface(
                key: ValueKey(
                  membershipRequired
                      ? 'project-route-membership-required'
                      : authRequired
                      ? 'project-route-auth-required'
                      : notFound
                      ? 'project-route-not-found'
                      : conflict
                      ? 'project-route-conflict'
                      : unsavedTransition
                      ? 'project-route-unsaved-transition'
                      : 'project-route-error',
                ),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      membershipRequired || authRequired
                          ? Icons.lock_outline
                          : notFound
                          ? Icons.description_outlined
                          : Icons.cloud_off_outlined,
                      size: AppControlSize.regular,
                      color: context.appTokens.danger,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      membershipRequired
                          ? copy.projectMembershipRequiredDescription
                          : authRequired
                          ? copy.projectAuthRequiredDescription
                          : notFound
                          ? copy.projectNotFoundDescription
                          : conflict
                          ? 'Local and cloud snapshots differ. Neither copy was changed. Resolve the conflict before opening this project.'
                          : unsavedTransition
                          ? 'The sign-in changed before this edit could be saved. Your work is kept private on this screen until it can be recovered safely.'
                          : copy.projectUnavailableDescription,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: context.appTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md + AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: [
                        UiButton(
                          onPressed: membershipRequired
                              ? () => context.go('/join')
                              : authRequired
                              ? () => context.go(
                                  Uri(
                                    path: '/auth',
                                    queryParameters: {
                                      'returnTo': _projectPath(
                                        widget.projectId,
                                        role: widget.collaborationRole,
                                      ),
                                    },
                                  ).toString(),
                                )
                              : _loadProject,
                          prefix: Icon(
                            membershipRequired || authRequired
                                ? Icons.login_outlined
                                : Icons.refresh_outlined,
                          ),
                          child: Text(
                            membershipRequired
                                ? copy.projectRejoinAction
                                : authRequired
                                ? copy.authSignInAction
                                : copy.retry,
                          ),
                        ),
                        UiButton(
                          onPressed: () => context.go('/'),
                          variant: UiButtonVariant.outline,
                          child: Text(copy.authBackToCanvas),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final metadata = _metadata!;
    final role =
        widget.collaborationRole ??
        (metadata.collaborationRole == null
            ? null
            : CollaborationRole.fromWire(metadata.collaborationRole));
    final editor = widget.editorBuilder?.call(metadata.id, metadata.name, role);
    return KeyedSubtree(
      // Keep the stable route marker for diagnostics and tests, while the
      // project-specific child forces a fresh editor lifecycle on A -> B.
      key: const ValueKey('project-route-editor'),
      child: KeyedSubtree(
        key: ValueKey('project-route-editor-surface:${metadata.id}'),
        child:
            editor ??
            CanvasScreen(
              projectId: metadata.id,
              projectName: metadata.name,
              collaborationRole: role,
              captureHandoff: metadata.isCollaborationRoom || role != null
                  ? null
                  : widget.captureHandoff,
              onProjectNameChanged: metadata.collaborationRole == null
                  ? (name) async {
                      await ref
                          .read(homeProjectsProvider.notifier)
                          .renameProject(metadata.id, name);
                      return true;
                    }
                  : null,
              onCreateProject: _createProject,
              onSelectDocument: _selectProject,
              onCloseDocument: _closeProject,
            ),
      ),
    );
  }

  static bool _hasUnsafeProjectId(String value) =>
      value.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f);
}

class _ProjectMembershipRequiredException implements Exception {
  const _ProjectMembershipRequiredException();
}

class _ProjectAuthRequiredException implements Exception {
  const _ProjectAuthRequiredException();
}

class _ProjectNotFoundException implements Exception {
  const _ProjectNotFoundException();
}

class _ProjectUnavailableException implements Exception {
  const _ProjectUnavailableException();
}

class _ProjectConflictException implements Exception {
  const _ProjectConflictException();
}

class _UnsavedTransitionException implements Exception {
  const _UnsavedTransitionException();
}
