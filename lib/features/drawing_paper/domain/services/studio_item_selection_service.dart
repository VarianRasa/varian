import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/domain/models/manga_frame.dart';
import 'package:varian/features/drawing_paper/domain/models/studio_item_selection.dart';

class FocusStudioItemEntry {
  final FocusStudioItemReference reference;
  final Object item;

  const FocusStudioItemEntry({required this.reference, required this.item});
}

class FocusStudioClipboardItem {
  final FocusStudioItemReference reference;
  final Object item;

  const FocusStudioClipboardItem({required this.reference, required this.item});
}

/// Catalogues and transforms editable Focus Studio items without touching the
/// infinite-canvas node model.
class FocusStudioItemCatalog {
  const FocusStudioItemCatalog._();

  static List<FocusStudioItemEntry> all(DrawingPaperPayload payload) {
    final entries = <FocusStudioItemEntry>[];
    final structure = payload.mangaStructure;
    if (structure != null) {
      for (final balloon in structure.balloons.reversed) {
        entries.add(
          FocusStudioItemEntry(
            reference: FocusStudioItemReference.speechBalloon(
              objectId: balloon.id,
            ),
            item: balloon,
          ),
        );
      }
      for (final panel in structure.panels.reversed) {
        entries.add(
          FocusStudioItemEntry(
            reference: FocusStudioItemReference.mangaPanelCut(
              objectId: panel.id,
            ),
            item: panel,
          ),
        );
      }
    }

    for (var layerIndex = 0; layerIndex < payload.layers.length; layerIndex++) {
      final layer = payload.layers[layerIndex];
      if (!isLayerVisible(payload, layer) || layer.type == LayerType.folder) {
        continue;
      }
      for (final text in layer.texts.reversed) {
        entries.add(
          FocusStudioItemEntry(
            reference: FocusStudioItemReference.textObject(
              layerId: layer.id,
              objectId: text.id,
            ),
            item: text,
          ),
        );
      }
      for (final shape in layer.shapes.reversed) {
        entries.add(
          FocusStudioItemEntry(
            reference: FocusStudioItemReference.vectorShapeObject(
              layerId: layer.id,
              objectId: shape.id,
            ),
            item: shape,
          ),
        );
      }
      for (final stroke in layer.strokes.reversed) {
        entries.add(
          FocusStudioItemEntry(
            reference: FocusStudioItemReference.drawingStroke(
              layerId: layer.id,
              objectId: stroke.id,
            ),
            item: stroke,
          ),
        );
      }
    }
    return entries;
  }

  static List<FocusStudioItemEntry> editable(DrawingPaperPayload payload) {
    return all(payload).where((entry) {
      if (entry.reference.layerId == null) return true;
      final layer = payload.layers.firstWhere(
        (candidate) => candidate.id == entry.reference.layerId,
        orElse: () => const DrawingLayer(id: '', name: '', locked: true),
      );
      return isLayerEditable(payload, layer);
    }).toList();
  }

  static FocusStudioItemEntry? find(
    DrawingPaperPayload payload,
    FocusStudioItemReference reference,
  ) {
    for (final entry in all(payload)) {
      if (entry.reference == reference) return entry;
    }
    return null;
  }

  static Object clone(Object item) {
    return switch (item) {
      DrawingStroke stroke => stroke.copyWith(points: List.of(stroke.points)),
      VectorShapeObject shape => shape.copyWith(points: List.of(shape.points)),
      TextObjectData text => text.copyWith(),
      MangaPanelCut panel => panel.copyWith(),
      SpeechBalloon balloon => balloon.copyWith(),
      _ => throw ArgumentError('Unsupported Focus Studio item: $item'),
    };
  }

  static Object withId(Object item, String id) {
    return switch (item) {
      DrawingStroke stroke => stroke.copyWith(id: id),
      VectorShapeObject shape => shape.copyWith(id: id),
      TextObjectData text => text.copyWith(id: id),
      MangaPanelCut panel => panel.copyWith(id: id),
      SpeechBalloon balloon => balloon.copyWith(id: id),
      _ => throw ArgumentError('Unsupported Focus Studio item: $item'),
    };
  }

  static Object translate(Object item, Offset delta) {
    if (delta == Offset.zero) return item;
    return switch (item) {
      DrawingStroke stroke => stroke.copyWith(
        points: stroke.points
            .map(
              (point) =>
                  point.copyWith(x: point.x + delta.dx, y: point.y + delta.dy),
            )
            .toList(),
      ),
      VectorShapeObject shape => shape.copyWith(
        points: shape.points.map((point) => point + delta).toList(),
      ),
      TextObjectData text => text.copyWith(
        x: text.x + delta.dx,
        y: text.y + delta.dy,
      ),
      MangaPanelCut panel => panel.copyWith(rect: panel.rect.shift(delta)),
      SpeechBalloon balloon => balloon.copyWith(
        position: balloon.position + delta,
        tailTarget: balloon.tailTarget + delta,
      ),
      _ => item,
    };
  }

  static Object scale(Object item, Rect sourceBounds, Rect targetBounds) {
    if (sourceBounds.isEmpty || targetBounds.isEmpty) return item;
    final sx = targetBounds.width / math.max(0.0001, sourceBounds.width);
    final sy = targetBounds.height / math.max(0.0001, sourceBounds.height);
    final uniform = (sx.abs() + sy.abs()) / 2;

    Offset mapPoint(Offset point) => Offset(
      targetBounds.left + (point.dx - sourceBounds.left) * sx,
      targetBounds.top + (point.dy - sourceBounds.top) * sy,
    );

    Rect mapRect(Rect rect) =>
        Rect.fromPoints(mapPoint(rect.topLeft), mapPoint(rect.bottomRight));

    return switch (item) {
      DrawingStroke stroke => stroke.copyWith(
        size: math.max(0.1, stroke.size * uniform),
        points: stroke.points.map((point) {
          final mapped = mapPoint(point.offset);
          return point.copyWith(x: mapped.dx, y: mapped.dy);
        }).toList(),
      ),
      VectorShapeObject shape => shape.copyWith(
        strokeWidth: math.max(0.0, shape.strokeWidth * uniform),
        points: shape.points.map(mapPoint).toList(),
      ),
      TextObjectData text => text.copyWith(
        x: mapPoint(Offset(text.x, text.y)).dx,
        y: mapPoint(Offset(text.x, text.y)).dy,
        width: math.max(1.0, text.width * sx.abs()),
        fontSize: math.max(1.0, text.fontSize * sy.abs()),
        outlineWidth: math.max(0.0, text.outlineWidth * uniform),
      ),
      MangaPanelCut panel => panel.copyWith(
        rect: mapRect(panel.rect),
        borderWidth: math.max(0.1, panel.borderWidth * uniform),
      ),
      SpeechBalloon balloon => balloon.copyWith(
        position: mapPoint(balloon.position),
        size: Size(
          math.max(1.0, balloon.size.width * sx.abs()),
          math.max(1.0, balloon.size.height * sy.abs()),
        ),
        tailTarget: mapPoint(balloon.tailTarget),
        fontSize: math.max(1.0, balloon.fontSize * sy.abs()),
        borderWidth: math.max(0.1, balloon.borderWidth * uniform),
      ),
      _ => item,
    };
  }

  static Object rotate(Object item, double angle, Offset pivot) {
    if (angle == 0.0) return item;
    final bounds = FocusStudioItemGeometry.boundsOf(item);
    if (bounds == null) return item;
    final center = bounds.center;
    final rotatedCenter = _rotate(center, pivot, angle);
    final translation = rotatedCenter - center;
    final balloonCenter = item is SpeechBalloon
        ? Offset(
            item.position.dx + item.size.width / 2,
            item.position.dy + item.size.height / 2,
          )
        : Offset.zero;

    return switch (item) {
      DrawingStroke stroke => stroke.copyWith(
        points: stroke.points.map((point) {
          final rotated = _rotate(point.offset, pivot, angle);
          return point.copyWith(x: rotated.dx, y: rotated.dy);
        }).toList(),
      ),
      VectorShapeObject shape => shape.copyWith(
        points: shape.points.map((point) => point + translation).toList(),
        rotation: shape.rotation + angle,
      ),
      TextObjectData text => text.copyWith(
        x: text.x + translation.dx,
        y: text.y + translation.dy,
        rotation: text.rotation + angle,
      ),
      MangaPanelCut panel => panel.copyWith(
        rect: panel.rect.shift(translation),
        rotation: panel.rotation + angle,
      ),
      SpeechBalloon balloon => balloon.copyWith(
        position:
            balloon.position +
            (_rotate(balloonCenter, pivot, angle) - balloonCenter),
        tailTarget: _rotate(balloon.tailTarget, pivot, angle),
        rotation: balloon.rotation + angle,
      ),
      _ => item,
    };
  }

  static DrawingPaperPayload applyUpdates(
    DrawingPaperPayload payload,
    Map<FocusStudioItemReference, Object> updates,
  ) {
    if (updates.isEmpty) return payload;
    final layers = List<DrawingLayer>.from(payload.layers);
    for (var index = 0; index < layers.length; index++) {
      final layer = layers[index];
      final strokes = layer.strokes
          .map(
            (stroke) =>
                updates[FocusStudioItemReference.drawingStroke(
                      layerId: layer.id,
                      objectId: stroke.id,
                    )]
                    as DrawingStroke? ??
                stroke,
          )
          .toList();
      final shapes = layer.shapes
          .map(
            (shape) =>
                updates[FocusStudioItemReference.vectorShapeObject(
                      layerId: layer.id,
                      objectId: shape.id,
                    )]
                    as VectorShapeObject? ??
                shape,
          )
          .toList();
      final texts = layer.texts
          .map(
            (text) =>
                updates[FocusStudioItemReference.textObject(
                      layerId: layer.id,
                      objectId: text.id,
                    )]
                    as TextObjectData? ??
                text,
          )
          .toList();
      layers[index] = layer.copyWith(
        strokes: strokes,
        shapes: shapes,
        texts: texts,
      );
    }

    final structure = payload.mangaStructure;
    MangaStructure? updatedStructure;
    if (structure != null) {
      updatedStructure = structure.copyWith(
        panels: structure.panels
            .map(
              (panel) =>
                  updates[FocusStudioItemReference.mangaPanelCut(
                        objectId: panel.id,
                      )]
                      as MangaPanelCut? ??
                  panel,
            )
            .toList(),
        balloons: structure.balloons
            .map(
              (balloon) =>
                  updates[FocusStudioItemReference.speechBalloon(
                        objectId: balloon.id,
                      )]
                      as SpeechBalloon? ??
                  balloon,
            )
            .toList(),
      );
    }
    return payload.copyWith(layers: layers, mangaStructure: updatedStructure);
  }

  static DrawingPaperPayload remove(
    DrawingPaperPayload payload,
    Set<FocusStudioItemReference> references,
  ) {
    if (references.isEmpty) return payload;
    final layers = payload.layers
        .map(
          (layer) => layer.copyWith(
            strokes: layer.strokes
                .where(
                  (stroke) => !references.contains(
                    FocusStudioItemReference.drawingStroke(
                      layerId: layer.id,
                      objectId: stroke.id,
                    ),
                  ),
                )
                .toList(),
            shapes: layer.shapes
                .where(
                  (shape) => !references.contains(
                    FocusStudioItemReference.vectorShapeObject(
                      layerId: layer.id,
                      objectId: shape.id,
                    ),
                  ),
                )
                .toList(),
            texts: layer.texts
                .where(
                  (text) => !references.contains(
                    FocusStudioItemReference.textObject(
                      layerId: layer.id,
                      objectId: text.id,
                    ),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final structure = payload.mangaStructure;
    return payload.copyWith(
      layers: layers,
      mangaStructure: structure?.copyWith(
        panels: structure.panels
            .where(
              (panel) => !references.contains(
                FocusStudioItemReference.mangaPanelCut(objectId: panel.id),
              ),
            )
            .toList(),
        balloons: structure.balloons
            .where(
              (balloon) => !references.contains(
                FocusStudioItemReference.speechBalloon(objectId: balloon.id),
              ),
            )
            .toList(),
      ),
    );
  }

  static DrawingPaperPayload addClipboardItems(
    DrawingPaperPayload payload,
    List<FocusStudioClipboardItem> items,
  ) {
    if (items.isEmpty) return payload;
    final layers = List<DrawingLayer>.from(payload.layers);
    final panels = List<MangaPanelCut>.from(
      payload.mangaStructure?.panels ?? const [],
    );
    final balloons = List<SpeechBalloon>.from(
      payload.mangaStructure?.balloons ?? const [],
    );

    for (final entry in items) {
      final item = entry.item;
      final reference = entry.reference;
      if (item is MangaPanelCut) {
        panels.add(item);
      } else if (item is SpeechBalloon) {
        balloons.add(item);
      } else if (reference.layerId != null) {
        final layerIndex = layers.indexWhere(
          (layer) => layer.id == reference.layerId,
        );
        if (layerIndex == -1) continue;
        final layer = layers[layerIndex];
        layers[layerIndex] = switch (item) {
          DrawingStroke stroke => layer.copyWith(
            strokes: [...layer.strokes, stroke],
          ),
          VectorShapeObject shape => layer.copyWith(
            shapes: [...layer.shapes, shape],
          ),
          TextObjectData text => layer.copyWith(texts: [...layer.texts, text]),
          _ => layer,
        };
      }
    }

    final structure = payload.mangaStructure;
    final hasStructureItems = panels.isNotEmpty || balloons.isNotEmpty;
    return payload.copyWith(
      layers: layers,
      mangaStructure: structure == null && !hasStructureItems
          ? null
          : MangaStructure(
              panels: panels,
              balloons: balloons,
              gutterHorizontal: structure?.gutterHorizontal ?? 18.0,
              gutterVertical: structure?.gutterVertical ?? 12.0,
            ),
    );
  }

  static bool isLayerVisible(DrawingPaperPayload payload, DrawingLayer layer) {
    if (!layer.visible) return false;
    final visited = <String>{};
    var parentId = layer.parentFolderId;
    while (parentId != null && visited.add(parentId)) {
      final parent = payload.layers.firstWhere(
        (candidate) => candidate.id == parentId,
        orElse: () => const DrawingLayer(id: '', name: '', visible: false),
      );
      if (!parent.visible) return false;
      parentId = parent.parentFolderId;
    }
    return true;
  }

  static bool isLayerEditable(DrawingPaperPayload payload, DrawingLayer layer) {
    if (layer.locked || !isLayerVisible(payload, layer)) return false;
    final visited = <String>{};
    var parentId = layer.parentFolderId;
    while (parentId != null && visited.add(parentId)) {
      final parent = payload.layers.firstWhere(
        (candidate) => candidate.id == parentId,
        orElse: () => const DrawingLayer(id: '', name: '', locked: true),
      );
      if (parent.locked ||
          (parent.type == LayerType.folder && !parent.visible)) {
        return false;
      }
      parentId = parent.parentFolderId;
    }
    return true;
  }

  static Offset _rotate(Offset point, Offset pivot, double angle) {
    final dx = point.dx - pivot.dx;
    final dy = point.dy - pivot.dy;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
      pivot.dx + dx * cosA - dy * sinA,
      pivot.dy + dx * sinA + dy * cosA,
    );
  }
}
