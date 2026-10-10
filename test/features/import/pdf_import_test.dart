import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/import/import_loss_report.dart';
import 'package:varian/features/import/import_service.dart';
import 'package:varian/domain/models/vector_path_payload.dart';

void main() {
  test('imports PDF page and text operators as editable nodes', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 58 >>
stream
0.2 0.4 0.8 rg
72 560 180 80 re f
BT
/F1 24 Tf
72 720 Td
(Editable PDF title) Tj
ET
endstream
endobj
trailer
<< /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'deck.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    expect(result.lossReport?.format, ImportSourceFormat.pdf);
    expect(result.nodes.any((node) => node.type == NodeType.frame), isTrue);
    final text = result.nodes.firstWhere((node) => node.type == NodeType.text);
    expect((text.payload as TextPayload).text, 'Editable PDF title');
    expect(text.parentId, isNotNull);
    expect(result.nodes.any((node) => node.type == NodeType.rectangle), isTrue);
    expect(result.lossReport?.lossy, isNotEmpty);
  });

  test('falls back to an auditable attachment for invalid PDF bytes', () {
    final result = ImportService.importFromFileBytes(
      fileName: 'broken.pdf',
      bytes: Uint8List.fromList(utf8.encode('not a pdf')),
    );

    expect(result.isSuccess, isTrue);
    expect(result.nodes.single.type, NodeType.fileCard);
    expect(result.lossReport?.format, ImportSourceFormat.file);
    expect(result.lossReport?.lossy, isNotEmpty);
  });

  test('decodes compressed PDF streams and UTF-16 hex text', () {
    final compressed = const ZLibEncoder().encode(
      utf8.encode('BT /F1 18 Tf 72 700 Td <0045006400690074> Tj ET'),
    );
    final bytes = Uint8List.fromList([
      ...utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length ${compressed.length} /Filter /FlateDecode >> stream
'''),
      ...compressed,
      ...utf8.encode('''
endstream endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    ]);

    final result = ImportService.importFromFileBytes(
      fileName: 'compressed.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final text = result.nodes.firstWhere((node) => node.type == NodeType.text);
    expect((text.payload as TextPayload).text, 'Edit');
  });

  test('imports basic line and cubic PDF paths as editable vector nodes', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length 140 >> stream
0.1 0.8 0.2 RG 3 w
72 120 m 180 120 l 240 180 300 240 360 180 c S
endstream endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'paths.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final path = result.nodes.firstWhere(
      (node) => node.type == NodeType.vectorPath,
    );
    final payload = path.payload as VectorPathPayload;
    expect(payload.allSubpaths.single, hasLength(3));
    expect(payload.strokeWidth, 4);
    expect(payload.fill, Colors.transparent);
    expect(payload.stroke.toARGB32(), const Color(0xFF1ACC33).toARGB32());
  });

  test(
    'preserves PDF path transforms, transparency, fill rules, and stroke styles',
    () {
      final bytes = Uint8List.fromList(
        utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length 150 >> stream
q
2 0 0 2 10 20 cm
0.2 0.4 0.8 rg 0.8 0.1 0.1 RG
0.5 ca 0.25 CA 2 w 1 J 2 j [3 4] 1 d
0 0 m 10 0 l 10 10 l 0 10 l h B*
Q
endstream endobj
trailer << /Root 1 0 R >>
%%EOF'''),
      );

      final result = ImportService.importFromFileBytes(
        fileName: 'styled-path.pdf',
        bytes: bytes,
      );

      expect(result.isSuccess, isTrue);
      final path = result.nodes.firstWhere(
        (node) => node.type == NodeType.vectorPath,
      );
      final payload = path.payload as VectorPathPayload;
      final points = payload.allSubpaths.single;
      expect(points, hasLength(4));
      expect(points[1].point.dx - points[0].point.dx, closeTo(26.6667, 0.001));
      expect(payload.fillRule, VectorFillRule.evenOdd);
      expect(payload.subpathClosed, [true]);
      expect(payload.fill.a, closeTo(0.5, 0.01));
      expect(payload.stroke.a, closeTo(0.25, 0.01));
      expect(payload.strokeWidth, closeTo(5.3333, 0.001));
      expect(payload.strokeCap, VectorStrokeCap.round);
      expect(payload.strokeJoin, VectorStrokeJoin.bevel);
      expect(payload.dashPattern, [closeTo(8, 0.001), closeTo(10.6667, 0.001)]);
      expect(payload.dashOffset, closeTo(2.6667, 0.001));
    },
  );

  test('restores PDF graphics state after q and Q', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length 105 >> stream
0 0 1 RG
q
1 0 0 RG
0 0 m 10 0 l S
Q
0 10 m 10 10 l S
endstream endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'graphics-state.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final paths = result.nodes
        .where((node) => node.type == NodeType.vectorPath)
        .map((node) => node.payload as VectorPathPayload)
        .toList();
    expect(paths, hasLength(2));
    expect(paths[0].stroke.toARGB32(), const Color(0xFFFF0000).toARGB32());
    expect(paths[1].stroke.toARGB32(), const Color(0xFF0000FF).toARGB32());
  });

  test('applies PDF ExtGState alpha resources to editable paths', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 4 0 R >> endobj
4 0 obj << /Length 62 >> stream
/GS1 gs
1 0 0 rg 0 0 1 RG
0 0 m 20 0 l 20 20 l 0 20 l h B
endstream endobj
6 0 obj << /ExtGState << /GS1 7 0 R >> >> endobj
7 0 obj << /Type /ExtGState /ca 0.3 /CA 0.7 >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'alpha-path.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final path = result.nodes.firstWhere(
      (node) => node.type == NodeType.vectorPath,
    );
    final payload = path.payload as VectorPathPayload;
    expect(payload.fill.a, closeTo(0.3, 0.01));
    expect(payload.stroke.a, closeTo(0.7, 0.01));
  });

  test('imports embedded JPEG XObjects as durable image assets', () {
    final bytes = Uint8List.fromList([
      ...utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 4 0 R >> endobj
4 0 obj << /Length 33 >> stream
144 0 0 96 72 520 cm /Im1 Do
endstream endobj
5 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length 4 >> stream
'''),
      0xFF,
      0xD8,
      0xFF,
      0xD9,
      ...utf8.encode('''
endstream endobj
6 0 obj << /XObject << /Im1 5 0 R >> >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    ]);

    final result = ImportService.importFromFileBytes(
      fileName: 'image.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    expect(result.assets.items, hasLength(1));
    final image = result.nodes.firstWhere(
      (node) => node.type == NodeType.image,
    );
    final payload = image.payload as ImagePayload;
    final asset = result.assets[payload.assetId!];
    expect(asset, isNotNull);
    expect(asset!.mimeType, 'image/jpeg');
    expect(asset.durableReference, isNull);
    expect(result.transientAssetBytes[asset.id], isNotNull);
    expect(image.width, 192);
    expect(image.height, 128);
  });

  test('decodes simple Flate RGB XObjects into durable PNG assets', () {
    final compressed = const ZLibEncoder().encode(<int>[255, 0, 0, 0, 255, 0]);
    final bytes = Uint8List.fromList([
      ...utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 4 0 R >> endobj
4 0 obj << /Length 31 >> stream
2 0 0 1 72 520 cm /Im1 Do
endstream endobj
5 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >> stream
'''),
      ...compressed,
      ...utf8.encode('''
endstream endobj
6 0 obj << /XObject << /Im1 5 0 R >> >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    ]);

    final result = ImportService.importFromFileBytes(
      fileName: 'flate-image.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    expect(result.assets.items, hasLength(1));
    final asset = result.assets.items.single;
    expect(asset.mimeType, 'image/png');
    expect(asset.metadata['width'], 2);
    expect(asset.metadata['height'], 1);
    expect(asset.durableReference, isNull);
    expect(result.transientAssetBytes[asset.id], isNotNull);
    expect(result.nodes.any((node) => node.type == NodeType.image), isTrue);
  });

  test(
    'keeps rotated PDF image placements as editable bounds with loss evidence',
    () {
      final compressed = const ZLibEncoder().encode(<int>[
        255,
        0,
        0,
        0,
        255,
        0,
      ]);
      final bytes = Uint8List.fromList([
        ...utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources 6 0 R /Contents 4 0 R >> endobj
4 0 obj << /Length 36 >> stream
q 0 2 -1 0 200 400 cm /Im1 Do Q
endstream endobj
5 0 obj << /Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length ${compressed.length} >> stream
'''),
        ...compressed,
        ...utf8.encode('''
endstream endobj
6 0 obj << /XObject << /Im1 5 0 R >> >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
      ]);

      final result = ImportService.importFromFileBytes(
        fileName: 'rotated-flate-image.pdf',
        bytes: bytes,
      );

      expect(result.isSuccess, isTrue);
      final image = result.nodes.firstWhere(
        (node) => node.type == NodeType.image,
      );
      expect(image.width, 1.3333333333333333);
      expect(image.height, 2.6666666666666665);
      expect(
        result.lossReport?.unsupported,
        contains(
          'PDF image XObject Im1 uses rotation or shear; it was imported with an axis-aligned editable bounds.',
        ),
      );
    },
  );

  test('imports simple PDF text widgets as editable text nodes', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [7 0 R] >> endobj
7 0 obj << /Type /Annot /Subtype /Widget /FT /Tx /Rect [72 500 300 540] /T (Name) /V (Alice) /DA (/F1 18 Tf 0 g) >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'form.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final field = result.nodes.firstWhere((node) => node.type == NodeType.text);
    final payload = field.payload as TextPayload;
    expect(field.name, 'Name');
    expect(payload.text, 'Alice');
    expect(payload.fontSize, 24);
    expect(payload.color, Colors.black);
    expect(field.width, 304);
    expect(field.height, closeTo(53.33333333333333, 0.0000001));
    expect(
      result.lossReport!.unsupported,
      isNot(
        contains('PDF form fields are not converted to editable controls.'),
      ),
    );
  });

  test('imports checkbox, radio, and choice widgets as editable nodes', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [8 0 R 9 0 R 10 0 R] >> endobj
8 0 obj << /Type /Annot /Subtype /Widget /FT /Btn /Ff 0 /Rect [72 500 100 528] /T (Agree) /V /Yes /DA (/F1 12 Tf 0 g) >> endobj
9 0 obj << /Type /Annot /Subtype /Widget /FT /Btn /Ff 32768 /Rect [120 500 148 528] /T (Choice) /V /On /DA (/F1 12 Tf 0 g) >> endobj
10 0 obj << /Type /Annot /Subtype /Widget /FT /Ch /Rect [170 500 320 540] /T (Country) /V (Indonesia) /DA (/F1 12 Tf 0 g) >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'controls.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final checkbox = result.nodes.firstWhere((node) => node.name == 'Agree');
    final checkboxPayload = checkbox.payload as ShapePayload;
    expect(checkbox.type, NodeType.rectangle);
    expect(checkboxPayload.label, '✓');
    final radio = result.nodes.firstWhere((node) => node.name == 'Choice');
    final radioPayload = radio.payload as ShapePayload;
    expect(radio.type, NodeType.ellipse);
    expect(radioPayload.label, '●');
    final choice = result.nodes.firstWhere((node) => node.name == 'Country');
    expect(choice.type, NodeType.text);
    expect((choice.payload as TextPayload).text, 'Indonesia');
    expect(
      result.lossReport?.unsupported,
      isNot(
        contains(
          'PDF form widget Btn is not converted to an editable canvas control.',
        ),
      ),
    );
  });

  test('imports PDF push buttons as labeled editable shapes', () {
    final bytes = Uint8List.fromList(
      utf8.encode('''%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [8 0 R] >> endobj
8 0 obj << /Type /Annot /Subtype /Widget /FT /Btn /Ff 65536 /Rect [72 500 100 528] /T (Submit) /MK << /CA (Submit) >> /V /Yes >> endobj
trailer << /Root 1 0 R >>
%%EOF'''),
    );

    final result = ImportService.importFromFileBytes(
      fileName: 'checkbox.pdf',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.nodes.where((node) => node.type == NodeType.frame),
      isNotEmpty,
    );
    final button = result.nodes.firstWhere((node) => node.name == 'Submit');
    expect(button.type, NodeType.rectangle);
    expect((button.payload as ShapePayload).label, 'Submit');
    expect(
      result.lossReport?.unsupported,
      isNot(
        contains(
          'PDF form widget Btn is not converted to an editable canvas control.',
        ),
      ),
    );
  });
}
