import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import '../data/asset_library_repository.dart';
import '../data/asset_service.dart';
import '../domain/asset_library.dart';
import 'asset_library_catalog_panel.dart';

/// The media categories exposed by the node-derived asset library.
enum AssetLibraryTypeFilter { all, images, files, models3d, videos, audio }

/// Returns visible, source-bearing nodes that can be reused from the library.
List<CanvasNode> filterAssetLibraryNodes(
  Iterable<CanvasNode> nodes, {
  String query = '',
  AssetLibraryTypeFilter type = AssetLibraryTypeFilter.all,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return nodes.where((node) {
    if (!node.visible || !_isSupportedType(node.type)) return false;
    if (!_hasSource(node)) return false;
    if (!_matchesType(node.type, type)) return false;
    if (normalizedQuery.isEmpty) return true;
    return _searchText(node).toLowerCase().contains(normalizedQuery);
  }).toList();
}

bool _isSupportedType(NodeType type) =>
    type == NodeType.image ||
    type == NodeType.fileCard ||
    type == NodeType.model3d ||
    type == NodeType.videoCard ||
    type == NodeType.audioCard;

bool _matchesType(NodeType nodeType, AssetLibraryTypeFilter filter) {
  switch (filter) {
    case AssetLibraryTypeFilter.all:
      return true;
    case AssetLibraryTypeFilter.images:
      return nodeType == NodeType.image;
    case AssetLibraryTypeFilter.files:
      return nodeType == NodeType.fileCard;
    case AssetLibraryTypeFilter.models3d:
      return nodeType == NodeType.model3d;
    case AssetLibraryTypeFilter.videos:
      return nodeType == NodeType.videoCard;
    case AssetLibraryTypeFilter.audio:
      return nodeType == NodeType.audioCard;
  }
}

bool _hasSource(CanvasNode node) {
  switch (node.payload) {
    case ImagePayload p:
      return validImageArtifactReference(p.imageArtifactReference) != null ||
          durableAssetReference(p.storagePath) != null;
    case FilePayload p:
      return validFileArtifactReference(p.artifactReference) != null ||
          durableAssetReference(p.storagePath) != null;
    case Model3DPayload p:
      return validModel3DArtifactReference(p.artifactReference) != null ||
          durableAssetReference(p.storagePath) != null;
    case VideoPayload p:
      return validVideoArtifactReference(p.videoArtifactReference) != null ||
          durableAssetReference(p.storagePath) != null;
    case AudioPayload p:
      return validMediaArtifactReference(p.audioArtifactReference) != null ||
          durableAssetReference(p.storagePath) != null;
    default:
      return false;
  }
}

String _searchText(CanvasNode node) {
  final values = <String>[node.name ?? ''];
  switch (node.payload) {
    case ImagePayload p:
      values.addAll([p.assetId ?? '', p.caption ?? '']);
    case FilePayload p:
      values.addAll([p.fileName, p.fileExtension, p.description ?? '']);
    case Model3DPayload p:
      values.addAll([p.displayName, p.fileSizeText]);
    case VideoPayload p:
      values.addAll([p.title, p.caption ?? '']);
    case AudioPayload p:
      values.addAll([p.trackName, p.artist, p.description]);
    default:
      break;
  }
  return values.join(' ');
}

String assetLibraryTypeLabel(NodeType type) {
  switch (type) {
    case NodeType.image:
      return 'Image';
    case NodeType.fileCard:
      return 'File';
    case NodeType.model3d:
      return '3D Model';
    case NodeType.videoCard:
      return 'Video';
    case NodeType.audioCard:
      return 'Audio';
    default:
      return type.name;
  }
}

String assetLibraryTitle(CanvasNode node) {
  final explicitName = node.name?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;
  switch (node.payload) {
    case ImagePayload p:
      final assetId = p.assetId?.trim();
      return assetId?.isNotEmpty == true ? assetId! : 'Image';
    case FilePayload p:
      return p.fileName;
    case Model3DPayload p:
      return p.displayName;
    case VideoPayload p:
      return p.title;
    case AudioPayload p:
      return p.trackName;
    default:
      return 'Asset';
  }
}

class AssetLibraryDialog extends StatefulWidget {
  final List<CanvasNode> nodes;
  final DocumentAssetManifest manifest;
  final bool readOnly;
  final ValueChanged<CanvasNode>? onInsert;
  final AssetLibraryRepository? library;
  final AssetService? assetService;
  final String? scopeId;
  final CanvasImageCache? imageCache;
  final Future<void> Function(AssetLibraryItem item)? onInsertAsset;

  const AssetLibraryDialog({
    required this.nodes,
    this.manifest = const DocumentAssetManifest(),
    this.readOnly = false,
    this.onInsert,
    this.library,
    this.assetService,
    this.scopeId,
    this.imageCache,
    this.onInsertAsset,
    super.key,
  });

  @override
  State<AssetLibraryDialog> createState() => _AssetLibraryDialogState();
}

class _AssetLibraryDialogState extends State<AssetLibraryDialog> {
  final _queryController = TextEditingController();
  final _tagController = TextEditingController();
  String _query = '';
  String _tagQuery = '';
  String _folderFilter = '';
  AssetLibraryTypeFilter _filter = AssetLibraryTypeFilter.all;
  List<AssetLibraryItem> _catalogItems = const [];
  List<AssetLibraryFolder> _folders = const [];
  String? _catalogCursor;
  String? _catalogError;
  bool _catalogLoading = false;
  bool _catalogOffline = false;
  bool _searchOpenverse = false;
  bool _favoritesOnly = false;
  bool _uploading = false;
  int _uploadCompleted = 0;
  int _uploadTotal = 0;
  final List<String> _uploadFailures = <String>[];
  AssetLibrarySort _catalogSort = AssetLibrarySort.recent;
  int _catalogRequest = 0;
  Timer? _catalogDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.library != null && widget.scopeId != null) {
      unawaited(_loadCatalog());
    }
  }

  @override
  void dispose() {
    _catalogDebounce?.cancel();
    _queryController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _scheduleCatalogLoad() {
    if (!_hasCatalog) return;
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 300), () {
      _catalogDebounce = null;
      if (mounted) unawaited(_loadCatalog());
    });
  }

  bool get _hasCatalog => widget.library != null && widget.scopeId != null;

  List<CanvasNode> get _assets =>
      filterAssetLibraryNodes(widget.nodes, query: _query, type: _filter);

  List<CanvasNode> get _visibleCanvasAssets {
    if (_tagQuery.trim().isNotEmpty || _folderFilter.isNotEmpty) {
      return const [];
    }
    return _assets;
  }

  List<DocumentAsset> get _manifestAssets => widget.manifest
      .search(
        query: _query,
        kind: _manifestKindFilter,
        folderId: _folderFilter.isEmpty ? null : _folderFilter,
        tags: _tagQuery.isEmpty ? const [] : [_tagQuery],
      )
      .toList(growable: false);

  DocumentAssetKind? get _manifestKindFilter => switch (_filter) {
    AssetLibraryTypeFilter.all => null,
    AssetLibraryTypeFilter.images => DocumentAssetKind.image,
    AssetLibraryTypeFilter.files => DocumentAssetKind.document,
    AssetLibraryTypeFilter.models3d => DocumentAssetKind.model3d,
    AssetLibraryTypeFilter.videos => DocumentAssetKind.video,
    AssetLibraryTypeFilter.audio => DocumentAssetKind.audio,
  };

  Map<String, String> get _folderItems {
    final folderIds =
        <String?>{
              ...widget.manifest.items.map((asset) => asset.folderId),
              ..._catalogItems.map((asset) => asset.folderId),
            }
            .whereType<String>()
            .where((folder) => folder.trim().isNotEmpty)
            .toList()
          ..sort();
    final items = <String, String>{'All folders': ''};
    for (final folder in _folders) {
      var label = folder.name;
      if (items.containsKey(label)) {
        final suffix = folder.id.length > 6
            ? folder.id.substring(0, 6)
            : folder.id;
        label = '${folder.name} · $suffix';
      }
      items[label] = folder.id;
    }
    for (final folder in folderIds) {
      items.putIfAbsent(folder, () => folder);
    }
    return items;
  }

  List<AssetLibraryItem> get _visibleCatalogItems => _catalogItems
      .where((item) => _matchesCatalogFilter(item.kind, _filter))
      .toList(growable: false);

  bool get _providerSupportsFilter =>
      _filter == AssetLibraryTypeFilter.all ||
      _filter == AssetLibraryTypeFilter.images ||
      _filter == AssetLibraryTypeFilter.audio;

  AssetLibraryItemKind? get _providerKindFilter {
    if (_filter == AssetLibraryTypeFilter.audio) {
      return AssetLibraryItemKind.audio;
    }
    return null;
  }

  bool _matchesCatalogFilter(
    AssetLibraryItemKind kind,
    AssetLibraryTypeFilter filter,
  ) {
    switch (filter) {
      case AssetLibraryTypeFilter.all:
        return true;
      case AssetLibraryTypeFilter.images:
        return kind == AssetLibraryItemKind.image ||
            kind == AssetLibraryItemKind.graphic ||
            kind == AssetLibraryItemKind.icon ||
            kind == AssetLibraryItemKind.illustration;
      case AssetLibraryTypeFilter.files:
        return kind == AssetLibraryItemKind.file;
      case AssetLibraryTypeFilter.models3d:
        return kind == AssetLibraryItemKind.model3d;
      case AssetLibraryTypeFilter.videos:
        return kind == AssetLibraryItemKind.video;
      case AssetLibraryTypeFilter.audio:
        return kind == AssetLibraryItemKind.audio;
    }
  }

  Future<void> _loadCatalog({bool append = false}) async {
    final repository = widget.library;
    final scopeId = widget.scopeId;
    if (repository == null || scopeId == null) return;
    final request = ++_catalogRequest;
    if (append && mounted) {
      setState(() => _catalogLoading = true);
    }
    if (!append) {
      _catalogCursor = null;
      if (mounted) {
        setState(() {
          _catalogLoading = true;
          _catalogError = null;
        });
      }
    }
    try {
      final page = await repository.search(
        AssetLibraryQuery(
          scopeId: scopeId,
          kind: _searchOpenverse ? _providerKindFilter : null,
          query: _query,
          folderId: _folderFilter.isEmpty ? null : _folderFilter,
          tags: _tagQuery.isEmpty ? const [] : [_tagQuery],
          favoritesOnly: _favoritesOnly,
          sort: _catalogSort,
          cursor: append ? _catalogCursor : null,
          includeRemote: _searchOpenverse && _providerSupportsFilter,
        ),
      );
      final folders = await repository.loadFolders();
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _catalogItems = append ? [..._catalogItems, ...page.items] : page.items;
        _folders = folders;
        if (_folderFilter.isNotEmpty &&
            !folders.any((folder) => folder.id == _folderFilter)) {
          _folderFilter = '';
        }
        _catalogCursor = page.nextCursor;
        _catalogLoading = false;
        _catalogOffline = page.isOffline;
        _catalogError = null;
      });
    } catch (error) {
      if (!mounted || request != _catalogRequest) return;
      setState(() {
        _catalogLoading = false;
        _catalogOffline = false;
        _catalogError = 'Library could not be loaded.';
      });
    }
  }

  void _insert(CanvasNode node) {
    if (widget.readOnly || widget.onInsert == null) return;
    widget.onInsert!(node);
    Navigator.pop(context);
  }

  Future<void> _insertCatalogItem(AssetLibraryItem item) async {
    if (widget.readOnly || widget.onInsertAsset == null) return;
    final repository = widget.library;
    try {
      final saved =
          item.source == AssetLibrarySource.bundled || repository == null
          ? item
          : await repository.saveProviderItem(item);
      final insertable = saved.isInsertable;
      if (!insertable) {
        if (mounted) {
          setState(
            () => _catalogError =
                'Asset must finish syncing before it can be inserted.',
          );
        }
        return;
      }
      await widget.onInsertAsset!(saved);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'Asset could not be inserted.');
      }
    }
  }

  Future<void> _toggleCatalogFavorite(AssetLibraryItem item) async {
    final repository = widget.library;
    if (repository == null || item.source == AssetLibrarySource.bundled) return;
    try {
      await repository.setFavorite(item.id, !item.favorite);
      await _loadCatalog();
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'Favorite could not be saved.');
      }
    }
  }

  Future<void> _uploadToCatalog() async {
    final repository = widget.library;
    final picker = widget.assetService;
    final scopeId = widget.scopeId;
    if (repository == null ||
        picker == null ||
        scopeId == null ||
        widget.readOnly ||
        _uploading) {
      return;
    }
    setState(() {
      _uploading = true;
      _uploadCompleted = 0;
      _uploadTotal = 0;
      _uploadFailures.clear();
      _catalogError = null;
    });
    try {
      final results = await picker.pickAnyFiles(
        projectId: scopeId,
        storageFolder: 'library',
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _uploadCompleted = completed;
            _uploadTotal = total;
          });
        },
      );
      if (results.isEmpty) return;
      for (final result in results) {
        if (result.errorMessage != null &&
            result.durableReference == null &&
            (result.bytes == null || result.bytes!.isEmpty)) {
          _uploadFailures.add('${result.name}: ${result.errorMessage}');
          continue;
        }
        try {
          await repository.saveUpload(result);
          if (result.errorMessage != null) {
            _uploadFailures.add('${result.name}: ${result.errorMessage}');
          }
        } on AssetLibraryQuotaExceededException {
          _uploadFailures.add(
            '${result.name}: workspace asset storage quota exceeded.',
          );
        } catch (_) {
          _uploadFailures.add('${result.name}: could not be saved.');
        }
      }
      if (mounted) {
        setState(() {
          _uploadCompleted = results.length;
          _uploadTotal = results.length;
        });
      }
      await _loadCatalog();
      if (mounted && _uploadFailures.isNotEmpty) {
        setState(
          () => _catalogError =
              '${_uploadFailures.length} upload(s) need attention.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'Upload could not be started.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _buildCatalogActions() {
    if (!_hasCatalog) return const SizedBox.shrink();
    final narrow = AppResponsive.isNarrow(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (_uploading)
          UiBadge(
            _uploadTotal == 0
                ? 'Preparing uploads...'
                : 'Uploading $_uploadCompleted/$_uploadTotal',
          ),
        if (!widget.readOnly && widget.assetService != null)
          UiButton(
            key: const ValueKey('asset-library-upload'),
            onPressed: _uploading ? null : _uploadToCatalog,
            prefix: const Icon(Icons.upload_outlined, size: 16),
            child: const Text('Upload'),
          ),
        if (!_uploading && _uploadFailures.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: Text(
              _uploadFailures.join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.appTokens.warning,
              ),
            ),
          ),
        UiButton(
          key: const ValueKey('asset-library-openverse'),
          variant: _searchOpenverse
              ? UiButtonVariant.primary
              : UiButtonVariant.ghost,
          onPressed: () {
            setState(() => _searchOpenverse = !_searchOpenverse);
            _scheduleCatalogLoad();
          },
          prefix: const Icon(Icons.public, size: 16),
          child: Text(
            _searchOpenverse
                ? 'Openverse on'
                : narrow
                ? 'Openverse'
                : 'Search Openverse',
          ),
        ),
        UiButton(
          key: const ValueKey('asset-library-favorites'),
          variant: _favoritesOnly
              ? UiButtonVariant.primary
              : UiButtonVariant.ghost,
          onPressed: () {
            setState(() => _favoritesOnly = !_favoritesOnly);
            _scheduleCatalogLoad();
          },
          prefix: const Icon(Icons.star_outline, size: 16),
          child: const Text('Favorites'),
        ),
        SizedBox(
          width: narrow ? double.infinity : null,
          child: _buildCatalogSortSelect(),
        ),
      ],
    );
  }

  Widget _buildCatalogSortSelect() => UiSelect<AssetLibrarySort>(
    label: 'Sort',
    items: const {
      'Recent': AssetLibrarySort.recent,
      'Name': AssetLibrarySort.name,
      'Most used': AssetLibrarySort.mostUsed,
    },
    value: _catalogSort,
    onChanged: (value) {
      if (value == null) return;
      setState(() => _catalogSort = value);
      _scheduleCatalogLoad();
    },
  );

  Widget _buildCatalogSection() => AssetLibraryCatalogPanel(
    items: _visibleCatalogItems,
    actions: _buildCatalogActions(),
    loading: _catalogLoading,
    offline: _catalogOffline,
    error: _catalogError,
    nextCursor: _catalogCursor,
    canInsert: !widget.readOnly && widget.onInsertAsset != null,
    onInsert: _insertCatalogItem,
    onFavorite: (item) =>
        () => _toggleCatalogFavorite(item),
    onEdit: (item) =>
        () => _editCatalogItem(item),
    onLoadMore: () => _loadCatalog(append: true),
  );
  Widget _buildAssetSearchField() => UiTextField(
    controller: _queryController,
    label: 'Search assets',
    hint: 'Name, type, caption, artist...',
    onChanged: (value) {
      setState(() => _query = value);
      _scheduleCatalogLoad();
    },
  );

  Widget _buildAssetTypeSelect() => UiSelect<AssetLibraryTypeFilter>(
    label: 'Type',
    items: const {
      'All': AssetLibraryTypeFilter.all,
      'Images': AssetLibraryTypeFilter.images,
      'Files': AssetLibraryTypeFilter.files,
      '3D Models': AssetLibraryTypeFilter.models3d,
      'Video': AssetLibraryTypeFilter.videos,
      'Audio': AssetLibraryTypeFilter.audio,
    },
    value: _filter,
    onChanged: (value) {
      if (value == null) return;
      setState(() => _filter = value);
      _scheduleCatalogLoad();
    },
  );

  Widget _buildAssetTagField() => UiTextField(
    key: const ValueKey('asset-manifest-tag-filter'),
    controller: _tagController,
    label: 'Tag filter',
    hint: 'e.g. brand, hero, approved',
    onChanged: (value) {
      setState(() => _tagQuery = value);
      _scheduleCatalogLoad();
    },
  );

  Widget _buildAssetFolderSelect() => UiSelect<String>(
    label: 'Folder',
    items: _folderItems,
    value: _folderFilter,
    onChanged: (value) {
      if (value == null) return;
      setState(() => _folderFilter = value);
      _scheduleCatalogLoad();
    },
  );

  Widget _buildFolderControl() {
    final canCreate = _hasCatalog && !widget.readOnly;
    return Row(
      children: [
        Expanded(child: _buildAssetFolderSelect()),
        if (canCreate)
          UiIconButton(
            key: const ValueKey('asset-library-new-folder'),
            icon: Icons.create_new_folder_outlined,
            iconSize: 16,
            size: UiButtonSize.xs,
            tooltip: 'New folder',
            onPressed: _createCatalogFolder,
          ),
      ],
    );
  }

  Future<void> _editCatalogItem(AssetLibraryItem item) async {
    final repository = widget.library;
    if (repository == null ||
        widget.readOnly ||
        item.source == AssetLibrarySource.bundled) {
      return;
    }
    var editedName = item.name;
    var editedTags = item.tags.join(', ');
    var selectedFolder = item.folderId ?? '';
    final folderItems = Map<String, String>.from(_folderItems);
    if (selectedFolder.isNotEmpty &&
        !folderItems.values.contains(selectedFolder)) {
      folderItems[selectedFolder] = selectedFolder;
    }
    final result = await showUiDialog<(String, String, String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => UiDialog(
          semanticsLabel: 'Edit library asset',
          constraints: AppResponsive.dialogConstraints(context, maxWidth: 480),
          builder: (context, style) => Padding(
            padding: AppResponsive.dialogPadding(context),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Edit library asset', style: style.titleTextStyle),
                  const SizedBox(height: AppSpacing.lg),
                  UiTextField(
                    initialValue: item.name,
                    label: 'Name',
                    autofocus: true,
                    onChanged: (value) => editedName = value,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  UiTextField(
                    initialValue: item.tags.join(', '),
                    label: 'Tags',
                    hint: 'brand, hero, approved',
                    onChanged: (value) => editedTags = value,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  UiSelect<String>(
                    value: selectedFolder,
                    items: folderItems,
                    label: 'Folder',
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedFolder = value);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.pop(context),
                        variant: UiButtonVariant.ghost,
                        size: UiButtonSize.xs,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () =>
                            Navigator.pop(context, ('', '', '', true)),
                        variant: UiButtonVariant.destructive,
                        size: UiButtonSize.xs,
                        child: const Text('Delete'),
                      ),
                      UiButton(
                        onPressed: () => Navigator.pop(context, (
                          editedName.trim(),
                          editedTags,
                          selectedFolder,
                          false,
                        )),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.$4) {
      final confirmed = await showUiDialog<bool>(
        context: context,
        builder: (context) => UiDialog(
          semanticsLabel: 'Confirm asset deletion',
          constraints: AppResponsive.dialogConstraints(context, maxWidth: 420),
          builder: (context, style) => Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Delete library asset?', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md),
                Text('Remove “${item.name}” from this project library?'),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    UiButton(
                      onPressed: () => Navigator.pop(context, false),
                      variant: UiButtonVariant.ghost,
                      size: UiButtonSize.xs,
                      child: const Text('Cancel'),
                    ),
                    UiButton(
                      onPressed: () => Navigator.pop(context, true),
                      variant: UiButtonVariant.destructive,
                      size: UiButtonSize.xs,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true) return;
      try {
        await repository.delete(item.id);
        await _loadCatalog();
      } catch (_) {
        if (mounted) {
          setState(() => _catalogError = 'Asset could not be deleted.');
        }
      }
      return;
    }
    if (result.$1.isEmpty) return;
    try {
      await repository.updateMetadata(
        item.id,
        name: result.$1,
        folderId: result.$3.isEmpty ? null : result.$3,
        tags: result.$2
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty),
      );
      await _loadCatalog();
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'Asset metadata could not be saved.');
      }
    }
  }

  Future<void> _createCatalogFolder() async {
    final repository = widget.library;
    if (repository == null || widget.readOnly) return;
    final controller = TextEditingController();
    final name = await showUiDialog<String>(
      context: context,
      builder: (context) => UiDialog(
        semanticsLabel: 'Create asset folder',
        constraints: AppResponsive.dialogConstraints(context, maxWidth: 420),
        builder: (context, style) => Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New asset folder', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: controller,
                autofocus: true,
                maxLength: 120,
                label: 'Folder name',
                onSubmitted: (value) => Navigator.pop(context, value.trim()),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    onPressed: () => Navigator.pop(context),
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.xs,
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await repository.createFolder(name);
      await _loadCatalog();
    } catch (_) {
      if (mounted) {
        setState(() => _catalogError = 'Folder could not be created.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final assets = _visibleCanvasAssets;
    final manifestAssets = _manifestAssets;
    final compact = AppResponsive.isNarrow(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = AppResponsive.dialogHeight(
      context,
      preferred: availableHeight * 0.82,
    );

    return UiDialog(
      semanticsLabel: 'Asset library',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: maxHeight,
      ),
      builder: (context, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.perm_media_outlined, color: tokens.accent),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'ASSET LIBRARY',
                            style: style.titleTextStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: UiBadge(
                        '${_catalogItems.length} library · ${assets.length} canvas · ${manifestAssets.length} manifest',
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(Icons.perm_media_outlined, color: tokens.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('ASSET LIBRARY', style: style.titleTextStyle),
                    ),
                    UiBadge(
                      '${_catalogItems.length} library · ${assets.length} canvas · ${manifestAssets.length} manifest',
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAssetSearchField(),
                    const SizedBox(height: AppSpacing.sm),
                    _buildAssetTypeSelect(),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _buildAssetSearchField()),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(width: 150, child: _buildAssetTypeSelect()),
                  ],
                ),
              if (_hasCatalog || widget.manifest.items.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                if (widget.manifest.items.isNotEmpty)
                  UiSectionHeader(
                    title: 'DURABLE ASSET MANIFEST',
                    trailing: UiBadge(
                      '${widget.manifest.items.length} records',
                    ),
                  )
                else
                  const UiSectionHeader(title: 'LIBRARY FILTERS'),
                const SizedBox(height: AppSpacing.sm),
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAssetTagField(),
                      const SizedBox(height: AppSpacing.sm),
                      _buildFolderControl(),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _buildAssetTagField()),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(width: 200, child: _buildFolderControl()),
                    ],
                  ),
              ],
              SizedBox(
                height: compact
                    ? AppSpacing.sm
                    : AppSpacing.md + AppSpacing.xxs,
              ),
              Flexible(
                fit: FlexFit.tight,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_hasCatalog) ...[
                        _buildCatalogSection(),
                        if (manifestAssets.isNotEmpty || assets.isNotEmpty)
                          const SizedBox(height: AppSpacing.lg),
                      ],
                      if (manifestAssets.isNotEmpty) ...[
                        UiSectionHeader(
                          title: 'MANIFEST RESULTS',
                          trailing: UiBadge('${manifestAssets.length} records'),
                        ),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                        for (final asset in manifestAssets) ...[
                          _DocumentAssetRow(asset: asset),
                          const SizedBox(
                            height: AppSpacing.sm + AppSpacing.xxs,
                          ),
                        ],
                      ],
                      if (assets.isNotEmpty) ...[
                        UiSectionHeader(
                          title: 'CANVAS ASSETS',
                          trailing: UiBadge('${assets.length} nodes'),
                        ),
                        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                        for (final node in assets) ...[
                          _AssetLibraryRow(
                            node: node,
                            imageCache: widget.imageCache,
                            canInsert:
                                !widget.readOnly && widget.onInsert != null,
                            onInsert: () => _insert(node),
                          ),
                          const SizedBox(
                            height: AppSpacing.sm + AppSpacing.xxs,
                          ),
                        ],
                      ],
                      if (!_hasCatalog &&
                          _catalogError == null &&
                          manifestAssets.isEmpty &&
                          assets.isEmpty)
                        const UiEmptyState(
                          icon: Icons.perm_media_outlined,
                          title: 'NO ASSETS FOUND',
                          message:
                              'Place an image, file, 3D model, video, or audio asset on the canvas first.',
                        ),
                      if (_hasCatalog &&
                          !_catalogLoading &&
                          _catalogError == null &&
                          _visibleCatalogItems.isEmpty &&
                          manifestAssets.isEmpty &&
                          assets.isEmpty)
                        const UiEmptyState(
                          icon: Icons.perm_media_outlined,
                          title: 'NO ASSETS FOUND',
                          message:
                              'Upload an asset or search Openverse to populate this library.',
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: compact
                    ? AppSpacing.sm
                    : AppSpacing.md + AppSpacing.xxs,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentAssetRow extends StatelessWidget {
  final DocumentAsset asset;

  const _DocumentAssetRow({required this.asset});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final location = asset.folderId == null || asset.folderId!.isEmpty
        ? 'Root folder'
        : asset.folderId!;
    final linked = asset.hasDurableReference;
    return UiSurface(
      color: tokens.panelElevated,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            asset.hasDurableReference
                ? Icons.inventory_2_outlined
                : Icons.warning_amber_outlined,
            color: asset.hasDurableReference ? tokens.accent : tokens.warning,
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '$location · v${asset.version} · ${linked ? 'Linked' : 'Local only'}${asset.tags.isEmpty ? '' : ' · ${asset.tags.join(', ')}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          if (asset.license?.trim().isNotEmpty == true)
            UiBadge(asset.license!.trim()),
        ],
      ),
    );
  }
}

class _AssetLibraryRow extends StatelessWidget {
  final CanvasNode node;
  final CanvasImageCache? imageCache;
  final bool canInsert;
  final VoidCallback onInsert;

  const _AssetLibraryRow({
    required this.node,
    this.imageCache,
    required this.canInsert,
    required this.onInsert,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final title = assetLibraryTitle(node);
    final type = assetLibraryTypeLabel(node.type);
    return UiSurface(
      color: tokens.panelElevated,
      padding: const EdgeInsets.all(AppSpacing.sm),
      borderRadius: BorderRadius.circular(tokens.panelRadius),
      child: Row(
        children: [
          _AssetThumbnail(node: node, imageCache: imageCache),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  type,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          if (canInsert)
            UiButton(
              key: ValueKey('asset-insert-${node.id}'),
              onPressed: onInsert,
              prefix: const Icon(Icons.add, size: 16),
              child: const Text('Insert'),
            ),
        ],
      ),
    );
  }
}

class _AssetThumbnail extends StatefulWidget {
  final CanvasNode node;
  final CanvasImageCache? imageCache;

  const _AssetThumbnail({required this.node, this.imageCache});

  @override
  State<_AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<_AssetThumbnail> {
  ui.Image? _image;

  CanvasImageCache get _cache => widget.imageCache ?? CanvasImageCache.instance;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCacheUpdate);
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _AssetThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = _imageKeyForNode(oldWidget.node);
    final nextKey = _imageKeyForNode(widget.node);
    if (oldWidget.imageCache != widget.imageCache || oldKey != nextKey) {
      final oldCache = oldWidget.imageCache ?? CanvasImageCache.instance;
      oldCache.removeListener(_onCacheUpdate);
      _cache.addListener(_onCacheUpdate);
      _image = null;
      _loadImage();
    }
  }

  @override
  void dispose() {
    _cache.removeListener(_onCacheUpdate);
    super.dispose();
  }

  void _onCacheUpdate() {
    if (!mounted) return;
    final next = _cachedImage();
    if (next != _image) setState(() => _image = next);
  }

  void _loadImage() {
    if (widget.node.payload is! ImagePayload) return;
    final payload = widget.node.payload as ImagePayload;
    final key = _imageKey(payload);
    _image = _cache.getImage(key);
    _cache.requestImage(
      storagePath: payload.storagePath,
      localPath: payload.localPath,
      url: payload.url,
      imageArtifactReference: payload.imageArtifactReference,
    );
  }

  ui.Image? _cachedImage() {
    if (widget.node.payload is! ImagePayload) return null;
    return _cache.getImage(_imageKey(widget.node.payload as ImagePayload));
  }

  String? _imageKeyForNode(CanvasNode node) {
    if (node.payload is! ImagePayload) return null;
    return _imageKey(node.payload as ImagePayload);
  }

  String? _imageKey(ImagePayload payload) {
    final imageArtifactReference = payload.imageArtifactReference?.trim();
    if (imageArtifactReference != null && imageArtifactReference.isNotEmpty) {
      return imageArtifactReference;
    }
    final storagePath = payload.storagePath?.trim();
    if (storagePath != null && storagePath.isNotEmpty) return storagePath;
    final localPath = payload.localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) return localPath;
    return payload.url?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final icon = switch (widget.node.type) {
      NodeType.image => Icons.image_outlined,
      NodeType.model3d => Icons.view_in_ar_outlined,
      NodeType.videoCard => Icons.videocam_outlined,
      NodeType.audioCard => Icons.audiotrack_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return Container(
      key: ValueKey('asset-library-thumbnail-${widget.node.id}'),
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      clipBehavior: Clip.antiAlias,
      child: _image == null
          ? Icon(icon, color: tokens.textMuted, size: 22)
          : RawImage(image: _image, fit: BoxFit.cover),
    );
  }
}
