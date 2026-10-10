import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/canvas/domain/command_palette.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('command catalog searches title, keywords, and shortcut', () {
    final commands = CanvasCommandCatalog.core();

    expect(
      commands.where((command) => command.matches('grid')).single.id,
      'view.precision_settings',
    );
    expect(
      commands.where((command) => command.matches('Ctrl/Cmd+F')).single.id,
      'canvas.search',
    );
  });

  test('read-only catalog disables mutating commands', () {
    final commands = CanvasCommandCatalog.core(
      readOnly: true,
      hasSelection: true,
    );

    expect(
      commands.firstWhere((command) => command.id == 'history.undo').enabled,
      isFalse,
    );
    expect(
      commands
          .firstWhere((command) => command.id == 'selection.delete')
          .enabled,
      isFalse,
    );
    expect(
      commands.firstWhere((command) => command.id == 'canvas.search').enabled,
      isTrue,
    );
  });

  test('tool history keeps most recent unique tools and caps entries', () {
    var history = const CanvasToolHistory();
    history = history.record('select', now: DateTime.utc(2026, 1, 1));
    history = history.record('rectangle', now: DateTime.utc(2026, 1, 2));
    history = history.record('select', now: DateTime.utc(2026, 1, 3));

    expect(history.recentToolIds, ['select', 'rectangle']);
    expect(history.entries.first.useCount, 2);
    expect(
      CanvasToolHistory.fromJson(history.encode()).recentToolIds,
      history.recentToolIds,
    );
  });

  test(
    'active tool notifier records tool history when attached to a container',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeToolProvider.notifier).setTool(CanvasTool.pen);

      expect(container.read(activeToolProvider), CanvasTool.pen);
      expect(
        container.read(canvasToolHistoryProvider).single.toolId,
        CanvasTool.pen.name,
      );
    },
  );
}
