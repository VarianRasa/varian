import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/viewport.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fit bounds centers content while respecting zoom limits', () {
    final viewport = CanvasNavigationMath.fitBounds(
      const Rect.fromLTWH(100, 50, 400, 200),
      const Size(800, 600),
      padding: 40,
    );

    expect(viewport.zoom, closeTo(1.666666, 0.0001));
    expect(viewport.x, closeTo(-100, 0.001));
    expect(viewport.y, closeTo(50, 0.001));
  });

  test('navigation state round-trips pages, sections, and bookmarks', () {
    final now = DateTime.utc(2026, 9, 12, 10);
    const viewport = Viewport(x: -120, y: 48, zoom: 1.25);
    final state = CanvasNavigationState(
      sections: const [CanvasSection(id: 'section-a', name: 'Marketing')],
      pages: const [
        CanvasPage(id: 'page-a', name: 'Landing', sectionId: 'section-a'),
      ],
      bookmarks: [
        ViewportBookmark(
          id: 'view-a',
          name: 'Hero area',
          viewport: viewport,
          pageId: 'page-a',
          selectedNodeIds: const ['hero'],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activePageId: 'page-a',
      focusMode: true,
    );

    final restored = CanvasNavigationState.fromJson(state.toJson());

    expect(restored.sections.single.name, 'Marketing');
    expect(restored.pages.single.sectionId, 'section-a');
    expect(restored.bookmarks.single.viewport.zoom, 1.25);
    expect(restored.bookmarks.single.selectedNodeIds, ['hero']);
    expect(restored.activePageId, 'page-a');
    expect(restored.focusMode, isTrue);
    expect(
      restored.toJson()['schemaVersion'],
      CanvasNavigationState.schemaVersion,
    );
  });

  test('legacy navigation payload migrates safely and repairs active page', () {
    final restored = CanvasNavigationState.fromJson({
      'pages': [
        {'id': 'page-b', 'name': 'Second', 'order': 2},
        {'id': 'page-b', 'name': 'Duplicate', 'order': 1},
        {'id': 'page-a', 'name': 'First', 'order': 0},
      ],
      'activePageId': 'missing',
    });

    expect(restored.pages.map((page) => page.id), ['page-a', 'page-b']);
    expect(restored.activePageId, 'page-a');
    expect(
      restored.toJson()['schemaVersion'],
      CanvasNavigationState.schemaVersion,
    );
  });

  test('search includes node name, type, and serialized payload text', () {
    final nodes = [
      CanvasNode(
        id: 'hero',
        type: NodeType.text,
        x: 0,
        y: 0,
        width: 100,
        height: 40,
        name: 'Hero heading',
        payload: TextPayload(text: 'Build faster'),
      ),
      CanvasNode(
        id: 'card',
        type: NodeType.rectangle,
        x: 120,
        y: 0,
        width: 100,
        height: 40,
        payload: ShapePayload(label: 'Pricing card'),
      ),
    ];

    expect(CanvasNavigationMath.searchNodes(nodes, 'faster').single.id, 'hero');
    expect(
      CanvasNavigationMath.searchNodes(nodes, 'rectangle').single.id,
      'card',
    );
    expect(CanvasNavigationMath.searchNodes(nodes, '').length, 2);
  });

  test(
    'page filtering keeps legacy nodes visible and isolates scoped nodes',
    () {
      final nodes = [
        CanvasNode(
          id: 'legacy',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 10,
          height: 10,
          payload: ShapePayload(),
        ),
        CanvasNode(
          id: 'page-a',
          type: NodeType.rectangle,
          x: 20,
          y: 0,
          width: 10,
          height: 10,
          pageId: 'page-a',
          payload: ShapePayload(),
        ),
        CanvasNode(
          id: 'page-b',
          type: NodeType.rectangle,
          x: 40,
          y: 0,
          width: 10,
          height: 10,
          pageId: 'page-b',
          payload: ShapePayload(),
        ),
      ];

      expect(
        CanvasNavigationMath.nodesForPage(
          nodes,
          'page-a',
        ).map((node) => node.id),
        ['legacy', 'page-a'],
      );
      expect(
        CanvasNavigationMath.nodesForPage(
          nodes,
          'page-b',
        ).map((node) => node.id),
        ['legacy', 'page-b'],
      );
    },
  );

  test('navigation persistence survives a local storage round trip', () async {
    final storage = LocalStorageService();
    final now = DateTime.utc(2026, 9, 12);
    final navigation = CanvasNavigationState(
      bookmarks: [
        ViewportBookmark(
          id: 'view-a',
          name: 'Overview',
          viewport: const Viewport(zoom: 0.8),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    await storage.saveCanvasNavigation('project-a', navigation);
    final restored = await storage.loadCanvasNavigation('project-a');

    expect(restored.bookmarks.single.name, 'Overview');
    expect(restored.bookmarks.single.viewport.zoom, 0.8);
  });

  test('viewport notifier fits multiple content bounds', () {
    final notifier = ViewportNotifier();
    notifier.zoomToContent(const [
      Rect.fromLTWH(0, 0, 100, 100),
      Rect.fromLTWH(300, 200, 100, 100),
    ], const Size(800, 600));

    expect(notifier.state.zoom, greaterThan(0.1));
    expect(notifier.state.x, isNot(0));
    expect(notifier.state.y, isNot(0));
  });
}
