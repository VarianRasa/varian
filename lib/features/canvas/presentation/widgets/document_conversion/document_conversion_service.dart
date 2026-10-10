import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_service_stub.dart'
    if (dart.library.io) 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_service_io.dart'
    as platform;

export 'document_conversion_models.dart' show DocumentConversionService;

DocumentConversionService createDocumentConversionService() =>
    platform.createDocumentConversionService();
