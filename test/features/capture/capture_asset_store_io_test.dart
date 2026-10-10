import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:varian/features/capture/data/capture_asset_store_io.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persists, reads, checks and deletes only owned capture assets',
    () async {
      final original = PathProviderPlatform.instance;
      final temporary = await Directory.systemTemp.createTemp('capture-store-');
      PathProviderPlatform.instance = _TestPathProvider(temporary.path);
      addTearDown(() async {
        PathProviderPlatform.instance = original;
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final store = NativeCaptureAssetStore();
      final bytes = Uint8List.fromList([7, 8, 9]);
      final reference = await store.save(
        bytes,
        fileName: r'private\folder\sample.bin',
        mimeType: 'application/octet-stream',
      );
      expect(await store.exists(reference), isTrue);
      expect(await store.read(reference), orderedEquals(bytes));

      final directory = Directory(p.join(temporary.path, 'varian-captures'));
      final saved = await directory.list().single;
      expect(p.basename(saved.path), endsWith('_sample.bin'));
      expect(await store.read('file:///private/sample.bin'), isNull);
      await store.delete('file:///private/sample.bin');
      expect(await store.exists(reference), isTrue);

      await store.delete(reference);
      expect(await store.exists(reference), isFalse);
      expect(await directory.list().isEmpty, isTrue);
    },
  );

  test(
    'rejects malformed capture references without touching other files',
    () async {
      final original = PathProviderPlatform.instance;
      final temporary = await Directory.systemTemp.createTemp('capture-store-');
      PathProviderPlatform.instance = _TestPathProvider(temporary.path);
      addTearDown(() async {
        PathProviderPlatform.instance = original;
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final outside = File(p.join(temporary.path, 'unrelated.bin'));
      await outside.writeAsBytes([1]);
      final store = NativeCaptureAssetStore();
      await store.delete(outside.path);
      expect(await outside.exists(), isTrue);
      expect(await store.read('capture-asset://../../unrelated'), isNull);
    },
  );
}
