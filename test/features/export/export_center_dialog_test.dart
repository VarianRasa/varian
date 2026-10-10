import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/export/presentation/export_center_dialog.dart';
import 'package:varian/features/export/export_presets.dart';

import '../../test_app.dart';

void main() {
  testWidgets('renders initial target and delegates changed choices', (
    tester,
  ) async {
    ExportTarget? target;
    ExportPreset? preset;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              initialPreset: ExportPresetRegistry.json,
              initialTarget: ExportTarget.selection,
              hasSelection: true,
              hasSelectedFrame: true,
              onExport: (selectedTarget, selectedPreset) async {
                target = selectedTarget;
                preset = selectedPreset;
                return ExportSaveOutcome.saved;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();

    expect(find.text('EXPORT CENTER'), findsOneWidget);
    expect(find.text('Export JSON'), findsOneWidget);
    final radios = tester
        .widgetList<UiRadioChoice>(find.byType(UiRadioChoice))
        .toList();
    expect(radios[1].value, isTrue);

    await tester.tap(find.bySemanticsLabel('Current canvas').first);
    await tester.tap(find.text('Export JSON'));
    await tester.pumpAndSettle();
    final presetMenu = find
        .ancestor(
          of: find.text('Export SVG Vector'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Export SVG Vector'),
      -100,
      scrollable: presetMenu,
    );
    await tester.tap(find.text('Export SVG Vector'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Save export'));
    await tester.pumpAndSettle();

    expect(target, ExportTarget.currentCanvas);
    expect(preset, same(ExportPresetRegistry.svg));
  });

  testWidgets('does not allow unavailable targets', (tester) async {
    ExportTarget? target;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              onExport: (selectedTarget, _) async {
                target = selectedTarget;
                return ExportSaveOutcome.saved;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();

    final radios = tester
        .widgetList<UiRadioChoice>(find.byType(UiRadioChoice))
        .toList();
    expect(radios[1].enabled, isFalse);
    expect(radios[2].enabled, isFalse);

    await tester.tap(find.bySemanticsLabel('Selection').first);
    await tester.tap(find.bySemanticsLabel('Selected frame').first);
    await tester.tap(find.bySemanticsLabel('Save export'));
    await tester.pumpAndSettle();

    expect(target, ExportTarget.currentCanvas);
  });

  testWidgets('shows loading state and closes with the save outcome', (
    tester,
  ) async {
    final saveCompleter = Completer<ExportSaveOutcome>();
    var calls = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              onExport: (_, _) {
                calls++;
                return saveCompleter.future;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Save export'));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Saving...'), findsOneWidget);
    expect(find.bySemanticsLabel('Saving export'), findsWidgets);

    saveCompleter.complete(ExportSaveOutcome.saved);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('catches export failures and keeps the dialog open', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              onExport: (_, _) async {
                throw StateError('save failed');
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Save export'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Export failed. Please try again.'), findsOneWidget);
    expect(find.bySemanticsLabel('Save export'), findsOneWidget);
  });
  testWidgets('export dialog stays within compact viewport bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              onExport: (_, _) async => ExportSaveOutcome.canceled,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final saveAction = find.bySemanticsLabel('Save export');
    await tester.ensureVisible(saveAction);
    final saveRect = tester.getRect(saveAction);
    expect(saveRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(saveRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(saveRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('export actions remain available on a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          _DialogLauncher(
            dialog: ExportCenterDialog(
              hasSelection: true,
              onExport: (_, _) async => ExportSaveOutcome.saved,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open export center'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.bySemanticsLabel('Save export'));
    expect(find.bySemanticsLabel('Cancel export'), findsOneWidget);
    expect(find.bySemanticsLabel('Save export'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DialogLauncher extends StatelessWidget {
  final ExportCenterDialog dialog;

  const _DialogLauncher({required this.dialog});

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<ExportSaveOutcome>(
      context: context,
      builder: (_) => dialog,
    ),
    child: const Text('Open export center'),
  );
}
