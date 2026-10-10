import 'dart:ui';
import '../../domain/models/document.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import '../../domain/models/vector_path_payload.dart';
import '../canvas/commands/command_replay.dart';

enum BooleanOp { union, subtract, intersect }

class VectorGeometryHelper {
  /// Computes Boolean Path Operation between two vector paths or rectangle/shape nodes
  static Path computeBoolean(Path pathA, Path pathB, BooleanOp op) {
    try {
      switch (op) {
        case BooleanOp.union:
          return Path.combine(PathOperation.union, pathA, pathB);
        case BooleanOp.subtract:
          return Path.combine(PathOperation.difference, pathA, pathB);
        case BooleanOp.intersect:
          return Path.combine(PathOperation.intersect, pathA, pathB);
      }
    } catch (_) {
      return pathA;
    }
  }

  /// Converts a standard CanvasNode (rectangle, ellipse, diamond, vectorPath) to a Flutter Path
  static Path nodeToPath(CanvasNode node) {
    final path = Path();
    final rect = Rect.fromLTWH(node.x, node.y, node.width, node.height);

    switch (node.type) {
      case NodeType.rectangle:
      case NodeType.frame:
      case NodeType.stickyNote:
      case NodeType.text:
      case NodeType.component:
      case NodeType.group:
      case NodeType.image:
      case NodeType.model3d:
      case NodeType.cylinder:
      case NodeType.parallelogram:
      case NodeType.line:
      case NodeType.arrow:
      case NodeType.drawing:
      case NodeType.drawingPaper:
        path.addRect(rect);
        break;
      case NodeType.ellipse:
        path.addOval(rect);
        break;
      case NodeType.diamond:
        path.moveTo(node.x + node.width / 2, node.y);
        path.lineTo(node.x + node.width, node.y + node.height / 2);
        path.lineTo(node.x + node.width / 2, node.y + node.height);
        path.lineTo(node.x, node.y + node.height / 2);
        path.close();
        break;
      case NodeType.vectorPath:
        if (node.payload is VectorPathPayload) {
          final p = node.payload as VectorPathPayload;
          return p.toPath().shift(Offset(node.x, node.y));
        }
        break;
      default:
        path.addRect(rect);
        break;
    }
    return path;
  }
}

/// Snapshot representation for Project Version History
class DocumentSnapshotRecord {
  final String id;
  final String description;
  final DateTime timestamp;
  final CanvasDocument document;
  final CommandReplayLog? commandReplay;

  DocumentSnapshotRecord({
    required this.id,
    required this.description,
    required this.timestamp,
    required this.document,
    this.commandReplay,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'document': document.toJson(),
    if (commandReplay != null) 'commandReplay': commandReplay!.toJson(),
  };

  Map<String, dynamic> toPersistenceJson() => {
    'id': id,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
    'document': document.toPersistenceJson(),
    if (commandReplay != null) 'commandReplay': commandReplay!.toJson(),
  };

  factory DocumentSnapshotRecord.fromJson(Map<String, dynamic> json) =>
      DocumentSnapshotRecord(
        id: json['id'] as String,
        description: json['description'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        document: CanvasDocument.fromJson(
          json['document'] as Map<String, dynamic>,
        ),
        commandReplay: json['commandReplay'] is Map
            ? CommandReplayLog.fromJson(
                Map<String, dynamic>.from(json['commandReplay'] as Map),
              )
            : null,
      );
}
