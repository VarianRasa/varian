import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../test_app.dart';

void main() {
  testWidgets('build editor-key wrapper', (tester) async {
    debugPrint('probe before pump');
    await tester.pumpWidget(
      testApp(
        const Scaffold(
          body: UiMenuButton<String>(
            key: Key('canvas-settings-menu'),
            tooltip: 'Settings',
            icon: Icons.settings,
            items: [],
            onSelected: _ignore,
          ),
        ),
      ),
    );
    debugPrint('probe after pumpWidget');
    await tester.pump();
    debugPrint('probe after pump');
    final finder = find.byKey(const Key('canvas-settings-menu'));
    debugPrint('probe before evaluate');
    final elements = finder.evaluate();
    debugPrint('probe after evaluate count=${elements.length}');
    final widget = elements.single.widget as UiMenuButton<String>;
    debugPrint('probe after cast=$widget');
    expect(widget.items, isEmpty);
  });
}

void _ignore(String _) {}
