import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  group('NestedBoardPayload Model & Serialization Tests', () {
    test('NestedBoardPayload default initialization has correct values', () {
      final payload = NestedBoardPayload();
      expect(payload.boardName, 'Sub-Project Moodboard');
      expect(payload.childNodeCount, 0);
      expect(payload.subNodes, isEmpty);
      expect(payload.subEdges, isEmpty);
      expect(payload.tags, isEmpty);
      expect(payload.iconEmoji, '🗂');
      expect(payload.showGridPreview, isTrue);
    });

    test(
      'NestedBoardPayload serialization and deserialization with subNodes',
      () {
        final subNode = CanvasNode(
          id: 'sub_1',
          type: NodeType.stickyNote,
          name: 'Inner Note',
          x: 10,
          y: 20,
          width: 100,
          height: 80,
          payload: StickyNotePayload(text: 'Hello sub canvas'),
        );

        final payload = NestedBoardPayload(
          boardName: 'Brand Strategy Board',
          description: 'Nested moodboard for brand assets',
          tags: ['Design', 'Sprint1'],
          iconEmoji: '🚀',
          subNodes: [subNode],
          backgroundColor: const Color(0xFF1E1B4B),
          borderColor: const Color(0xFF818CF8),
        );

        final json = payload.toJson();
        expect(json['boardName'], 'Brand Strategy Board');
        expect(json['description'], 'Nested moodboard for brand assets');
        expect(json['childNodeCount'], 1);
        expect(json['iconEmoji'], '🚀');
        expect((json['tags'] as List).length, 2);

        final deserialized = NestedBoardPayload.fromJson(json);
        expect(deserialized.boardName, 'Brand Strategy Board');
        expect(deserialized.description, 'Nested moodboard for brand assets');
        expect(deserialized.subNodes.length, 1);
        expect(deserialized.subNodes.first.id, 'sub_1');
        expect(deserialized.subNodes.first.name, 'Inner Note');
        expect(deserialized.childNodeCount, 1);
      },
    );

    test('NestedBoardPayload copyWith and clone work correctly', () {
      final original = NestedBoardPayload(
        boardName: 'Original Board',
        tags: ['Alpha'],
        iconEmoji: '📁',
      );

      final cloned = original.clone();
      expect(cloned.boardName, original.boardName);
      expect(cloned.tags, original.tags);
      expect(cloned.iconEmoji, original.iconEmoji);

      final updated = original.copyWith(
        boardName: 'Updated Board',
        iconEmoji: '🎨',
      );
      expect(updated.boardName, 'Updated Board');
      expect(updated.iconEmoji, '🎨');
      expect(updated.tags, original.tags);
    });
  });

  group('NestedBoard Canvas Painter Tests', () {
    testWidgets('NodePainter renders NestedBoard node without throwing', (
      tester,
    ) async {
      final subNode = CanvasNode(
        id: 'sub_note',
        type: NodeType.stickyNote,
        name: 'Mini Note',
        x: 0,
        y: 0,
        width: 60,
        height: 40,
        payload: StickyNotePayload(text: 'Mini'),
      );

      final node = CanvasNode(
        id: 'nested_1',
        type: NodeType.nestedBoard,
        name: 'Product Specs',
        x: 50,
        y: 50,
        width: 280,
        height: 180,
        payload: NestedBoardPayload(
          boardName: 'Product Specs Board',
          subNodes: [subNode],
          tags: ['Tech'],
          iconEmoji: '🗂',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              size: const Size(400, 300),
              painter: _TestNestedBoardPainter(node: node),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}

class _TestNestedBoardPainter extends CustomPainter {
  final CanvasNode node;
  _TestNestedBoardPainter({required this.node});

  @override
  void paint(Canvas canvas, Size size) {
    NodePainter.paint(canvas, node);
  }

  @override
  bool shouldRepaint(covariant _TestNestedBoardPainter oldDelegate) => true;
}
