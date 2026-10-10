import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/capture/data/capture_asset_store.dart';
import 'package:varian/features/capture/data/capture_repository.dart';
import 'package:varian/features/capture/domain/capture_item.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('creates, reloads, sorts, and updates capture metadata', () async {
    var tick = 0;
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
      clock: () => DateTime(2026, 9, 27, 10, 0, tick++),
    );
    final first = await repository.createCapture(
      CaptureInput.text('https://example.com', origin: CaptureOrigin.clipboard),
    );
    final second = await repository.createCapture(CaptureInput.text('A note'));

    expect(first.kind, CaptureKind.link);
    expect((await repository.listCaptures()).map((item) => item.id), [
      second.id,
      first.id,
    ]);

    await repository.setRead(first.id, true);
    await repository.setFavorite(first.id, true);
    final reloaded = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final stored = await reloaded.getCapture(first.id);
    expect(stored?.isRead, isTrue);
    expect(stored?.isFavorite, isTrue);
    expect(stored?.origin, CaptureOrigin.clipboard);
  });

  test(
    'stores file bytes outside metadata and removes them on purge',
    () async {
      final assets = MemoryCaptureAssetStore();
      final repository = LocalCaptureRepository(assetStore: assets);
      final item = await repository.createCapture(
        CaptureInput.file(
          name: 'reference.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
        ),
      );
      expect(item.assetId, isNotNull);
      expect(await assets.exists(item.assetId!), isTrue);
      final raw = (await SharedPreferences.getInstance()).getString(
        'ccs_capture_items_v1',
      );
      expect(raw, isNot(contains('AQID')));

      await repository.purgeCapture(item.id);
      expect(await assets.exists(item.assetId!), isFalse);
      expect(await repository.getCapture(item.id), isNull);
    },
  );

  test(
    'reads capture bytes without mutating or deleting the Inbox item',
    () async {
      final assets = MemoryCaptureAssetStore();
      final repository = LocalCaptureRepository(assetStore: assets);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final item = await repository.createCapture(
        CaptureInput.file(
          name: 'reference.bin',
          bytes: bytes,
          mimeType: 'application/octet-stream',
        ),
      );

      final read = await repository.readCaptureAsset(item.id);

      expect(read, bytes);
      expect(await repository.getCapture(item.id), isNotNull);
      expect(await assets.exists(item.assetId!), isTrue);
      expect(
        (await repository.getCapture(item.id))?.status,
        CaptureStatus.ready,
      );
    },
  );

  test('does not read a capture that was moved to Inbox Trash', () async {
    final assets = MemoryCaptureAssetStore();
    final repository = LocalCaptureRepository(assetStore: assets);
    final item = await repository.createCapture(
      CaptureInput.file(
        name: 'reference.bin',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        mimeType: 'application/octet-stream',
      ),
    );
    await repository.deleteCapture(item.id);

    expect(await repository.readCaptureAsset(item.id), isNull);
    expect(await assets.exists(item.assetId!), isTrue);
  });

  test('empty input creates no record', () async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    expect(
      () => repository.createCapture(CaptureInput.text('')),
      throwsA(isA<CaptureFailure>()),
    );
    expect(await repository.listCaptures(), isEmpty);
  });

  test('delete and restore preserve the capture', () async {
    final repository = LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    );
    final item = await repository.createCapture(CaptureInput.text('Keep this'));
    await repository.deleteCapture(item.id);
    expect(
      (await repository.listCaptures(
        query: const CaptureQuery(filter: CaptureFilter.trash),
      )).single.status,
      CaptureStatus.deleted,
    );
    expect(await repository.listCaptures(), isEmpty);
    await repository.restoreCapture(item.id);
    expect(
      (await repository.listCaptures()).single.status,
      CaptureStatus.ready,
    );
  });

  test('does not delete an asset still referenced by another item', () async {
    final assets = MemoryCaptureAssetStore();
    final repository = LocalCaptureRepository(assetStore: assets);
    final first = await repository.createCapture(
      CaptureInput.file(
        name: 'shared.bin',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'application/octet-stream',
      ),
    );
    final second = first.copyWith(id: 'second-capture');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'ccs_capture_items_v1',
      jsonEncode([first.toJson(), second.toJson()]),
    );

    await repository.purgeCapture(first.id);

    expect(await assets.exists(first.assetId!), isTrue);
    expect((await repository.getCapture(second.id))?.assetId, first.assetId);
  });

  test(
    'serializes concurrent metadata writes without losing captures',
    () async {
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );
      await Future.wait([
        repository.createCapture(CaptureInput.text('First concurrent capture')),
        repository.createCapture(
          CaptureInput.text('Second concurrent capture'),
        ),
      ]);

      expect(await repository.listCaptures(), hasLength(2));
    },
  );

  test(
    'rejects malformed stored entries instead of silently discarding them',
    () async {
      SharedPreferences.setMockInitialValues({
        'ccs_capture_items_v1': '[{"id":"not-valid"},null]',
      });
      final repository = LocalCaptureRepository(
        assetStore: MemoryCaptureAssetStore(),
      );

      await expectLater(
        repository.listCaptures(),
        throwsA(isA<CaptureFailure>()),
      );
    },
  );

  test('removes a newly saved asset if metadata persistence fails', () async {
    final assets = MemoryCaptureAssetStore();
    final repository = LocalCaptureRepository(
      preferenceStore: _FailingPreferences(),
      assetStore: assets,
    );

    await expectLater(
      repository.createCapture(
        CaptureInput.file(
          name: 'reference.bin',
          bytes: Uint8List.fromList([4, 5, 6]),
          mimeType: 'application/octet-stream',
        ),
      ),
      throwsA(isA<CaptureFailure>()),
    );
    expect(assets.references, isEmpty);
  });
}

class _FailingPreferences implements CapturePreferences {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async => false;
}
