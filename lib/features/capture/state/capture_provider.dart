import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assets/data/asset_service.dart';
import '../data/capture_asset_store.dart';
import '../data/capture_repository.dart';
import '../domain/capture_item.dart';

final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => LocalCaptureRepository(assetStore: createCaptureAssetStore()),
);

final captureFilterProvider = StateProvider<CaptureFilter>(
  (ref) => CaptureFilter.all,
);

final captureItemsProvider =
    StateNotifierProvider<CaptureNotifier, AsyncValue<List<CaptureItem>>>((
      ref,
    ) {
      final notifier = CaptureNotifier(ref.read(captureRepositoryProvider));
      ref.listen<CaptureFilter>(captureFilterProvider, (previous, next) {
        notifier.load(next);
      });
      return notifier;
    });

class CaptureNotifier extends StateNotifier<AsyncValue<List<CaptureItem>>> {
  CaptureNotifier(this._repository) : super(const AsyncValue.loading()) {
    Future<void>.microtask(load);
  }

  final CaptureRepository _repository;
  CaptureFilter _filter = CaptureFilter.all;
  int _loadGeneration = 0;

  Future<void> load([CaptureFilter? filter]) async {
    if (filter != null) _filter = filter;
    final generation = ++_loadGeneration;
    final query = CaptureQuery(filter: _filter);
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
      () => _repository.listCaptures(query: query),
    );
    if (!mounted || generation != _loadGeneration) return;
    state = result;
  }

  Future<CaptureItem?> getCapture(String id) => _repository.getCapture(id);

  Future<Uint8List?> readCaptureAsset(String id) =>
      _repository.readCaptureAsset(id);

  Future<CaptureItem> captureText(String value) async {
    final item = await _repository.createCapture(CaptureInput.text(value));
    await load();
    return item;
  }

  Future<List<CaptureItem>> captureFiles(List<AssetPickerResult> files) async {
    final created = <CaptureItem>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || file.errorMessage != null) continue;
      try {
        if (!assetBytesMatchMimeSignature(bytes, file.detectedMimeType)) {
          continue;
        }
        final item = await _repository.createCapture(
          CaptureInput.file(
            name: file.name,
            bytes: bytes,
            mimeType: file.detectedMimeType,
            title: file.name,
          ),
        );
        created.add(item);
      } on CaptureFailure {
        if (created.isEmpty) rethrow;
        continue;
      }
    }
    if (created.isNotEmpty) await load();
    return created;
  }

  Future<void> setRead(String id, bool value) =>
      _mutate(() => _repository.setRead(id, value));

  Future<void> setFavorite(String id, bool value) =>
      _mutate(() => _repository.setFavorite(id, value));

  Future<void> delete(String id) =>
      _mutate(() => _repository.deleteCapture(id));

  Future<void> restore(String id) =>
      _mutate(() => _repository.restoreCapture(id));

  Future<void> purge(String id) => _mutate(() => _repository.purgeCapture(id));

  Future<void> _mutate(Future<void> Function() operation) async {
    await operation();
    await load();
  }
}
