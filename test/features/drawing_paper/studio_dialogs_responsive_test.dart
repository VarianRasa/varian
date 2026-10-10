import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_canvas_controls_dialog.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_brush_settings_bar.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_layer_panel.dart';
import 'package:varian/features/drawing_paper/presentation/studio/widgets/studio_color_panel.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';
import '../../test_app.dart';

DrawingPaperPayload _payload() => DrawingPaperPayload(
  presetName: 'Test Paper',
  pixelWidth: 240,
  pixelHeight: 180,
);

void main() {
  testWidgets(
    'canvas controls scroll and preserve paper payload in short view',
    (tester) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final payload = _payload();

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showUiDialog<void>(
                  context: context,
                  builder: (_) =>
                      StudioCanvasControlsDialog(initialPayload: payload),
                ),
                child: const Text('Open controls'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open controls'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Canvas and view controls'), findsOneWidget);
      expect(
        tester.getSize(find.byType(Dialog).last).height,
        lessThanOrEqualTo(360),
      );
      final controlsDialog = tester.widget<Dialog>(find.byType(Dialog).last);
      expect(
        (controlsDialog.shape! as RoundedRectangleBorder).side.width,
        AppBorder.thin,
      );
      final controlsDivider = tester.widget<Divider>(
        find.descendant(
          of: find.byType(StudioCanvasControlsDialog),
          matching: find.byType(Divider),
        ),
      );
      expect(controlsDivider.thickness, AppBorder.thin);
      expect(tester.takeException(), isNull);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioCanvasControlsDialog)),
      );
      final gridSwitch = find.bySemanticsLabel('Show grid');
      await tester.ensureVisible(gridSwitch);
      await tester.tap(gridSwitch);
      await tester.pumpAndSettle();
      expect(
        container.read(drawingStudioProviderFamily(payload)).payload.showGrid,
        isTrue,
      );
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(drawingStudioProviderFamily(payload)).payload.pixelWidth,
        payload.pixelWidth,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'color swap control is keyboard focusable and swaps only colors',
    (tester) async {
      tester.view.physicalSize = const Size(420, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final payload = _payload();

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Scaffold(
              body: Center(child: StudioColorPanel(initialPayload: payload)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final swap = find.bySemanticsLabel('Swap primary and secondary colors');
      expect(swap, findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioColorPanel)),
      );
      final before = container.read(drawingStudioProviderFamily(payload));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final after = container.read(drawingStudioProviderFamily(payload));
      expect(after.primaryColor, before.secondaryColor);
      expect(after.secondaryColor, before.primaryColor);
      expect(after.payload.toJson(), before.payload.toJson());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'color swatches retain a touch-sized accessible target on compact screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final payload = _payload();

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Scaffold(
              body: Center(child: StudioColorPanel(initialPayload: payload)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final swatch = find.bySemanticsLabel('Set color ffec4899');
      expect(swatch, findsOneWidget);
      expect(
        tester.getSize(swatch).height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      Container swatchDecoration(Finder semantics) => tester.widget<Container>(
        find
            .descendant(
              of: semantics,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).border != null,
              ),
            )
            .last,
      );
      final selectedPreset = find.bySemanticsLabel('Set color ff000000');
      final selectedPresetSwatch = swatchDecoration(selectedPreset);
      expect(
        tester.getSize(
          find.descendant(
            of: selectedPreset,
            matching: find.byWidget(selectedPresetSwatch),
          ),
        ),
        const Size(AppControlSize.touch, AppControlSize.touch),
      );
      expect(
        (selectedPresetSwatch.decoration! as BoxDecoration).border!.top.width,
        AppBorder.focus,
      );
      final unselectedPresetSwatch = swatchDecoration(
        find.bySemanticsLabel('Set color ff3b82f6'),
      );
      expect(
        (unselectedPresetSwatch.decoration! as BoxDecoration).border!.top.width,
        AppBorder.thin,
      );
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      final recentSwatch = find.bySemanticsLabel('Use recent color #F97316');
      expect(recentSwatch, findsOneWidget);
      expect(
        tester.getSize(recentSwatch).height,
        greaterThanOrEqualTo(AppControlSize.minimumHitTarget),
      );
      await tester.tap(recentSwatch);
      await tester.pumpAndSettle();
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(StudioColorPanel)),
        ).read(drawingStudioProviderFamily(payload)).primaryColor,
        const Color(0xFFF97316),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'brush settings stay scrollable and expose accessible sliders on narrow view',
    (tester) async {
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final payload = _payload();

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 300,
                  child: StudioBrushSettingsBar(initialPayload: payload),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Size'), findsOneWidget);
      expect(find.bySemanticsLabel('Opacity'), findsOneWidget);
      expect(find.bySemanticsLabel('Stabilizer'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioBrushSettingsBar)),
      );
      final before = container.read(drawingStudioProviderFamily(payload));
      final stabilizer = find.bySemanticsLabel('Stabilizer');
      await tester.ensureVisible(stabilizer);
      final sliderRect = tester.getRect(stabilizer);
      expect(sliderRect.left, greaterThanOrEqualTo(0));
      expect(sliderRect.right, lessThanOrEqualTo(320));
      await tester.tapAt(Offset(sliderRect.right - 4, sliderRect.center.dy));
      await tester.pumpAndSettle();
      final after = container.read(drawingStudioProviderFamily(payload));
      expect(after.stabilizer, greaterThan(before.stabilizer));
      expect(after.payload.toJson(), before.payload.toJson());
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'layer menu duplicates selected layer and keyboard selects a layer',
    (tester) async {
      tester.view.physicalSize = const Size(420, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final payload = DrawingPaperPayload(
        presetName: 'Layer controls test',
        pixelWidth: 240,
        pixelHeight: 180,
        layers: const [
          DrawingLayer(id: 'top', name: 'Top', opacity: 0.75),
          DrawingLayer(id: 'bottom', name: 'Bottom'),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 280,
                  height: 560,
                  child: StudioLayerPanel(initialPayload: payload),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final top = find.bySemanticsLabel('Layer Top');
      final bottom = find.bySemanticsLabel('Layer Bottom');
      final layerNameStyle = tester.widget<Text>(find.text('Top')).style!;
      final layerNameTheme = Theme.of(
        tester.element(find.text('Top')),
      ).textTheme.labelSmall!;
      expect(layerNameStyle.fontFamily, layerNameTheme.fontFamily);
      expect(layerNameStyle.letterSpacing, layerNameTheme.letterSpacing);
      expect(top, findsOneWidget);
      expect(bottom, findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(top).flagsCollection.isButton, isTrue);
      expect(
        tester.getSemantics(top).flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(StudioLayerPanel)),
      );
      Focus.of(
        tester.element(find.byKey(const ValueKey('drawing-layer-row-bottom'))),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(
        container.read(drawingStudioProviderFamily(payload)).activeLayerIndex,
        1,
      );

      await tester.tap(find.byTooltip('Layer actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate Layer'));
      await tester.pumpAndSettle();
      final updated = container.read(drawingStudioProviderFamily(payload));
      expect(updated.payload.layers, hasLength(3));
      expect(updated.payload.layers.first.name, 'Top Copy');
      expect(updated.payload.layers.first.opacity, 0.75);
      expect(updated.payload.layers[1].id, 'top');
      expect(updated.payload.layers[2].id, 'bottom');
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
