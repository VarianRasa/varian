import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/features/components/domain/component_library.dart';
import 'package:varian/features/components/presentation/component_library_dialog.dart';

import 'package:varian/app/widgets/ui_primitives.dart';
import '../../test_app.dart';

CanvasNode _master() => CanvasNode(
  id: 'master-node',
  type: NodeType.component,
  x: 0,
  y: 0,
  width: 180,
  height: 56,
  payload: ComponentPayload(
    masterComponentId: 'button',
    componentName: 'Primary button',
    isMaster: true,
  ),
);

void main() {
  testWidgets('publishes a master and exposes insert only after publish', (
    tester,
  ) async {
    ComponentLibrary? changed;
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
          onLibraryChanged: (library) async => changed = library,
          onInsert: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Primary button'), findsOneWidget);
    expect(find.text('Insert'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('component-publish-button')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(changed?.entries['button']?.published, isTrue);
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('Insert'), findsOneWidget);
  });

  testWidgets('pins a component and filters the library to pinned entries', (
    tester,
  ) async {
    ComponentLibrary? changed;
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
          onLibraryChanged: (library) async => changed = library,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('component-pin-button')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(changed?.entries['button']?.pinned, isTrue);

    await tester.tap(find.byKey(const ValueKey('component-pinned-only')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('component-entry-button')),
      findsOneWidget,
    );
    expect(find.text('No pinned components found'), findsNothing);
  });
  testWidgets('component metadata follows the Material label-small role', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pump();

    final metadata = find.byWidgetPredicate(
      (widget) =>
          widget is Text && widget.data?.contains('/ v1 / Used 0x') == true,
    );
    final theme = Theme.of(tester.element(metadata));
    final tokens = theme.extension<AppTokens>()!;

    expect(
      tester.widget<Text>(metadata).style,
      theme.textTheme.labelSmall!.copyWith(color: tokens.textMuted),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('component title follows the Material body-medium role', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('Primary button');
    final theme = Theme.of(tester.element(title));
    expect(
      tester.widget<Text>(title).style,
      theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('component library stays within a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('component-library-dialog'));
    expect(dialog, findsOneWidget);
    final bounds = tester.getRect(dialog);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(360));
    expect(bounds.bottom, lessThanOrEqualTo(640));
    expect(find.text('Component Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('component library header reflows below 420 px', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Component Library'));
    final count = tester.getRect(find.text('1 components'));
    expect(count.top, greaterThanOrEqualTo(title.bottom));
    expect(count.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('component library header stays inline on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Component Library'));
    final count = tester.getRect(find.text('1 components'));
    expect(count.left, greaterThan(title.right));
    expect(count.center.dy, closeTo(title.center.dy, 1));
    expect(count.right, lessThanOrEqualTo(1000));
    expect(tester.takeException(), isNull);
  });
  testWidgets('component entry chrome follows shared surface tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: ComponentLibrary.discover([_master()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('component-entry-button'));
    final tokens = Theme.of(tester.element(entry)).extension<AppTokens>()!;
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    final dialogShape = dialog.shape! as RoundedRectangleBorder;
    expect(dialogShape.borderRadius, BorderRadius.circular(AppRadius.dialog));
    final surface = tester.widget<UiSurface>(entry);
    final actions = tester.widget<Wrap>(
      find.descendant(of: entry, matching: find.byType(Wrap)),
    );

    expect(surface.padding, const EdgeInsets.all(AppSpacing.md));
    expect(surface.color, tokens.panelElevated);
    expect(surface.borderWidth, AppBorder.thin);
    expect(actions.spacing, AppSpacing.sm);
    expect(actions.runSpacing, AppSpacing.sm);
    expect(tester.takeException(), isNull);
  });
  testWidgets('published component controls retain touch-sized chrome', (
    tester,
  ) async {
    final library = ComponentLibrary.discover([
      _master(),
    ]).setPublished('button', true);
    await tester.pumpWidget(
      testApp(
        ComponentLibraryDialog(
          nodes: [_master()],
          initialLibrary: library,
          onInsert: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey('component-entry-button'));
    final entryBounds = tester.getRect(entry);
    for (final key in [
      const ValueKey('component-pin-button'),
      const ValueKey('component-unpublish-button'),
      const ValueKey('component-insert-button'),
    ]) {
      final control = find.byKey(key);
      expect(control, findsOneWidget);
      final bounds = tester.getRect(control);
      expect(bounds.height, greaterThanOrEqualTo(AppControlSize.touch));
      expect(bounds.left, greaterThanOrEqualTo(entryBounds.left));
      expect(bounds.right, lessThanOrEqualTo(entryBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(entryBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(entryBounds.bottom));
    }
    expect(tester.takeException(), isNull);
  });
}
