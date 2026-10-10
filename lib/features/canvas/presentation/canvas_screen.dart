import 'package:flutter/material.dart';

import '../../../domain/models/collaboration.dart';
import '../../../domain/models/document.dart';
import '../../capture/domain/capture_canvas_handoff.dart';
import '../state/open_document_tabs_provider.dart';
import 'widgets/canvas_editor_services.dart';
import 'widgets/canvas_editor_surface.dart';

/// Compatibility facade for the project-level canvas route.
///
/// The shared editor lives in [CanvasEditorSurface]. This facade supplies the
/// root project services while preserving the existing public route API.
class CanvasScreen extends StatelessWidget {
  final String projectId;
  final String projectName;
  final CanvasDocument? initialDocument;
  final List<CanvasComment> initialComments;
  final bool readOnly;
  final CollaborationRole? collaborationRole;
  final CaptureCanvasHandoff? captureHandoff;
  final CanvasEditorServices services;
  final Future<bool> Function(String newName)? onProjectNameChanged;
  final Future<void> Function(BuildContext context)? onCreateProject;
  final Future<void> Function(BuildContext context)? onOpenProjectLibrary;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectDocument;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseDocument;

  const CanvasScreen({
    super.key,
    required this.projectId,
    this.projectName = 'Untitled Project',
    this.initialDocument,
    this.initialComments = const [],
    this.readOnly = false,
    this.collaborationRole,
    this.captureHandoff,
    this.services = CanvasEditorServices.root,
    this.onProjectNameChanged,
    this.onCreateProject,
    this.onOpenProjectLibrary,
    this.onSelectDocument,
    this.onCloseDocument,
  });

  @override
  Widget build(BuildContext context) => CanvasEditorSurface(
    projectId: projectId,
    projectName: projectName,
    initialDocument: initialDocument,
    initialComments: initialComments,
    readOnly: readOnly,
    collaborationRole: collaborationRole,
    captureHandoff: captureHandoff,
    services: services,
    onProjectNameChanged: onProjectNameChanged,
    onCreateProject: onCreateProject,
    onOpenProjectLibrary: onOpenProjectLibrary,
    onSelectDocument: onSelectDocument,
    onCloseDocument: onCloseDocument,
  );
}
