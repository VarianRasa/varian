import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/features/model3d/data/model3d_texture_upload.dart';
import 'package:varian/features/model3d/presentation/model3d_node_widget.dart';
import 'package:varian/features/model3d/presentation/model3d_preview.dart';
import 'package:varian/features/model3d/presentation/model3d_rendering.dart';

void main() {
  testWidgets('shows an actionable fallback when interactive preview fails', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 240,
          child: Model3DFallbackCard(
            payload: Model3DPayload(fileName: 'chair.glb'),
            error: 'Renderer unavailable',
            selected: true,
            canvasColor: Colors.black,
            panelColor: const Color(0xFF151B2B),
            borderColor: Colors.lightBlue,
            textColor: Colors.white,
            mutedColor: Colors.blueGrey,
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );

    expect(find.text('chair.glb'), findsOneWidget);
    expect(find.text('Renderer unavailable'), findsOneWidget);
    expect(find.text('Retry preview'), findsOneWidget);
    final retryLabel = tester.widget<Text>(find.text('Retry preview'));
    expect(retryLabel.style?.color, Colors.white);

    await tester.tap(find.text('Retry preview'));
    await tester.pumpAndSettle();
    expect(retryCount, 1);
  });

  testWidgets('shows the native renderer capability fallback on Android', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 240,
            child: Model3DNodeWidget(
              payload: Model3DPayload(
                fileName: 'chair.glb',
                artifactReference: 'varian-model3d://chair1234',
              ),
              readOnly: false,
              canMove: false,
              selected: true,
              width: 320,
              height: 240,
              canvasColor: Colors.black,
              panelColor: const Color(0xFF151B2B),
              borderColor: Colors.lightBlue,
              textColor: Colors.white,
              mutedColor: Colors.blueGrey,
              nativeRendererAvailableOverride: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Android native renderer is unavailable on this device. The project library remains usable. Retry preview when a supported renderer is available.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry preview'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  test(
    'a native runtime path alone is unavailable at the durable boundary',
    () {
      final payload = Model3DPayload(modelPath: 'chair.glb');

      expect(payload.hasSource, isFalse);
      expect(payload.toPersistenceJson().containsKey('modelPath'), isFalse);
    },
  );

  testWidgets('storage-only models show an explicit materialization fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 240,
          child: Model3DNodeWidget(
            payload: Model3DPayload(
              fileName: 'chair.glb',
              storagePath: 'project-1/models3d/chair.glb',
            ),
            readOnly: true,
            canMove: false,
            selected: false,
            interactive: false,
            width: 320,
            height: 240,
            canvasColor: Colors.black,
            panelColor: const Color(0xFF151B2B),
            borderColor: Colors.lightBlue,
            textColor: Colors.white,
            mutedColor: Colors.blueGrey,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'This GLB is stored in private project storage and needs materialization before preview. Retry when the project storage is available.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry preview'), findsOneWidget);
  });

  test('selection changes do not require an ANGLE viewer restart', () {
    expect(
      model3DViewerNeedsRestart(
        sourceChanged: false,
        retryChanged: false,
        sizeChanged: false,
      ),
      isFalse,
    );
    expect(
      model3DViewerNeedsRestart(
        sourceChanged: true,
        retryChanged: false,
        sizeChanged: false,
      ),
      isTrue,
    );
  });

  test('starts the viewer ticker only when it is inactive', () {
    expect(
      model3DViewerShouldStartTicker(enabled: true, isActive: false),
      isTrue,
    );
    expect(
      model3DViewerShouldStartTicker(enabled: true, isActive: true),
      isFalse,
    );
    expect(
      model3DViewerShouldStartTicker(enabled: false, isActive: false),
      isFalse,
    );
  });

  test('uses the canvas RGB value for the viewer clear color', () {
    expect(model3DViewerClearColor(const Color(0xFFF5F5F5)), 0x00F5F5F5);
    expect(model3DViewerClearColor(const Color(0xFF0A0A0A)), 0x000A0A0A);
  });

  test('keeps ANGLE-safe viewer settings and gates animation state', () {
    final settings = model3DViewerSettings(
      clearColor: 0x000A0A0A,
      clearAlpha: 0,
      animate: false,
    );

    expect(settings.alpha, isTrue);
    expect(settings.premultipliedAlpha, isFalse);
    expect(settings.useSurfaceProducer, isTrue);
    expect(settings.enableShadowMap, isFalse);
    expect(settings.animate, isFalse);
    expect(settings.toneMapping, three.ACESFilmicToneMapping);
    expect(settings.toneMappingExposure, 1.1);

    final interactive = model3DViewerSettings(
      clearColor: 0x000A0A0A,
      clearAlpha: 1,
      animate: true,
    );
    expect(interactive.animate, isTrue);
  });

  test('builds a bounded direct-light studio rig', () {
    final lights = model3DStudioLights();
    final directional = lights.whereType<three.DirectionalLight>().toList();

    expect(lights, hasLength(6));
    expect(lights.whereType<three.HemisphereLight>(), hasLength(1));
    expect(lights.whereType<three.AmbientLight>(), hasLength(1));
    expect(directional, hasLength(4));
    expect(
      directional.every((light) => light.intensity > 0 && light.intensity <= 3),
      isTrue,
    );
    expect(directional.map((light) => light.position.z), contains(-4.0));
  });

  testWidgets('renders each configured viewport mode in the node', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var payload = Model3DPayload(fileName: 'chair.glb');
    var selectionCount = 0;
    final dragDeltas = <Offset>[];

    Widget buildNode() => SizedBox(
      width: 320,
      height: 240,
      child: Model3DNodeWidget(
        payload: payload,
        readOnly: false,
        canMove: true,
        selected: false,
        interactive: false,
        width: 320,
        height: 240,
        canvasColor: Colors.black,
        panelColor: const Color(0xFF151B2B),
        borderColor: Colors.lightBlue,
        textColor: Colors.white,
        mutedColor: Colors.blueGrey,
        onSelect: () => selectionCount++,
        onDragDelta: dragDeltas.add,
      ),
    );

    await tester.pumpWidget(MaterialApp(home: buildNode()));
    final header = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.color == const Color(0xFF151B2B).withValues(alpha: 0.76),
    );
    expect(header, findsOneWidget);
    expect(tester.getSize(header).height, AppControlSize.minimumHitTarget);
    final headerRect = tester.getRect(header);
    final headerTarget = find.byKey(
      const ValueKey('model3d-drag-header-target'),
    );
    expect(tester.getRect(headerTarget), headerRect);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(headerTarget),
      matchesSemantics(
        isButton: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: '3D model chair.glb',
        hint: 'Drag to move this model.',
      ),
    );
    semantics.dispose();
    await tester.tapAt(headerRect.bottomRight - const Offset(1, 1));
    await tester.pump();
    expect(selectionCount, 1);

    final headerDrag = await tester.startGesture(headerRect.center);
    await tester.pump();
    await headerDrag.moveBy(const Offset(10, 7));
    await tester.pump();
    await headerDrag.moveBy(const Offset(30, 21));
    await tester.pump();
    await headerDrag.up();
    await tester.pump();
    await tester.pump();
    expect(dragDeltas, isNotEmpty);
    final totalDragDelta = dragDeltas.fold(
      Offset.zero,
      (sum, delta) => sum + delta,
    );
    expect(totalDragDelta.dx, greaterThan(0));
    expect(totalDragDelta.dy, greaterThan(0));

    final headerFocus = Focus.of(tester.element(headerTarget));
    headerFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selectionCount, 2);
    expect(find.byKey(const ValueKey('model3d-viewport-3d')), findsOneWidget);
    expect(find.byType(Model3DPreviewPane), findsNothing);

    payload = payload.copyWith(viewportMode: Model3DViewportMode.threeDAndTwoD);
    await tester.pumpWidget(MaterialApp(home: buildNode()));
    expect(tester.getSize(header).height, AppControlSize.minimumHitTarget);
    expect(
      find.byKey(const ValueKey('model3d-viewport-3d-and-2d')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('model3d-viewport-3d')), findsNothing);
    expect(find.byType(Model3DPreviewPane), findsOneWidget);
    expect(tester.takeException(), isNull);

    payload = payload.copyWith(viewportMode: Model3DViewportMode.twoD);
    await tester.pumpWidget(MaterialApp(home: buildNode()));
    expect(tester.getSize(header).height, AppControlSize.minimumHitTarget);
    expect(find.byKey(const ValueKey('model3d-viewport-2d')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('model3d-viewport-3d-and-2d')),
      findsNothing,
    );
    expect(find.byType(Model3DPreviewPane), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders UV and texture channel preview data', (tester) async {
    tester.view.physicalSize = const Size(240, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 240,
          height: 180,
          child: Model3DPreviewPane(
            snapshot: Model3DSceneSnapshot(
              uvTriangles: const [
                Model3DUvTriangle(u1: 0, v1: 0, u2: 1, v2: 0, u3: 0.5, v3: 1),
              ],
              textureBytes: Uint8List.fromList(const <int>[255, 0, 0, 255]),
              textureWidth: 1,
              textureHeight: 1,
              channelLabel: 'Base Color',
            ),
            checker: false,
            canvasColor: Colors.black,
            panelColor: const Color(0xFF151B2B),
            borderColor: Colors.lightBlue,
            foregroundColor: Colors.white,
            mutedColor: Colors.white54,
          ),
        ),
      ),
    );
    final previewBounds = tester.getRect(find.byType(Model3DPreviewPane));
    expect(previewBounds.size, const Size(240, 180));
    final channelLabel = tester.getRect(find.text('Base Color • 1×1'));
    expect(channelLabel.left, greaterThanOrEqualTo(previewBounds.left));
    expect(channelLabel.right, lessThanOrEqualTo(previewBounds.right));
    expect(channelLabel.top, greaterThanOrEqualTo(previewBounds.top));
    expect(channelLabel.bottom, lessThanOrEqualTo(previewBounds.bottom));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Base Color • 1×1'), findsOneWidget);
  });

  testWidgets('uses theme surfaces in the UV preview pane', (tester) async {
    final themes = [
      (
        canvas: const Color(0xFFF5F5F5),
        panel: const Color(0xFFFAFAFA),
        border: const Color(0xFFE5E5E5),
        foreground: const Color(0xFF171717),
        muted: const Color(0xFF737373),
      ),
      (
        canvas: const Color(0xFF0A0A0A),
        panel: const Color(0xFF171717),
        border: const Color(0xFF404040),
        foreground: const Color(0xFFFAFAFA),
        muted: const Color(0xFFA1A1A1),
      ),
    ];

    for (final theme in themes) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 240,
            height: 180,
            child: Model3DPreviewPane(
              snapshot: const Model3DSceneSnapshot(),
              checker: true,
              canvasColor: theme.canvas,
              panelColor: theme.panel,
              borderColor: theme.border,
              foregroundColor: theme.foreground,
              mutedColor: theme.muted,
            ),
          ),
        ),
      );

      final decorated = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.color, theme.panel);
      expect(
        decoration.border!.top.color,
        theme.border.withValues(alpha: 0.64),
      );
    }
  });

  testWidgets('scrolls fallback content in short node layouts', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 110,
          height: 100,
          child: Model3DFallbackCard(
            payload: Model3DPayload(fileName: 'chair.glb'),
            error: 'Renderer unavailable',
            selected: true,
            canvasColor: Colors.black,
            panelColor: const Color(0xFF151B2B),
            borderColor: Colors.lightBlue,
            textColor: Colors.white,
            mutedColor: Colors.blueGrey,
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Retry preview'));
    await tester.tap(find.text('Retry preview'));

    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('uses a compact retry action for narrow fallback cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 110,
          height: 160,
          child: Model3DFallbackCard(
            payload: Model3DPayload(fileName: 'chair.glb'),
            error: 'Renderer unavailable',
            selected: true,
            canvasColor: Colors.black,
            panelColor: const Color(0xFF151B2B),
            borderColor: Colors.lightBlue,
            textColor: Colors.white,
            mutedColor: Colors.blueGrey,
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Retry preview'), findsOneWidget);
  });

  test('installs and removes the platform texture upload repair', () {
    final texture = three.Texture(
      three.ImageElement(
        data: Uint8List.fromList(const <int>[255, 0, 0, 255]),
        width: 1,
        height: 1,
      ),
    );
    final model = three.Mesh(
      three.PlaneGeometry(1, 1),
      three.MeshBasicMaterial({three.MaterialProperty.map: texture}),
    );
    final repair = Model3DTextureUploadRepair();

    repair.attach(model);
    if (repair.isSupported) {
      expect(texture.onUpdate, isNotNull);
    } else {
      expect(texture.onUpdate, isNull);
    }

    repair.dispose();
    expect(texture.onUpdate, isNull);
  });

  test('repairs grouped and non-mesh texture owners safely', () {
    final shortTexture = three.DataTexture(
      Uint8List.fromList(const <int>[255]),
      1,
      1,
      three.RGBAFormat,
      three.UnsignedByteType,
    );
    final cubeTexture = three.CubeTexture(
      List<three.ImageElement>.generate(
        6,
        (_) => three.ImageElement(width: 1, height: 1),
      ),
    );
    final groupedMaterial = three.GroupMaterial([
      three.MeshBasicMaterial()..map = shortTexture,
      three.MeshBasicMaterial()..envMap = cubeTexture,
    ]);
    final points = three.Points(three.BufferGeometry(), groupedMaterial);
    final model = three.Object3D()..add(points);
    final repair = Model3DTextureUploadRepair();

    repair.attach(model);
    if (repair.isSupported) {
      final firstCallback = shortTexture.onUpdate;
      repair.attach(model);
      expect(identical(shortTexture.onUpdate, firstCallback), isTrue);
      expect(shortTexture.onUpdate, isNotNull);
      expect(cubeTexture.onUpdate, isNotNull);
      expect(() => shortTexture.onUpdate!(shortTexture), returnsNormally);
      expect(() => cubeTexture.onUpdate!(cubeTexture), returnsNormally);

      shortTexture.dispose();
      expect(shortTexture.onUpdate, isNull);
    }

    repair.dispose();
    expect(cubeTexture.onUpdate, isNull);
  });

  test('attaches repair before a skinned animation creates bone updates', () {
    final skeleton = three.Skeleton([three.Bone()]);
    final mesh = three.SkinnedMesh(
      three.BufferGeometry(),
      three.MeshBasicMaterial(),
    )..skeleton = skeleton;
    final model = three.Object3D()..add(mesh);
    final repair = Model3DTextureUploadRepair();

    repair.attach(model);
    if (repair.isSupported) {
      final boneTexture = skeleton.boneTexture;
      expect(boneTexture, isNotNull);
      expect(boneTexture!.type, three.FloatType);
      expect(boneTexture.onUpdate, isNotNull);
      boneTexture.dispose();
      expect(boneTexture.onUpdate, isNull);
    } else {
      expect(skeleton.boneTexture, isNull);
    }

    repair.dispose();
  });
}
