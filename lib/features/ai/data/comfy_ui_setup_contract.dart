import 'dart:async';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import 'comfy_ui_bridge_manager.dart';

class ComfyUiSetupAsset {
  final String id;
  final String source;
  final String fileName;
  final String relativeDestination;
  final int sizeBytes;
  final String sha256;

  const ComfyUiSetupAsset({
    required this.id,
    required this.source,
    required this.fileName,
    required this.relativeDestination,
    required this.sizeBytes,
    required this.sha256,
  });

  bool get isBundled => source.startsWith('asset://');
}

/// Verifies a setup asset without loading the complete file into memory.
Future<bool> verifyComfyUiSetupAssetStream(
  Stream<List<int>> source,
  ComfyUiSetupAsset asset,
) async {
  final digestSink = AccumulatorSink<Digest>();
  final digestInput = sha256.startChunkedConversion(digestSink);
  var size = 0;
  try {
    await for (final chunk in source) {
      size += chunk.length;
      if (size > asset.sizeBytes) return false;
      digestInput.add(chunk);
    }
    digestInput.close();
    return size == asset.sizeBytes &&
        digestSink.events.length == 1 &&
        digestSink.events.single.toString() == asset.sha256;
  } catch (_) {
    return false;
  }
}

class ComfyUiSetupManifest {
  final String profile;
  final String comfyUiVersion;
  final String licenseSummary;
  final List<String> licenseUrls;
  final int requiredDiskBytes;
  final List<ComfyUiSetupAsset> assets;

  const ComfyUiSetupManifest({
    required this.profile,
    required this.comfyUiVersion,
    required this.licenseSummary,
    required this.licenseUrls,
    required this.requiredDiskBytes,
    required this.assets,
  });

  int get totalDownloadBytes => assets
      .where((asset) => !asset.isBundled)
      .fold(0, (total, asset) => total + asset.sizeBytes);
}

const comfyUiSetupManifest = ComfyUiSetupManifest(
  profile: comfyUiBridgeModel,
  comfyUiVersion: 'v0.3.70',
  licenseSummary: 'ComfyUI GPL-3.0; LTX-Video model license applies.',
  licenseUrls: [
    'https://github.com/Comfy-Org/ComfyUI/blob/v0.3.70/LICENSE',
    'https://huggingface.co/Lightricks/LTX-Video/blob/1ca03a33f1fde651a01ab69d7a3a2b88b7fbf32f/ltx-video-2b-v0.9.5.license.txt',
  ],
  requiredDiskBytes: 30000000000,
  assets: [
    ComfyUiSetupAsset(
      id: 'comfyui-portable-nvidia',
      source:
          'https://github.com/Comfy-Org/ComfyUI/releases/download/v0.3.70/ComfyUI_windows_portable_nvidia.7z',
      fileName: 'ComfyUI_windows_portable_nvidia.7z',
      relativeDestination: '.',
      sizeBytes: 1724109702,
      sha256:
          'c592bfe232f6880cd4e892f830393811054d154a5006145c2289f3c856ebad7a',
    ),
    ComfyUiSetupAsset(
      id: 'ltx-checkpoint',
      source:
          'https://huggingface.co/Lightricks/LTX-Video/resolve/1ca03a33f1fde651a01ab69d7a3a2b88b7fbf32f/ltx-video-2b-v0.9.5.safetensors',
      fileName: 'ltx-video-2b-v0.9.5.safetensors',
      relativeDestination: 'ComfyUI/models/checkpoints',
      sizeBytes: 6340729500,
      sha256:
          '720d15c9f19f7d0f6b2a92bbbc34410e2cfb2f6856a100b38f734fbf973d4adf',
    ),
    ComfyUiSetupAsset(
      id: 'ltx-text-encoder',
      source:
          'https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/6af2a98e3f615bdfa612fbd85da93d1ed5f69ef5/t5xxl_fp16.safetensors',
      fileName: 't5xxl_fp16.safetensors',
      relativeDestination: 'ComfyUI/models/text_encoders',
      sizeBytes: 9787841024,
      sha256:
          '6e480b09fae049a72d2a8c5fbccb8d3e92febeb233bbe9dfe7256958a9167635',
    ),
    ComfyUiSetupAsset(
      id: 'ltx-workflow',
      source: 'asset://tool/comfyui_video_bridge/workflow_api.json',
      fileName: 'workflow_api.json',
      relativeDestination: 'ComfyUI',
      sizeBytes: 4307,
      sha256:
          'ad1ec02677d0735d43463862a53ee6061769cbbe311cf12bee047d19f1c67204',
    ),
  ],
);

abstract interface class ComfyUiSetupService {
  Future<String> defaultInstallationPath();

  Future<void> install({
    required String destination,
    required bool confirmed,
    ComfyUiSetupCancellation? cancellation,
    void Function(double progress)? onProgress,
  });
}

class ComfyUiSetupCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
