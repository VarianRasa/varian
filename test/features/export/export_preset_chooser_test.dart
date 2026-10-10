import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/presentation/export_preset_chooser.dart';

import '../../test_app.dart';

void main() {
  testWidgets('preset chooser returns selected preset without exporting', (
    tester,
  ) async {
    ExportPreset? selected;
    await tester.pumpWidget(
      testApp(
        StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(16),
            child: ExportPresetChooser(
              selected: selected ?? ExportPresetRegistry.json,
              presets: const [
                ExportPresetRegistry.json,
                ExportPresetRegistry.svg,
              ],
              onChanged: (preset) => setState(() => selected = preset),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Export format'), findsOneWidget);
    await tester.tap(find.text('Export JSON'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export SVG Vector').last);
    await tester.pumpAndSettle();

    expect(selected, same(ExportPresetRegistry.svg));
    expect(find.text('Export SVG Vector'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
