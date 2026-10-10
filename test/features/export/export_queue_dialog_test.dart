import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_queue.dart';
import 'package:varian/features/export/presentation/export_queue_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('queue dialog and footer fit a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final queue = ExportQueue();
    addTearDown(queue.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => ExportQueueDialog(queue: queue),
              ),
              child: const Text('Open queue'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open queue'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final closeButton = find.widgetWithText(UiButton, 'Close').last;
    final closeRect = tester.getRect(closeButton);
    expect(closeRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(closeRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(closeRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows completed jobs and clears terminal history', (
    tester,
  ) async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () async =>
          const ExportPresetResult.text(ExportPresetRegistry.json, '{}'),
    );
    await queue.waitForIdle();

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          UiButton(
            onPressed: () => showUiDialog<void>(
              context: tester.element(find.byType(UiButton)),
              builder: (_) => ExportQueueDialog(queue: queue),
            ),
            child: const Text('Open queue'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open queue'));
    await tester.pumpAndSettle();

    expect(find.text('EXPORT QUEUE'), findsOneWidget);
    expect(find.text('Export JSON'), findsOneWidget);
    await tester.tap(find.text('Clear finished'));
    await tester.pumpAndSettle();
    expect(find.text('No export jobs yet.'), findsOneWidget);
  });
  testWidgets('announces queued job status as a live semantics update', (
    tester,
  ) async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    final taskStarted = Completer<void>();
    final completeTask = Completer<ExportPresetResult?>();
    queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () {
        taskStarted.complete();
        return completeTask.future;
      },
    );
    await taskStarted.future;

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          UiButton(
            onPressed: () => showUiDialog<void>(
              context: tester.element(find.byType(UiButton)),
              builder: (_) => ExportQueueDialog(queue: queue),
            ),
            child: const Text('Open queue'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open queue'));
    await tester.pumpAndSettle();

    final status = find.textContaining('running');
    expect(status, findsOneWidget);
    expect(tester.getSemantics(status).flagsCollection.isLiveRegion, isTrue);

    completeTask.complete(
      const ExportPresetResult.text(ExportPresetRegistry.json, '{}'),
    );
    await queue.waitForIdle();
    await tester.pumpAndSettle();
    expect(find.textContaining('completed'), findsOneWidget);
    semantics.dispose();
  });
}
