import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:varian/features/ai/data/comfy_ui_setup.dart';
import 'package:varian/features/ai/data/video_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pinned setup manifest matches the bundled workflow asset', () async {
    final workflowAsset = comfyUiSetupManifest.assets.firstWhere(
      (asset) => asset.id == 'ltx-workflow',
    );
    final data = await rootBundle.load(workflowAsset.source.substring(8));
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final setupManifest =
        jsonDecode(
              await rootBundle.loadString(
                'tool/comfyui_video_bridge/setup_manifest.json',
              ),
            )
            as Map<String, dynamic>;
    final setupAssets = setupManifest['assets'] as List<dynamic>;
    final setupLicense = setupManifest['license'] as Map<String, dynamic>;
    expect(setupManifest['profile'], comfyUiSetupManifest.profile);
    expect(
      setupManifest['comfyui_version'],
      comfyUiSetupManifest.comfyUiVersion,
    );
    expect(
      setupManifest['required_disk_bytes'],
      comfyUiSetupManifest.requiredDiskBytes,
    );
    expect(setupLicense['summary'], comfyUiSetupManifest.licenseSummary);
    expect(setupLicense['urls'], comfyUiSetupManifest.licenseUrls);
    final setupWorkflow =
        setupAssets.firstWhere(
              (asset) =>
                  (asset as Map<String, dynamic>)['id'] == workflowAsset.id,
            )
            as Map<String, dynamic>;

    expect(bytes.length, workflowAsset.sizeBytes);
    expect(sha256.convert(bytes).toString(), workflowAsset.sha256);
    final workflow = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final sampler =
        (workflow['graph'] as Map<String, dynamic>)['72']
            as Map<String, dynamic>;
    final samplerInputs = sampler['inputs'] as Map<String, dynamic>;
    expect(samplerInputs['cfg'], 3);
    expect(samplerInputs.containsKey('control_after_generate'), isFalse);
    expect(setupWorkflow['size_bytes'], workflowAsset.sizeBytes);
    expect(setupWorkflow['sha256'], workflowAsset.sha256);
    for (final asset in comfyUiSetupManifest.assets) {
      final recorded = setupAssets.whereType<Map>().firstWhere(
        (candidate) => candidate['id'] == asset.id,
      );
      expect(recorded['source'], asset.source);
      expect(recorded['file_name'], asset.fileName);
      expect(recorded['relative_destination'], asset.relativeDestination);
      expect(recorded['size_bytes'], asset.sizeBytes);
      expect(recorded['sha256'], asset.sha256);
    }
  });

  test('streamed asset verification checks size and SHA-256', () async {
    final bytes = utf8.encode('known asset bytes');
    final asset = ComfyUiSetupAsset(
      id: 'test-asset',
      source: 'https://example.invalid/test.bin',
      fileName: 'test.bin',
      relativeDestination: '.',
      sizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );

    expect(
      await verifyComfyUiSetupAssetStream(
        Stream<List<int>>.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]),
        asset,
      ),
      isTrue,
    );
    expect(
      await verifyComfyUiSetupAssetStream(
        Stream<List<int>>.fromIterable([utf8.encode('tampered')]),
        asset,
      ),
      isFalse,
    );
    expect(
      await verifyComfyUiSetupAssetStream(
        Stream<List<int>>.fromIterable([
          bytes,
          <int>[0],
        ]),
        asset,
      ),
      isFalse,
    );
  });

  test('manifest keeps downloads pinned to the supported profile', () {
    expect(comfyUiSetupManifest.comfyUiVersion, 'v0.3.70');
    expect(comfyUiSetupManifest.profile, 'ltx-video-0.9.5-2b-low-vram');
    expect(
      comfyUiSetupManifest.totalDownloadBytes,
      1724109702 + 6340729500 + 9787841024,
    );
    expect(
      comfyUiSetupManifest.assets.every(
        (asset) => asset.isBundled || asset.source.startsWith('https://'),
      ),
      isTrue,
    );
  });

  test(
    'installer requires confirmation before validating a destination',
    () async {
      final service = createComfyUiSetupService();
      try {
        await service.install(destination: '', confirmed: false);
        fail('expected setup confirmation error');
      } on VideoProviderException catch (error) {
        expect(
          error.code,
          Platform.isWindows
              ? 'VIDEO_SETUP_CONFIRMATION_REQUIRED'
              : 'VIDEO_CONFIGURATION_ERROR',
        );
      }
    },
  );

  test('installer cancellation keeps the destination untouched', () async {
    final service = createComfyUiSetupService();
    final parent = await Directory.systemTemp.createTemp('varian-setup-test-');
    addTearDown(() => parent.delete(recursive: true));
    final destination = p.join(parent.path, 'install');
    final cancellation = ComfyUiSetupCancellation()..cancel();

    if (Platform.isWindows) {
      await expectLater(
        service.install(
          destination: destination,
          confirmed: true,
          cancellation: cancellation,
        ),
        throwsA(
          isA<VideoProviderException>().having(
            (error) => error.code,
            'code',
            'VIDEO_SETUP_CANCELLED',
          ),
        ),
      );
      expect(Directory(destination).existsSync(), isFalse);
    }
  });
}
