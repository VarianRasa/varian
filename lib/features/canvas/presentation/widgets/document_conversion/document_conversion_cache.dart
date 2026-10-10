import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';

class DocumentPreviewCache {
  DocumentPreviewCache(
    this.directory, {
    this.maxBytes = 1024 * 1024 * 1024,
    this.maxAge = const Duration(days: 30),
  });

  final Directory directory;
  final int maxBytes;
  final Duration maxAge;

  String key(Uint8List bytes, String extension) => sha256.convert([
    ...bytes,
    ...utf8.encode('|$extension|document-preview-v1'),
  ]).toString();

  Future<DocumentConversionResult?> find(String key) async {
    final pdf = File(p.join(directory.path, '$key.pdf'));
    final metadata = File(p.join(directory.path, '$key.json'));
    if (!await _validPdf(pdf) || !await metadata.exists()) return null;
    try {
      final data =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      final created = DateTime.parse(data['createdAt'] as String);
      if (DateTime.now().difference(created) > maxAge) {
        await _deletePair(key);
        return null;
      }
      data['lastAccessAt'] = DateTime.now().toUtc().toIso8601String();
      await metadata.writeAsString(jsonEncode(data), flush: true);
      final bytes = Uint8List.fromList(await pdf.readAsBytes());
      return DocumentConversionResult(pdfBytes: bytes, fromCache: true);
    } catch (_) {
      await _deletePair(key);
      return null;
    }
  }

  Future<DocumentConversionResult> store({
    required String key,
    required Uint8List pdfBytes,
    required String extension,
    required int sourceSize,
  }) async {
    if (pdfBytes.length < 5 || utf8.decode(pdfBytes.sublist(0, 5)) != '%PDF-') {
      throw const DocumentConversionFailure(
        DocumentConversionFailureCode.invalidPdf,
        'LibreOffice did not create a valid PDF.',
      );
    }
    await directory.create(recursive: true);
    final pdf = File(p.join(directory.path, '$key.pdf'));
    final temporary = File('${pdf.path}.tmp');
    await temporary.writeAsBytes(pdfBytes, flush: true);
    await temporary.rename(pdf.path);
    final now = DateTime.now().toUtc().toIso8601String();
    await File(p.join(directory.path, '$key.json')).writeAsString(
      jsonEncode({
        'extension': extension,
        'sourceSize': sourceSize,
        'pdfSize': pdfBytes.length,
        'createdAt': now,
        'lastAccessAt': now,
        'converterVersion': 'document-preview-v1',
      }),
      flush: true,
    );
    await evict();
    return DocumentConversionResult(pdfBytes: Uint8List.fromList(pdfBytes));
  }

  Future<void> evict() async {
    if (!await directory.exists()) return;
    final entries = <({String key, int size, DateTime access})>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final key = p.basenameWithoutExtension(entity.path);
        final access = DateTime.parse(data['lastAccessAt'] as String);
        final created = DateTime.parse(data['createdAt'] as String);
        if (DateTime.now().difference(created) > maxAge) {
          await _deletePair(key);
        } else {
          entries.add((key: key, size: data['pdfSize'] as int, access: access));
        }
      } catch (_) {}
    }
    entries.sort((a, b) => a.access.compareTo(b.access));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    for (final entry in entries) {
      if (total <= maxBytes) break;
      await _deletePair(entry.key);
      total -= entry.size;
    }
  }

  Future<bool> _validPdf(File file) async {
    if (!await file.exists() || await file.length() < 5) return false;
    final handle = await file.open();
    try {
      return utf8.decode(await handle.read(5)) == '%PDF-';
    } finally {
      await handle.close();
    }
  }

  Future<void> _deletePair(String key) async {
    for (final extension in ['pdf', 'json']) {
      final file = File(p.join(directory.path, '$key.$extension'));
      if (await file.exists()) await file.delete();
    }
  }
}
