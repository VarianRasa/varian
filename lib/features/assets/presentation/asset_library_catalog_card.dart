import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../domain/asset_library.dart';

class AssetLibraryCatalogCard extends StatelessWidget {
  final AssetLibraryItem item;
  final bool canInsert;
  final VoidCallback onInsert;
  final VoidCallback onFavorite;
  final VoidCallback onEdit;

  const AssetLibraryCatalogCard({
    required this.item,
    required this.canInsert,
    required this.onInsert,
    required this.onFavorite,
    required this.onEdit,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final preview = item.previewUrl ?? item.downloadUrl ?? item.sourceUrl;
    final provenance = item.creator ?? item.attribution;
    final statusLabel = switch (item.status) {
      AssetLibraryItemStatus.ready =>
        item.isInsertable ? 'Ready' : 'Unavailable',
      AssetLibraryItemStatus.syncing => 'Syncing',
      AssetLibraryItemStatus.missing => 'Missing',
      AssetLibraryItemStatus.failed => 'Failed',
    };
    final statusVariant = switch (item.status) {
      AssetLibraryItemStatus.ready =>
        item.isInsertable ? UiBadgeVariant.success : UiBadgeVariant.warning,
      AssetLibraryItemStatus.syncing => UiBadgeVariant.info,
      AssetLibraryItemStatus.missing => UiBadgeVariant.warning,
      AssetLibraryItemStatus.failed => UiBadgeVariant.destructive,
    };
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm),
      color: tokens.panelElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: tokens.canvas,
                    alignment: Alignment.center,
                    child:
                        preview != null &&
                            preview.trim().toLowerCase().startsWith('https://')
                        ? Image.network(
                            preview,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : const Center(
                                    child: UiProgressIndicator(
                                      semanticsLabel: 'Loading asset preview',
                                      size: 18,
                                    ),
                                  ),
                            errorBuilder: (_, _, _) =>
                                AssetLibraryCatalogIcon(item: item),
                          )
                        : AssetLibraryCatalogIcon(item: item),
                  ),
                  Positioned(
                    top: AppSpacing.xxs,
                    left: AppSpacing.xxs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UiBadge(
                          item.typeLabel,
                          variant: UiBadgeVariant.secondary,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        UiBadge(statusLabel, variant: statusVariant),
                      ],
                    ),
                  ),
                  if (item.source != AssetLibrarySource.bundled)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UiIconButton(
                            icon: item.favorite
                                ? Icons.star
                                : Icons.star_outline,
                            iconSize: 14,
                            size: UiButtonSize.xs,
                            tooltip: item.favorite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                            onPressed: onFavorite,
                            selected: item.favorite,
                          ),
                          UiIconButton(
                            icon: Icons.more_horiz,
                            iconSize: 14,
                            size: UiButtonSize.xs,
                            tooltip: 'Edit asset metadata',
                            onPressed: onEdit,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            item.license == null
                ? item.source.name
                : 'License · ${item.license}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
          ),
          if (provenance?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'By ${provenance!.trim()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: AppControlSize.minimumHitTarget,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 130;
                return UiButton(
                  key: ValueKey('asset-library-insert-${item.id}'),
                  onPressed: canInsert ? onInsert : null,
                  size: UiButtonSize.xs,
                  prefix: compact ? null : const Icon(Icons.add, size: 14),
                  child: Text(compact ? 'Add' : 'Insert'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AssetLibraryCatalogIcon extends StatelessWidget {
  final AssetLibraryItem item;

  const AssetLibraryCatalogIcon({required this.item, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final icon = switch (item.metadata['icon']) {
      'crop_square' => Icons.crop_square,
      'circle_outlined' => Icons.circle_outlined,
      'change_history_outlined' => Icons.change_history_outlined,
      'view_in_ar_outlined' => Icons.view_in_ar_outlined,
      'filter_none_outlined' => Icons.filter_none_outlined,
      'arrow_forward' => Icons.arrow_forward,
      _ => switch (item.kind) {
        AssetLibraryItemKind.video => Icons.videocam_outlined,
        AssetLibraryItemKind.audio => Icons.audiotrack_outlined,
        AssetLibraryItemKind.model3d => Icons.view_in_ar_outlined,
        AssetLibraryItemKind.file => Icons.insert_drive_file_outlined,
        _ => Icons.image_outlined,
      },
    };
    return Icon(icon, color: tokens.textMuted, size: 32);
  }
}
