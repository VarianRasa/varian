import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/import/import_loss_report.dart';
import 'package:varian/features/import/import_service.dart';

void main() {
  test('imports PPTX slide shapes and text as editable canvas nodes', () {
    final source = Archive()
      ..addFile(
        ArchiveFile.string(
          'ppt/presentation.xml',
          '<p:presentation xmlns:p="p" xmlns:a="a"><p:sldSz cx="12192000" cy="6858000"/></p:presentation>',
        ),
      )
      ..addFile(
        ArchiveFile.string('ppt/slides/slide1.xml', '''
          <p:sld xmlns:p="p" xmlns:a="a">
            <p:cSld>
              <p:sp>
                <p:nvSpPr><p:cNvPr id="2" name="Title"/></p:nvSpPr>
                <p:spPr>
                  <a:xfrm><a:off x="952500" y="952500"/><a:ext cx="3810000" cy="952500"/></a:xfrm>
                  <a:prstGeom prst="roundRect"/>
                </p:spPr>
                <p:txBody><a:p><a:r><a:t>Editable title</a:t></a:r></a:p></p:txBody>
              </p:sp>
            </p:cSld>
          </p:sld>
          '''),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(source));

    final result = ImportService.importFromFileBytes(
      fileName: 'deck.pptx',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    expect(result.lossReport?.format, ImportSourceFormat.pptx);
    expect(result.nodes.any((node) => node.type == NodeType.frame), isTrue);
    final shape = result.nodes.firstWhere(
      (node) => node.type == NodeType.rectangle,
    );
    expect((shape.payload as ShapePayload).label, 'Editable title');
    expect(shape.parentId, isNotNull);
    expect(result.lossReport?.lossy, isNotEmpty);
  });

  test('falls back to an auditable attachment for invalid PPTX bytes', () {
    final result = ImportService.importFromFileBytes(
      fileName: 'broken.pptx',
      bytes: Uint8List.fromList(utf8.encode('not a zip')),
    );

    expect(result.isSuccess, isTrue);
    expect(result.nodes.single.type, NodeType.fileCard);
    expect(result.lossReport?.format, ImportSourceFormat.file);
    expect(result.lossReport?.lossy, isNotEmpty);
  });

  test('imports PPTX picture relationships as durable image assets', () {
    final source = Archive()
      ..addFile(
        ArchiveFile.string(
          'ppt/presentation.xml',
          '<p:presentation xmlns:p="p" xmlns:a="a"><p:sldSz cx="12192000" cy="6858000"/></p:presentation>',
        ),
      )
      ..addFile(
        ArchiveFile.string('ppt/slides/slide1.xml', '''
          <p:sld xmlns:p="p" xmlns:a="a" xmlns:r="r">
            <p:cSld>
              <p:pic>
                <p:nvPicPr><p:cNvPr id="2" name="Hero image"/><p:cNvPicPr/></p:nvPicPr>
                <p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
                <p:spPr>
                  <a:xfrm><a:off x="914400" y="914400"/><a:ext cx="4572000" cy="2286000"/></a:xfrm>
                  <a:prstGeom prst="rect"/>
                </p:spPr>
              </p:pic>
            </p:cSld>
          </p:sld>
          '''),
      )
      ..addFile(
        ArchiveFile.string(
          'ppt/slides/_rels/slide1.xml.rels',
          '<Relationships xmlns="r"><Relationship Id="rId1" Target="../media/image1.png" Type="image"/></Relationships>',
        ),
      )
      ..addFile(ArchiveFile.bytes('ppt/media/image1.png', [1, 2, 3]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(source));

    final result = ImportService.importFromFileBytes(
      fileName: 'image-deck.pptx',
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
    expect(asset!.mimeType, 'image/png');
    expect(asset.durableReference, isNull);
    expect(result.transientAssetBytes[asset.id], [1, 2, 3]);
    expect(image.x, 176);
    expect(image.y, 176);
    expect(image.width, 480);
    expect(image.height, 240);
  });

  test('preserves PPTX rotation, stroke width, and label text style', () {
    final source = Archive()
      ..addFile(
        ArchiveFile.string(
          'ppt/presentation.xml',
          '<p:presentation xmlns:p="p" xmlns:a="a"><p:sldSz cx="12192000" cy="6858000"/></p:presentation>',
        ),
      )
      ..addFile(
        ArchiveFile.string('ppt/slides/slide1.xml', '''
          <p:sld xmlns:p="p" xmlns:a="a">
            <p:cSld>
              <p:sp>
                <p:nvSpPr><p:cNvPr id="2" name="Styled shape"/></p:nvSpPr>
                <p:spPr>
                  <a:xfrm rot="900000"><a:off x="952500" y="952500"/><a:ext cx="3810000" cy="952500"/></a:xfrm>
                  <a:prstGeom prst="roundRect"/>
                  <a:solidFill><a:srgbClr val="112233"/></a:solidFill>
                  <a:ln w="12700"><a:solidFill><a:srgbClr val="00AAFF"/></a:solidFill></a:ln>
                </p:spPr>
                <p:txBody><a:p><a:r><a:rPr sz="1800"><a:solidFill><a:srgbClr val="00FF00"/></a:solidFill></a:rPr><a:t>Styled title</a:t></a:r></a:p></p:txBody>
              </p:sp>
            </p:cSld>
          </p:sld>
          '''),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(source));

    final result = ImportService.importFromFileBytes(
      fileName: 'styled-deck.pptx',
      bytes: bytes,
    );

    expect(result.isSuccess, isTrue);
    final shape = result.nodes.firstWhere(
      (node) => node.type == NodeType.rectangle,
    );
    final payload = shape.payload as ShapePayload;
    expect(shape.rotation, closeTo(15 * math.pi / 180, 0.0000001));
    expect(payload.strokeWidth, closeTo(1.3333333333333333, 0.0000001));
    expect(payload.label, 'Styled title');
    expect(payload.labelColor, const Color(0xFF00FF00));
    expect(payload.labelFontSize, closeTo(24, 0.0000001));
  });
}
