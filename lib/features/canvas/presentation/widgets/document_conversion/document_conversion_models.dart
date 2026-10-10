import 'dart:typed_data';

import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

enum DocumentConversionFailureCode {
  missingSource,
  invalidSource,
  unsupportedExtension,
  converterUnavailable,
  timeout,
  processFailure,
  invalidPdf,
  unsupportedPlatform,
}

class DocumentConversionFailure implements Exception {
  const DocumentConversionFailure(this.code, this.message);

  final DocumentConversionFailureCode code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class DocumentConversionService {
  Future<DocumentConversionResult> convertToPdf(
    FilePayload payload, {
    TransientFileSourceResolver? sourceResolver,
  });
}

class DocumentConversionResult {
  const DocumentConversionResult({
    required this.pdfBytes,
    this.fromCache = false,
  });

  final Uint8List pdfBytes;
  final bool fromCache;
}
