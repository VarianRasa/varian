import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  group('ColumnPayload & ColumnCardItem Model Tests', () {
    test('default initialization has proper values', () {
      final payload = ColumnPayload();
      expect(payload.headerTitle, 'In Progress');
      expect(payload.cards.length, 3);
      expect(payload.wipLimit, 0);
      expect(payload.isCollapsed, false);
      expect(payload.filterMode, 'all');
      expect(payload.itemTitles, [
        'Review UI spec',
        'Build wireframe',
        'Export assets',
      ]);
    });

    test('toJson and fromJson preserves data integrity', () {
      final original = ColumnPayload(
        headerTitle: 'Done Stage',
        headerColor: const Color(0xFF10B981),
        wipLimit: 5,
        isCollapsed: false,
        backgroundColor: const Color(0xFF1A1C22),
        borderColor: const Color(0xFF3B82F6),
        borderWidth: 2.0,
        cornerRadius: 8.0,
        hasShadow: true,
        showProgressBar: true,
        filterMode: 'active',
        cards: const [
          ColumnCardItem(
            id: 'c_1',
            title: 'Design Logo',
            description: 'Vector SVG',
            isDone: true,
            priority: ColumnCardPriority.high,
            tags: ['Branding', 'Design'],
            dueDate: '2026-09-01',
            assignee: 'alex',
            cardColor: Color(0xFFEF4444),
          ),
          ColumnCardItem(
            id: 'c_2',
            title: 'Write Docs',
            priority: ColumnCardPriority.low,
          ),
        ],
      );

      final json = original.toJson();
      final restored = ColumnPayload.fromJson(json);

      expect(restored.headerTitle, 'Done Stage');
      expect(
        restored.headerColor.toARGB32(),
        const Color(0xFF10B981).toARGB32(),
      );
      expect(restored.wipLimit, 5);
      expect(restored.filterMode, 'active');
      expect(restored.cards.length, 2);

      final firstCard = restored.cards[0];
      expect(firstCard.id, 'c_1');
      expect(firstCard.title, 'Design Logo');
      expect(firstCard.description, 'Vector SVG');
      expect(firstCard.isDone, true);
      expect(firstCard.priority, ColumnCardPriority.high);
      expect(firstCard.tags, ['Branding', 'Design']);
      expect(firstCard.dueDate, '2026-09-01');
      expect(firstCard.assignee, 'alex');
      expect(
        firstCard.cardColor?.toARGB32(),
        const Color(0xFFEF4444).toARGB32(),
      );
    });

    test('backward compatibility with itemTitles in fromJson', () {
      final legacyJson = {
        'headerTitle': 'Legacy Stage',
        'headerColor': 0xFF3B82F6,
        'itemTitles': ['Task A', 'Task B'],
      };

      final restored = ColumnPayload.fromJson(legacyJson);
      expect(restored.headerTitle, 'Legacy Stage');
      expect(restored.cards.length, 2);
      expect(restored.cards[0].title, 'Task A');
      expect(restored.cards[1].title, 'Task B');
      expect(restored.itemTitles, ['Task A', 'Task B']);
    });

    test('copyWith updates specific properties without altering others', () {
      final base = ColumnPayload();
      final modified = base.copyWith(
        headerTitle: 'Review Column',
        wipLimit: 3,
        isCollapsed: true,
      );

      expect(modified.headerTitle, 'Review Column');
      expect(modified.wipLimit, 3);
      expect(modified.isCollapsed, true);
      expect(modified.cards.length, base.cards.length);
    });

    test('clone returns deep copy of payload and cards', () {
      final base = ColumnPayload(
        cards: const [ColumnCardItem(id: 'c1', title: 'Task 1', isDone: false)],
      );
      final cloned = base.clone();

      expect(cloned.headerTitle, base.headerTitle);
      expect(cloned.cards.length, 1);
      expect(cloned.cards[0].title, 'Task 1');
      expect(identical(cloned.cards, base.cards), isFalse);
    });
  });

  group('Column Canvas Painting Tests', () {
    test('CanvasNode painter renders ColumnContainer without exceptions', () {
      final node = CanvasNode(
        id: 'node_col_1',
        type: NodeType.columnContainer,
        x: 100,
        y: 100,
        width: 240,
        height: 320,
        payload: ColumnPayload(
          headerTitle: 'Sprint 4',
          wipLimit: 2,
          cards: const [
            ColumnCardItem(
              id: '1',
              title: 'Feature Alpha',
              priority: ColumnCardPriority.high,
              tags: ['Core'],
              dueDate: '2026-08-30',
            ),
            ColumnCardItem(
              id: '2',
              title: 'Feature Beta',
              priority: ColumnCardPriority.medium,
              assignee: 'dev',
            ),
            ColumnCardItem(id: '3', title: 'QA Testing', isDone: true),
          ],
        ),
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);

      expect(() => NodePainter.paint(canvas, node), returnsNormally);
      final picture = recorder.endRecording();
      picture.dispose();
    });

    test(
      'CanvasNode painter renders Collapsed ColumnContainer without exceptions',
      () {
        final node = CanvasNode(
          id: 'node_col_2',
          type: NodeType.columnContainer,
          x: 0,
          y: 0,
          width: 200,
          height: 100,
          payload: ColumnPayload(
            headerTitle: 'Collapsed Lane',
            isCollapsed: true,
          ),
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);

        expect(() => NodePainter.paint(canvas, node), returnsNormally);
        final picture = recorder.endRecording();
        picture.dispose();
      },
    );
  });
}
