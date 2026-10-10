import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/state/capture_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads repository and captures text', () async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final container = ProviderContainer(
      overrides: [captureRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(captureItemsProvider.notifier).load();
    final created = await container
        .read(captureItemsProvider.notifier)
        .captureText('A provider note');

    expect(container.read(captureItemsProvider).value?.single.id, created.id);
  });

  test('filter changes the repository query', () async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final unread = await repository.createCapture(CaptureInput.text('Unread'));
    final favorite = await repository.createCapture(
      CaptureInput.text('Favorite'),
    );
    await repository.setRead(unread.id, false);
    await repository.setRead(favorite.id, true);
    await repository.setFavorite(favorite.id, true);
    final container = ProviderContainer(
      overrides: [captureRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(captureItemsProvider.notifier).load();
    container.read(captureFilterProvider.notifier).state =
        CaptureFilter.favorites;
    await Future<void>.delayed(Duration.zero);

    expect(container.read(captureItemsProvider).value?.map((item) => item.id), [
      favorite.id,
    ]);
  });

  test(
    'captures each valid picker file and ignores empty or invalid files',
    () async {
      final assets = MemoryCaptureAssetStore();
      final repository = LocalCaptureRepository(assetStore: assets);
      final container = ProviderContainer(
        overrides: [captureRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(captureItemsProvider.notifier);

      expect(await notifier.captureFiles(const []), isEmpty);
      final items = await notifier.captureFiles([
        AssetPickerResult(name: 'first.txt', bytes: Uint8List.fromList([65])),
        AssetPickerResult(name: 'bad.png', bytes: Uint8List.fromList([66])),
        AssetPickerResult(name: 'unavailable.txt', errorMessage: 'unavailable'),
        AssetPickerResult(name: 'empty.txt', bytes: Uint8List(0)),
        AssetPickerResult(name: 'second.txt', bytes: Uint8List.fromList([66])),
      ]);

      expect(items, hasLength(2));
      expect((await repository.listCaptures()).length, 2);
      expect(assets.references, hasLength(2));
      expect(items.map((item) => item.assetId), everyElement(isNotNull));
    },
  );
}
