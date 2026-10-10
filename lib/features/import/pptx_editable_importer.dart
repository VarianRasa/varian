import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../domain/models/document_asset.dart';
import '../../domain/models/document_package_archive.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import 'import_loss_report.dart';

class PptxEditableImportResult {
  final List<CanvasNode> nodes;
  final DocumentAssetManifest assets;
  final ImportLossReport lossReport;
  final Map<String, Uint8List> transientAssetBytes;

  const PptxEditableImportResult({
    required this.nodes,
    this.assets = const DocumentAssetManifest(),
    required this.lossReport,
    this.transientAssetBytes = const {},
  });
}

class PptxEditableImporter {
  static const double _emuPerInch = 914400.0;
  static const double _pixelsPerInch = 96.0;
  static const double _defaultSlideWidth = 1280.0;
  static const double _defaultSlideHeight = 720.0;

  static PptxEditableImportResult? tryImport(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      final entries = <String, ArchiveFile>{
        for (final file in archive)
          if (file.isFile && _isSafeEntry(file.name)) file.name: file,
      };
      final slideNames =
          entries.keys
              .where(
                (name) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name),
              )
              .toList()
            ..sort(_slideNameCompare);
      if (slideNames.isEmpty) return null;

      final presentation = _parseDocument(entries['ppt/presentation.xml']);
      final slideSize = _slideSize(presentation);
      final nodes = <CanvasNode>[];
      var assets = const DocumentAssetManifest();
      final imageAssetIds = <String, String>{};
      final transientAssetBytes = <String, Uint8List>{};
      final lossy = <String>[
        'PPTX slide geometry and text are mapped to editable canvas nodes.',
        'PPTX theme, master, font, and exact visual style fidelity is not preserved.',
      ];
      final unsupported = <String>[];

      for (var index = 0; index < slideNames.length; index++) {
        final slideName = slideNames[index];
        final document = _parseDocument(entries[slideName]);
        if (document == null) continue;

        final frameId = const Uuid().v4();
        final frameX = 80.0 + (index % 2) * (slideSize.width + 80.0);
        final frameY = 80.0 + (index ~/ 2) * (slideSize.height + 80.0);
        nodes.add(
          CanvasNode(
            id: frameId,
            type: NodeType.frame,
            x: frameX,
            y: frameY,
            width: slideSize.width,
            height: slideSize.height,
            name: 'Slide ${index + 1}',
            payload: FramePayload(
              name: 'Slide ${index + 1}',
              isLandscape: slideSize.width >= slideSize.height,
            ),
          ),
        );

        _recordUnsupportedContent(document, unsupported);
        final shapes = document.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'sp',
        );
        for (final shape in shapes) {
          final node = _shapeNode(
            shape,
            frameId: frameId,
            frameX: frameX,
            frameY: frameY,
            slideWidth: slideSize.width,
            slideHeight: slideSize.height,
            unsupported: unsupported,
          );
          if (node != null) nodes.add(node);
        }
        final relationships = _relationships(entries, slideName);
        final pictures = document.descendants.whereType<XmlElement>().where(
          (element) => element.name.local == 'pic',
        );
        for (var imageIndex = 0; imageIndex < pictures.length; imageIndex++) {
          final placement = _imagePlacement(
            pictures.elementAt(imageIndex),
            relationships,
            entries,
            unsupported,
          );
          if (placement == null) continue;
          final assetId = imageAssetIds.putIfAbsent(placement.targetPath, () {
            final now = DateTime.now().toUtc();
            final asset = DocumentAsset(
              id: const Uuid().v4(),
              kind: DocumentAssetKind.image,
              storage: DocumentAssetStorage.embedded,
              name: placement.name,
              mimeType: placement.mimeType,
              sizeBytes: placement.bytes.length,
              checksum: DocumentPackageArchiveChecksum.sha256(placement.bytes),
              createdAt: now,
              updatedAt: now,
              metadata: {
                'source': 'pptx-media',
                'targetPath': placement.targetPath,
                'width': placement.pixelWidth,
                'height': placement.pixelHeight,
              },
            );
            assets = assets.upsert(asset);
            transientAssetBytes[asset.id] = placement.bytes;
            return asset.id;
          });
          nodes.add(
            CanvasNode(
              id: const Uuid().v4(),
              type: NodeType.image,
              x: frameX + placement.x,
              y: frameY + placement.y,
              width: placement.width,
              height: placement.height,
              rotation: placement.rotation,
              parentId: frameId,
              name: 'Slide ${index + 1} image ${imageIndex + 1}',
              payload: ImagePayload(
                assetId: assetId,
                fit: 'contain',
                caption: placement.name,
              ),
            ),
          );
        }
      }

      if (nodes.isEmpty) return null;
      return PptxEditableImportResult(
        nodes: nodes,
        assets: assets,
        transientAssetBytes: transientAssetBytes,
        lossReport: ImportLossReport(
          format: ImportSourceFormat.pptx,
          preserved: [
            'Slide count and slide order',
            'Editable shape geometry',
            'Editable shape text',
            'Embedded raster image assets',
          ],
          lossy: lossy,
          unsupported: _unique(unsupported),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static CanvasNode? _shapeNode(
    XmlElement shape, {
    required String frameId,
    required double frameX,
    required double frameY,
    required double slideWidth,
    required double slideHeight,
    required List<String> unsupported,
  }) {
    final transform = _descendant(shape, 'xfrm');
    final offset = _descendant(transform, 'off');
    final extent = _descendant(transform, 'ext');
    final x = _emuToPixels(_number(offset?.getAttribute('x')) ?? 0);
    final y = _emuToPixels(_number(offset?.getAttribute('y')) ?? 0);
    final width = _safeDimension(
      _emuToPixels(_number(extent?.getAttribute('cx')) ?? 0),
      fallback: 180,
      max: slideWidth,
    );
    final height = _safeDimension(
      _emuToPixels(_number(extent?.getAttribute('cy')) ?? 0),
      fallback: 90,
      max: slideHeight,
    );
    final geometry = _descendant(shape, 'prstGeom')?.getAttribute('prst');
    final type = _nodeTypeForGeometry(geometry, unsupported);
    final label = _shapeText(shape);
    final name = _descendant(shape, 'cNvPr')?.getAttribute('name');
    final fill =
        _colorFromElement(_descendant(shape, 'solidFill')) ??
        const Color(0xFF2563EB);
    final stroke =
        _colorFromElement(_descendant(_descendant(shape, 'ln'), 'solidFill')) ??
        const Color(0xFF60A5FA);
    final line = _descendant(shape, 'ln');
    final textStyle = _shapeTextStyle(shape);

    return CanvasNode(
      id: const Uuid().v4(),
      type: type,
      x: frameX + x,
      y: frameY + y,
      width: width,
      height: height,
      rotation: _rotationRadians(
        _number(_attributeByLocalName(transform, 'rot')) ?? 0,
      ),
      parentId: frameId,
      name: name,
      payload: ShapePayload(
        fill: fill,
        stroke: stroke,
        strokeWidth: _strokeWidth(line),
        label: label,
        labelColor: textStyle.color,
        labelFontSize: textStyle.fontSize,
        cornerRadius: geometry == 'roundRect' ? 12.0 : 4.0,
      ),
    );
  }

  static NodeType _nodeTypeForGeometry(
    String? geometry,
    List<String> unsupported,
  ) {
    switch (geometry) {
      case null:
      case 'rect':
      case 'roundRect':
        return NodeType.rectangle;
      case 'ellipse':
        return NodeType.ellipse;
      case 'diamond':
        return NodeType.diamond;
      case 'parallelogram':
        return NodeType.parallelogram;
      case 'cylinder':
        return NodeType.cylinder;
      default:
        unsupported.add('Unsupported PPTX geometry: $geometry');
        return NodeType.rectangle;
    }
  }

  static String _shapeText(XmlElement shape) {
    final text = <String>[];
    for (final paragraph in shape.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'p',
    )) {
      final value = paragraph.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 't')
          .map((element) => element.innerText)
          .join();
      if (value.isNotEmpty) text.add(value);
    }
    return text.join('\n').trim();
  }

  static _PptxTextStyle _shapeTextStyle(XmlElement shape) {
    final runProperties =
        _descendant(shape, 'rPr') ?? _descendant(shape, 'defRPr');
    final fontSize = _number(_attributeByLocalName(runProperties, 'sz'));
    return _PptxTextStyle(
      color:
          _colorFromElement(_descendant(runProperties, 'solidFill')) ??
          Colors.white,
      fontSize: fontSize == null
          ? 14.0
          : (fontSize / 100.0) * _pixelsPerInch / 72.0,
    );
  }

  static double _strokeWidth(XmlElement? line) {
    final emu = _number(_attributeByLocalName(line, 'w'));
    if (emu == null || emu <= 0) return 2.0;
    return _emuToPixels(emu);
  }

  static double _rotationRadians(double value) =>
      value / 60000.0 * math.pi / 180.0;

  static void _recordUnsupportedContent(
    XmlDocument document,
    List<String> unsupported,
  ) {
    final elements = document.descendants.whereType<XmlElement>();
    if (elements.any((element) => element.name.local == 'tbl')) {
      unsupported.add('PPTX tables are not converted to editable table nodes.');
    }
    if (elements.any((element) => element.name.local == 'chart')) {
      unsupported.add('PPTX charts are not converted to editable chart nodes.');
    }
    if (elements.any((element) => element.name.local == 'timing')) {
      unsupported.add('PPTX animations and timings are not imported.');
    }
    if (elements.any((element) => element.name.local == 'cxnSp')) {
      unsupported.add('PPTX connectors are not converted to canvas edges.');
    }
  }

  static Map<String, String> _relationships(
    Map<String, ArchiveFile> entries,
    String slideName,
  ) {
    final slash = slideName.lastIndexOf('/');
    if (slash < 0) return const {};
    final baseName = slideName.substring(slash + 1);
    final relationshipPath =
        '${slideName.substring(0, slash)}/_rels/$baseName.rels';
    final document = _parseDocument(entries[relationshipPath]);
    if (document == null) return const {};
    return {
      for (final element in document.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'Relationship',
      ))
        if (_attributeByLocalName(element, 'Id') != null &&
            _attributeByLocalName(element, 'Target') != null)
          _attributeByLocalName(element, 'Id')!: _resolveArchivePath(
            slideName,
            _attributeByLocalName(element, 'Target')!,
          ),
    };
  }

  static _PptxImagePlacement? _imagePlacement(
    XmlElement picture,
    Map<String, String> relationships,
    Map<String, ArchiveFile> entries,
    List<String> unsupported,
  ) {
    final blip = _descendant(picture, 'blip');
    final relationshipId =
        _attributeByLocalName(blip, 'embed') ??
        _attributeByLocalName(blip, 'link');
    if (relationshipId == null) {
      unsupported.add('PPTX image has no resolvable relationship ID.');
      return null;
    }
    final targetPath = relationships[relationshipId];
    if (targetPath == null) {
      unsupported.add('PPTX image relationship $relationshipId is missing.');
      return null;
    }
    final file = entries[targetPath];
    if (file == null) {
      unsupported.add('PPTX image target $targetPath is missing.');
      return null;
    }
    final extension = _fileExtension(targetPath);
    final mimeType = _imageMimeType(extension);
    if (mimeType == null) {
      unsupported.add('PPTX image format .$extension is not supported.');
      return null;
    }
    final transform = _descendant(picture, 'xfrm');
    final offset = _descendant(transform, 'off');
    final extent = _descendant(transform, 'ext');
    final name =
        _descendant(picture, 'cNvPr')?.getAttribute('name') ??
        targetPath.split('/').last;
    return _PptxImagePlacement(
      targetPath: targetPath,
      name: name,
      mimeType: mimeType,
      bytes: Uint8List.fromList(List<int>.from(file.content)),
      pixelWidth: _number(_attributeByLocalName(extent, 'cx'))?.round() ?? 1,
      pixelHeight: _number(_attributeByLocalName(extent, 'cy'))?.round() ?? 1,
      x: _emuToPixels(_number(_attributeByLocalName(offset, 'x')) ?? 0),
      y: _emuToPixels(_number(_attributeByLocalName(offset, 'y')) ?? 0),
      rotation: _rotationRadians(
        _number(_attributeByLocalName(transform, 'rot')) ?? 0,
      ),
      width: _safeDimension(
        _emuToPixels(_number(_attributeByLocalName(extent, 'cx')) ?? 0),
        fallback: 180,
        max: double.maxFinite,
      ),
      height: _safeDimension(
        _emuToPixels(_number(_attributeByLocalName(extent, 'cy')) ?? 0),
        fallback: 90,
        max: double.maxFinite,
      ),
    );
  }

  static String _resolveArchivePath(String sourcePath, String target) {
    final parts = sourcePath.split('/')..removeLast();
    for (final part in target.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static String? _attributeByLocalName(XmlNode? node, String name) {
    if (node is! XmlElement) return null;
    for (final attribute in node.attributes) {
      if (attribute.name.local == name) return attribute.value;
    }
    return null;
  }

  static String _fileExtension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String? _imageMimeType(String extension) => switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => null,
  };

  static XmlDocument? _parseDocument(ArchiveFile? file) {
    if (file == null) return null;
    final bytes = List<int>.from(file.content);
    if (bytes.isEmpty) return null;
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  }

  static Size _slideSize(XmlDocument? presentation) {
    final element = _descendant(presentation, 'sldSz');
    final width = _emuToPixels(_number(element?.getAttribute('cx')) ?? 0);
    final height = _emuToPixels(_number(element?.getAttribute('cy')) ?? 0);
    return Size(
      width > 0 ? width : _defaultSlideWidth,
      height > 0 ? height : _defaultSlideHeight,
    );
  }

  static Color? _colorFromElement(XmlElement? element) {
    if (element == null) return null;
    final color = _descendant(element, 'srgbClr');
    final raw = color?.getAttribute('val');
    if (raw == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) return null;
    return Color(int.parse('FF$raw', radix: 16));
  }

  static XmlElement? _descendant(XmlNode? node, String localName) {
    if (node == null) return null;
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static double? _number(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static double _emuToPixels(double value) =>
      value / _emuPerInch * _pixelsPerInch;

  static double _safeDimension(
    double value, {
    required double fallback,
    required double max,
  }) {
    if (value <= 0 || !value.isFinite) return fallback;
    return math.min(value, math.max(max, fallback));
  }

  static bool _isSafeEntry(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.split('/').contains('..');
  }

  static int _slideNameCompare(String left, String right) {
    final leftNumber =
        int.tryParse(RegExp(r'\d+').firstMatch(left)?.group(0) ?? '') ?? 0;
    final rightNumber =
        int.tryParse(RegExp(r'\d+').firstMatch(right)?.group(0) ?? '') ?? 0;
    return leftNumber.compareTo(rightNumber);
  }

  static List<String> _unique(Iterable<String> values) =>
      values.toSet().toList();
}

class _PptxImagePlacement {
  final String targetPath;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final int pixelWidth;
  final int pixelHeight;
  final double x;
  final double y;
  final double rotation;
  final double width;
  final double height;

  const _PptxImagePlacement({
    required this.targetPath,
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.x,
    required this.y,
    required this.rotation,
    required this.width,
    required this.height,
  });
}

class _PptxTextStyle {
  final Color color;
  final double fontSize;

  const _PptxTextStyle({required this.color, required this.fontSize});
}
