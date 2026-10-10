import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/presentation/capture_inbox_panel.dart';
import 'package:varian/features/capture/state/capture_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('captures typed text and displays it in the inbox', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'New reference');
    await tester.tap(find.byKey(const ValueKey('capture-inbox-submit')));
    await tester.pumpAndSettle();
    expect(find.text('New reference'), findsWidgets);
  });
  testWidgets('inbox separators use the shared thin border', (tester) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    await repository.createCapture(CaptureInput.text('Separator fixture'));
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(
      dividers.map((divider) => divider.height),
      everyElement(AppBorder.thin),
    );
  });
  testWidgets(
    'empty state fits the panel and list stays within compact height',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final emptyRepository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      await tester.pumpWidget(_host(emptyRepository));
      await tester.pumpAndSettle();
      final emptyState = find.ancestor(
        of: find.text('Your inbox is empty.'),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(emptyState.first).height, 44);

      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      for (var index = 0; index < 8; index++) {
        await repository.createCapture(
          CaptureInput.text('Compact capture $index'),
        );
      }
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      final list = find.byKey(const ValueKey('capture-inbox-list'));
      final listRect = tester.getRect(list);
      expect(listRect.height, 200);
      expect(listRect.left, greaterThanOrEqualTo(0));
      expect(listRect.right, lessThanOrEqualTo(320));
      expect(listRect.bottom, lessThanOrEqualTo(568));

      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();
      expect(tester.getRect(list).height, 176);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('loading and error states retain their compact row height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final delayedPreferences = _DelayedCapturePreferences();
    final loadingRepository = LocalCaptureRepository(
      preferenceStore: delayedPreferences,
      assetStore: MemoryCaptureAssetStore(),
    );
    await tester.pumpWidget(_host(loadingRepository));
    await tester.pump();
    final loadingRow = find.ancestor(
      of: find.bySemanticsLabel('Loading captures'),
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(loadingRow.first).height, 44);

    delayedPreferences.readResult.complete(null);
    await tester.pumpAndSettle();
    final emptyRow = find.ancestor(
      of: find.text('Your inbox is empty.'),
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(emptyRow.first).height, 44);

    final failedRepository = LocalCaptureRepository(
      preferenceStore: _FailingCapturePreferences(),
      assetStore: MemoryCaptureAssetStore(),
    );
    await tester.pumpWidget(_host(failedRepository));
    await tester.pumpAndSettle();
    final errorRow = find.ancestor(
      of: find.text('Could not load local captures.'),
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(errorRow.first).height, 44);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capture row remains readable and accessible in a compact viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      await repository.createCapture(CaptureInput.text('Compact note'));
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      final title = find.text('Compact note').first;
      final actions = find.byTooltip('Capture actions');
      expect(find.text('Compact note'), findsNWidgets(2));
      expect(actions, findsOneWidget);
      expect(tester.getRect(title).top, greaterThanOrEqualTo(0));
      expect(
        tester.getSize(actions),
        const Size(
          AppControlSize.minimumHitTarget,
          AppControlSize.minimumHitTarget,
        ),
      );
      expect(tester.getRect(actions).right, lessThanOrEqualTo(320));
      expect(tester.getRect(title).bottom, lessThanOrEqualTo(568));
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.text('Mark read'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('groups capture row actions in an overflow menu', (tester) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(
      CaptureInput.text('Read this later'),
    );
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Capture actions'), findsOneWidget);
    expect(find.byTooltip('Add to canvas'), findsNothing);
    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();

    expect(find.text('Add to canvas'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);
    expect(find.text('Add favorite'), findsOneWidget);
    expect(find.text('Move capture to Trash'), findsOneWidget);

    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();

    expect((await repository.getCapture(item.id))?.isRead, isTrue);
  });

  testWidgets('restores and purges deleted captures from the overflow menu', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(
      CaptureInput.text('Delete after restoring'),
    );
    await repository.deleteCapture(item.id);
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('capture-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    expect(find.text('Restore capture'), findsOneWidget);
    expect(find.text('Purge capture permanently'), findsOneWidget);
    await tester.tap(find.text('Restore capture'));
    await tester.pumpAndSettle();
    expect((await repository.getCapture(item.id))?.status, CaptureStatus.ready);

    await tester.tap(find.byKey(const ValueKey('capture-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All captures'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move capture to Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capture-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purge capture permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Purge this capture?'), findsOneWidget);
    await tester.tap(find.text('PURGE'));
    await tester.pumpAndSettle();
    expect(await repository.getCapture(item.id), isNull);
  });

  testWidgets('shows an empty state without creating an item', (tester) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    expect(find.text('Your inbox is empty.'), findsOneWidget);
    expect(await repository.listCaptures(), isEmpty);
  });

  testWidgets('shows soft-deleted captures under Trash and restores them', (
    tester,
  ) async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(
      CaptureInput.text('Saved before deletion'),
    );
    await repository.deleteCapture(item.id);
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    expect(find.text('Your inbox is empty.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('capture-filter-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox trash'));
    await tester.pumpAndSettle();
    expect(find.text('Saved before deletion'), findsWidgets);
    await tester.tap(find.byTooltip('Capture actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore capture'));
    await tester.pumpAndSettle();
    expect(find.text('Trash is empty.'), findsOneWidget);
    expect((await repository.getCapture(item.id))?.status.name, 'ready');
  });
}

Widget _host(LocalCaptureRepository repository) => ProviderScope(
  key: ValueKey(repository),
  overrides: [captureRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    builder: (context, child) => AppThemeScope(
      data: AppTheme.darkTheme,
      child: SizedBox(child: child ?? const SizedBox.shrink()),
    ),
    home: const CaptureInboxPanel(),
  ),
);

class _DelayedCapturePreferences implements CapturePreferences {
  final readResult = Completer<String?>();

  @override
  Future<String?> read(String key) => readResult.future;

  @override
  Future<bool> write(String key, String value) async => true;
}

class _FailingCapturePreferences implements CapturePreferences {
  @override
  Future<String?> read(String key) async =>
      throw StateError('fixture read failure');

  @override
  Future<bool> write(String key, String value) async => true;
}
