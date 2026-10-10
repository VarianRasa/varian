import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../data/local/local_storage_service.dart';
import '../../../data/local/durable/durable_project_store.dart';
import '../../../data/remote/supabase_app_config.dart';
import 'asset_library_repository.dart';
import 'asset_service.dart';
import 'providers/asset_provider_contract.dart';
import 'providers/openverse_asset_provider.dart';
import '../domain/asset_library.dart';

bool _hasAssetLibraryServiceControlCharacter(String value) =>
    value.codeUnits.any((code) => code < 0x20 || code == 0x7f);

class AssetLibraryService implements AssetLibraryRepository {
  final String scopeId;
  final LocalStorageService localStorage;
  final DurableProjectStore? durableStore;
  final SupabaseClient? client;
  final List<AssetCatalogProvider> providers;

  final List<AssetLibraryItem> _items = [];
  final List<AssetLibraryFolder> _folders = [];
  final Map<String, String?> _pendingDeletionTombstones = {};
  final Set<String> _pendingFolderDeletionTombstones = <String>{};
  final Set<String> _pendingFolderUpsertIds = <String>{};
  static const _pendingFavoriteMetadataKey = '_assetLibraryFavoritePending';

  final Set<String> _locallyRecordedUsageEvents = <String>{};
  static const _maxLocalUsageEvents = 10000;
  late final List<AssetCatalogProvider> providersForQuery = providers.isEmpty
      ? _defaultProviders()
      : List.unmodifiable(providers.take(10));
  Future<void>? _loadFuture;
  bool _loaded = false;
  bool _offline = false;

  AssetLibraryService({
    required this.scopeId,
    required this.localStorage,
    this.durableStore,
    this.client,
    this.providers = const [],
  }) {
    final normalizedScopeId = scopeId.trim();
    if (normalizedScopeId.isEmpty ||
        normalizedScopeId == 'drawing-paper' ||
        normalizedScopeId != scopeId ||
        safeAssetStorageSegment(normalizedScopeId, fallback: '') !=
            normalizedScopeId) {
      throw ArgumentError.value(
        scopeId,
        'scopeId',
        'Scope must be a path-safe project identifier.',
      );
    }
  }

  bool get isOffline => _offline;

  List<AssetLibraryItem> get items => List.unmodifiable(_items);

  List<AssetLibraryFolder> get folders => List.unmodifiable(_folders);

  @override
  Future<void> load() {
    if (_loaded) return Future<void>.value();
    final active = _loadFuture;
    if (active != null) return active;
    final future = _loadInternal();
    _loadFuture = future;
    return future.whenComplete(() {
      if (identical(_loadFuture, future)) _loadFuture = null;
    });
  }

  List<AssetCatalogProvider> _defaultProviders() {
    final proxyBaseUri = SupabaseAppConfig.assetLibraryProviderBaseUri;
    final remoteClient = client;
    if (proxyBaseUri == null || remoteClient == null) {
      return [OpenverseAssetProvider()];
    }
    final accessToken = remoteClient.auth.currentSession?.accessToken;
    return [
      OpenverseAssetProvider(
        baseUri: proxyBaseUri,
        headers: {
          if (SupabaseAppConfig.publishableKey.trim().isNotEmpty)
            'apikey': SupabaseAppConfig.publishableKey.trim(),
          if (accessToken?.trim().isNotEmpty == true)
            'authorization': 'Bearer ${accessToken!.trim()}',
        },
      ),
    ];
  }

  Future<void> _loadInternal() async {
    _offline = false;
    final storedTombstones = await localStorage
        .loadAssetLibraryDeletionTombstones(scopeId);
    _pendingDeletionTombstones
      ..clear()
      ..addAll(storedTombstones);
    _pendingFolderDeletionTombstones
      ..clear()
      ..addAll(
        await localStorage.loadAssetLibraryFolderDeletionTombstones(scopeId),
      );
    _pendingFolderUpsertIds
      ..clear()
      ..addAll(await localStorage.loadAssetLibraryFolderUpsertQueue(scopeId));
    final durable = durableStore == null
        ? const <AssetLibraryItem>[]
        : await durableStore!.loadAssetLibrary(scopeId);
    final legacy = await localStorage.loadAssetLibrary(scopeId);
    final mergedLocalById = <String, AssetLibraryItem>{
      for (final item in legacy) item.id: item,
      for (final item in durable) item.id: item,
    };
    final local = mergedLocalById.values
        .where((item) => !_pendingDeletionTombstones.containsKey(item.id))
        .toList(growable: false);
    final localFolders = await localStorage.loadAssetLibraryFolders(scopeId);
    _items
      ..clear()
      ..addAll(builtInItems(scopeId))
      ..addAll(local);
    _folders
      ..clear()
      ..addAll(
        localFolders.where(
          (folder) => !_pendingFolderDeletionTombstones.contains(folder.id),
        ),
      );
    final pendingFolderUpsertsBeforePrune = _pendingFolderUpsertIds.length;
    final localFolderIds = _folders.map((folder) => folder.id).toSet();
    _pendingFolderUpsertIds.removeWhere(
      (folderId) => !localFolderIds.contains(folderId),
    );
    if (_pendingFolderUpsertIds.length != pendingFolderUpsertsBeforePrune) {
      await _persistFolderUpsertQueue();
    }

    final remoteClient = client;
    if (remoteClient != null) {
      try {
        final response = await remoteClient
            .from('asset_library_items')
            .select()
            .eq('project_id', scopeId)
            .order('updated_at', ascending: false)
            .limit(500);
        final remoteItems = <String, AssetLibraryItem>{};
        final localById = <String, AssetLibraryItem>{
          for (final item in local) item.id: item,
        };
        final pendingRemoteItems = <String, AssetLibraryItem>{};
        for (final row in response.whereType<Map>()) {
          try {
            var item = _fromRemoteRow(Map<String, dynamic>.from(row));
            if (item.source == AssetLibrarySource.bundled) {
              throw ArgumentError('Bundled assets are local-only.');
            }
            if (_pendingDeletionTombstones.containsKey(item.id)) {
              pendingRemoteItems[item.id] = item;
              continue;
            }
            final localItem = localById[item.id];
            final mergedRemoteItem = localItem == null
                ? item
                : item.copyWith(
                    localPath: localItem.localPath,
                    favorite: _hasPendingFavorite(localItem)
                        ? localItem.favorite
                        : item.favorite,
                    metadata: _hasPendingFavorite(localItem)
                        ? {...item.metadata, _pendingFavoriteMetadataKey: true}
                        : item.metadata,
                  );
            remoteItems[item.id] = mergedRemoteItem;
            final localWins =
                localItem != null &&
                (localItem.status == AssetLibraryItemStatus.syncing ||
                    localItem.updatedAt.isAfter(item.updatedAt));
            _upsertInMemory(
              localWins
                  ? _mergeLocalWithRemoteBinary(localItem, mergedRemoteItem)
                  : mergedRemoteItem,
            );
          } catch (error) {
            debugPrint('[AssetLibrary] Ignoring invalid remote item: $error');
          }
        }
        if (_pendingDeletionTombstones.isNotEmpty) {
          final pending = await _loadPendingRemoteItems(remoteClient);
          pendingRemoteItems.addAll(pending.items);
          var tombstonesChanged = false;
          for (final entry in _pendingDeletionTombstones.entries.toList()) {
            if (pending.foundIds.contains(entry.key)) continue;
            final path = _isGeneratedUploadPath(entry.value)
                ? entry.value
                : null;
            if (await _removeStorageObject(path)) {
              _pendingDeletionTombstones.remove(entry.key);
              tombstonesChanged = true;
            }
          }
          if (tombstonesChanged) await _persistDeletionTombstones();
        }
        await _reconcileLocalItems(local, remoteItems);
        await _reconcilePendingDeletions(pendingRemoteItems);
        await _applyRemoteFavorites();
        await _reconcilePendingFolderDeletions();
        await _loadRemoteFolders();
        await _persistLocal();
      } catch (error) {
        _offline = true;
        debugPrint('[AssetLibrary] Remote catalog unavailable: $error');
      }
    }
    _loaded = true;
  }

  Future<void> _reconcileLocalItems(
    Iterable<AssetLibraryItem> localItems,
    Map<String, AssetLibraryItem> remoteItems,
  ) async {
    for (final localItem in localItems) {
      if (localItem.source == AssetLibrarySource.bundled) continue;
      final remoteItem = remoteItems[localItem.id];
      final candidate = remoteItem == null
          ? localItem
          : _mergeLocalWithRemoteBinary(localItem, remoteItem);
      final shouldSync =
          candidate.status == AssetLibraryItemStatus.syncing ||
          (remoteItem != null &&
              candidate.updatedAt.isAfter(remoteItem.updatedAt));
      if (!shouldSync || !_hasRemoteReference(candidate)) continue;
      bool synced;
      try {
        synced = await _upsertRemote(
          candidate.copyWith(status: AssetLibraryItemStatus.ready),
        );
      } catch (error) {
        _offline = true;
        debugPrint('[AssetLibrary] Local item reconciliation failed: $error');
        // Keep the pending local version visible and continue reconciling the
        // rest of the catalog on the same load.
        _upsertInMemory(candidate);
        continue;
      }
      if (synced) {
        _upsertInMemory(
          candidate.copyWith(status: AssetLibraryItemStatus.ready),
        );
      } else {
        // Keep the pending local version visible and persisted when an
        // online client still cannot write the catalog row.
        _upsertInMemory(candidate);
      }
    }
  }

  Future<({Map<String, AssetLibraryItem> items, Set<String> foundIds})>
  _loadPendingRemoteItems(SupabaseClient remoteClient) async {
    final items = <String, AssetLibraryItem>{};
    final foundIds = <String>{};
    final ids = _pendingDeletionTombstones.keys.toList(growable: false);
    for (var offset = 0; offset < ids.length; offset += 50) {
      final end = offset + 50 > ids.length ? ids.length : offset + 50;
      final response = await remoteClient
          .from('asset_library_items')
          .select()
          .eq('project_id', scopeId)
          .inFilter('id', ids.sublist(offset, end));
      for (final row in response.whereType<Map>()) {
        final rawId = row['id'];
        if (rawId is! String ||
            !_pendingDeletionTombstones.containsKey(rawId)) {
          continue;
        }
        final id = rawId;
        foundIds.add(id);
        try {
          final item = _fromRemoteRow(Map<String, dynamic>.from(row));
          if (item.source != AssetLibrarySource.bundled) items[id] = item;
        } catch (error) {
          debugPrint(
            '[AssetLibrary] Ignoring invalid pending deletion: $error',
          );
        }
      }
    }
    return (items: items, foundIds: foundIds);
  }

  Future<void> _reconcilePendingDeletions(
    Map<String, AssetLibraryItem> remoteItems,
  ) async {
    final remoteClient = client;
    if (remoteClient == null || _pendingDeletionTombstones.isEmpty) return;
    var changed = false;
    for (final entry in remoteItems.entries) {
      final tombstonePath = _pendingDeletionTombstones[entry.key];
      final safeTombstonePath = _isGeneratedUploadPath(tombstonePath)
          ? tombstonePath
          : null;
      final path = entry.value.storagePath ?? safeTombstonePath;
      final deletionItem = path == entry.value.storagePath
          ? entry.value
          : entry.value.copyWith(storagePath: path);
      try {
        await _deleteRemoteItem(deletionItem);
        if (_pendingDeletionTombstones.containsKey(entry.key)) {
          // A null storage path is a valid tombstone value, so the map
          // membership check must happen before removal.
          _pendingDeletionTombstones.remove(entry.key);
          changed = true;
        }
      } catch (error) {
        _offline = true;
        debugPrint('[AssetLibrary] Pending deletion retry failed: $error');
      }
    }
    if (changed) await _persistDeletionTombstones();
  }

  bool _hasRemoteReference(AssetLibraryItem item) =>
      item.sourceUrl != null ||
      item.downloadUrl != null ||
      item.previewUrl?.trim().toLowerCase().startsWith('https://') == true ||
      item.storagePath != null;

  AssetLibraryItem _mergeLocalWithRemoteBinary(
    AssetLibraryItem localItem,
    AssetLibraryItem remoteItem,
  ) {
    if (localItem.storagePath != null || remoteItem.storagePath == null) {
      return localItem;
    }
    return localItem.copyWith(
      storagePath: remoteItem.storagePath,
      mimeType: remoteItem.mimeType,
      sizeBytes: remoteItem.sizeBytes,
      checksum: remoteItem.checksum,
      downloadUrl: localItem.downloadUrl ?? remoteItem.downloadUrl,
    );
  }

  void _validateLookupId(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized != value ||
        normalized.length > 256 ||
        _hasAssetLibraryServiceControlCharacter(value)) {
      throw ArgumentError.value(
        value,
        field,
        'Asset library identifiers are invalid.',
      );
    }
  }

  void _validateTags(Iterable<String> tags, String field) {
    final values = tags.toList(growable: false);
    if (values.length > 50 ||
        values.any(
          (tag) =>
              tag.isEmpty ||
              tag.length > 80 ||
              tag != tag.trim() ||
              _hasAssetLibraryServiceControlCharacter(tag),
        )) {
      throw ArgumentError.value(
        values,
        field,
        'Asset library tags are invalid.',
      );
    }
  }

  @override
  Future<List<AssetLibraryFolder>> loadFolders() async {
    await load();
    return folders;
  }

  @override
  Future<AssetLibraryFolder> createFolder(
    String name, {
    String? parentId,
  }) async {
    if (parentId != null) _validateLookupId(parentId, 'parentId');
    await load();
    final normalizedParentId = parentId?.trim();
    if (normalizedParentId != null && normalizedParentId.isNotEmpty) {
      final parent = _folders
          .where((candidate) => candidate.id == normalizedParentId)
          .firstOrNull;
      if (parent == null) {
        throw ArgumentError.value(
          parentId,
          'parentId',
          'Parent folder does not belong to this asset library.',
        );
      }
    }
    final now = DateTime.now().toUtc();
    final folder = AssetLibraryFolder(
      id: const Uuid().v4(),
      scopeId: scopeId,
      name: name,
      parentId: normalizedParentId,
      createdAt: now,
      updatedAt: now,
    );
    final duplicate = _folders.where((candidate) {
      return candidate.parentId == folder.parentId &&
          candidate.name.toLowerCase() == folder.name.toLowerCase();
    }).firstOrNull;
    if (duplicate != null) return duplicate;
    _folders.add(folder);
    _pendingFolderUpsertIds.add(folder.id);
    await _persistFolders();
    await _persistFolderUpsertQueue();
    if (await _upsertRemoteFolder(folder)) {
      _pendingFolderUpsertIds.remove(folder.id);
      await _persistFolderUpsertQueue();
    }
    return folder;
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    _validateLookupId(folderId, 'folderId');
    final normalizedFolderId = folderId.trim();
    await load();
    final folder = _folders
        .where((candidate) => candidate.id == normalizedFolderId)
        .firstOrNull;
    if (folder == null) return;
    final removedFolderIds = <String>{normalizedFolderId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final candidate in _folders) {
        if (candidate.parentId != null &&
            removedFolderIds.contains(candidate.parentId) &&
            removedFolderIds.add(candidate.id)) {
          changed = true;
        }
      }
    }
    _folders.removeWhere(
      (candidate) => removedFolderIds.contains(candidate.id),
    );
    for (final item in List<AssetLibraryItem>.from(_items)) {
      if (removedFolderIds.contains(item.folderId)) {
        _upsertInMemory(
          item.copyWith(folderId: null, updatedAt: DateTime.now().toUtc()),
        );
      }
    }
    for (final removedFolderId in removedFolderIds) {
      // Re-inserting preserves insertion order so the bounded queue keeps a
      // recently retried deletion rather than an older tombstone.
      _pendingFolderDeletionTombstones.remove(removedFolderId);
      _pendingFolderDeletionTombstones.add(removedFolderId);
    }
    _pendingFolderUpsertIds.removeAll(removedFolderIds);
    await _persistFolders();
    await _persistLocal();
    await _persistFolderDeletionTombstones();
    await _persistFolderUpsertQueue();
    await _reconcilePendingFolderDeletions();
  }

  @override
  Future<AssetLibraryPage> search(AssetLibraryQuery query) async {
    if (query.scopeId != scopeId) {
      throw ArgumentError.value(
        query.scopeId,
        'query.scopeId',
        'Asset library query scope does not match the service scope.',
      );
    }
    _validateQuery(query);
    await load();
    final filtered = filterAssetLibraryItems(_items, query);
    final wantsRemote =
        query.includeRemote &&
        !query.favoritesOnly &&
        query.folderId == null &&
        query.tags.isEmpty &&
        providersForQuery.isNotEmpty;
    if (!wantsRemote) {
      final offset = int.tryParse(query.cursor ?? '') ?? 0;
      final pageItems = filtered.skip(offset).take(query.pageSize).toList();
      final nextOffset = offset + pageItems.length;
      return AssetLibraryPage(
        items: pageItems,
        nextCursor: nextOffset < filtered.length ? '$nextOffset' : null,
        fromCache: _offline,
        isOffline: _offline,
      );
    }

    final rawCursor = query.cursor;
    final remoteCursor = rawCursor?.startsWith('remote:') == true
        ? rawCursor!.substring('remote:'.length)
        : null;
    final parsedLocalOffset = rawCursor?.startsWith('local:') == true
        ? int.tryParse(rawCursor!.substring('local:'.length))
        : rawCursor == null || rawCursor.startsWith('remote:')
        ? 0
        : int.tryParse(rawCursor);
    final localOffset = parsedLocalOffset == null || parsedLocalOffset < 0
        ? 0
        : parsedLocalOffset;
    final localItems = remoteCursor == null
        ? filtered.skip(localOffset).take(query.pageSize).toList()
        : const <AssetLibraryItem>[];
    final remaining = query.pageSize - localItems.length;
    final remoteItems = <AssetLibraryItem>[];
    String? nextRemoteCursor;
    var providerFailure = false;
    if (remaining > 0 || remoteCursor != null) {
      final providerQuery = AssetLibraryQuery(
        scopeId: scopeId,
        kind: query.kind,
        query: query.query,
        pageSize: remoteCursor == null ? remaining : query.pageSize,
        cursor: remoteCursor,
      );
      for (final provider in providersForQuery) {
        final cacheKey = _providerCacheKey(provider, providerQuery);
        try {
          final remotePage = await provider.search(providerQuery);
          remoteItems.addAll(remotePage.items);
          final safeRemoteCursor = _safeProviderCursor(remotePage.nextCursor);
          nextRemoteCursor ??= safeRemoteCursor;
          try {
            await localStorage.saveAssetLibraryProviderCache(
              scopeId,
              provider.id,
              cacheKey,
              AssetLibraryProviderCache(
                items: remotePage.items,
                nextCursor: safeRemoteCursor,
                fetchedAt: DateTime.now().toUtc(),
              ),
            );
          } catch (cacheError) {
            debugPrint(
              '[AssetLibrary] Provider cache write skipped: $cacheError',
            );
          }
        } catch (error) {
          providerFailure = true;
          if (error is AssetProviderException) {
            debugPrint(
              '[AssetLibrary] ${error.provider} search unavailable: $error',
            );
          } else {
            debugPrint(
              '[AssetLibrary] ${provider.id} search unavailable: $error',
            );
          }
          final cached = await localStorage.loadAssetLibraryProviderCache(
            scopeId,
            provider.id,
            cacheKey,
          );
          if (cached != null && cached.isUsable()) {
            remoteItems.addAll(cached.items);
            nextRemoteCursor ??= _safeProviderCursor(cached.nextCursor);
          }
        }
      }
    } else if (localOffset + localItems.length < filtered.length) {
      // There are more local catalog records. Keep the provider cursor out of
      // the way until the local collection has been exhausted.
      nextRemoteCursor = null;
    } else if (providersForQuery.isNotEmpty) {
      // The local page is full and is the last local page. Continue with
      // provider page one on the next request instead of dropping provider
      // results altogether.
      nextRemoteCursor = '1';
    }
    if (providerFailure) {
      _offline = true;
    } else if (remaining > 0 || remoteCursor != null) {
      _offline = false;
    }
    final seen = <String>{};
    String dedupeKey(AssetLibraryItem item) => item.providerAssetId == null
        ? item.id
        : '${item.source.name}:${item.providerAssetId}';
    final dedupedLocal = [
      for (final item in localItems)
        if (seen.add(dedupeKey(item))) item,
    ];
    final dedupedRemote = [
      for (final item in remoteItems)
        if (seen.add(dedupeKey(item))) item,
    ];
    // Keep the local-first contract independent of the requested sort: the
    // provider is an additive source, never something that displaces local
    // catalog records from the current page.
    final ordered = [
      ...filterAssetLibraryItems(dedupedLocal, query),
      ...filterAssetLibraryItems(dedupedRemote, query),
    ];
    final nextCursor = nextRemoteCursor != null
        ? 'remote:$nextRemoteCursor'
        : localOffset + localItems.length < filtered.length
        ? 'local:${localOffset + localItems.length}'
        : null;
    return AssetLibraryPage(
      items: ordered.take(query.pageSize).toList(),
      nextCursor: nextCursor,
      fromCache: _offline,
      isOffline: _offline,
    );
  }

  void _validateQuery(AssetLibraryQuery query) {
    if (query.pageSize < 1 || query.pageSize > 100) {
      throw ArgumentError.value(
        query.pageSize,
        'query.pageSize',
        'Asset library pages must contain 1 to 100 items.',
      );
    }
    if (query.query.length > 200 ||
        _hasAssetLibraryServiceControlCharacter(query.query)) {
      throw ArgumentError.value(
        query.query,
        'query.query',
        'Asset library searches must be bounded and control-free.',
      );
    }
    if (query.cursor != null &&
        (query.cursor != query.cursor!.trim() ||
            query.cursor!.length > 128 ||
            _hasAssetLibraryServiceControlCharacter(query.cursor!))) {
      throw ArgumentError.value(
        query.cursor,
        'query.cursor',
        'Asset library cursors are invalid.',
      );
    }
    final cursor = query.cursor;
    if (cursor != null) {
      final isLocal = cursor.startsWith('local:');
      final isRemote = cursor.startsWith('remote:');
      final value = isLocal || isRemote
          ? cursor.substring(cursor.indexOf(':') + 1)
          : cursor;
      final valid = isRemote
          ? value.isNotEmpty
          : int.tryParse(value) != null && int.parse(value) >= 0;
      if (!valid) {
        throw ArgumentError.value(
          query.cursor,
          'query.cursor',
          'Asset library cursors are invalid.',
        );
      }
    }
    if (query.tags.length > 50 ||
        query.tags.any(
          (tag) =>
              tag.isEmpty ||
              tag.length > 80 ||
              tag != tag.trim() ||
              _hasAssetLibraryServiceControlCharacter(tag),
        )) {
      throw ArgumentError.value(
        query.tags,
        'query.tags',
        'Asset library tags are invalid.',
      );
    }
    if (query.folderId != null &&
        (_hasAssetLibraryServiceControlCharacter(query.folderId!) ||
            query.folderId != query.folderId!.trim())) {
      throw ArgumentError.value(
        query.folderId,
        'query.folderId',
        'Asset library folder IDs are invalid.',
      );
    }
    final folderId = query.folderId?.trim();
    if (folderId != null &&
        (folderId.length > 256 ||
            _hasAssetLibraryServiceControlCharacter(folderId))) {
      throw ArgumentError.value(
        query.folderId,
        'query.folderId',
        'Asset library folder IDs are invalid.',
      );
    }
  }

  String? _safeProviderCursor(String? value) {
    if (value == null ||
        value.length > 120 ||
        value != value.trim() ||
        _hasAssetLibraryServiceControlCharacter(value)) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _providerCacheKey(
    AssetCatalogProvider provider,
    AssetLibraryQuery query,
  ) => jsonEncode({
    'provider': provider.id,
    'kind': query.kind?.name,
    'query': query.query.trim().toLowerCase(),
    'pageSize': query.pageSize,
    'cursor': query.cursor,
  });

  @override
  Future<AssetLibraryItem> save(AssetLibraryItem item) => _save(item);

  Future<AssetLibraryItem> _save(
    AssetLibraryItem item, {
    bool allowLocalStorageFallback = false,
  }) async {
    if (item.source == AssetLibrarySource.bundled) {
      throw ArgumentError('Bundled assets are local-only.');
    }
    if ((item.source == AssetLibrarySource.openverse ||
            item.source == AssetLibrarySource.wikimedia ||
            item.source == AssetLibrarySource.remote) &&
        item.license?.trim().isNotEmpty != true) {
      throw ArgumentError('External asset licenses are required');
    }
    if (item.scopeId != scopeId) {
      throw ArgumentError.value(
        item.scopeId,
        'item.scopeId',
        'Asset library item scope does not match the service scope.',
      );
    }
    if (!_isScopedStoragePath(item.storagePath)) {
      throw ArgumentError.value(
        item.storagePath,
        'item.storagePath',
        'Storage paths must belong to the active project.',
      );
    }
    await load();
    final existing = _items
        .where((candidate) => candidate.id == item.id)
        .firstOrNull;
    final next = existing == null
        ? item
        : item.copyWith(
            favorite: item.favorite || existing.favorite,
            createdAt: existing.createdAt,
          );
    final checksumValue = next.checksum;
    if (checksumValue != null) {
      final duplicate = _items
          .where(
            (candidate) =>
                candidate.id != next.id && candidate.checksum == checksumValue,
          )
          .firstOrNull;
      if (duplicate != null) return duplicate;
    }
    final previousItems = List<AssetLibraryItem>.from(_items);
    final previousTombstones = Map<String, String?>.from(
      _pendingDeletionTombstones,
    );
    _pendingDeletionTombstones.remove(next.id);
    try {
      final shouldSync = _hasRemoteReference(next);
      final remoteCandidate = next.copyWith(
        status: shouldSync ? AssetLibraryItemStatus.ready : next.status,
      );
      final canUseLocalFallback =
          allowLocalStorageFallback &&
          next.localPath?.trim().isNotEmpty == true;
      _upsertInMemory(
        shouldSync && !canUseLocalFallback
            ? next.copyWith(status: AssetLibraryItemStatus.syncing)
            : next,
      );
      await _persistLocal();
      final synced = shouldSync ? await _upsertRemote(remoteCandidate) : false;
      if (synced) {
        _upsertInMemory(remoteCandidate);
        try {
          await _persistLocal();
        } catch (error) {
          // The remote row and quota transition are already committed. A
          // local-cache failure must not make the upload look failed and lead
          // the caller to delete a binary that the catalog now references.
          _offline = true;
          debugPrint('[AssetLibrary] Remote item cache write failed: $error');
        }
        return remoteCandidate;
      }
      if (shouldSync) {
        final pending = next.copyWith(
          status: canUseLocalFallback
              ? AssetLibraryItemStatus.ready
              : AssetLibraryItemStatus.syncing,
        );
        _upsertInMemory(pending);
        await _persistLocal();
        return pending;
      }
      return next;
    } catch (error) {
      _items
        ..clear()
        ..addAll(previousItems);
      _pendingDeletionTombstones
        ..clear()
        ..addAll(previousTombstones);
      try {
        await _persistLocal();
      } catch (rollbackError) {
        debugPrint('[AssetLibrary] Local item rollback failed: $rollbackError');
      }
      // Once the remote row is confirmed, leave its binary/quota intact even
      // if the final local-cache write fails; the next load can rehydrate it.
      rethrow;
    }
  }

  @override
  Future<AssetLibraryItem> saveProviderItem(AssetLibraryItem item) async {
    if (item.scopeId != scopeId) {
      throw ArgumentError.value(
        item.scopeId,
        'item.scopeId',
        'Asset provider item scope does not match the service scope.',
      );
    }
    await load();
    final existing = _items.where((candidate) {
      if (candidate.source != item.source) return false;
      if (candidate.providerAssetId != null && item.providerAssetId != null) {
        return candidate.providerAssetId == item.providerAssetId;
      }
      return candidate.id == item.id;
    }).firstOrNull;
    return save(existing == null ? item : item.copyWith(id: existing.id));
  }

  @override
  Future<AssetLibraryItem> saveUpload(
    AssetPickerResult result, {
    String? folderId,
    Iterable<String> tags = const [],
  }) async {
    await load();
    final uploadTags = tags.toList(growable: false);
    try {
      _validateTags(uploadTags, 'tags');
    } catch (_) {
      await _cleanupPickerStorage(result);
      rethrow;
    }
    if (folderId != null &&
        folderId.isNotEmpty &&
        folderId != folderId.trim()) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Asset library folder IDs are invalid.',
      );
    }
    if (folderId != null && _hasAssetLibraryServiceControlCharacter(folderId)) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Asset library folder IDs are invalid.',
      );
    }
    final normalizedFolderId = folderId?.trim();
    if (normalizedFolderId != null &&
        normalizedFolderId.isNotEmpty &&
        !_folders.any((folder) => folder.id == normalizedFolderId)) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Folder does not belong to this asset library.',
      );
    }
    final now = DateTime.now().toUtc();
    final bytes = result.bytes;
    final checksum = bytes == null || bytes.isEmpty
        ? null
        : 'sha256:${sha256.convert(bytes)}';
    final mimeName =
        result.extension?.trim().isNotEmpty == true &&
            !result.name.contains('.')
        ? '${result.name}.${result.extension}'
        : result.name;
    final mimeType = inferAssetMimeType(mimeName);
    if (result.errorMessage != null &&
        result.durableReference == null &&
        (bytes == null || bytes.isEmpty)) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        result.errorMessage,
        'result.errorMessage',
        'The selected asset could not be read or stored.',
      );
    }
    if (bytes != null && !assetBytesMatchMimeSignature(bytes, mimeType)) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        result.name,
        'result.bytes',
        'Asset bytes do not match the detected MIME type.',
      );
    }
    final remoteReference = result.remoteUrl?.trim();
    if (remoteReference != null &&
        remoteReference.isNotEmpty &&
        !remoteReference.toLowerCase().startsWith('https://')) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        result.remoteUrl,
        'result.remoteUrl',
        'Remote asset references must use HTTPS.',
      );
    }
    final storageReference = result.storagePath?.trim();
    if (storageReference != null &&
        storageReference.isNotEmpty &&
        !_isScopedStoragePath(storageReference)) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        result.storagePath,
        'result.storagePath',
        'Uploaded asset paths must belong to the active project.',
      );
    }
    if (storageReference != null &&
        storageReference.isNotEmpty &&
        remoteReference != null &&
        remoteReference.isNotEmpty) {
      await _cleanupPickerStorage(result);
      throw ArgumentError(
        'A private Storage upload must not persist a public URL alongside its path.',
      );
    }
    final hasRemoteReference =
        remoteReference?.isNotEmpty == true ||
        storageReference?.isNotEmpty == true;
    final localReference = result.path?.trim();
    final localPathIsNonLocal =
        localReference != null &&
        localReference.isNotEmpty &&
        !RegExp(r'^[a-z]:[\\/]').hasMatch(localReference.toLowerCase()) &&
        RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(localReference.toLowerCase());
    if (localPathIsNonLocal) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        result.path,
        'result.path',
        'Asset paths cannot be remote URLs or binary data URIs.',
      );
    }
    final reference = result.durableReference;
    // Picked bytes are authoritative; a caller-controlled size hint must not
    // under-report the bytes that will be billed or persisted.
    final sizeBytes = bytes != null
        ? bytes.lengthInBytes
        : result.size != null && result.size! > 0
        ? result.size
        : null;
    if (sizeBytes != null && sizeBytes > 512 * 1024 * 1024) {
      await _cleanupPickerStorage(result);
      throw ArgumentError.value(
        sizeBytes,
        'result.size',
        'Asset uploads cannot exceed 512 MB.',
      );
    }
    final canKeepSmallWebPreview =
        reference == null &&
        bytes != null &&
        bytes.length <= 512 * 1024 &&
        mimeType.startsWith('image/');
    late AssetLibraryItem item;
    try {
      item = AssetLibraryItem(
        id: const Uuid().v4(),
        scopeId: scopeId,
        kind: _kindFromMime(mimeType),
        source: AssetLibrarySource.upload,
        status: reference == null && !hasRemoteReference
            ? AssetLibraryItemStatus.missing
            : AssetLibraryItemStatus.ready,
        name: result.name,
        sourceUrl: result.remoteUrl,
        previewUrl:
            result.remoteUrl ??
            (result.path == null && canKeepSmallWebPreview
                ? result.previewUrl
                : null),
        localPath: result.path,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        checksum: checksum,
        // The catalog stores a stable bucket-relative path. Signed URLs are
        // resolved only by runtime readers and are never persisted here.
        storagePath: storageReference,
        folderId: normalizedFolderId?.isEmpty == true
            ? null
            : normalizedFolderId,
        tags: uploadTags,
        license: 'User supplied',
        createdAt: now,
        updatedAt: now,
        metadata: {
          'originalName': result.name,
          if (canKeepSmallWebPreview) 'smallPreviewOnly': true,
        },
      );
    } catch (_) {
      await _cleanupPickerStorage(result);
      rethrow;
    }
    try {
      final saved = await _save(
        item,
        allowLocalStorageFallback: item.localPath?.trim().isNotEmpty == true,
      );
      if (saved.id != item.id || item.storagePath == null) {
        // A checksum duplicate, a local fallback, or a failed cloud upload
        // leaves the staged object unreferenced by this catalog row.
        await _cleanupPickerStorage(result);
      }
      return saved;
    } catch (error, stackTrace) {
      // A unique checksum conflict or an ambiguous response may still have a
      // committed catalog row. Resolve that row before deleting the staged
      // object; otherwise a committed upload could be left pointing at a
      // missing Storage object.
      final remoteDuplicate = checksum == null
          ? null
          : await _findRemoteChecksumDuplicate(checksum);
      if (remoteDuplicate != null && remoteDuplicate.id == item.id) {
        return remoteDuplicate;
      }
      // save() rolls back its catalog state; discard the staged remote object
      // and retain a native local copy when the picker supplied one. This
      // preserves local-first behavior without leaving a missing Storage
      // reference in the catalog.
      final binaryCleanupConfirmed = await _cleanupPickerStorage(result);
      if (remoteDuplicate != null) {
        if (!binaryCleanupConfirmed &&
            item.storagePath != null &&
            client != null) {
          _pendingDeletionTombstones[item.id] = item.storagePath;
          await _persistDeletionTombstones();
        }
        return remoteDuplicate;
      }
      var remoteCleanupConfirmed = true;
      if (item.storagePath != null && client != null) {
        remoteCleanupConfirmed = await _deleteRemoteCatalogRow(item.id);
        if (!binaryCleanupConfirmed || !remoteCleanupConfirmed) {
          // Keep the path until both sides are known to be gone. This covers
          // ambiguous catalog responses and a transient Storage outage.
          _pendingDeletionTombstones[item.id] = item.storagePath;
          await _persistDeletionTombstones();
        }
      }
      final fallback = await _saveLocalUploadFallback(
        binaryCleanupConfirmed && remoteCleanupConfirmed
            ? item
            : item.copyWith(id: const Uuid().v4()),
      );
      if (fallback != null) return fallback;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AssetLibraryItem?> _saveLocalUploadFallback(
    AssetLibraryItem item,
  ) async {
    if (item.localPath?.trim().isNotEmpty != true) return null;
    try {
      return await _save(
        item.copyWith(
          status: AssetLibraryItemStatus.ready,
          sourceUrl: null,
          previewUrl: null,
          downloadUrl: null,
          storagePath: null,
        ),
        allowLocalStorageFallback: true,
      );
    } catch (fallbackError) {
      debugPrint('[AssetLibrary] Local upload fallback failed: $fallbackError');
      return null;
    }
  }

  Future<bool> _cleanupPickerStorage(AssetPickerResult result) async {
    final path = result.storagePath;
    if (!result.storagePathOwned || !_isGeneratedUploadPath(path)) return true;
    return _removeStorageObject(path);
  }

  bool _isGeneratedUploadPath(String? path) {
    if (!_isScopedStoragePath(path)) return false;
    final pattern = RegExp(
      '^${RegExp.escape(scopeId)}/(?:images|files|audio|video|library)/'
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[^/]+$',
      caseSensitive: false,
    );
    return pattern.hasMatch(path!);
  }

  @override
  Future<void> setFavorite(String itemId, bool active) async {
    _validateLookupId(itemId, 'itemId');
    final normalizedItemId = itemId.trim();
    await load();
    final item = _items
        .where((candidate) => candidate.id == normalizedItemId)
        .firstOrNull;
    if (item == null || item.source == AssetLibrarySource.bundled) return;
    final remoteClient = client;
    final userId = remoteClient?.auth.currentUser?.id;
    final updated = item.copyWith(
      favorite: active,
      updatedAt: DateTime.now().toUtc(),
      metadata: remoteClient != null
          ? _pendingFavoriteMetadata(item.metadata)
          : item.metadata,
    );
    _upsertInMemory(updated);
    await _persistLocal();

    if (remoteClient == null || userId == null) return;
    try {
      await _writeRemoteFavorite(
        remoteClient,
        normalizedItemId,
        userId,
        active,
      );
      _upsertInMemory(_clearPendingFavorite(updated));
      await _persistLocal();
    } catch (error) {
      _offline = true;
      debugPrint('[AssetLibrary] Favorite sync unavailable: $error');
    }
  }

  @override
  Future<void> updateMetadata(
    String itemId, {
    String? name,
    String? folderId,
    Iterable<String>? tags,
  }) async {
    _validateLookupId(itemId, 'itemId');
    final normalizedItemId = itemId.trim();
    await load();
    final item = _items
        .where((candidate) => candidate.id == normalizedItemId)
        .firstOrNull;
    if (item == null || item.source == AssetLibrarySource.bundled) return;
    final metadataTags = tags?.toList(growable: false);
    if (metadataTags != null) _validateTags(metadataTags, 'tags');
    if (folderId != null &&
        folderId.isNotEmpty &&
        folderId != folderId.trim()) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Asset library folder IDs are invalid.',
      );
    }
    if (folderId != null && _hasAssetLibraryServiceControlCharacter(folderId)) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Asset library folder IDs are invalid.',
      );
    }
    final normalizedFolderId = folderId?.trim();
    if (normalizedFolderId != null &&
        normalizedFolderId.isNotEmpty &&
        !_folders.any((folder) => folder.id == normalizedFolderId)) {
      throw ArgumentError.value(
        folderId,
        'folderId',
        'Folder does not belong to this asset library.',
      );
    }
    await save(
      item.copyWith(
        name: name?.trim().isEmpty == true ? item.name : name,
        folderId: normalizedFolderId,
        tags: metadataTags,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> delete(String itemId) async {
    _validateLookupId(itemId, 'itemId');
    final normalizedItemId = itemId.trim();
    await load();
    final item = _items
        .where((candidate) => candidate.id == normalizedItemId)
        .firstOrNull;
    if (item == null || item.source == AssetLibrarySource.bundled) return;
    _items.removeWhere((candidate) => candidate.id == normalizedItemId);
    _pendingDeletionTombstones.remove(item.id);
    _pendingDeletionTombstones[item.id] = item.storagePath;
    await _persistLocal();

    final remoteClient = client;
    if (remoteClient == null) return;
    try {
      await _deleteRemoteItem(item);
      _pendingDeletionTombstones.remove(item.id);
      await _persistLocal();
    } catch (error) {
      // Keep the local tombstone so a later online load retries the remote
      // catalog and Storage deletion instead of resurrecting the item.
      _offline = true;
      debugPrint('[AssetLibrary] Item deletion sync unavailable: $error');
    }
  }

  /// Removes aged upload objects that no longer have a catalog row.
  ///
  /// This is intentionally conservative: only UUID-named asset-library upload
  /// paths are eligible, a grace period avoids deleting an in-flight upload,
  /// and collaborative/AI objects in the shared bucket are excluded.
  Future<int> cleanupOrphanedStorage({
    Duration minimumAge = const Duration(hours: 1),
    int maxObjects = 500,
  }) async {
    if (minimumAge < Duration.zero) {
      throw ArgumentError.value(
        minimumAge,
        'minimumAge',
        'Cleanup age cannot be negative.',
      );
    }
    if (maxObjects < 1 || maxObjects > 5000) {
      throw ArgumentError.value(
        maxObjects,
        'maxObjects',
        'Cleanup must inspect between 1 and 5000 objects.',
      );
    }
    await load();
    final remoteClient = client;
    if (remoteClient == null) return 0;

    final referenced = <String>{};
    var offset = 0;
    const pageSize = 1000;
    while (true) {
      final rows = await remoteClient
          .from('asset_library_items')
          .select('storage_path')
          .eq('project_id', scopeId)
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        final rawPath = row['storage_path'];
        if (rawPath is String && _isGeneratedUploadPath(rawPath)) {
          referenced.add(rawPath);
        }
      }
      if (rows.length < pageSize) break;
      offset += pageSize;
    }

    final now = DateTime.now().toUtc();
    final eligiblePath = RegExp(
      '^${RegExp.escape(scopeId)}/(?:images|files|audio|video|library)/'
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[^/]+$',
      caseSensitive: false,
    );
    var deleted = 0;
    var inspected = 0;
    var pagesRead = 0;
    for (final folder in const [
      'images',
      'files',
      'audio',
      'video',
      'library',
    ]) {
      if (inspected >= maxObjects) break;
      String? cursor;
      do {
        // A malformed Storage pagination response must not turn cleanup into
        // an unbounded request loop. The object budget is also the request
        // budget in the worst case of one object per page.
        if (pagesRead >= maxObjects) break;
        pagesRead++;
        final page = await remoteClient.storage
            .from('assets')
            .listPaginated(
              options: PaginatedSearchOptions(
                prefix: '$scopeId/$folder/',
                cursor: cursor,
                limit: 1000,
                withDelimiter: false,
              ),
            );
        for (final object in page.objects) {
          if (inspected++ >= maxObjects) break;
          final path = object.key ?? '$scopeId/$folder/${object.name}';
          if (!eligiblePath.hasMatch(path) || referenced.contains(path)) {
            continue;
          }
          final updatedAt = DateTime.tryParse(
            object.updatedAt ?? object.createdAt ?? '',
          )?.toUtc();
          if (updatedAt == null || now.difference(updatedAt) < minimumAge) {
            continue;
          }
          if (await _removeStorageObject(path)) deleted++;
        }
        if (inspected >= maxObjects || !page.hasNext) break;
        final nextCursor = page.nextCursor;
        if (nextCursor == null || nextCursor.isEmpty || nextCursor == cursor) {
          break;
        }
        cursor = nextCursor;
      } while (cursor.isNotEmpty);
    }
    return deleted;
  }

  @override
  Future<void> recordUsage(
    String itemId, {
    String? projectId,
    String? nodeId,
  }) async {
    final normalizedItemId = itemId.trim();
    if (_hasAssetLibraryServiceControlCharacter(itemId) ||
        itemId != normalizedItemId ||
        normalizedItemId.isEmpty ||
        normalizedItemId.length > 256) {
      throw ArgumentError.value(
        itemId,
        'itemId',
        'Asset library usage item IDs are invalid.',
      );
    }
    final trimmedNodeId = nodeId?.trim();
    final normalizedNodeId = trimmedNodeId == null || trimmedNodeId.isEmpty
        ? null
        : trimmedNodeId;
    if ((nodeId != null &&
            (_hasAssetLibraryServiceControlCharacter(nodeId) ||
                nodeId != trimmedNodeId)) ||
        (normalizedNodeId != null && normalizedNodeId.length > 256)) {
      throw ArgumentError.value(
        nodeId,
        'nodeId',
        'Asset library usage node IDs are invalid.',
      );
    }
    if (projectId != null && projectId != scopeId) {
      throw ArgumentError.value(
        projectId,
        'projectId',
        'Usage project does not match the asset library scope.',
      );
    }
    await load();
    final item = _items
        .where((candidate) => candidate.id == normalizedItemId)
        .firstOrNull;
    if (item == null) return;

    final usageKey = normalizedNodeId == null
        ? null
        : '$normalizedItemId:$normalizedNodeId';
    final remoteClient = item.source == AssetLibrarySource.bundled
        ? null
        : client;
    var updateLocal = true;
    if (remoteClient != null) {
      try {
        final result = await remoteClient.rpc(
          'record_asset_library_usage',
          params: {
            'p_project_id': scopeId,
            'p_item_id': normalizedItemId,
            'p_node_id': normalizedNodeId,
          },
        );
        updateLocal = _usageRpcRecorded(result);
        if (updateLocal &&
            usageKey != null &&
            !_rememberLocalUsageEvent(usageKey)) {
          // A retry after a network error may have been accepted remotely.
          // Keep the local count idempotent while the RPC remains authoritative.
          updateLocal = false;
        }
        if (!updateLocal && usageKey != null) {
          _rememberLocalUsageEvent(usageKey);
        }
      } catch (error) {
        _offline = true;
        debugPrint('[AssetLibrary] Usage sync unavailable: $error');
        updateLocal = usageKey == null || _rememberLocalUsageEvent(usageKey);
      }
    } else if (usageKey != null && !_rememberLocalUsageEvent(usageKey)) {
      updateLocal = false;
    }

    if (!updateLocal) return;
    _upsertInMemory(
      item.copyWith(
        usageCount: item.usageCount + 1,
        lastUsedAt: DateTime.now().toUtc(),
      ),
    );
    await _persistLocal();
  }

  bool _rememberLocalUsageEvent(String key) {
    if (_locallyRecordedUsageEvents.contains(key)) return false;
    if (_locallyRecordedUsageEvents.length >= _maxLocalUsageEvents) {
      _locallyRecordedUsageEvents.remove(_locallyRecordedUsageEvents.first);
    }
    _locallyRecordedUsageEvents.add(key);
    return true;
  }

  bool _usageRpcRecorded(Object? result) {
    if (result is bool) return result;
    if (result is List && result.length == 1) {
      return _usageRpcRecorded(result.first);
    }
    if (result is Map) {
      final duplicate = result['duplicate'];
      if (duplicate is bool && duplicate) return false;
      final accepted = result['accepted'];
      if (accepted is bool) return accepted;
      if (result.length == 1) return _usageRpcRecorded(result.values.first);
    }
    // Older deployments used a void RPC. Treat a successful response as an
    // accepted event so local-first clients do not lose usage telemetry.
    return true;
  }

  Future<void> _deleteRemoteItem(AssetLibraryItem item) async {
    final remoteClient = client;
    if (remoteClient == null) return;
    // Remove the binary first. If Storage is unavailable, keep the catalog
    // row so a retry still has the metadata needed to finish cleanup.
    final binaryRemoved = await _removeStorageObject(item.storagePath);
    if (!binaryRemoved) {
      throw StateError('Asset binary could not be removed from Storage.');
    }
    final deletedRows = await remoteClient
        .from('asset_library_items')
        .delete()
        .eq('id', item.id)
        .eq('project_id', scopeId)
        .select('id');
    if (deletedRows.isEmpty) {
      throw StateError('Asset catalog row could not be removed.');
    }
    // The database delete trigger releases the quota in the same transaction.
  }

  Future<AssetLibraryItem?> _findRemoteChecksumDuplicate(
    String checksum,
  ) async {
    final remoteClient = client;
    if (remoteClient == null) return null;
    try {
      final response = await remoteClient
          .from('asset_library_items')
          .select()
          .eq('project_id', scopeId)
          .eq('checksum', checksum)
          .limit(1);
      for (final row in response.whereType<Map>()) {
        try {
          final item = _fromRemoteRow(Map<String, dynamic>.from(row));
          if (item.source != AssetLibrarySource.bundled) return item;
        } catch (error) {
          debugPrint('[AssetLibrary] Ignoring duplicate catalog row: $error');
        }
      }
    } catch (error) {
      debugPrint('[AssetLibrary] Duplicate lookup unavailable: $error');
    }
    return null;
  }

  Future<bool> _deleteRemoteCatalogRow(String itemId) async {
    final remoteClient = client;
    if (remoteClient == null) return true;
    try {
      // This cleanup is used after an ambiguous insert response. Deleting an
      // absent row is success; deleting a committed row also releases quota
      // through the database trigger.
      await remoteClient
          .from('asset_library_items')
          .delete()
          .eq('id', itemId)
          .eq('project_id', scopeId)
          .select('id');
      return true;
    } catch (error) {
      _offline = true;
      debugPrint('[AssetLibrary] Failed to reconcile an upload row: $error');
      return false;
    }
  }

  bool _isQuotaExceeded(Object error) =>
      error is PostgrestException && error.code == '54000' ||
      error.toString().toLowerCase().contains('workspace quota exceeded');

  Future<bool> _removeStorageObject(String? storagePath) async {
    if (storagePath != null && storagePath != storagePath.trim()) return false;
    final path = storagePath;
    final remoteClient = client;
    if (path == null || path.isEmpty) return true;
    if (!_isGeneratedUploadPath(path) || remoteClient == null) return false;
    try {
      await remoteClient.storage.from('assets').remove([path]);
      return true;
    } catch (error) {
      debugPrint('[AssetLibrary] Orphaned asset cleanup failed: $error');
      return false;
    }
  }

  Future<void> _persistLocal() async {
    final localItems = _items
        .where((item) => item.source != AssetLibrarySource.bundled)
        .toList(growable: false);
    if (durableStore != null) {
      await durableStore!.saveAssetLibrary(scopeId, localItems);
    }
    await localStorage.saveAssetLibrary(scopeId, localItems);
    await _persistDeletionTombstones();
  }

  Future<void> _persistDeletionTombstones() => localStorage
      .saveAssetLibraryDeletionTombstones(scopeId, _pendingDeletionTombstones);

  Future<void> _persistFolderDeletionTombstones() =>
      localStorage.saveAssetLibraryFolderDeletionTombstones(
        scopeId,
        _pendingFolderDeletionTombstones,
      );

  Future<void> _persistFolderUpsertQueue() => localStorage
      .saveAssetLibraryFolderUpsertQueue(scopeId, _pendingFolderUpsertIds);

  Future<void> _persistFolders() =>
      localStorage.saveAssetLibraryFolders(scopeId, _folders);

  Future<bool> _upsertRemoteFolder(AssetLibraryFolder folder) async {
    final remoteClient = client;
    if (remoteClient == null) {
      _offline = true;
      return false;
    }
    try {
      await remoteClient.from('asset_library_folders').upsert({
        'id': folder.id,
        'project_id': scopeId,
        'parent_id': folder.parentId,
        'name': folder.name,
        'created_at': folder.createdAt.toIso8601String(),
        'updated_at': folder.updatedAt.toIso8601String(),
      });
      return true;
    } catch (error) {
      _offline = true;
      debugPrint('[AssetLibrary] Folder sync unavailable: $error');
      return false;
    }
  }

  Future<void> _reconcilePendingFolderDeletions() async {
    final remoteClient = client;
    if (remoteClient == null || _pendingFolderDeletionTombstones.isEmpty) {
      return;
    }
    final ids = _pendingFolderDeletionTombstones.toList(growable: false);
    try {
      for (var offset = 0; offset < ids.length; offset += 50) {
        final end = offset + 50 > ids.length ? ids.length : offset + 50;
        await remoteClient
            .from('asset_library_folders')
            .delete()
            .eq('project_id', scopeId)
            .inFilter('id', ids.sublist(offset, end));
      }
      _pendingFolderUpsertIds.removeAll(_pendingFolderDeletionTombstones);
      _pendingFolderDeletionTombstones.clear();
      await localStorage.saveAssetLibraryFolderDeletionTombstones(
        scopeId,
        _pendingFolderDeletionTombstones,
      );
      await _persistFolderUpsertQueue();
    } catch (error) {
      _offline = true;
      debugPrint('[AssetLibrary] Pending folder deletion failed: $error');
    }
  }

  Future<void> _loadRemoteFolders() async {
    final remoteClient = client;
    if (remoteClient == null) return;
    final localFolders = List<AssetLibraryFolder>.from(_folders);
    final response = await remoteClient
        .from('asset_library_folders')
        .select()
        .eq('project_id', scopeId)
        .order('name')
        .limit(500);
    final remoteFolders = <String, AssetLibraryFolder>{};
    for (final row in response.whereType<Map>()) {
      try {
        final rawScopeId = row['project_id'];
        if (rawScopeId is! String || rawScopeId != scopeId) {
          final rowScopeId = rawScopeId is String ? rawScopeId : '<invalid>';
          throw ArgumentError.value(
            rowScopeId,
            'row.project_id',
            'Remote folder scope does not match the active project.',
          );
        }
        final rowScopeId = rawScopeId;
        final rawFolderId = row['id'];
        if (rawFolderId is! String) {
          throw const FormatException('Remote folder ID is invalid.');
        }
        final folderId = rawFolderId;
        if (_pendingFolderDeletionTombstones.contains(folderId)) continue;
        final folder = AssetLibraryFolder.fromJson({
          'id': folderId,
          'scopeId': rowScopeId,
          'parentId': row['parent_id'],
          'name': row['name'],
          'createdAt': row['created_at'],
          'updatedAt': row['updated_at'],
        });
        remoteFolders[folder.id] = folder;
      } catch (error) {
        debugPrint('[AssetLibrary] Ignoring invalid remote folder: $error');
      }
    }

    _folders
      ..clear()
      ..addAll(remoteFolders.values);
    for (final localFolder in localFolders) {
      if (_pendingFolderDeletionTombstones.contains(localFolder.id)) continue;
      final remoteFolder = remoteFolders[localFolder.id];
      final localWins =
          _pendingFolderUpsertIds.contains(localFolder.id) ||
          (remoteFolder != null &&
              localFolder.updatedAt.isAfter(remoteFolder.updatedAt));
      if (!localWins) continue;
      final synced = await _upsertRemoteFolder(localFolder);
      _folders.removeWhere((folder) => folder.id == localFolder.id);
      _folders.add(localFolder);
      if (synced) _pendingFolderUpsertIds.remove(localFolder.id);
    }
    await _persistFolders();
    await _persistFolderUpsertQueue();
  }

  Future<bool> _upsertRemote(AssetLibraryItem item) async {
    if (item.source == AssetLibrarySource.bundled) return false;
    final remoteClient = client;
    if (remoteClient == null) {
      _offline = true;
      return false;
    }
    try {
      await remoteClient.from('asset_library_items').upsert(_toRemoteRow(item));
      return true;
    } catch (error) {
      _offline = true;
      debugPrint('[AssetLibrary] Item sync unavailable: $error');
      if (_isQuotaExceeded(error)) {
        throw const AssetLibraryQuotaExceededException();
      }
      // A Storage-backed item must not report success while its catalog row is
      // missing. The caller can roll back the local record and clean up the
      // object; local-only items remain usable offline.
      if (item.storagePath != null) rethrow;
      return false;
    }
  }

  Future<void> _applyRemoteFavorites() async {
    final remoteClient = client;
    final userId = remoteClient?.auth.currentUser?.id;
    if (remoteClient == null || userId == null) return;
    final response = await remoteClient
        .from('asset_library_favorites')
        .select('item_id')
        .eq('project_id', scopeId)
        .eq('user_id', userId);
    final favoriteIds = response
        .whereType<Map>()
        .map((row) => row['item_id']?.toString())
        .whereType<String>()
        .toSet();
    for (final item in List<AssetLibraryItem>.from(_items)) {
      if (item.source == AssetLibrarySource.bundled) continue;
      if (_hasPendingFavorite(item)) {
        try {
          await _writeRemoteFavorite(
            remoteClient,
            item.id,
            userId,
            item.favorite,
          );
          _upsertInMemory(_clearPendingFavorite(item));
        } catch (error) {
          _offline = true;
          debugPrint(
            '[AssetLibrary] Favorite reconciliation unavailable: $error',
          );
        }
      } else {
        _upsertInMemory(item.copyWith(favorite: favoriteIds.contains(item.id)));
      }
    }
  }

  Future<void> _writeRemoteFavorite(
    SupabaseClient remoteClient,
    String itemId,
    String userId,
    bool active,
  ) async {
    if (active) {
      await remoteClient.from('asset_library_favorites').upsert({
        'project_id': scopeId,
        'item_id': itemId,
        'user_id': userId,
      });
    } else {
      await remoteClient
          .from('asset_library_favorites')
          .delete()
          .eq('project_id', scopeId)
          .eq('item_id', itemId)
          .eq('user_id', userId);
    }
  }

  bool _hasPendingFavorite(AssetLibraryItem item) =>
      item.metadata[_pendingFavoriteMetadataKey] == true;

  Map<String, dynamic> _pendingFavoriteMetadata(
    Map<String, dynamic> metadata,
  ) => {...metadata, _pendingFavoriteMetadataKey: true};

  AssetLibraryItem _clearPendingFavorite(AssetLibraryItem item) {
    if (!_hasPendingFavorite(item)) return item;
    final metadata = Map<String, dynamic>.from(item.metadata)
      ..remove(_pendingFavoriteMetadataKey);
    return item.copyWith(metadata: metadata);
  }

  void _upsertInMemory(AssetLibraryItem item) {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) {
      _items.add(item);
    } else {
      _items[index] = item;
    }
  }

  Map<String, dynamic> _toRemoteRow(AssetLibraryItem item) => {
    'id': item.id,
    'project_id': scopeId,
    'kind': item.kind.name,
    'source': item.source.name,
    'status': item.status.name,
    'name': item.name,
    'description': item.description,
    'creator': item.creator,
    'creator_url': item.creatorUrl,
    'source_url': item.sourceUrl,
    // Data URIs are local previews, never binary catalog payloads.
    'preview_url':
        item.previewUrl?.trim().toLowerCase().startsWith('https://') == true
        ? item.previewUrl
        : null,
    'download_url': item.downloadUrl,
    // Absolute local paths are intentionally never uploaded to the catalog.
    'storage_path': item.storagePath,
    'mime_type': item.mimeType,
    'size_bytes': item.sizeBytes,
    'width': item.width,
    'height': item.height,
    'duration_ms': item.durationMs,
    'checksum': item.checksum,
    'provider_asset_id': item.providerAssetId,
    'license': item.license,
    'license_url': item.licenseUrl,
    'attribution': item.attribution,
    'folder_id': item.folderId,
    'tags': item.tags,
    'metadata': Map<String, dynamic>.from(item.metadata)
      ..remove(_pendingFavoriteMetadataKey),
    'updated_at': item.updatedAt.toIso8601String(),
  };

  AssetLibraryItem _fromRemoteRow(Map<String, dynamic> row) {
    final rawScopeId = row['project_id'];
    if (rawScopeId is! String || rawScopeId != scopeId) {
      throw ArgumentError.value(
        rawScopeId,
        'row.project_id',
        'Remote asset scope does not match the active project.',
      );
    }
    final rowScopeId = rawScopeId;
    final rawStoragePath = row['storage_path'];
    if (rawStoragePath != null && rawStoragePath is! String) {
      throw const FormatException('Remote asset storage path is invalid.');
    }
    final storagePath = rawStoragePath as String?;
    if (storagePath != null && !_isGeneratedUploadPath(storagePath)) {
      throw ArgumentError.value(
        storagePath,
        'row.storage_path',
        'Remote asset storage path is outside the active project.',
      );
    }
    final rawDownloadUrl = row['download_url'];
    if (rawDownloadUrl != null && rawDownloadUrl is! String) {
      throw const FormatException('Remote asset download URL is invalid.');
    }
    // A Storage path is catalog metadata, not a canvas-ready reference. Do
    // not synthesize a public URL from it; the upload/reconciliation path must
    // persist an explicit HTTPS reference when one is available.
    final downloadUrl =
        rawDownloadUrl is String && rawDownloadUrl.trim().isNotEmpty
        ? rawDownloadUrl
        : null;
    return AssetLibraryItem.fromJson({
      'id': row['id'],
      'scopeId': rowScopeId,
      'kind': row['kind'],
      'source': row['source'],
      'status': row['status'],
      'name': row['name'],
      'description': row['description'],
      'creator': row['creator'],
      'creatorUrl': row['creator_url'],
      'sourceUrl': row['source_url'],
      'previewUrl': row['preview_url'],
      'downloadUrl': downloadUrl,
      // Machine-local paths are never trusted from a remote row.
      'localPath': null,
      'storagePath': storagePath,
      'mimeType': row['mime_type'],
      'sizeBytes': row['size_bytes'],
      'width': row['width'],
      'height': row['height'],
      'durationMs': row['duration_ms'],
      'checksum': row['checksum'],
      'providerAssetId': row['provider_asset_id'],
      'license': row['license'],
      'licenseUrl': row['license_url'],
      'attribution': row['attribution'],
      'folderId': row['folder_id'],
      'tags': row['tags'],
      'usageCount': row['usage_count'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'lastUsedAt': row['last_used_at'],
      'metadata': row['metadata'],
    });
  }

  bool _isScopedStoragePath(String? storagePath) {
    if (storagePath == null) return true;
    if (_hasAssetLibraryServiceControlCharacter(storagePath)) return false;
    final path = storagePath.trim();
    if (path.isEmpty) return true;
    if (path != storagePath) return false;
    final segments = path.split('/');
    return path.length <= 512 &&
        !path.startsWith('/') &&
        !path.contains('\\') &&
        segments.length >= 3 &&
        segments.first ==
            safeAssetStorageSegment(scopeId, fallback: 'global') &&
        const {
          'images',
          'files',
          'audio',
          'video',
          'library',
        }.contains(segments[1]) &&
        !segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) &&
        !_hasAssetLibraryServiceControlCharacter(path);
  }

  static AssetLibraryItemKind _kindFromMime(String mimeType) {
    if (mimeType.startsWith('image/')) return AssetLibraryItemKind.image;
    if (mimeType.startsWith('video/')) return AssetLibraryItemKind.video;
    if (mimeType.startsWith('audio/')) return AssetLibraryItemKind.audio;
    if (mimeType.startsWith('model/')) return AssetLibraryItemKind.model3d;
    return AssetLibraryItemKind.file;
  }

  static List<AssetLibraryItem> builtInItems(String scopeId) {
    final now = DateTime.utc(2026, 1, 1);
    const shapes = [
      ('rectangle', 'Rectangle', 'crop_square'),
      ('ellipse', 'Ellipse', 'circle_outlined'),
      ('diamond', 'Diamond', 'change_history_outlined'),
      ('cylinder', 'Cylinder', 'view_in_ar_outlined'),
      ('parallelogram', 'Parallelogram', 'filter_none_outlined'),
      ('arrow', 'Arrow', 'arrow_forward'),
    ];
    return [
      for (final shape in shapes)
        AssetLibraryItem(
          id: 'bundled:shape-${shape.$1}',
          scopeId: scopeId,
          kind: AssetLibraryItemKind.graphic,
          source: AssetLibrarySource.bundled,
          name: shape.$2,
          license: 'Built-in Varian shape',
          tags: const ['shape', 'diagram'],
          createdAt: now,
          updatedAt: now,
          metadata: {'insertNodeType': shape.$1, 'icon': shape.$3},
        ),
    ];
  }
}
