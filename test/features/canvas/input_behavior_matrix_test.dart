import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/domain/input_behavior_matrix.dart';

void main() {
  test('default input matrix covers every supported platform', () {
    final matrix = InputBehaviorMatrix.defaults();

    for (final platform in CanvasPlatform.values) {
      expect(matrix.forPlatform(platform), isNotEmpty);
    }
    expect(matrix.validate(), isEmpty);
  });

  test(
    'shortcut remapping replaces one command without duplicate bindings',
    () {
      final matrix = InputBehaviorMatrix.defaults().remap(
        'undo',
        const ShortcutBinding(command: 'undo', key: 'U', control: true),
      );

      expect(
        matrix.shortcuts
            .where((binding) => binding.command == 'undo')
            .single
            .key,
        'U',
      );
      expect(matrix.validate(), isEmpty);
    },
  );

  test('matrix reports conflicting shortcut assignments', () {
    const matrix = InputBehaviorMatrix(
      shortcuts: [
        ShortcutBinding(command: 'one', key: 'K', control: true),
        ShortcutBinding(command: 'two', key: 'K', control: true),
      ],
    );

    expect(matrix.validate(), hasLength(1));
  });
}
