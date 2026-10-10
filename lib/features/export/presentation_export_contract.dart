import 'dart:convert';

import '../../domain/models/document.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';

class PresentationExportSlide {
  final String id;
  final String title;
  final List<String> nodeIds;
  final int durationMs;

  const PresentationExportSlide({
    required this.id,
    required this.title,
    required this.nodeIds,
    this.durationMs = 5000,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'nodeIds': nodeIds,
    'durationMs': durationMs,
  };
}

class PresentationExportContract {
  static const schemaVersion = 1;

  final String projectId;
  final String canvasId;
  final DateTime sourceUpdatedAt;
  final List<PresentationExportSlide> slides;

  const PresentationExportContract({
    required this.projectId,
    required this.canvasId,
    required this.sourceUpdatedAt,
    required this.slides,
  });

  Map<String, dynamic> toJson() => {
    'format': 'varian.presentation.contract',
    'schemaVersion': schemaVersion,
    'projectId': projectId,
    'canvasId': canvasId,
    'sourceUpdatedAt': sourceUpdatedAt.toUtc().toIso8601String(),
    'slides': slides.map((slide) => slide.toJson()).toList(growable: false),
    'provenance': {
      'source': 'varian.canvas.document',
      'projectId': projectId,
      'documentSchemaVersion': 4,
    },
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory PresentationExportContract.fromDocument(CanvasDocument document) {
    final frames =
        document.nodes
            .where((node) => node.type == NodeType.frame && node.visible)
            .toList()
          ..sort((a, b) {
            final y = a.y.compareTo(b.y);
            return y == 0 ? a.x.compareTo(b.x) : y;
          });
    final slides = frames.isEmpty
        ? [
            PresentationExportSlide(
              id: document.canvasId,
              title: document.canvasId,
              nodeIds: document.nodes
                  .where((node) => node.visible)
                  .map((node) => node.id)
                  .toList(growable: false),
            ),
          ]
        : frames
              .map((frame) {
                final nodeIds = document.nodes
                    .where(
                      (node) =>
                          node.visible &&
                          (node.id == frame.id || _isInside(frame, node)),
                    )
                    .map((node) => node.id)
                    .toList(growable: false);
                return PresentationExportSlide(
                  id: frame.id,
                  title: frame.name?.trim().isNotEmpty == true
                      ? frame.name!.trim()
                      : frame.id,
                  nodeIds: nodeIds,
                );
              })
              .toList(growable: false);
    return PresentationExportContract(
      projectId: document.projectId,
      canvasId: document.canvasId,
      sourceUpdatedAt: document.updatedAt,
      slides: slides,
    );
  }

  static bool _isInside(CanvasNode frame, CanvasNode node) {
    final centerX = node.x + node.width / 2;
    final centerY = node.y + node.height / 2;
    return centerX >= frame.x &&
        centerX <= frame.x + frame.width &&
        centerY >= frame.y &&
        centerY <= frame.y + frame.height;
  }
}
