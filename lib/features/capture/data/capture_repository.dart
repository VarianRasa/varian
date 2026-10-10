import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/capture_item.dart';
import 'capture_asset_store.dart';

const captureItemsStorageKey = 'ccs_capture_items_v1';

enum CaptureFilter { all, unread, favorites, trash }

class CaptureQuery {
  const CaptureQuery({this.filter = CaptureFilter.all});

  final CaptureFilter filter;
}

abstract interface class CapturePreferences {
  Future<String?> read(String key);

  Future<bool> write(String key, String value);
}

class SharedCapturePreferences implements CapturePreferences {
  SharedCapturePreferences([this._preferences]);

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _instance async =>
      _preferences ?? await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance).getString(key);

  @override
  Future<bool> write(String key, String value) async =>
      (await _instance).setString(key, value);
}

abstract interface class CaptureRepository {
  Future<CaptureItem> createCapture(CaptureInput input);

  Future<List<CaptureItem>> listCaptures({
    CaptureQuery query = const CaptureQuery(),
  });

  Future<CaptureItem?> getCapture(String id);

  Future<Uint8List?> readCaptureAsset(String id);

  Future<void> setRead(String id, bool value);

  Future<void> setFavorite(String id, bool value);

  Future<void> deleteCapture(String id);

  Future<void> restoreCapture(String id);

  Future<void> purgeCapture(String id);
}

class LocalCaptureRepository implements CaptureRepository {
  LocalCaptureRepository({
    SharedPreferences? preferences,
    CapturePreferences? preferenceStore,
    CaptureAssetStore? assetStore,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _preferences = preferenceStore ?? SharedCapturePreferences(preferences),
       _assetStore = assetStore ?? createCaptureAssetStore(),
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final CapturePreferences _preferences;
  final CaptureAssetStore _assetStore;
  final Uuid _uuid;
  final DateTime Function() _clock;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<CaptureItem> createCapture(CaptureInput input) async {
    String? assetId;
    try {
      final bytes = input.bytes;
      if (bytes != null) {
        assetId = await _assetStore.save(
          Uint8List.fromList(bytes),
          fileName: input.name ?? 'capture.bin',
          mimeType: input.mimeType ?? 'application/octet-stream',
        );
      }
      final now = _clock();
      final item = CaptureItem(
        id: _uuid.v4(),
        kind: input.kind,
        createdAt: now,
        updatedAt: now,
        title: input.title ?? input.name,
        text: input.text,
        sourceUri: input.sourceUri,
        assetId: assetId,
        mimeType: input.mimeType,
        extension: input.extension,
        byteSize: input.byteSize,
        status: CaptureStatus.ready,
        syncState: CaptureSyncState.localOnly,
        origin: input.origin,
      );
      await _mutate((items) => [item, ...items]);
      return item;
    } on CaptureFailure {
      if (assetId != null) await _deleteQuietly(assetId);
      rethrow;
    } on CaptureAssetStoreException {
      if (assetId != null) await _deleteQuietly(assetId);
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Capture file could not be saved locally.',
      );
    } catch (_) {
      if (assetId != null) await _deleteQuietly(assetId);
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Capture could not be saved locally.',
      );
    }
  }

  @override
  Future<List<CaptureItem>> listCaptures({
    CaptureQuery query = const CaptureQuery(),
  }) async {
    final items = await _readItems();
    final visible =
        items.where((item) {
            if (query.filter == CaptureFilter.trash) {
              if (item.status != CaptureStatus.deleted) return false;
            } else if (item.status == CaptureStatus.deleted) {
              return false;
            }
            return switch (query.filter) {
              CaptureFilter.all || CaptureFilter.trash => true,
              CaptureFilter.unread => !item.isRead,
              CaptureFilter.favorites => item.isFavorite,
            };
          }).toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return visible;
  }

  @override
  Future<CaptureItem?> getCapture(String id) async {
    for (final item in await _readItems()) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<Uint8List?> readCaptureAsset(String id) async {
    final item = await getCapture(id);
    if (item == null ||
        item.status == CaptureStatus.deleted ||
        item.assetId == null) {
      return null;
    }
    try {
      return await _assetStore.read(item.assetId!);
    } on CaptureAssetStoreException {
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Capture file could not be read locally.',
      );
    } catch (_) {
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Capture file could not be read locally.',
      );
    }
  }

  @override
  Future<void> setRead(String id, bool value) => _updateItem(
    id,
    (item) => item.copyWith(isRead: value, updatedAt: _clock()),
  );

  @override
  Future<void> setFavorite(String id, bool value) => _updateItem(
    id,
    (item) => item.copyWith(isFavorite: value, updatedAt: _clock()),
  );

  @override
  Future<void> deleteCapture(String id) => _updateItem(
    id,
    (item) => item.copyWith(status: CaptureStatus.deleted, updatedAt: _clock()),
  );

  @override
  Future<void> restoreCapture(String id) => _updateItem(
    id,
    (item) => item.copyWith(status: CaptureStatus.ready, updatedAt: _clock()),
  );

  @override
  Future<void> purgeCapture(String id) async {
    String? assetId;
    CaptureItem? target;
    var removed = false;
    await _mutate((items) {
      for (final item in items) {
        if (item.id == id) {
          target = item;
          assetId = item.assetId;
          removed = true;
          break;
        }
      }
      return items.where((item) => item.id != id).toList();
    });
    if (!removed) return;
    if (assetId != null) {
      try {
        final stillReferenced = (await _readItems()).any(
          (item) => item.assetId == assetId,
        );
        if (!stillReferenced) await _assetStore.delete(assetId!);
      } catch (_) {
        await _restorePurgedItem(target);
        throw const CaptureFailure(
          'CAPTURE_STORAGE_ERROR',
          'Capture metadata was removed, but its local file could not be purged.',
        );
      }
    }
  }

  Future<void> _restorePurgedItem(CaptureItem? item) async {
    if (item == null) return;
    try {
      await _mutate((items) {
        if (items.any((entry) => entry.id == item.id)) return items;
        return [...items, item];
      });
    } catch (_) {}
  }

  Future<void> _updateItem(
    String id,
    CaptureItem Function(CaptureItem item) update,
  ) => _mutate((items) {
    var found = false;
    final updated = items.map((item) {
      if (item.id != id) return item;
      found = true;
      return update(item);
    }).toList();
    if (!found) return items;
    return updated;
  });

  Future<List<CaptureItem>> _readItems() async {
    try {
      final raw = await _preferences.read(captureItemsStorageKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      final items = <CaptureItem>[];
      for (final value in decoded) {
        if (value is! Map) throw const FormatException();
        items.add(CaptureItem.fromJson(Map<String, dynamic>.from(value)));
      }
      return items;
    } on CaptureFailure {
      rethrow;
    } catch (_) {
      throw const CaptureFailure(
        'CAPTURE_STORAGE_ERROR',
        'Stored captures could not be read.',
      );
    }
  }

  Future<void> _mutate(List<CaptureItem> Function(List<CaptureItem>) mutation) {
    final result = Completer<void>();
    _writeQueue = _writeQueue
        .then((_) async {
          try {
            final items = await _readItems();
            final changed = mutation(items);
            final encoded = jsonEncode(
              changed.map((item) => item.toJson()).toList(),
            );
            if (!await _preferences.write(captureItemsStorageKey, encoded)) {
              throw const CaptureFailure(
                'CAPTURE_STORAGE_ERROR',
                'Capture metadata could not be saved.',
              );
            }
            result.complete();
          } catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        })
        .catchError((Object _) {});
    return result.future;
  }

  Future<void> _deleteQuietly(String reference) async {
    try {
      await _assetStore.delete(reference);
    } catch (_) {}
  }
}
