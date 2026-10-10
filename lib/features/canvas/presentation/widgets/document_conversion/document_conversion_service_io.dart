import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_cache.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_source_resolver.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';

DocumentConversionService createDocumentConversionService() =>
    IoDocumentConversionService();

class IoDocumentConversionService implements DocumentConversionService {
  IoDocumentConversionService({this.timeout = const Duration(minutes: 2)});

  final Duration timeout;

  @override
  Future<DocumentConversionResult> convertToPdf(
    FilePayload payload, {
    TransientFileSourceResolver? sourceResolver,
  }) async {
    final source = await resolveDocumentSource(
      payload,
      sourceResolver: sourceResolver,
      readLocal: sourceResolver == null
          ? (path) async {
              final file = File(path);
              return await file.exists() ? file.readAsBytes() : null;
            }
          : null,
    );
    final cacheRoot = Directory(
      p.join(
        (await getApplicationCacheDirectory()).path,
        'document-preview-v1',
      ),
    );
    final cache = DocumentPreviewCache(cacheRoot);
    final key = cache.key(source.bytes, source.extension);
    final hit = await cache.find(key);
    if (hit != null) return hit;

    final executable = await _findLibreOffice();
    if (executable == null) {
      throw const DocumentConversionFailure(
        DocumentConversionFailureCode.converterUnavailable,
        'LibreOffice is unavailable. Install it or bundle its runtime.',
      );
    }
    final working = await Directory.systemTemp.createTemp('varian_document_');
    try {
      final input = File(p.join(working.path, 'input.${source.extension}'));
      final output = Directory(p.join(working.path, 'output'));
      final profile = Directory(p.join(working.path, 'profile'));
      await output.create();
      await profile.create();
      await input.writeAsBytes(source.bytes, flush: true);
      final profileUri = profile.uri.toString();
      final process = await Process.start(executable, [
        '--headless',
        '--nologo',
        '--nodefault',
        '--nolockcheck',
        '--norestore',
        '--nofirststartwizard',
        '-env:UserInstallation=$profileUri',
        '--convert-to',
        'pdf',
        '--outdir',
        output.path,
        input.path,
      ]);
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw const DocumentConversionFailure(
            DocumentConversionFailureCode.timeout,
            'Document conversion timed out.',
          );
        },
      );
      if (exitCode != 0) {
        throw const DocumentConversionFailure(
          DocumentConversionFailureCode.processFailure,
          'LibreOffice could not convert this document.',
        );
      }
      final pdf = File(p.join(output.path, 'input.pdf'));
      if (!await pdf.exists()) {
        throw const DocumentConversionFailure(
          DocumentConversionFailureCode.invalidPdf,
          'LibreOffice did not create a PDF.',
        );
      }
      final bytes = Uint8List.fromList(await pdf.readAsBytes());
      return cache.store(
        key: key,
        pdfBytes: bytes,
        extension: source.extension,
        sourceSize: source.bytes.length,
      );
    } finally {
      if (await working.exists()) await working.delete(recursive: true);
    }
  }

  Future<String?> _findLibreOffice() async {
    if (Platform.isWindows) {
      final program = p.join(
        p.dirname(Platform.resolvedExecutable),
        'libreoffice',
        'program',
      );
      for (final launcher in ['soffice.com', 'soffice.exe']) {
        final bundled = p.join(program, launcher);
        if (await File(bundled).exists()) return bundled;
      }
      return null;
    }
    for (final executable in ['libreoffice', 'soffice']) {
      try {
        final result = await Process.run(executable, ['--version']);
        if (result.exitCode == 0) return executable;
      } catch (_) {}
    }
    return null;
  }
}
