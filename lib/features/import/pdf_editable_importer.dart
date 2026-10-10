import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:uuid/uuid.dart';

import '../../domain/models/document_asset.dart';
import '../../domain/models/document_package_archive.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import '../../domain/models/vector_path_payload.dart';
import 'import_loss_report.dart';

class PdfEditableImportResult {
  final List<CanvasNode> nodes;
  final DocumentAssetManifest assets;
  final ImportLossReport lossReport;
  final Map<String, Uint8List> transientAssetBytes;

  const PdfEditableImportResult({
    required this.nodes,
    this.assets = const DocumentAssetManifest(),
    required this.lossReport,
    this.transientAssetBytes = const {},
  });
}

class PdfEditableImporter {
  static const double _pointsToPixels = 96.0 / 72.0;
  static const double _defaultPageWidth = 612.0;
  static const double _defaultPageHeight = 792.0;
  static const int _maxImportBytes = 50 * 1024 * 1024;

  static PdfEditableImportResult? tryImport(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxImportBytes) return null;
    final source = latin1.decode(bytes, allowInvalid: true);
    if (!source.startsWith('%PDF-') || !source.contains('%%EOF')) return null;

    final objects = _objects(source);
    final pages = objects.values.where(_isPageObject).toList();
    if (pages.isEmpty) return null;

    final nodes = <CanvasNode>[];
    var assets = const DocumentAssetManifest();
    final imageAssetIds = <String, String>{};
    final transientAssetBytes = <String, Uint8List>{};
    final lossy = <String>[
      'PDF pages, text operators, and basic vector path operators are mapped to editable canvas nodes.',
      'PDF font metrics, advanced vector styling, clipping, blend modes, and exact layout fidelity are not preserved.',
      'Simple PDF text, checkbox, radio, choice, and push-button form widgets are mapped to editable canvas nodes.',
    ];
    final unsupported = <String>[];

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      final pageSize = _pageSize(page.body);
      final frameId = const Uuid().v4();
      final frameX = 80.0 + (pageIndex % 2) * (pageSize.width + 80.0);
      final frameY = 80.0 + (pageIndex ~/ 2) * (pageSize.height + 80.0);
      nodes.add(
        CanvasNode(
          id: frameId,
          type: NodeType.frame,
          x: frameX,
          y: frameY,
          width: pageSize.width,
          height: pageSize.height,
          name: 'PDF page ${pageIndex + 1}',
          payload: FramePayload(
            name: 'PDF page ${pageIndex + 1}',
            background: Colors.white,
            borderColor: const Color(0xFFCBD5E1),
            isLandscape: pageSize.width >= pageSize.height,
          ),
        ),
      );

      _recordUnsupported(page.body, objects, unsupported);
      final content = _contentForPage(page.body, objects);
      final graphicsStates = _graphicsStates(page.body, objects);
      final textOperators = _textOperators(content);
      for (var textIndex = 0; textIndex < textOperators.length; textIndex++) {
        final operator = textOperators[textIndex];
        final fontSize = operator.fontSize * _pointsToPixels;
        final x = operator.x * _pointsToPixels;
        final y =
            (pageSize.height / _pointsToPixels -
                operator.y -
                operator.fontSize) *
            _pointsToPixels;
        nodes.add(
          CanvasNode(
            id: const Uuid().v4(),
            type: NodeType.text,
            x: frameX + math.max(0, x),
            y: frameY + math.max(0, y),
            width: math.max(120, operator.text.length * fontSize * 0.55),
            height: math.max(24, fontSize * 1.35),
            parentId: frameId,
            name: 'PDF text ${textIndex + 1}',
            payload: TextPayload(
              text: operator.text,
              fontSize: fontSize,
              color: Colors.black,
            ),
          ),
        );
      }
      final formFields = _formFields(page.body, objects);
      for (var fieldIndex = 0; fieldIndex < formFields.length; fieldIndex++) {
        final field = formFields[fieldIndex];
        final x = field.rect.left * _pointsToPixels;
        final y =
            (pageSize.height / _pointsToPixels - field.rect.bottom) *
            _pointsToPixels;
        nodes.add(
          CanvasNode(
            id: const Uuid().v4(),
            type: NodeType.text,
            x: frameX + math.max(0, x),
            y: frameY + math.max(0, y),
            width: math.max(24, field.rect.width * _pointsToPixels),
            height: math.max(24, field.rect.height * _pointsToPixels),
            parentId: frameId,
            name: field.name.isEmpty
                ? 'PDF text field ${fieldIndex + 1}'
                : field.name,
            payload: TextPayload(
              text: field.value,
              fontSize: field.fontSize * _pointsToPixels,
              color: field.color,
              backgroundColor: const Color(0xFFF8FAFC),
              backgroundRadius: 2,
              backgroundPadding: 4,
            ),
          ),
        );
      }
      final formControls = _formControls(page.body, objects);
      for (
        var controlIndex = 0;
        controlIndex < formControls.length;
        controlIndex++
      ) {
        final control = formControls[controlIndex];
        final x = control.rect.left * _pointsToPixels;
        final y =
            (pageSize.height / _pointsToPixels - control.rect.bottom) *
            _pointsToPixels;
        final width = math
            .max(24, control.rect.width * _pointsToPixels)
            .toDouble();
        final height = math
            .max(24, control.rect.height * _pointsToPixels)
            .toDouble();
        final name = control.name.isEmpty
            ? 'PDF ${control.fieldType} field ${controlIndex + 1}'
            : control.name;
        if (control.fieldType == 'Btn') {
          final isRadio = control.isRadio;
          final checked = control.checked;
          nodes.add(
            CanvasNode(
              id: const Uuid().v4(),
              type: isRadio ? NodeType.ellipse : NodeType.rectangle,
              x: frameX + math.max(0, x),
              y: frameY + math.max(0, y),
              width: width,
              height: height,
              parentId: frameId,
              name: name,
              payload: ShapePayload(
                fill: control.isPushButton
                    ? const Color(0xFFE2E8F0)
                    : checked
                    ? const Color(0xFF2563EB)
                    : Colors.transparent,
                fillOpacity: control.isPushButton || checked ? 1 : 0,
                stroke: control.color,
                strokeWidth: math.max(1, control.fontSize * 0.08),
                cornerRadius: isRadio ? height / 2 : 4,
                label: control.isPushButton
                    ? control.label
                    : checked
                    ? (isRadio ? '●' : '✓')
                    : '',
                labelColor: control.isPushButton
                    ? const Color(0xFF0F172A)
                    : checked
                    ? Colors.white
                    : control.color,
                labelFontSize: control.isPushButton
                    ? math.max(10, control.fontSize * _pointsToPixels)
                    : math.max(10, height * 0.55),
              ),
            ),
          );
        } else {
          nodes.add(
            CanvasNode(
              id: const Uuid().v4(),
              type: NodeType.text,
              x: frameX + math.max(0, x),
              y: frameY + math.max(0, y),
              width: width,
              height: height,
              parentId: frameId,
              name: name,
              payload: TextPayload(
                text: control.value,
                fontSize: control.fontSize * _pointsToPixels,
                color: control.color,
                backgroundColor: const Color(0xFFF8FAFC),
                backgroundRadius: 2,
                backgroundPadding: 4,
              ),
            ),
          );
        }
      }
      final vectorRectangles = _vectorRectangles(
        content,
        pageHeightPoints: pageSize.height / _pointsToPixels,
      );
      for (
        var shapeIndex = 0;
        shapeIndex < vectorRectangles.length;
        shapeIndex++
      ) {
        final rectangle = vectorRectangles[shapeIndex];
        final x = rectangle.x * _pointsToPixels;
        final y =
            (pageSize.height / _pointsToPixels -
                rectangle.y -
                rectangle.height) *
            _pointsToPixels;
        nodes.add(
          CanvasNode(
            id: const Uuid().v4(),
            type: NodeType.rectangle,
            x: frameX + math.max(0, x),
            y: frameY + math.max(0, y),
            width: math.max(1, rectangle.width * _pointsToPixels),
            height: math.max(1, rectangle.height * _pointsToPixels),
            parentId: frameId,
            name: 'PDF rectangle ${shapeIndex + 1}',
            payload: ShapePayload(
              fill: rectangle.fill,
              fillOpacity: rectangle.hasFill ? 1 : 0,
              stroke: rectangle.stroke,
              strokeWidth: rectangle.strokeWidth * _pointsToPixels,
            ),
          ),
        );
      }
      final vectorPaths = _vectorPaths(content, graphicsStates: graphicsStates);
      for (var pathIndex = 0; pathIndex < vectorPaths.length; pathIndex++) {
        final pathNode = _vectorPathNode(
          vectorPaths[pathIndex],
          frameId: frameId,
          frameX: frameX,
          frameY: frameY,
          pageHeightPoints: pageSize.height / _pointsToPixels,
          name: 'PDF path ${pathIndex + 1}',
        );
        if (pathNode != null) nodes.add(pathNode);
      }
      final imagePlacements = _imagePlacements(
        page.body,
        content,
        objects,
        unsupported,
      );
      for (
        var imageIndex = 0;
        imageIndex < imagePlacements.length;
        imageIndex++
      ) {
        final placement = imagePlacements[imageIndex];
        final assetId = imageAssetIds.putIfAbsent(placement.objectId, () {
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
              'source': 'pdf-xobject',
              'objectId': placement.objectId,
              'width': placement.pixelWidth,
              'height': placement.pixelHeight,
            },
          );
          assets = assets.upsert(asset);
          transientAssetBytes[asset.id] = placement.bytes;
          return asset.id;
        });
        final x = placement.x * _pointsToPixels;
        final y =
            (pageSize.height / _pointsToPixels -
                placement.y -
                placement.height) *
            _pointsToPixels;
        nodes.add(
          CanvasNode(
            id: const Uuid().v4(),
            type: NodeType.image,
            x: frameX + math.max(0, x),
            y: frameY + math.max(0, y),
            width: math.max(1, placement.width * _pointsToPixels),
            height: math.max(1, placement.height * _pointsToPixels),
            parentId: frameId,
            name: 'PDF image ${pageIndex + 1}-${imageIndex + 1}',
            payload: ImagePayload(
              assetId: assetId,
              fit: 'contain',
              caption: placement.name,
            ),
          ),
        );
      }
      if (textOperators.isEmpty) {
        unsupported.add(
          'PDF page ${pageIndex + 1} has no extractable text operators.',
        );
      }
    }

    return PdfEditableImportResult(
      nodes: nodes,
      assets: assets,
      transientAssetBytes: transientAssetBytes,
      lossReport: ImportLossReport(
        format: ImportSourceFormat.pdf,
        preserved: [
          'PDF page count and page order',
          'Extractable literal text operators',
          'Basic line and cubic path operators',
          'Embedded JPEG and simple FlateDecode image XObjects with basic translation and scale',
        ],
        lossy: lossy,
        unsupported: _unique(unsupported),
      ),
    );
  }

  static Map<String, _PdfObject> _objects(String source) {
    final result = <String, _PdfObject>{};
    final objectPattern = RegExp(
      r'(\d+)\s+(\d+)\s+obj\s*(.*?)\s*endobj',
      multiLine: true,
      dotAll: true,
    );
    for (final match in objectPattern.allMatches(source)) {
      final id = '${match.group(1)} ${match.group(2)}';
      result[id] = _PdfObject(id: id, body: match.group(3) ?? '');
    }
    return result;
  }

  static bool _isPageObject(_PdfObject object) =>
      RegExp(r'/Type\s*/Page(?:\s|/|$)').hasMatch(object.body) &&
      !RegExp(r'/Type\s*/Pages(?:\s|/|$)').hasMatch(object.body);

  static Size _pageSize(String body) {
    final cropBox = _numberList(body, 'CropBox');
    final mediaBox = _numberList(body, 'MediaBox');
    final box = cropBox.length >= 4 ? cropBox : mediaBox;
    final width = box.length >= 4 ? (box[2] - box[0]).abs() : _defaultPageWidth;
    final height = box.length >= 4
        ? (box[3] - box[1]).abs()
        : _defaultPageHeight;
    return Size(
      math.max(72, width) * _pointsToPixels,
      math.max(72, height) * _pointsToPixels,
    );
  }

  static String _contentForPage(
    String pageBody,
    Map<String, _PdfObject> objects,
  ) {
    final references = RegExp(r'/Contents\s+(\d+)\s+(\d+)\s+R')
        .allMatches(pageBody)
        .map((match) => '${match.group(1)} ${match.group(2)}');
    final streams = <String>[];
    for (final reference in references) {
      final body = objects[reference]?.body;
      if (body == null) continue;
      final stream = RegExp(
        r'stream\s*(.*?)\s*endstream',
        multiLine: true,
        dotAll: true,
      ).firstMatch(body);
      final rawStream = stream?.group(1) ?? body;
      streams.add(
        body.contains('/FlateDecode') ? _inflateStream(rawStream) : rawStream,
      );
    }
    if (streams.isNotEmpty) return streams.join('\n');
    return pageBody;
  }

  static List<_PdfTextOperator> _textOperators(String content) {
    final result = <_PdfTextOperator>[];
    final textPattern = RegExp(
      r'(.*?)\(((?:\\.|[^\\)])*)\)\s*Tj',
      dotAll: true,
    );
    for (final match in textPattern.allMatches(content)) {
      final text = _decodePdfLiteral(match.group(2) ?? '').trim();
      if (text.isEmpty) continue;
      result.add(_textOperator(content, match.start, text));
    }
    final hexPattern = RegExp(r'(.*?)<([0-9a-fA-F\s]+)>\s*Tj', dotAll: true);
    for (final match in hexPattern.allMatches(content)) {
      final text = _decodePdfHex(match.group(2) ?? '').trim();
      if (text.isEmpty) continue;
      result.add(_textOperator(content, match.start, text));
    }
    return result;
  }

  static List<_PdfFormField> _formFields(
    String pageBody,
    Map<String, _PdfObject> objects,
  ) {
    final annotationSection = RegExp(
      r'/Annots\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pageBody)?.group(1);
    final references = <RegExpMatch>[];
    if (annotationSection == null) {
      final reference = RegExp(
        r'/Annots\s+(\d+)\s+(\d+)\s+R',
      ).firstMatch(pageBody);
      if (reference != null) references.add(reference);
    } else {
      references.addAll(
        RegExp(r'(\d+)\s+(\d+)\s+R').allMatches(annotationSection),
      );
    }

    final result = <_PdfFormField>[];
    for (final reference in references) {
      final objectId = '${reference.group(1)} ${reference.group(2)}';
      final object = objects[objectId];
      if (object == null) continue;
      var body = object.body;
      final parent = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R').firstMatch(body);
      if (parent != null) {
        body =
            '${objects['${parent.group(1)} ${parent.group(2)}']?.body ?? ''} $body';
      }
      if (!body.contains('/Subtype /Widget')) continue;
      final fieldType = RegExp(
        r'/FT\s*/([A-Za-z0-9]+)',
      ).firstMatch(body)?.group(1);
      if (fieldType != 'Tx') continue;
      final rectValues = _numberList(body, 'Rect');
      if (rectValues.length < 4) continue;
      final left = math.min(rectValues[0], rectValues[2]);
      final bottom = math.min(rectValues[1], rectValues[3]);
      final right = math.max(rectValues[0], rectValues[2]);
      final top = math.max(rectValues[1], rectValues[3]);
      final appearance = _dictionaryString(body, 'DA') ?? '';
      final value = _dictionaryString(body, 'V') ?? '';
      final name =
          _dictionaryString(body, 'TU') ?? _dictionaryString(body, 'T') ?? '';
      final color =
          _lastRgb(appearance, 'rg') ??
          _lastGray(appearance, 'g') ??
          Colors.black;
      result.add(
        _PdfFormField(
          rect: Rect.fromLTRB(left, bottom, right, top),
          name: name,
          value: value,
          fontSize: _lastFontSize(appearance),
          color: color,
        ),
      );
    }
    return result;
  }

  static List<_PdfFormControl> _formControls(
    String pageBody,
    Map<String, _PdfObject> objects,
  ) {
    final annotationSection = RegExp(
      r'/Annots\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pageBody)?.group(1);
    final references = annotationSection == null
        ? RegExp(r'/Annots\s+(\d+)\s+(\d+)\s+R').allMatches(pageBody)
        : RegExp(r'(\d+)\s+(\d+)\s+R').allMatches(annotationSection);
    final result = <_PdfFormControl>[];
    for (final reference in references) {
      final objectId = '${reference.group(1)} ${reference.group(2)}';
      final object = objects[objectId];
      if (object == null) continue;
      var body = object.body;
      final parent = RegExp(r'/Parent\s+(\d+)\s+(\d+)\s+R').firstMatch(body);
      if (parent != null) {
        body =
            '${objects['${parent.group(1)} ${parent.group(2)}']?.body ?? ''} $body';
      }
      if (!body.contains('/Subtype /Widget')) continue;
      final fieldType = RegExp(
        r'/FT\s*/([A-Za-z0-9]+)',
      ).firstMatch(body)?.group(1);
      if (fieldType == null || (fieldType != 'Btn' && fieldType != 'Ch')) {
        continue;
      }
      final rectValues = _numberList(body, 'Rect');
      if (rectValues.length < 4) continue;
      final left = math.min(rectValues[0], rectValues[2]);
      final bottom = math.min(rectValues[1], rectValues[3]);
      final right = math.max(rectValues[0], rectValues[2]);
      final top = math.max(rectValues[1], rectValues[3]);
      final flags = _dictionaryInt(body, 'Ff') ?? 0;
      final isPushButton = fieldType == 'Btn' && (flags & (1 << 16)) != 0;
      final appearance = _dictionaryString(body, 'DA') ?? '';
      final value =
          _dictionaryValue(body, 'V') ?? _dictionaryValue(body, 'DV') ?? '';
      final name =
          _dictionaryString(body, 'TU') ?? _dictionaryString(body, 'T') ?? '';
      final label = isPushButton ? (_dictionaryString(body, 'CA') ?? name) : '';
      final selected = value.isNotEmpty && value != 'Off';
      result.add(
        _PdfFormControl(
          rect: Rect.fromLTRB(left, bottom, right, top),
          fieldType: fieldType,
          name: name,
          value: fieldType == 'Btn' && !selected && !isPushButton ? '' : value,
          label: label,
          fontSize: _lastFontSize(appearance),
          color:
              _lastRgb(appearance, 'rg') ??
              _lastGray(appearance, 'g') ??
              Colors.black,
          isRadio: fieldType == 'Btn' && (flags & (1 << 15)) != 0,
          isPushButton: isPushButton,
          checked: fieldType == 'Btn' && selected,
        ),
      );
    }
    return result;
  }

  static _PdfTextOperator _textOperator(
    String content,
    int matchStart,
    String text,
  ) {
    final prefix = content.substring(0, matchStart);
    final x = _lastNumberPair(prefix, r'(?:Td|Tm)');
    final fontSize = _lastFontSize(prefix);
    return _PdfTextOperator(
      text: text,
      x: x?.$1 ?? 72,
      y: x?.$2 ?? 72,
      fontSize: fontSize,
    );
  }

  static String _inflateStream(String rawStream) {
    try {
      return latin1.decode(
        const ZLibDecoder().decodeBytes(latin1.encode(rawStream)),
      );
    } catch (_) {
      return rawStream;
    }
  }

  static String _decodePdfHex(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return '';
    final normalized = compact.length.isOdd ? '${compact}0' : compact;
    final bytes = <int>[];
    for (var index = 0; index < normalized.length; index += 2) {
      bytes.add(int.parse(normalized.substring(index, index + 2), radix: 16));
    }
    final isUtf16Be =
        bytes.length.isEven &&
        bytes.length >= 2 &&
        ((bytes[0] == 0xFE && bytes[1] == 0xFF) || bytes[0] == 0);
    if (isUtf16Be) {
      final codeUnits = <int>[];
      final start = bytes[0] == 0xFE && bytes[1] == 0xFF ? 2 : 0;
      for (var index = start; index + 1 < bytes.length; index += 2) {
        codeUnits.add((bytes[index] << 8) | bytes[index + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }
    return latin1.decode(bytes);
  }

  static String _decodePdfLiteral(String value) => value
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\\', '\\')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');

  static (double, double)? _lastNumberPair(String source, String operator) {
    final matches = RegExp(
      r'([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+' + operator,
    ).allMatches(source).toList();
    if (matches.isEmpty) return null;
    final match = matches.last;
    return (
      double.tryParse(match.group(1) ?? '') ?? 0,
      double.tryParse(match.group(2) ?? '') ?? 0,
    );
  }

  static double _lastFontSize(String source) {
    final matches = RegExp(
      r'/\S+\s+([-+]?\d+(?:\.\d+)?)\s+Tf',
    ).allMatches(source).toList();
    if (matches.isEmpty) return 12;
    return double.tryParse(matches.last.group(1) ?? '') ?? 12;
  }

  static List<double> _numberList(String source, String key) {
    final value = RegExp(
      '/${RegExp.escape(key)}\\s*\\[([^\\]]+)\\]',
    ).firstMatch(source)?.group(1);
    if (value == null) return const [];
    return [
      for (final match in RegExp(
        r'[-+]?(?:\d+\.\d*|\.\d+|\d+)',
      ).allMatches(value))
        double.tryParse(match.group(0) ?? '') ?? 0,
    ];
  }

  static String? _dictionaryString(String source, String key) {
    final literal = RegExp(
      '/${RegExp.escape(key)}\\s*\\(((?:\\\\.|[^\\\\)])*)\\)',
      dotAll: true,
    ).firstMatch(source);
    if (literal != null) return _decodePdfLiteral(literal.group(1) ?? '');
    final hex = RegExp(
      '/${RegExp.escape(key)}\\s*<([0-9a-fA-F\\s]+)>',
    ).firstMatch(source);
    if (hex != null) return _decodePdfHex(hex.group(1) ?? '');
    return null;
  }

  static String? _dictionaryName(String source, String key) {
    final match = RegExp(
      '/${RegExp.escape(key)}\\s*/([A-Za-z0-9_.+-]+)',
    ).firstMatch(source);
    return match?.group(1);
  }

  static String? _dictionaryValue(String source, String key) =>
      _dictionaryString(source, key) ?? _dictionaryName(source, key);

  static int? _dictionaryInt(String source, String key) {
    final match = RegExp('/${RegExp.escape(key)}\\s+(\\d+)').firstMatch(source);
    return int.tryParse(match?.group(1) ?? '');
  }

  static List<_PdfVectorPath> _vectorPaths(
    String content, {
    Map<String, _PdfExtGState> graphicsStates = const {},
  }) {
    final result = <_PdfVectorPath>[];
    final operands = <double>[];
    final subpaths = <List<BezierPoint>>[];
    final subpathClosed = <bool>[];
    final graphicsStack = <_PdfPathGraphicsState>[];
    List<BezierPoint>? current;
    var currentClosed = false;
    var fill = const Color(0xFF2563EB);
    var stroke = const Color(0xFF111827);
    var strokeWidth = 1.0;
    var fillRule = VectorFillRule.nonZero;
    var strokeCap = VectorStrokeCap.butt;
    var strokeJoin = VectorStrokeJoin.miter;
    var dashPattern = const <double>[];
    var dashOffset = 0.0;
    var fillAlpha = 1.0;
    var strokeAlpha = 1.0;
    var matrix = _PdfMatrix.identity();
    String? resourceName;

    void storeCurrent() {
      final path = current;
      if (path != null && path.length >= 2) {
        subpaths.add(List<BezierPoint>.unmodifiable(path));
        subpathClosed.add(currentClosed);
      }
      current = null;
      currentClosed = false;
    }

    void paintCurrent({required bool hasFill, required bool hasStroke}) {
      storeCurrent();
      if (subpaths.isEmpty) return;
      result.add(
        _PdfVectorPath(
          subpaths: List<List<BezierPoint>>.unmodifiable(subpaths),
          subpathClosed: List<bool>.unmodifiable(subpathClosed),
          fillRule: fillRule,
          fill: fill,
          stroke: stroke,
          strokeWidth: strokeWidth * matrix.geometricScale,
          strokeCap: strokeCap,
          strokeJoin: strokeJoin,
          dashPattern: List<double>.unmodifiable(
            dashPattern.map((value) => value * matrix.geometricScale),
          ),
          dashOffset: dashOffset * matrix.geometricScale,
          hasFill: hasFill,
          hasStroke: hasStroke,
        ),
      );
      subpaths.clear();
      subpathClosed.clear();
    }

    void discardCurrent() {
      current = null;
      currentClosed = false;
      subpaths.clear();
      subpathClosed.clear();
    }

    final tokens = _pdfTokens(content);
    for (final token in tokens) {
      if (token is double) {
        operands.add(token);
        continue;
      }
      if (token is _PdfLiteralToken) {
        operands.clear();
        continue;
      }
      if (token is! String) continue;
      if (token.startsWith('/')) {
        resourceName = token.substring(1);
        continue;
      }
      final resourceNameForOperator = resourceName;
      resourceName = null;

      switch (token) {
        case 'rg':
          if (operands.length >= 3) {
            fill = _colorFromComponents(operands, alpha: fillAlpha);
          }
          operands.clear();
        case 'RG':
          if (operands.length >= 3) {
            stroke = _colorFromComponents(operands, alpha: strokeAlpha);
          }
          operands.clear();
        case 'g':
          if (operands.isNotEmpty) {
            final gray = operands.last.clamp(0.0, 1.0);
            fill = Color.fromRGBO(
              (gray * 255).round(),
              (gray * 255).round(),
              (gray * 255).round(),
              fillAlpha,
            );
          }
          operands.clear();
        case 'G':
          if (operands.isNotEmpty) {
            final gray = operands.last.clamp(0.0, 1.0);
            stroke = Color.fromRGBO(
              (gray * 255).round(),
              (gray * 255).round(),
              (gray * 255).round(),
              strokeAlpha,
            );
          }
          operands.clear();
        case 'w':
          if (operands.isNotEmpty) {
            strokeWidth = math.max(0, operands.last);
          }
          operands.clear();
        case 'ca':
          if (operands.isNotEmpty) {
            fillAlpha = operands.last.clamp(0.0, 1.0);
            fill = _colorWithAlpha(fill, fillAlpha);
          }
          operands.clear();
        case 'CA':
          if (operands.isNotEmpty) {
            strokeAlpha = operands.last.clamp(0.0, 1.0);
            stroke = _colorWithAlpha(stroke, strokeAlpha);
          }
          operands.clear();
        case 'gs':
          final graphicsState = resourceNameForOperator == null
              ? null
              : graphicsStates[resourceNameForOperator];
          if (graphicsState != null) {
            final nextFillAlpha = graphicsState.fillAlpha;
            if (nextFillAlpha != null) {
              fillAlpha = nextFillAlpha;
              fill = _colorWithAlpha(fill, fillAlpha);
            }
            final nextStrokeAlpha = graphicsState.strokeAlpha;
            if (nextStrokeAlpha != null) {
              strokeAlpha = nextStrokeAlpha;
              stroke = _colorWithAlpha(stroke, strokeAlpha);
            }
          }
          operands.clear();
        case 'J':
          if (operands.isNotEmpty) {
            strokeCap = switch (operands.last.round()) {
              1 => VectorStrokeCap.round,
              2 => VectorStrokeCap.square,
              _ => VectorStrokeCap.butt,
            };
          }
          operands.clear();
        case 'j':
          if (operands.isNotEmpty) {
            strokeJoin = switch (operands.last.round()) {
              1 => VectorStrokeJoin.round,
              2 => VectorStrokeJoin.bevel,
              _ => VectorStrokeJoin.miter,
            };
          }
          operands.clear();
        case 'd':
          if (operands.isNotEmpty) {
            dashOffset = math.max(0, operands.last);
            dashPattern = operands.length == 1
                ? const []
                : operands
                      .sublist(0, operands.length - 1)
                      .where((value) => value > 0)
                      .toList(growable: false);
          }
          operands.clear();
        case 'cm':
          if (operands.length >= 6) {
            final values = operands.sublist(operands.length - 6);
            matrix = matrix.multiply(
              _PdfMatrix(
                a: values[0],
                b: values[1],
                c: values[2],
                d: values[3],
                e: values[4],
                f: values[5],
              ),
            );
          }
          operands.clear();
        case 'q':
          graphicsStack.add(
            _PdfPathGraphicsState(
              fill: fill,
              stroke: stroke,
              strokeWidth: strokeWidth,
              fillRule: fillRule,
              strokeCap: strokeCap,
              strokeJoin: strokeJoin,
              dashPattern: dashPattern,
              dashOffset: dashOffset,
              fillAlpha: fillAlpha,
              strokeAlpha: strokeAlpha,
              matrix: matrix,
            ),
          );
          operands.clear();
        case 'Q':
          if (graphicsStack.isNotEmpty) {
            final state = graphicsStack.removeLast();
            fill = state.fill;
            stroke = state.stroke;
            strokeWidth = state.strokeWidth;
            fillRule = state.fillRule;
            strokeCap = state.strokeCap;
            strokeJoin = state.strokeJoin;
            dashPattern = state.dashPattern;
            dashOffset = state.dashOffset;
            fillAlpha = state.fillAlpha;
            strokeAlpha = state.strokeAlpha;
            matrix = state.matrix;
          }
          operands.clear();
        case 'm':
          if (operands.length >= 2) {
            storeCurrent();
            current = [
              BezierPoint(
                point: matrix.transform(
                  Offset(operands[operands.length - 2], operands.last),
                ),
              ),
            ];
          }
          operands.clear();
        case 'l':
          if (current != null && operands.length >= 2) {
            current!.add(
              BezierPoint(
                point: matrix.transform(
                  Offset(operands[operands.length - 2], operands.last),
                ),
              ),
            );
          }
          operands.clear();
        case 'c':
          if (current != null && operands.length >= 6) {
            final values = operands.sublist(operands.length - 6);
            _appendCubic(
              current!,
              firstControl: matrix.transform(Offset(values[0], values[1])),
              secondControl: matrix.transform(Offset(values[2], values[3])),
              endpoint: matrix.transform(Offset(values[4], values[5])),
            );
          }
          operands.clear();
        case 'v':
          if (current != null && operands.length >= 4) {
            final values = operands.sublist(operands.length - 4);
            _appendCubic(
              current!,
              firstControl: current!.last.point,
              secondControl: matrix.transform(Offset(values[0], values[1])),
              endpoint: matrix.transform(Offset(values[2], values[3])),
            );
          }
          operands.clear();
        case 'y':
          if (current != null && operands.length >= 4) {
            final values = operands.sublist(operands.length - 4);
            _appendCubic(
              current!,
              firstControl: matrix.transform(Offset(values[0], values[1])),
              secondControl: matrix.transform(Offset(values[2], values[3])),
              endpoint: matrix.transform(Offset(values[2], values[3])),
            );
          }
          operands.clear();
        case 'h':
          if (current != null && current!.length >= 2) {
            currentClosed = true;
          }
          operands.clear();
        case 'S':
          paintCurrent(hasFill: false, hasStroke: true);
          operands.clear();
        case 's':
          if (current != null) currentClosed = true;
          paintCurrent(hasFill: false, hasStroke: true);
          operands.clear();
        case 'f' || 'F':
          fillRule = VectorFillRule.nonZero;
          paintCurrent(hasFill: true, hasStroke: false);
          operands.clear();
        case 'f*':
          fillRule = VectorFillRule.evenOdd;
          paintCurrent(hasFill: true, hasStroke: false);
          operands.clear();
        case 'B':
          fillRule = VectorFillRule.nonZero;
          paintCurrent(hasFill: true, hasStroke: true);
          operands.clear();
        case 'B*':
          fillRule = VectorFillRule.evenOdd;
          paintCurrent(hasFill: true, hasStroke: true);
          operands.clear();
        case 'b' || 'b*':
          if (current != null) currentClosed = true;
          fillRule = token == 'b*'
              ? VectorFillRule.evenOdd
              : VectorFillRule.nonZero;
          paintCurrent(hasFill: true, hasStroke: true);
          operands.clear();
        case 'n':
          discardCurrent();
          operands.clear();
        default:
          operands.clear();
      }
    }
    return result;
  }

  static List<_PdfImagePlacement> _imagePlacements(
    String pageBody,
    String content,
    Map<String, _PdfObject> objects,
    List<String> unsupported,
  ) {
    final resources = _resourceBody(pageBody, objects);
    final xObjects = _xObjectReferences(resources);
    if (xObjects.isEmpty) return const [];
    final placements = <_PdfImagePlacement>[];
    for (final match in RegExp(
      r'/([A-Za-z0-9_.-]+)\s+Do',
    ).allMatches(content)) {
      final name = match.group(1) ?? '';
      final objectId = xObjects[name];
      if (objectId == null) continue;
      final object = objects[objectId];
      if (object == null || !object.body.contains('/Subtype /Image')) continue;
      final filter = _imageFilter(object.body);
      if (filter != 'DCTDecode' && filter != 'FlateDecode') {
        unsupported.add(
          'PDF image XObject $name uses an unsupported filter and was not converted.',
        );
        continue;
      }
      final rawBytes = _streamBytes(object.body);
      final imageData = filter == 'DCTDecode'
          ? _PdfImageData(
              bytes: rawBytes,
              mimeType: 'image/jpeg',
              name: '$name.jpg',
            )
          : _decodeFlateImage(object.body, rawBytes);
      if (imageData == null) {
        unsupported.add(
          'PDF image XObject $name uses an unsupported FlateDecode color space or bit depth.',
        );
        continue;
      }
      final bytes = imageData.bytes;
      if (bytes.isEmpty) {
        unsupported.add(
          'PDF image XObject $name has no readable stream bytes.',
        );
        continue;
      }
      final pixelWidth = _dictionaryNumber(object.body, 'Width') ?? 1;
      final pixelHeight = _dictionaryNumber(object.body, 'Height') ?? 1;
      final matrix = _currentPdfMatrix(content.substring(0, match.start));
      var x = 72.0;
      var y = 72.0;
      var width = math.max(24, pixelWidth).toDouble();
      var height = math.max(24, pixelHeight).toDouble();
      if (matrix != null) {
        final corners = <Offset>[
          matrix.transform(Offset.zero),
          matrix.transform(const Offset(1, 0)),
          matrix.transform(const Offset(0, 1)),
          matrix.transform(const Offset(1, 1)),
        ];
        var minX = double.infinity;
        var minY = double.infinity;
        var maxX = double.negativeInfinity;
        var maxY = double.negativeInfinity;
        for (final corner in corners) {
          minX = math.min(minX, corner.dx);
          minY = math.min(minY, corner.dy);
          maxX = math.max(maxX, corner.dx);
          maxY = math.max(maxY, corner.dy);
        }
        x = minX;
        y = minY;
        width = math.max(1, maxX - minX).toDouble();
        height = math.max(1, maxY - minY).toDouble();
        if (matrix.hasRotationOrShear) {
          unsupported.add(
            'PDF image XObject $name uses rotation or shear; it was imported with an axis-aligned editable bounds.',
          );
        }
      }
      placements.add(
        _PdfImagePlacement(
          objectId: objectId,
          name: imageData.name,
          mimeType: imageData.mimeType,
          bytes: bytes,
          pixelWidth: pixelWidth,
          pixelHeight: pixelHeight,
          x: x,
          y: y,
          width: width,
          height: height,
        ),
      );
    }
    return placements;
  }

  static String _resourceBody(
    String pageBody,
    Map<String, _PdfObject> objects,
  ) {
    final reference = RegExp(
      r'/Resources\s+(\d+)\s+(\d+)\s+R',
    ).firstMatch(pageBody);
    if (reference == null) return pageBody;
    return objects['${reference.group(1)} ${reference.group(2)}']?.body ??
        pageBody;
  }

  static Map<String, _PdfExtGState> _graphicsStates(
    String pageBody,
    Map<String, _PdfObject> objects,
  ) {
    final resources = _resourceBody(pageBody, objects);
    final dictionary = RegExp(
      r'/ExtGState\s*<<(.*?)>>',
      dotAll: true,
    ).firstMatch(resources)?.group(1);
    if (dictionary == null) return const {};
    final result = <String, _PdfExtGState>{};
    for (final match in RegExp(
      r'/([A-Za-z0-9_.-]+)\s+(\d+)\s+(\d+)\s+R',
    ).allMatches(dictionary)) {
      final object = objects['${match.group(2)} ${match.group(3)}'];
      if (object == null) continue;
      result[match.group(1)!] = _PdfExtGState(
        fillAlpha: _dictionaryDecimal(object.body, 'ca')?.clamp(0.0, 1.0),
        strokeAlpha: _dictionaryDecimal(object.body, 'CA')?.clamp(0.0, 1.0),
      );
    }
    return result;
  }

  static Map<String, String> _xObjectReferences(String resources) {
    final dictionary = RegExp(
      r'/XObject\s*<<(.*?)>>',
      dotAll: true,
    ).firstMatch(resources)?.group(1);
    if (dictionary == null) return const {};
    return {
      for (final match in RegExp(
        r'/([A-Za-z0-9_.-]+)\s+(\d+)\s+(\d+)\s+R',
      ).allMatches(dictionary))
        match.group(1)!: '${match.group(2)} ${match.group(3)}',
    };
  }

  static String? _imageFilter(String body) {
    final array = RegExp(r'/Filter\s*\[\s*/([A-Za-z0-9]+)').firstMatch(body);
    if (array != null) return array.group(1);
    return RegExp(r'/Filter\s*/([A-Za-z0-9]+)').firstMatch(body)?.group(1);
  }

  static _PdfImageData? _decodeFlateImage(
    String objectBody,
    Uint8List compressedBytes,
  ) {
    final width = _dictionaryNumber(objectBody, 'Width');
    final height = _dictionaryNumber(objectBody, 'Height');
    final bitsPerComponent = _dictionaryNumber(objectBody, 'BitsPerComponent');
    final colorSpace = RegExp(
      r'/ColorSpace\s*/([A-Za-z0-9]+)',
    ).firstMatch(objectBody)?.group(1);
    if (width == null || height == null || width < 1 || height < 1) {
      return null;
    }
    if (bitsPerComponent != 8 ||
        (colorSpace != 'DeviceRGB' && colorSpace != 'DeviceGray')) {
      return null;
    }
    final channels = colorSpace == 'DeviceRGB' ? 3 : 1;
    final decoded = _inflateBytes(compressedBytes);
    if (decoded == null) return null;
    final rowBytes = width * channels;
    final unfiltered = _unfilterPdfRows(
      decoded,
      width: width,
      height: height,
      channels: channels,
      rowBytes: rowBytes,
      predictor: _dictionaryNumber(objectBody, 'Predictor') ?? 1,
    );
    if (unfiltered == null || unfiltered.length < rowBytes * height) {
      return null;
    }
    final decodedImage = image.Image(width: width, height: height);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (channels == 1) {
          final gray = unfiltered[offset++];
          decodedImage.setPixelRgb(x, y, gray, gray, gray);
        } else {
          decodedImage.setPixelRgb(
            x,
            y,
            unfiltered[offset++],
            unfiltered[offset++],
            unfiltered[offset++],
          );
        }
      }
    }
    return _PdfImageData(
      bytes: Uint8List.fromList(image.encodePng(decodedImage)),
      mimeType: 'image/png',
      name: 'image.png',
    );
  }

  static Uint8List? _inflateBytes(Uint8List compressedBytes) {
    try {
      return Uint8List.fromList(
        const ZLibDecoder().decodeBytes(compressedBytes),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _unfilterPdfRows(
    Uint8List decoded, {
    required int width,
    required int height,
    required int channels,
    required int rowBytes,
    required int predictor,
  }) {
    if (predictor <= 1) return decoded;
    if (predictor < 10 || predictor > 15) return null;
    final stride = rowBytes + 1;
    if (decoded.length < stride * height) return null;
    final output = Uint8List(rowBytes * height);
    var inputOffset = 0;
    for (var row = 0; row < height; row++) {
      final filter = decoded[inputOffset++];
      if (filter > 4) return null;
      final rowOffset = row * rowBytes;
      final previousOffset = (row - 1) * rowBytes;
      for (var column = 0; column < rowBytes; column++) {
        final raw = decoded[inputOffset++];
        final left = column >= channels
            ? output[rowOffset + column - channels]
            : 0;
        final up = row > 0 ? output[previousOffset + column] : 0;
        final upperLeft = row > 0 && column >= channels
            ? output[previousOffset + column - channels]
            : 0;
        final value = switch (filter) {
          0 => raw,
          1 => (raw + left) & 0xff,
          2 => (raw + up) & 0xff,
          3 => (raw + ((left + up) ~/ 2)) & 0xff,
          4 => (raw + _paeth(left, up, upperLeft)) & 0xff,
          _ => raw,
        };
        output[rowOffset + column] = value;
      }
    }
    return output;
  }

  static int _paeth(int left, int up, int upperLeft) {
    final estimate = left + up - upperLeft;
    final leftDistance = (estimate - left).abs();
    final upDistance = (estimate - up).abs();
    final upperLeftDistance = (estimate - upperLeft).abs();
    if (leftDistance <= upDistance && leftDistance <= upperLeftDistance) {
      return left;
    }
    if (upDistance <= upperLeftDistance) return up;
    return upperLeft;
  }

  static _PdfMatrix? _currentPdfMatrix(String source) {
    final operands = <double>[];
    final stack = <_PdfMatrix>[];
    var matrix = _PdfMatrix.identity();
    var foundTransform = false;
    for (final token in _pdfTokens(source)) {
      if (token is double) {
        operands.add(token);
        continue;
      }
      if (token is _PdfLiteralToken) {
        operands.clear();
        continue;
      }
      if (token is! String) continue;
      switch (token) {
        case 'q':
          stack.add(matrix);
          operands.clear();
        case 'Q':
          if (stack.isNotEmpty) matrix = stack.removeLast();
          operands.clear();
        case 'cm':
          if (operands.length >= 6) {
            final values = operands.sublist(operands.length - 6);
            matrix = matrix.multiply(
              _PdfMatrix(
                a: values[0],
                b: values[1],
                c: values[2],
                d: values[3],
                e: values[4],
                f: values[5],
              ),
            );
            foundTransform = true;
          }
          operands.clear();
        default:
          operands.clear();
      }
    }
    return foundTransform ? matrix : null;
  }

  static int? _dictionaryNumber(String body, String key) {
    final match = RegExp(
      '/$key'
      r'\s+(\d+)',
    ).firstMatch(body);
    return int.tryParse(match?.group(1) ?? '');
  }

  static double? _dictionaryDecimal(String body, String key) {
    final match = RegExp(
      '/${RegExp.escape(key)}\\s+([-+]?(?:\\d+\\.\\d*|\\.\\d+|\\d+))',
    ).firstMatch(body);
    return double.tryParse(match?.group(1) ?? '');
  }

  static Uint8List _streamBytes(String body) {
    final startMarker = body.indexOf('stream');
    final endMarker = body.lastIndexOf('endstream');
    if (startMarker < 0 || endMarker <= startMarker) return Uint8List(0);
    var start = startMarker + 'stream'.length;
    if (start < endMarker && body[start] == '\r') start++;
    if (start < endMarker && body[start] == '\n') start++;
    var end = endMarker;
    while (end > start && (body[end - 1] == '\r' || body[end - 1] == '\n')) {
      end--;
    }
    if (end <= start) return Uint8List(0);
    return Uint8List.fromList(latin1.encode(body.substring(start, end)));
  }

  static List<Object> _pdfTokens(String source) {
    final result = <Object>[];
    var index = 0;
    while (index < source.length) {
      final char = source[index];
      if (char.trim().isEmpty) {
        index++;
        continue;
      }
      if (char == '%') {
        final lineEnd = source.indexOf('\n', index);
        index = lineEnd < 0 ? source.length : lineEnd + 1;
        continue;
      }
      if (char == '(') {
        index = _skipPdfLiteral(source, index);
        result.add(const _PdfLiteralToken());
        continue;
      }
      if (char == '<') {
        if (index + 1 < source.length && source[index + 1] == '<') {
          index += 2;
        } else {
          final end = source.indexOf('>', index + 1);
          index = end < 0 ? source.length : end + 1;
        }
        result.add(const _PdfLiteralToken());
        continue;
      }
      if (char == '/') {
        var end = index + 1;
        while (end < source.length && !_isPdfDelimiter(source[end])) {
          end++;
        }
        result.add(source.substring(index, end));
        index = end;
        continue;
      }
      final number = RegExp(
        r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?',
      ).matchAsPrefix(source, index);
      if (number != null) {
        result.add(double.parse(number.group(0)!));
        index = number.end;
        continue;
      }
      if ('[]{}>'.contains(char)) {
        index++;
        continue;
      }
      var end = index;
      while (end < source.length && !_isPdfDelimiter(source[end])) {
        end++;
      }
      if (end == index) {
        index++;
      } else {
        result.add(source.substring(index, end));
        index = end;
      }
    }
    return result;
  }

  static bool _isPdfDelimiter(String value) =>
      value.trim().isEmpty || '()<>[]{}/%'.contains(value);

  static int _skipPdfLiteral(String source, int start) {
    var depth = 0;
    var escaped = false;
    for (var index = start; index < source.length; index++) {
      final char = source[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) return index + 1;
      }
    }
    return source.length;
  }

  static Color _colorFromComponents(
    List<double> values, {
    required double alpha,
  }) {
    final red = values[values.length - 3].clamp(0.0, 1.0);
    final green = values[values.length - 2].clamp(0.0, 1.0);
    final blue = values[values.length - 1].clamp(0.0, 1.0);
    return Color.fromRGBO(
      (red * 255).round(),
      (green * 255).round(),
      (blue * 255).round(),
      alpha,
    );
  }

  static Color _colorWithAlpha(Color color, double alpha) => Color.fromRGBO(
    (color.r * 255.0).round().clamp(0, 255),
    (color.g * 255.0).round().clamp(0, 255),
    (color.b * 255.0).round().clamp(0, 255),
    alpha.clamp(0.0, 1.0),
  );

  static void _appendCubic(
    List<BezierPoint> path, {
    required Offset firstControl,
    required Offset secondControl,
    required Offset endpoint,
  }) {
    final previous = path.last;
    path[path.length - 1] = previous.copyWith(
      handleOut: firstControl - previous.point,
      type: PointType.disconnected,
    );
    path.add(
      BezierPoint(
        point: endpoint,
        handleIn: secondControl - endpoint,
        type: PointType.disconnected,
      ),
    );
  }

  static CanvasNode? _vectorPathNode(
    _PdfVectorPath path, {
    required String frameId,
    required double frameX,
    required double frameY,
    required double pageHeightPoints,
    required String name,
  }) {
    final transformed = [
      for (final subpath in path.subpaths)
        [
          for (final point in subpath)
            _transformPdfPoint(point, pageHeightPoints: pageHeightPoints),
        ],
    ];
    if (transformed.every((subpath) => subpath.isEmpty)) return null;
    final double padding = path.hasStroke
        ? path.strokeWidth * _pointsToPixels / 2
        : 0.0;
    final bounds = _pathBounds(transformed).inflate(padding);
    final localSubpaths = [
      for (final subpath in transformed)
        [
          for (final point in subpath)
            point.copyWith(point: point.point - bounds.topLeft),
        ],
    ];
    return CanvasNode(
      id: const Uuid().v4(),
      type: NodeType.vectorPath,
      x: frameX + bounds.left,
      y: frameY + bounds.top,
      width: math.max(1, bounds.width),
      height: math.max(1, bounds.height),
      parentId: frameId,
      name: name,
      payload: VectorPathPayload(
        subpaths: localSubpaths,
        subpathClosed: path.subpathClosed,
        fillRule: path.fillRule,
        fill: path.hasFill ? path.fill : Colors.transparent,
        stroke: path.hasStroke ? path.stroke : Colors.transparent,
        strokeWidth: path.hasStroke ? path.strokeWidth * _pointsToPixels : 0,
        strokeCap: path.strokeCap,
        strokeJoin: path.strokeJoin,
        dashPattern: path.dashPattern
            .map((value) => value * _pointsToPixels)
            .toList(growable: false),
        dashOffset: path.dashOffset * _pointsToPixels,
      ),
    );
  }

  static BezierPoint _transformPdfPoint(
    BezierPoint point, {
    required double pageHeightPoints,
  }) {
    return point.copyWith(
      point: Offset(
        point.point.dx * _pointsToPixels,
        (pageHeightPoints - point.point.dy) * _pointsToPixels,
      ),
      handleIn: Offset(
        point.handleIn.dx * _pointsToPixels,
        -point.handleIn.dy * _pointsToPixels,
      ),
      handleOut: Offset(
        point.handleOut.dx * _pointsToPixels,
        -point.handleOut.dy * _pointsToPixels,
      ),
    );
  }

  static Rect _pathBounds(List<List<BezierPoint>> paths) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final path in paths) {
      for (final point in path) {
        final locations = [
          point.point,
          point.point + point.handleIn,
          point.point + point.handleOut,
        ];
        for (final location in locations) {
          minX = math.min(minX, location.dx);
          minY = math.min(minY, location.dy);
          maxX = math.max(maxX, location.dx);
          maxY = math.max(maxY, location.dy);
        }
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<_PdfVectorRectangle> _vectorRectangles(
    String content, {
    required double pageHeightPoints,
  }) {
    final result = <_PdfVectorRectangle>[];
    final rectanglePattern = RegExp(
      r'([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+re',
    );
    for (final match in rectanglePattern.allMatches(content)) {
      final x = double.tryParse(match.group(1) ?? '') ?? 0;
      final y = double.tryParse(match.group(2) ?? '') ?? 0;
      final width = double.tryParse(match.group(3) ?? '') ?? 0;
      final height = double.tryParse(match.group(4) ?? '') ?? 0;
      if (width == 0 || height == 0) continue;
      final after = content.substring(
        match.end,
        math.min(content.length, match.end + 24),
      );
      final hasFill = RegExp(r'\b(?:f|f\*|B|B\*)\b').hasMatch(after);
      final hasStroke = RegExp(r'\b(?:S|s|B|B\*)\b').hasMatch(after);
      if (!hasFill && !hasStroke) continue;
      final before = content.substring(0, match.start);
      result.add(
        _PdfVectorRectangle(
          x: x,
          y: y,
          width: width.abs(),
          height: height.abs(),
          fill: _lastRgb(before, 'rg') ?? const Color(0xFF2563EB),
          stroke: _lastRgb(before, 'RG') ?? const Color(0xFF111827),
          strokeWidth: _lastLineWidth(before),
          hasFill: hasFill,
        ),
      );
    }
    return result;
  }

  static Color? _lastRgb(String source, String operator) {
    final matches = RegExp(
      r'([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+([-+]?\d+(?:\.\d+)?)\s+' +
          operator,
    ).allMatches(source).toList();
    if (matches.isEmpty) return null;
    final match = matches.last;
    final red = (double.tryParse(match.group(1) ?? '') ?? 0).clamp(0, 1);
    final green = (double.tryParse(match.group(2) ?? '') ?? 0).clamp(0, 1);
    final blue = (double.tryParse(match.group(3) ?? '') ?? 0).clamp(0, 1);
    return Color.fromRGBO(
      (red * 255).round(),
      (green * 255).round(),
      (blue * 255).round(),
      1,
    );
  }

  static Color? _lastGray(String source, String operator) {
    final matches = RegExp(
      r'([-+]?(?:\d+\.\d*|\.\d+|\d+))\s+' + operator,
    ).allMatches(source).toList();
    if (matches.isEmpty) return null;
    final gray = (double.tryParse(matches.last.group(1) ?? '') ?? 0).clamp(
      0,
      1,
    );
    final channel = (gray * 255).round();
    return Color.fromRGBO(channel, channel, channel, 1);
  }

  static double _lastLineWidth(String source) {
    final matches = RegExp(
      r'([-+]?\d+(?:\.\d+)?)\s+w',
    ).allMatches(source).toList();
    if (matches.isEmpty) return 1;
    return double.tryParse(matches.last.group(1) ?? '') ?? 1;
  }

  static void _recordUnsupported(
    String pageBody,
    Map<String, _PdfObject> objects,
    List<String> unsupported,
  ) {
    final annotationSection = RegExp(
      r'/Annots\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(pageBody)?.group(1);
    final references = annotationSection == null
        ? RegExp(r'/Annots\s+(\d+)\s+(\d+)\s+R').allMatches(pageBody)
        : RegExp(r'(\d+)\s+(\d+)\s+R').allMatches(annotationSection);
    for (final reference in references) {
      final objectId = '${reference.group(1)} ${reference.group(2)}';
      final object = objects[objectId];
      if (object == null) {
        unsupported.add('PDF annotation $objectId could not be resolved.');
        continue;
      }
      var annotationBody = object.body;
      final parent = RegExp(
        r'/Parent\s+(\d+)\s+(\d+)\s+R',
      ).firstMatch(annotationBody);
      if (parent != null) {
        annotationBody =
            '${objects['${parent.group(1)} ${parent.group(2)}']?.body ?? ''} $annotationBody';
      }
      final subtype = RegExp(
        r'/Subtype\s*/([A-Za-z0-9]+)',
      ).firstMatch(annotationBody)?.group(1);
      if (subtype == 'Widget') {
        final fieldType = RegExp(
          r'/FT\s*/([A-Za-z0-9]+)',
        ).firstMatch(annotationBody)?.group(1);
        if (fieldType == 'Tx' || fieldType == 'Ch') continue;
        if (fieldType == 'Btn') {
          continue;
        }
        unsupported.add(
          'PDF form widget ${fieldType ?? 'unknown'} is not converted to an editable canvas control.',
        );
        continue;
      }
      unsupported.add(
        'PDF ${subtype ?? 'unknown'} annotation is not converted to an editable canvas node.',
      );
    }
  }

  static List<String> _unique(Iterable<String> values) =>
      values.toSet().toList();
}

class _PdfObject {
  final String id;
  final String body;

  const _PdfObject({required this.id, required this.body});
}

class _PdfTextOperator {
  final String text;
  final double x;
  final double y;
  final double fontSize;

  const _PdfTextOperator({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
  });
}

class _PdfVectorRectangle {
  final double x;
  final double y;
  final double width;
  final double height;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final bool hasFill;

  const _PdfVectorRectangle({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.hasFill,
  });
}

class _PdfVectorPath {
  final List<List<BezierPoint>> subpaths;
  final List<bool> subpathClosed;
  final VectorFillRule fillRule;
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final VectorStrokeCap strokeCap;
  final VectorStrokeJoin strokeJoin;
  final List<double> dashPattern;
  final double dashOffset;
  final bool hasFill;
  final bool hasStroke;

  const _PdfVectorPath({
    required this.subpaths,
    required this.subpathClosed,
    required this.fillRule,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    this.strokeCap = VectorStrokeCap.butt,
    this.strokeJoin = VectorStrokeJoin.miter,
    this.dashPattern = const [],
    this.dashOffset = 0,
    required this.hasFill,
    required this.hasStroke,
  });
}

class _PdfPathGraphicsState {
  final Color fill;
  final Color stroke;
  final double strokeWidth;
  final VectorFillRule fillRule;
  final VectorStrokeCap strokeCap;
  final VectorStrokeJoin strokeJoin;
  final List<double> dashPattern;
  final double dashOffset;
  final double fillAlpha;
  final double strokeAlpha;
  final _PdfMatrix matrix;

  const _PdfPathGraphicsState({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.fillRule,
    required this.strokeCap,
    required this.strokeJoin,
    required this.dashPattern,
    required this.dashOffset,
    required this.fillAlpha,
    required this.strokeAlpha,
    required this.matrix,
  });
}

class _PdfExtGState {
  final double? fillAlpha;
  final double? strokeAlpha;

  const _PdfExtGState({this.fillAlpha, this.strokeAlpha});
}

class _PdfImagePlacement {
  final String objectId;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final int pixelWidth;
  final int pixelHeight;
  final double x;
  final double y;
  final double width;
  final double height;

  const _PdfImagePlacement({
    required this.objectId,
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class _PdfImageData {
  final Uint8List bytes;
  final String mimeType;
  final String name;

  const _PdfImageData({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });
}

class _PdfFormField {
  final Rect rect;
  final String name;
  final String value;
  final double fontSize;
  final Color color;

  const _PdfFormField({
    required this.rect,
    required this.name,
    required this.value,
    required this.fontSize,
    required this.color,
  });
}

class _PdfFormControl {
  final Rect rect;
  final String fieldType;
  final String name;
  final String value;
  final String label;
  final double fontSize;
  final Color color;
  final bool isRadio;
  final bool isPushButton;
  final bool checked;

  const _PdfFormControl({
    required this.rect,
    required this.fieldType,
    required this.name,
    required this.value,
    required this.label,
    required this.fontSize,
    required this.color,
    required this.isRadio,
    required this.isPushButton,
    required this.checked,
  });
}

class _PdfMatrix {
  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  const _PdfMatrix({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
  });

  factory _PdfMatrix.identity() =>
      const _PdfMatrix(a: 1, b: 0, c: 0, d: 1, e: 0, f: 0);

  _PdfMatrix multiply(_PdfMatrix other) => _PdfMatrix(
    a: a * other.a + c * other.b,
    b: b * other.a + d * other.b,
    c: a * other.c + c * other.d,
    d: b * other.c + d * other.d,
    e: a * other.e + c * other.f + e,
    f: b * other.e + d * other.f + f,
  );

  Offset transform(Offset point) =>
      Offset(a * point.dx + c * point.dy + e, b * point.dx + d * point.dy + f);

  bool get hasRotationOrShear => b.abs() > 0.0001 || c.abs() > 0.0001;

  double get geometricScale =>
      math.sqrt((a * d - b * c).abs()).clamp(0.0001, double.infinity);
}

class _PdfLiteralToken {
  const _PdfLiteralToken();
}
