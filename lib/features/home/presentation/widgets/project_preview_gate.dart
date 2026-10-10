import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/domain/models/document.dart';

import 'project_preview.dart';
import 'project_preview_load_scheduler.dart';

@visibleForTesting
bool shouldDeferProjectPreview({
  required bool isAndroid,
  required bool isWeb,
}) => isAndroid && !isWeb;

/// Defers creating a document-backed preview until the first frame is ready.
///
/// Home cards are built in a burst. Delaying each preview keeps local document
/// parsing out of the initial layout pass and serializes the work across cards.
class DeferredProjectPreview extends StatefulWidget {
  final LocalProjectMetadata project;
  final DurableProjectStore? durableStore;

  const DeferredProjectPreview({
    required this.project,
    this.durableStore,
    super.key,
  });

  @override
  State<DeferredProjectPreview> createState() => _DeferredProjectPreviewState();
}

class _DeferredProjectPreviewState extends State<DeferredProjectPreview> {
  static final ProjectPreviewLoadScheduler _scheduler =
      ProjectPreviewLoadScheduler();

  late final bool _deferForPlatform;
  late Future<CanvasDocument?> _ready;

  @override
  void initState() {
    super.initState();
    _deferForPlatform = shouldDeferProjectPreview(
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      isWeb: kIsWeb,
    );
    _ready = _schedulePreview();
  }

  @override
  void didUpdateWidget(covariant DeferredProjectPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.updatedAt != widget.project.updatedAt) {
      _ready = _schedulePreview();
    }
  }

  Future<CanvasDocument?> _schedulePreview() {
    if (!_deferForPlatform) return Future<CanvasDocument?>.value();
    final projectId = widget.project.id;
    return _scheduler.schedule(() async {
      await WidgetsBinding.instance.endOfFrame;
      final ownedStore = widget.durableStore == null;
      final store = widget.durableStore ?? DurableProjectStore();
      try {
        return await store.loadCanvasDocument(projectId) ??
            await LocalStorageService().loadDocument(projectId);
      } finally {
        if (ownedStore) await store.close();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_deferForPlatform) {
      return ProjectPreview(
        project: widget.project,
        durableStore: widget.durableStore,
      );
    }
    return FutureBuilder<CanvasDocument?>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Colors.transparent);
        }
        return ProjectPreview(
          project: widget.project,
          documentFuture: _ready,
          durableStore: widget.durableStore,
        );
      },
    );
  }
}
