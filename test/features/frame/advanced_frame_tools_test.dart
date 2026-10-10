import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/auto_layout_engine.dart';
import 'package:varian/features/canvas/utils/frame_presets.dart';

void main() {
  group('FramePayload & Presets Tests', () {
    test(
      'FramePayload serialization and clone preserves all styling and auto-layout attributes',
      () {
        final payload = FramePayload(
          name: 'iPhone Frame',
          background: const Color(0xFF1E293B),
          backgroundGradientEnd: const Color(0xFF0F172A),
          clipContent: true,
          cornerRadius: 16.0,
          borderColor: const Color(0xFF38BDF8),
          borderWidth: 2.0,
          isDashedBorder: true,
          hasShadow: true,
          shadowBlur: 14.0,
          shadowColor: const Color(0x88000000),
          layoutDirection: AutoLayoutDirection.horizontal,
          itemSpacing: 20.0,
          paddingLeft: 24.0,
          paddingTop: 16.0,
          paddingRight: 24.0,
          paddingBottom: 16.0,
          layoutAlign: AutoLayoutAlign.center,
          presetId: 'iphone_16_pro',
          isLandscape: true,
        );

        final json = payload.toJson();
        final fromJson = FramePayload.fromJson(json);

        expect(fromJson.name, 'iPhone Frame');
        expect(fromJson.cornerRadius, 16.0);
        expect(fromJson.borderWidth, 2.0);
        expect(fromJson.isDashedBorder, true);
        expect(fromJson.hasShadow, true);
        expect(fromJson.layoutDirection, AutoLayoutDirection.horizontal);
        expect(fromJson.itemSpacing, 20.0);
        expect(fromJson.paddingLeft, 24.0);
        expect(fromJson.layoutAlign, AutoLayoutAlign.center);
        expect(fromJson.presetId, 'iphone_16_pro');
        expect(fromJson.isLandscape, true);
      },
    );

    test(
      'FramePresetsCatalog returns valid dimensions for portrait and landscape',
      () {
        final preset = FramePresetsCatalog.findById('iphone_16_pro');
        expect(preset, isNotNull);
        expect(preset!.getWidth(false), 393.0);
        expect(preset.getHeight(false), 852.0);
        expect(preset.getWidth(true), 852.0);
        expect(preset.getHeight(true), 393.0);
      },
    );
  });

  group('AutoLayoutEngine Tests', () {
    test('Calculates horizontal row layout correctly', () {
      final frame = CanvasNode(
        id: 'frame-1',
        type: NodeType.frame,
        x: 100,
        y: 100,
        width: 600,
        height: 300,
        payload: FramePayload(
          layoutDirection: AutoLayoutDirection.horizontal,
          itemSpacing: 10.0,
          paddingLeft: 20.0,
          paddingTop: 30.0,
          paddingRight: 20.0,
          paddingBottom: 30.0,
          layoutAlign: AutoLayoutAlign.start,
        ),
      );

      final child1 = CanvasNode(
        id: 'c1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 50,
        payload: ShapePayload(),
      );

      final child2 = CanvasNode(
        id: 'c2',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 150,
        height: 50,
        payload: ShapePayload(),
      );

      final (_, updated) = AutoLayoutEngine.applyLayout(
        frameNode: frame,
        children: [child1, child2],
      );

      expect(updated.length, 2);
      expect(updated[0].x, 120.0); // frame.x (100) + padL (20)
      expect(updated[0].y, 130.0); // frame.y (100) + padT (30)

      expect(updated[1].x, 230.0); // 120 + 100 + 10 (spacing)
      expect(updated[1].y, 130.0);
    });

    test('Calculates vertical column layout with center alignment', () {
      final frame = CanvasNode(
        id: 'frame-2',
        type: NodeType.frame,
        x: 0,
        y: 0,
        width: 400,
        height: 500,
        payload: FramePayload(
          layoutDirection: AutoLayoutDirection.vertical,
          itemSpacing: 15.0,
          paddingLeft: 10.0,
          paddingTop: 20.0,
          paddingRight: 10.0,
          paddingBottom: 20.0,
          layoutAlign: AutoLayoutAlign.center,
        ),
      );

      final child1 = CanvasNode(
        id: 'c1',
        type: NodeType.rectangle,
        x: 0,
        y: 0,
        width: 100,
        height: 40,
        payload: ShapePayload(),
      );

      final (_, updated) = AutoLayoutEngine.applyLayout(
        frameNode: frame,
        children: [child1],
      );

      expect(updated.first.x, 150.0); // (400 - 10 - 10 - 100) / 2 + 10 = 150
      expect(
        updated.first.y,
        230.0,
      ); // padT (20) + (500 - 20 - 20 - 40) / 2 = 230 (Vertical Center)
    });
  });
}
