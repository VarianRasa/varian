import 'dart:ui';
import 'package:varian/domain/models/node.dart';

enum AlignmentType { left, center, right, top, middle, bottom }

enum DistributionType { horizontal, vertical }

class AlignEngine {
  static Rect getSelectionBounds(List<CanvasNode> nodes) {
    if (nodes.isEmpty) return Rect.zero;

    double minX = nodes.first.x;
    double minY = nodes.first.y;
    double maxX = nodes.first.x + nodes.first.width;
    double maxY = nodes.first.y + nodes.first.height;

    for (final node in nodes.skip(1)) {
      if (node.x < minX) minX = node.x;
      if (node.y < minY) minY = node.y;
      if (node.x + node.width > maxX) maxX = node.x + node.width;
      if (node.y + node.height > maxY) maxY = node.y + node.height;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<CanvasNode> align(
    List<CanvasNode> nodes,
    AlignmentType alignment,
  ) {
    if (nodes.length <= 1) return nodes;

    final bounds = getSelectionBounds(nodes);

    return nodes.map((node) {
      switch (alignment) {
        case AlignmentType.left:
          return node.copyWith(x: bounds.left);
        case AlignmentType.center:
          return node.copyWith(
            x: bounds.left + (bounds.width - node.width) / 2,
          );
        case AlignmentType.right:
          return node.copyWith(x: bounds.right - node.width);
        case AlignmentType.top:
          return node.copyWith(y: bounds.top);
        case AlignmentType.middle:
          return node.copyWith(
            y: bounds.top + (bounds.height - node.height) / 2,
          );
        case AlignmentType.bottom:
          return node.copyWith(y: bounds.bottom - node.height);
      }
    }).toList();
  }

  static List<CanvasNode> distribute(
    List<CanvasNode> nodes,
    DistributionType type,
  ) {
    if (nodes.length <= 2) return nodes;

    final result = List<CanvasNode>.from(nodes);

    if (type == DistributionType.horizontal) {
      result.sort((a, b) => a.x.compareTo(b.x));

      final first = result.first;
      final last = result.last;
      final totalSpan = (last.x + last.width) - first.x;
      final totalNodeWidths = result.fold<double>(
        0.0,
        (acc, n) => acc + n.width,
      );
      final totalSpacing = totalSpan - totalNodeWidths;
      final gap = totalSpacing / (result.length - 1);

      double currentX = first.x;
      for (int i = 0; i < result.length; i++) {
        result[i] = result[i].copyWith(x: currentX);
        currentX += result[i].width + gap;
      }
    } else {
      result.sort((a, b) => a.y.compareTo(b.y));

      final first = result.first;
      final last = result.last;
      final totalSpan = (last.y + last.height) - first.y;
      final totalNodeHeights = result.fold<double>(
        0.0,
        (acc, n) => acc + n.height,
      );
      final totalSpacing = totalSpan - totalNodeHeights;
      final gap = totalSpacing / (result.length - 1);

      double currentY = first.y;
      for (int i = 0; i < result.length; i++) {
        result[i] = result[i].copyWith(y: currentY);
        currentY += result[i].height + gap;
      }
    }

    return result;
  }
}
