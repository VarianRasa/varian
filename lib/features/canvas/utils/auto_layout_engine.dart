import 'dart:math' as math;

import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../domain/canvas_precision.dart';

class AutoLayoutEngine {
  static ({FramePayload framePayload, List<CanvasNode> children}) applyPreset({
    required CanvasNode frameNode,
    required List<CanvasNode> children,
    required CanvasLayoutPreset preset,
  }) {
    final payload = frameNode.payload;
    if (payload is! FramePayload) {
      return (
        framePayload: FramePayload(),
        children: List<CanvasNode>.from(children),
      );
    }

    switch (preset) {
      case CanvasLayoutPreset.freeform:
        return (
          framePayload: payload.copyWith(
            layoutDirection: AutoLayoutDirection.none,
          ),
          children: List<CanvasNode>.from(children),
        );
      case CanvasLayoutPreset.horizontal:
      case CanvasLayoutPreset.vertical:
        final nextPayload = payload.copyWith(
          layoutDirection: preset == CanvasLayoutPreset.horizontal
              ? AutoLayoutDirection.horizontal
              : AutoLayoutDirection.vertical,
          layoutAlign: AutoLayoutAlign.start,
        );
        final (nextFrame, nextChildren) = applyLayout(
          frameNode: frameNode.copyWith(payload: nextPayload),
          children: children,
        );
        return (
          framePayload: nextFrame.payload as FramePayload,
          children: nextChildren,
        );
      case CanvasLayoutPreset.grid:
        final columns = children.isEmpty
            ? 1
            : math.sqrt(children.length.toDouble()).ceil();
        final innerWidth =
            (frameNode.width - payload.paddingLeft - payload.paddingRight)
                .clamp(1.0, double.infinity);
        final innerHeight =
            (frameNode.height - payload.paddingTop - payload.paddingBottom)
                .clamp(1.0, double.infinity);
        final cellWidth = innerWidth / columns;
        final rows = (children.length / columns).ceil();
        final cellHeight = innerHeight / rows;
        final positioned = <CanvasNode>[];
        for (var index = 0; index < children.length; index++) {
          final row = index ~/ columns;
          final column = index % columns;
          final child = children[index];
          final x = frameNode.x + payload.paddingLeft + column * cellWidth;
          final y = frameNode.y + payload.paddingTop + row * cellHeight;
          positioned.add(
            child.copyWith(
              x: x + (cellWidth - child.width).clamp(0.0, double.infinity) / 2,
              y:
                  y +
                  (cellHeight - child.height).clamp(0.0, double.infinity) / 2,
            ),
          );
        }
        return (
          framePayload: payload.copyWith(
            layoutDirection: AutoLayoutDirection.none,
          ),
          children: positioned,
        );
    }
  }

  /// Recalculates child positions and updates frame dimensions if auto-layout is enabled.
  static (CanvasNode frameNode, List<CanvasNode> children) applyLayout({
    required CanvasNode frameNode,
    required List<CanvasNode> children,
  }) {
    if (frameNode.type != NodeType.frame ||
        frameNode.payload is! FramePayload) {
      return (frameNode, children);
    }

    final payload = frameNode.payload as FramePayload;
    if (payload.layoutDirection == AutoLayoutDirection.none ||
        children.isEmpty) {
      return (frameNode, children);
    }

    final isHorizontal =
        payload.layoutDirection == AutoLayoutDirection.horizontal;
    final padL = payload.paddingLeft;
    final padT = payload.paddingTop;
    final padR = payload.paddingRight;
    final padB = payload.paddingBottom;
    final spacing = payload.itemSpacing;

    final sortedChildren = List<CanvasNode>.from(children)
      ..sort((a, b) => isHorizontal ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    // Calculate total primary size of all children
    double totalChildrenPrimarySize = 0.0;
    for (final child in sortedChildren) {
      totalChildrenPrimarySize += isHorizontal ? child.width : child.height;
    }

    final int childCount = sortedChildren.length;
    final double totalAvailablePrimary = isHorizontal
        ? (frameNode.width - padL - padR)
        : (frameNode.height - padT - padB);

    double effectiveSpacing = spacing;
    double startPrimaryOffset = isHorizontal
        ? (frameNode.x + padL)
        : (frameNode.y + padT);

    if (payload.layoutAlign == AutoLayoutAlign.spaceBetween && childCount > 1) {
      final freeSpace = totalAvailablePrimary - totalChildrenPrimarySize;
      effectiveSpacing = freeSpace > 0 ? (freeSpace / (childCount - 1)) : 0.0;
    } else if (payload.layoutAlign == AutoLayoutAlign.center) {
      final totalLayoutSpan =
          totalChildrenPrimarySize +
          (childCount > 1 ? (childCount - 1) * spacing : 0.0);
      final freeSpace = totalAvailablePrimary - totalLayoutSpan;
      if (freeSpace > 0) {
        startPrimaryOffset += freeSpace / 2;
      }
    } else if (payload.layoutAlign == AutoLayoutAlign.end) {
      final totalLayoutSpan =
          totalChildrenPrimarySize +
          (childCount > 1 ? (childCount - 1) * spacing : 0.0);
      final freeSpace = totalAvailablePrimary - totalLayoutSpan;
      if (freeSpace > 0) {
        startPrimaryOffset += freeSpace;
      }
    }

    double currentOffset = startPrimaryOffset;
    double maxCrossSize = 0.0;
    final updatedChildren = <CanvasNode>[];

    for (final child in sortedChildren) {
      double childX = child.x;
      double childY = child.y;

      if (isHorizontal) {
        childX = currentOffset;
        switch (payload.layoutAlign) {
          case AutoLayoutAlign.start:
          case AutoLayoutAlign.spaceBetween:
            childY = frameNode.y + padT;
            break;
          case AutoLayoutAlign.center:
            final crossAvailable = frameNode.height - padT - padB;
            childY = frameNode.y + padT + (crossAvailable - child.height) / 2;
            break;
          case AutoLayoutAlign.end:
            childY = frameNode.y + frameNode.height - padB - child.height;
            break;
        }

        currentOffset += child.width + effectiveSpacing;
        if (child.height > maxCrossSize) maxCrossSize = child.height;
      } else {
        childY = currentOffset;
        switch (payload.layoutAlign) {
          case AutoLayoutAlign.start:
          case AutoLayoutAlign.spaceBetween:
            childX = frameNode.x + padL;
            break;
          case AutoLayoutAlign.center:
            final crossAvailable = frameNode.width - padL - padR;
            childX = frameNode.x + padL + (crossAvailable - child.width) / 2;
            break;
          case AutoLayoutAlign.end:
            childX = frameNode.x + frameNode.width - padR - child.width;
            break;
        }

        currentOffset += child.height + effectiveSpacing;
        if (child.width > maxCrossSize) maxCrossSize = child.width;
      }

      updatedChildren.add(child.copyWith(x: childX, y: childY));
    }

    return (frameNode, updatedChildren);
  }
}
