import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/assets/presentation/asset_library_catalog_card.dart';
import 'package:varian/features/assets/presentation/asset_library_catalog_panel.dart';

import '../../test_app.dart';

void main() {
  final timestamp = DateTime.utc(2026, 10, 3);

  AssetLibraryItem bundledItem(String id) => AssetLibraryItem(
    id: id,
    scopeId: 'local-scope',
    kind: AssetLibraryItemKind.image,
    source: AssetLibrarySource.bundled,
    name: 'Local asset $id',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  Widget panel(List<AssetLibraryItem> items) => AssetLibraryCatalogPanel(
    items: items,
    actions: const Text('Local catalog actions'),
    loading: false,
    offline: false,
    error: null,
    nextCursor: null,
    canInsert: true,
    onInsert: (_) async {},
    onFavorite: (_) => () {},
    onEdit: (_) => () {},
    onLoadMore: () {},
  );

  testWidgets('standalone catalog panel uses one column when narrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(SizedBox(width: 320, child: panel([bundledItem('one')]))),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    expect(find.text('REUSABLE LIBRARY'), findsOneWidget);
    final card = find.byType(AssetLibraryCatalogCard);
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    expect(cardRect.left, greaterThanOrEqualTo(0));
    expect(cardRect.right, lessThanOrEqualTo(320));
    expect(cardRect.top, greaterThanOrEqualTo(0));
    expect(cardRect.bottom, lessThanOrEqualTo(640));
    expect(find.text('Local asset one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone catalog panel uses four columns when wide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 760,
          child: panel([
            bundledItem('one'),
            bundledItem('two'),
            bundledItem('three'),
            bundledItem('four'),
          ]),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    final cards = find.byType(AssetLibraryCatalogCard);
    expect(cards, findsNWidgets(4));
    final cardRects = List.generate(
      4,
      (index) => tester.getRect(cards.at(index)),
    );
    for (final rect in cardRects) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(800));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
    }
    expect(cardRects[1].top, cardRects[0].top);
    expect(cardRects[2].top, cardRects[0].top);
    expect(cardRects[3].top, cardRects[0].top);
    expect(cardRects[1].left - cardRects[0].right, AppSpacing.sm);
    expect(cardRects[2].left - cardRects[1].right, AppSpacing.sm);
    expect(cardRects[3].left - cardRects[2].right, AppSpacing.sm);
    expect(tester.takeException(), isNull);
  });
  testWidgets('catalog card uses app chrome tokens around local asset data', (
    tester,
  ) async {
    var inserted = false;
    final item = bundledItem('direct-card');
    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 300,
          height: 280,
          child: AssetLibraryCatalogCard(
            item: item,
            canInsert: true,
            onInsert: () => inserted = true,
            onFavorite: () {},
            onEdit: () {},
          ),
        ),
      ),
    );

    final surface = tester.widget<UiSurface>(find.byType(UiSurface));
    expect(surface.padding, const EdgeInsets.all(AppSpacing.sm));
    final previewClip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(previewClip.borderRadius, BorderRadius.circular(AppRadius.control));
    expect(find.text('Local asset direct-card'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('asset-library-insert-direct-card')),
          )
          .height,
      AppControlSize.minimumHitTarget,
    );
    final insertRect = tester.getRect(
      find.byKey(const ValueKey('asset-library-insert-direct-card')),
    );
    await tester.tapAt(insertRect.bottomLeft + const Offset(20, -2));
    expect(inserted, isTrue);
    expect(tester.takeException(), isNull);
    final overlayBadges = find.descendant(
      of: find.byType(AssetLibraryCatalogCard),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.top == AppSpacing.xxs &&
            widget.left == AppSpacing.xxs,
      ),
    );
    expect(overlayBadges, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
