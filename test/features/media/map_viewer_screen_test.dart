import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/map_viewer_screen.dart';
import 'package:varian/features/media/map_location_service.dart';
import '../../test_app.dart';

void main() {
  Future<void> pumpMapScreen(
    WidgetTester tester,
    Size size, {
    MapLocationService? locationService,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      testApp(
        MapViewerScreen(
          initialPayload: MapPayload(),
          onSaveAndExit: (_) {},
          locationService: locationService,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('stacks location fields on compact screens', (tester) async {
    await pumpMapScreen(tester, const Size(390, 844));

    final fields = find.byType(UiTextField);
    expect(fields, findsNWidgets(3));
    final titleRect = tester.getRect(fields.at(1));
    final addressRect = tester.getRect(fields.at(2));
    expect(titleRect.bottom, lessThanOrEqualTo(addressRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps location fields side by side on wide screens', (
    tester,
  ) async {
    await pumpMapScreen(tester, const Size(900, 700));

    final fields = find.byType(UiTextField);
    expect(fields, findsNWidgets(3));
    final titleRect = tester.getRect(fields.at(1));
    final addressRect = tester.getRect(fields.at(2));
    expect(titleRect.right, lessThanOrEqualTo(addressRect.left));
    expect(tester.takeException(), isNull);
  });
  testWidgets('sets a map point from accessible coordinates', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMapScreen(
      tester,
      const Size(390, 844),
      locationService: _NoopMapLocationService(),
    );
    await tester.tap(find.text('Set coordinates manually'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('map-latitude-field')),
        matching: find.byType(TextFormField),
      ),
      '35.68',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('map-longitude-field')),
        matching: find.byType(TextFormField),
      ),
      '139.76',
    );
    await tester.tap(find.text('Update map location'));
    await tester.pump();

    expect(
      find.bySemanticsLabel('Selected map coordinates: 35.680000, 139.760000'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('rejects coordinates outside geographic bounds', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMapScreen(
      tester,
      const Size(390, 844),
      locationService: _NoopMapLocationService(),
    );

    await tester.tap(find.text('Set coordinates manually'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('map-latitude-field')),
        matching: find.byType(TextFormField),
      ),
      '-91',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('map-longitude-field')),
        matching: find.byType(TextFormField),
      ),
      '181',
    );
    await tester.tap(find.text('Update map location'));
    await tester.pump();

    expect(find.text('Enter a latitude from -90 to 90.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Selected map coordinates: 35.676200, 139.650300'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('keeps map controls usable in a short compact viewport', (
    tester,
  ) async {
    await pumpMapScreen(
      tester,
      const Size(320, 320),
      locationService: _NoopMapLocationService(),
    );

    await tester.tap(find.text('Set coordinates manually'));
    await tester.pump();
    final latitudeField = find.byKey(const ValueKey('map-latitude-field'));
    final longitudeField = find.byKey(const ValueKey('map-longitude-field'));
    await tester.ensureVisible(latitudeField);
    await tester.enterText(
      find.descendant(of: latitudeField, matching: find.byType(TextFormField)),
      '35.68',
    );
    await tester.ensureVisible(longitudeField);
    await tester.enterText(
      find.descendant(of: longitudeField, matching: find.byType(TextFormField)),
      '139.76',
    );
    final applyCoordinates = find.text('Update map location');
    await tester.ensureVisible(applyCoordinates);
    await tester.tap(applyCoordinates);
    await tester.pump();

    expect(
      find.bySemanticsLabel('Selected map coordinates: 35.680000, 139.760000'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('announces progress labels as live semantics updates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        const UiProgressIndicator(semanticsLabel: 'Loading embedded page'),
      ),
    );

    final progressSemantics = tester.getSemantics(
      find.byType(UiProgressIndicator),
    );
    expect(progressSemantics.label, 'Loading embedded page');
    expect(progressSemantics.flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
  });
}

class _NoopMapLocationService extends MapLocationService {
  @override
  Future<MapLocationResult?> reverse(double latitude, double longitude) async =>
      null;

  @override
  Future<List<MapLocationResult>> search(String query) async => const [];
}
