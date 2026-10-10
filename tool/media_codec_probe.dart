import 'dart:convert';
import 'dart:io';

import 'package:varian/features/media/data/media_codec_runtime.dart';

Future<void> main() async {
  final result = await const MediaCodecRuntime().probe(
    configuredPath: Platform.environment['VARIAN_VIDEO_ENCODER'],
  );
  final payload = <String, Object?>{
    'available': result.available,
    'executable': result.executable,
    'source': result.source?.name,
    'version': result.version,
    'reason': result.reason,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
  if (!result.available) exitCode = 1;
}
