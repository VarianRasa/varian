import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  group('Enhanced TodoList Feature Suite', () {
    test('TodoItem serializes and deserializes priority and tags', () {
      final item = TodoItem(
        id: 't1',
        text: 'Review Design System',
        isDone: true,
        dueDate: '2026-09-01',
        assignee: 'Alex',
        priority: TodoPriority.high,
        tags: ['ui', 'critical'],
      );

      final json = item.toJson();
      expect(json['priority'], equals('high'));
      expect(json['tags'], equals(['ui', 'critical']));

      final restored = TodoItem.fromJson(json);
      expect(restored.id, equals('t1'));
      expect(restored.text, equals('Review Design System'));
      expect(restored.isDone, isTrue);
      expect(restored.priority, equals(TodoPriority.high));
      expect(restored.tags, equals(['ui', 'critical']));
    });

    test(
      'TodoListPayload handles backward compatibility and new visual properties',
      () {
        final legacyJson = {
          'title': 'Sprint Sprint',
          'items': [
            {'id': '1', 'text': 'Task A', 'isDone': false},
          ],
        };

        final payload = TodoListPayload.fromJson(legacyJson);
        expect(payload.title, equals('Sprint Sprint'));
        expect(payload.items.length, equals(1));
        expect(payload.items.first.priority, equals(TodoPriority.none));
        expect(payload.borderWidth, equals(1.2));
        expect(payload.cornerRadius, equals(8.0));
        expect(payload.hasShadow, isTrue);
        expect(payload.showProgressBar, isTrue);
        expect(payload.filterMode, equals('all'));
      },
    );

    test('TodoListPayload clone and copyWith preserves extended styling', () {
      final original = TodoListPayload(
        title: 'Launch Prep',
        items: [
          TodoItem(
            id: '1',
            text: 'Build',
            isDone: false,
            priority: TodoPriority.medium,
          ),
        ],
        filterMode: 'active',
        showProgressBar: false,
      );

      final cloned = original.clone();
      expect(cloned.title, equals('Launch Prep'));
      expect(cloned.filterMode, equals('active'));
      expect(cloned.showProgressBar, isFalse);

      final updated = original.copyWith(filterMode: 'completed');
      expect(updated.filterMode, equals('completed'));
      expect(original.filterMode, equals('active'));
    });
  });
}
