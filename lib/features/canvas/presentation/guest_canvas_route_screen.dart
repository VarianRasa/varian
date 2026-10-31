import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/canvas_screen.dart';
import 'package:varian/features/canvas/presentation/guest_canvas_promotion.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/design_token_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/features/history/history_provider.dart';
import 'package:varian/features/home/state/home_provider.dart';

/// Opens an anonymous, locally persisted canvas without adding it to the library.
/// Saving promotes the same draft ID to a project after authentication.
class GuestCanvasRouteScreen extends ConsumerStatefulWidget {
  final bool saveAfterAuthentication;

  const GuestCanvasRouteScreen({
    super.key,
    this.saveAfterAuthentication = false,
  });

  @override
  ConsumerState<GuestCanvasRouteScreen> createState() =>
      _GuestCanvasRouteScreenState();
}

class _GuestCanvasRouteScreenState
    extends ConsumerState<GuestCanvasRouteScreen> {
  String? _projectId;
  final String _projectName = 'Untitled Project';
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (!widget.saveAfterAuthentication) {
        await preferences.remove(guestPendingRenamePreferenceKey);
      }
      final storage = ref.read(localStorageServiceProvider);
      var projectId = preferences.getString(guestDraftIdPreferenceKey);
      if (projectId == null || projectId.isEmpty) {
        projectId = const Uuid().v4();
      }

      final projects = await storage.getProjects();
      if (!mounted) return;
      final projectAlreadyExists = projects.any(
        (project) => project.id == projectId,
      );
      if (projectAlreadyExists) {
        if (widget.saveAfterAuthentication) {
          final client = ref.read(supabaseClientProvider);
          final authenticated =
              client?.auth.currentSession?.user ?? client?.auth.currentUser;
          if (authenticated == null) {
            if (mounted) context.go('/auth?returnTo=/canvas/save');
            return;
          }
          final pendingTitle = preferences
              .getString(guestPendingRenamePreferenceKey)
              ?.trim();
          if (pendingTitle != null && pendingTitle.isNotEmpty) {
            final existing = projects.firstWhere(
              (project) => project.id == projectId,
            );
            await storage.saveProjectMetadata(
              existing.copyWith(name: pendingTitle, updatedAt: DateTime.now()),
            );
            await preferences.remove(guestPendingRenamePreferenceKey);
          }
          await preferences.remove(guestDraftIdPreferenceKey);
          await ref.read(homeProjectsProvider.notifier).loadProjects();
          if (mounted) context.go('/project/$projectId');
          return;
        }
        projectId = const Uuid().v4();
      }
      await preferences.setString(guestDraftIdPreferenceKey, projectId);

      final session = ref.read(projectPersistenceSessionProvider(projectId));
      final document =
          await session.loadDocument() ?? await storage.loadDocument(projectId);
      if (!mounted) return;
      final draft =
          document ??
          CanvasDocument(projectId: projectId, updatedAt: DateTime.now());

      final autosave = ref.read(autosaveControllerProvider);
      final outgoingProjectId = autosave.activeProjectId;
      if (outgoingProjectId != null && outgoingProjectId != projectId) {
        await autosave.flushAndDeactivateProject(outgoingProjectId);
      }
      if (!mounted) return;
      _restoreDraft(draft);

      if (widget.saveAfterAuthentication) {
        final client = ref.read(supabaseClientProvider);
        final authenticated =
            client?.auth.currentSession?.user ?? client?.auth.currentUser;
        if (authenticated == null) {
          if (mounted) context.go('/auth?returnTo=/canvas/save');
          return;
        }
        await _promoteDraft(projectId, draft);
        return;
      }

      if (mounted) setState(() => _projectId = projectId);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _restoreDraft(CanvasDocument document) {
    ref.read(documentNodesProvider.notifier).setNodes(document.nodes);
    ref.read(documentEdgesProvider.notifier).setEdges(document.edges);
    ref.read(documentAssetsProvider.notifier).setManifest(document.assets);
    ref.read(designTokenSetProvider.notifier).setSet(document.tokens);
    ref.read(viewportProvider.notifier).setViewport(document.viewport);
    ref.read(selectionProvider.notifier).clear();
    ref.read(historyProvider.notifier).clear();
    ref.read(nodeHistoryProvider.notifier).clear();
  }

  Future<void> _promoteDraft(String projectId, CanvasDocument draft) async {
    final preferences = await SharedPreferences.getInstance();
    await promoteGuestCanvasDraft(
      projectId: projectId,
      draft: draft,
      storage: ref.read(localStorageServiceProvider),
      session: ref.read(projectPersistenceSessionProvider(projectId)),
      preferences: preferences,
    );
    if (!mounted) return;
    await ref.read(homeProjectsProvider.notifier).loadProjects();
    if (!mounted) return;
    context.go('/project/$projectId');
  }

  Future<void> _flushGuestBeforeNavigation(String projectId) async {
    final autosave = ref.read(autosaveControllerProvider);
    if (autosave.activeProjectId == projectId) {
      await autosave.flushAndDeactivateProject(projectId);
    } else {
      await autosave.flushDurable();
    }
  }

  Future<void> _requestWorkspaceSave(BuildContext context) async {
    final projectId = _projectId;
    if (projectId == null) return;
    try {
      await _flushGuestBeforeNavigation(projectId);
      if (!context.mounted) return;
      final client = ref.read(supabaseClientProvider);
      final authenticated =
          client?.auth.currentSession?.user ?? client?.auth.currentUser;
      if (authenticated == null) {
        context.go('/auth?returnTo=/canvas/save');
      } else {
        context.go('/canvas/save');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Draft could not be saved locally: $error')),
        );
      }
    }
  }

  Future<bool> _requestDocumentRename(String newName) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(newName, 'newName', 'Title cannot be empty.');
    }
    final projectId = _projectId;
    if (projectId == null) return false;

    await _flushGuestBeforeNavigation(projectId);
    if (!mounted) return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      guestPendingRenamePreferenceKey,
      normalizedName,
    );
    if (!mounted) return false;
    final client = ref.read(supabaseClientProvider);
    final authenticated =
        client?.auth.currentSession?.user ?? client?.auth.currentUser;
    if (authenticated == null) {
      context.go('/auth?returnTo=/canvas/save');
      return false;
    }
    context.go('/canvas/save');
    return false;
  }

  Future<void> _openLibrary(BuildContext context) async {
    final projectId = _projectId;
    if (projectId == null) return;
    try {
      await _flushGuestBeforeNavigation(projectId);
      if (!context.mounted) return;
      context.go('/');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Draft could not be saved locally: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = _projectId;
    if (_error case final error?) {
      return Scaffold(
        body: Center(child: Text('Unable to open canvas: $error')),
      );
    }
    if (projectId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return CanvasScreen(
      projectId: projectId,
      projectName: _projectName,
      services: CanvasEditorServices.root.copyWith(
        enableCloudSync: false,
        enableCollaboration: false,
      ),
      onCreateProject: _requestWorkspaceSave,
      onOpenProjectLibrary: _openLibrary,
      onProjectNameChanged: _requestDocumentRename,
    );
  }
}
