import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/asset_library.dart';
import 'asset_library_catalog_card.dart';

class AssetLibraryCatalogPanel extends StatelessWidget {
  final List<AssetLibraryItem> items;
  final Widget actions;
  final bool loading;
  final bool offline;
  final String? error;
  final String? nextCursor;
  final bool canInsert;
  final Future<void> Function(AssetLibraryItem item) onInsert;
  final VoidCallback Function(AssetLibraryItem item) onFavorite;
  final VoidCallback Function(AssetLibraryItem item) onEdit;
  final VoidCallback onLoadMore;

  const AssetLibraryCatalogPanel({
    required this.items,
    required this.actions,
    required this.loading,
    required this.offline,
    required this.error,
    required this.nextCursor,
    required this.canInsert,
    required this.onInsert,
    required this.onFavorite,
    required this.onEdit,
    required this.onLoadMore,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiSectionHeader(
          title: 'REUSABLE LIBRARY',
          trailing: UiBadge(
            offline ? 'offline · ${items.length}' : '${items.length} items',
          ),
        ),
        if (offline) ...[
          const SizedBox(height: AppSpacing.sm),
          const UiAlert(
            title: 'Offline',
            description: 'Showing saved project assets.',
            icon: Icons.cloud_off_outlined,
            variant: UiAlertVariant.info,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        actions,
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          UiAlert(
            title: error!,
            icon: Icons.error_outline,
            variant: UiAlertVariant.warning,
            liveRegion: true,
          ),
        ],
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        if (loading && items.isEmpty)
          UiSurface(
            color: tokens.panelElevated,
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: const Column(
              children: [
                UiProgressIndicator(
                  semanticsLabel: 'Loading library assets',
                  size: 24,
                ),
                SizedBox(height: AppSpacing.sm),
                Text('Loading reusable assets'),
              ],
            ),
          )
        else if (items.isEmpty && error == null)
          UiSurface(
            color: tokens.panelElevated,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: const UiEmptyState(
              icon: Icons.collections_outlined,
              title: 'NO LIBRARY ASSETS',
              message:
                  'Upload an asset or search Openverse for reusable media.',
            ),
          )
        else if (items.isNotEmpty) ...[
          if (loading) ...[
            const SizedBox(height: AppSpacing.xs),
            const UiLinearProgressIndicator(
              semanticsLabel: 'Refreshing library assets',
              height: AppBorder.thin * 2,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 360
                  ? 1
                  : constraints.maxWidth >= 720
                  ? 4
                  : constraints.maxWidth >= 460
                  ? 3
                  : 2;
              final aspectRatio = columns == 1 ? 0.86 : 0.7;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: aspectRatio,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return AssetLibraryCatalogCard(
                    item: item,
                    canInsert: canInsert && item.isInsertable,
                    onInsert: () => onInsert(item),
                    onFavorite: onFavorite(item),
                    onEdit: onEdit(item),
                  );
                },
              );
            },
          ),
        ],
        if (nextCursor != null) ...[
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
          Align(
            alignment: Alignment.center,
            child: UiButton(
              onPressed: loading ? null : onLoadMore,
              variant: UiButtonVariant.outline,
              prefix: loading ? null : const Icon(Icons.expand_more, size: 16),
              child: Text(loading ? 'Loading...' : 'Load more assets'),
            ),
          ),
        ],
      ],
    );
  }
}
