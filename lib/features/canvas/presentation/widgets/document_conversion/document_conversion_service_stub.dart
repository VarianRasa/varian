import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

DocumentConversionService createDocumentConversionService() =>
    _UnsupportedDocumentConversionService();

class _UnsupportedDocumentConversionService
    implements DocumentConversionService {
  @override
  Future<DocumentConversionResult> convertToPdf(
    FilePayload payload, {
    TransientFileSourceResolver? sourceResolver,
  }) {
    throw const DocumentConversionFailure(
      DocumentConversionFailureCode.unsupportedPlatform,
      'Document conversion is unavailable on this platform.',
    );
  }
}
