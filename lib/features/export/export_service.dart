import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../../domain/models/component_payload.dart';
import '../../domain/models/connector_edge.dart';
import '../../domain/models/document.dart';
import '../../domain/models/document_asset.dart';
import '../../domain/models/document_package.dart';
import '../../domain/models/document_package_archive.dart';
import '../../domain/models/drawing_paper_payload.dart';
import '../../domain/models/drawing_payload.dart';
import '../../domain/models/model3d_payload.dart';
import '../drawing_paper/domain/services/drawing_paper_renderer.dart';
import '../../domain/models/node.dart';
import '../../domain/models/node_payload.dart';
import '../../domain/models/rich_text.dart';
import '../../domain/models/vector_path_payload.dart';
import '../canvas/utils/connector_router.dart';
import '../diagrams/data/drawio_xml_codec.dart';
import '../canvas/commands/command_replay.dart';
import 'domain/asset_export_policy.dart';
import 'domain/portable_asset_collector.dart';
import 'presentation_export_contract.dart';

class ExportService {
  static String exportNativeJson(CanvasDocument document) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(document.toPersistenceJson());
  }

  static String exportCommandReplay(CommandReplayLog replay) => replay.encode();

  static String exportProjectPackage(
    CanvasDocument document, {
    AssetExportPolicy policy = const AssetExportPolicy(),
  }) {
    final assets = policy.apply(document.assets);
    return CanvasDocumentPackage(
      document: document.copyWith(assets: assets),
      assets: assets,
    ).encode();
  }

  static Uint8List exportPortablePackage(
    CanvasDocument document, {
    AssetExportPolicy policy = const AssetExportPolicy(),
    Map<String, Uint8List> assetBytes = const {},
    String? password,
  }) {
    final assets = policy.apply(
      document.assets,
      suppliedAssetIds: assetBytes.keys.toSet(),
    );
    if (assetBytes.keys.any((id) => !assets.entries.containsKey(id))) {
      throw const DocumentPackageArchiveException(
        'Portable export received bytes for an excluded or unknown asset.',
      );
    }
    final filteredBytes = <String, Uint8List>{
      for (final entry in assetBytes.entries)
        if (assets.entries.containsKey(entry.key)) entry.key: entry.value,
    };
    _validatePortableAssetKinds(assets);
    final missingBytes = assets.items
        .where((asset) => !filteredBytes.containsKey(asset.id))
        .map((asset) => asset.id)
        .toList(growable: false);
    if (missingBytes.isNotEmpty) {
      throw DocumentPackageArchiveException(
        'Portable export has unavailable asset bytes: ${missingBytes.join(', ')}.',
      );
    }
    final dependencyValidation = validatePortableDependencies(
      manifest: assets,
      nodes: document.nodes,
    );
    if (!dependencyValidation.isValid) {
      throw DocumentPackageArchiveException(
        'Portable export has unresolved document asset dependencies: '
        '${[...dependencyValidation.missingAssetIds, ...dependencyValidation.invalidAssetIds, ...dependencyValidation.invalidReferences].join(', ')}.',
      );
    }
    final materializedAssets = _withEmbeddedMetadata(assets, filteredBytes);
    final package = CanvasDocumentPackage(
      document: document.copyWith(assets: materializedAssets),
      assets: materializedAssets,
    );
    return DocumentPackageArchive(
      package: package,
      assetBytes: filteredBytes,
    ).encode(password: password);
  }

  static Future<Uint8List> exportPortablePackageWithAssets(
    CanvasDocument document, {
    AssetExportPolicy policy = const AssetExportPolicy(),
    required PortableAssetCollector collector,
    Map<String, Uint8List> assetBytes = const {},
    String? password,
  }) async {
    final assets = policy.apply(
      document.assets,
      suppliedAssetIds: assetBytes.keys.toSet(),
    );
    if (assetBytes.keys.any((id) => !assets.entries.containsKey(id))) {
      throw const DocumentPackageArchiveException(
        'Portable export received bytes for an excluded or unknown asset.',
      );
    }
    final dependencyValidation = validatePortableDependencies(
      manifest: assets,
      nodes: document.nodes,
    );
    if (!dependencyValidation.isValid) {
      throw DocumentPackageArchiveException(
        'Portable export has unresolved document asset dependencies: '
        '${[...dependencyValidation.missingAssetIds, ...dependencyValidation.invalidAssetIds, ...dependencyValidation.invalidReferences].join(', ')}.',
      );
    }
    _validatePortableAssetKinds(assets);
    final collected = await collector.collect(assets, nodes: document.nodes);
    final suppliedAssetIds = assetBytes.keys.toSet();
    final unresolvedCollectionErrors = <String>{
      ...collected.missingAssetIds,
      ...collected.invalidAssetIds,
    }..removeWhere(suppliedAssetIds.contains);
    if (collected.invalidReferences.isNotEmpty ||
        unresolvedCollectionErrors.isNotEmpty) {
      final failures = <String>{
        ...unresolvedCollectionErrors,
        ...collected.invalidReferences,
      };
      throw DocumentPackageArchiveException(
        'Portable export has unavailable or invalid asset sources: '
        '${failures.join(', ')}.',
      );
    }
    final mergedBytes = <String, Uint8List>{
      ...collected.assetBytes,
      ...assetBytes,
    };
    final filteredBytes = <String, Uint8List>{
      for (final entry in mergedBytes.entries)
        if (assets.entries.containsKey(entry.key)) entry.key: entry.value,
    };
    final missingBytes = assets.items
        .where((asset) => !filteredBytes.containsKey(asset.id))
        .map((asset) => asset.id)
        .toList(growable: false);
    if (missingBytes.isNotEmpty) {
      throw DocumentPackageArchiveException(
        'Portable export has unavailable asset bytes: ${missingBytes.join(', ')}.',
      );
    }
    final materializedAssets = _withEmbeddedMetadata(assets, filteredBytes);
    final package = CanvasDocumentPackage(
      document: document.copyWith(assets: materializedAssets),
      assets: materializedAssets,
    );
    return DocumentPackageArchive(
      package: package,
      assetBytes: filteredBytes,
    ).encode(password: password);
  }

  static void _validatePortableAssetKinds(DocumentAssetManifest manifest) {
    final unsupported = manifest.items
        .where(
          (asset) => switch (asset.kind) {
            DocumentAssetKind.drawing ||
            DocumentAssetKind.font ||
            DocumentAssetKind.other => true,
            _ => false,
          },
        )
        .map((asset) => asset.id)
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw DocumentPackageArchiveException(
        'Portable export does not support asset kinds for: '
        '${unsupported.join(', ')}.',
      );
    }
  }

  static DocumentAssetManifest _withEmbeddedMetadata(
    DocumentAssetManifest manifest,
    Map<String, Uint8List> bytesById,
  ) {
    if (bytesById.isEmpty) return manifest;
    return manifest.copyWith(
      entries: {
        for (final asset in manifest.items)
          asset.id: bytesById[asset.id] == null
              ? asset
              : asset.copyWith(
                  storage: DocumentAssetStorage.embedded,
                  sizeBytes: bytesById[asset.id]!.length,
                  checksum: DocumentPackageArchiveChecksum.sha256(
                    bytesById[asset.id]!,
                  ),
                ),
      },
    );
  }

  static String exportPresentationContract(CanvasDocument document) =>
      PresentationExportContract.fromDocument(document).encode();

  static String exportDrawioXml(CanvasDocument document) {
    return DrawioXmlCodec.exportDocument(
      nodes: document.nodes,
      edges: document.edges,
    );
  }

  /// Exports Mermaid's canonical source, never the detached native graph.
  ///
  /// A document can contain more than one Mermaid source node. In that case
  /// the result is a clearly marked source bundle so no source is silently
  /// discarded by a single-file export.
  static String exportMermaid(CanvasDocument document) {
    final sources =
        document.nodes.where((node) => node.payload is MermaidPayload).toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    if (sources.isEmpty) return '';
    if (sources.length == 1) {
      return (sources.single.payload as MermaidPayload).source;
    }

    final output = StringBuffer('%% Canvas Mermaid source bundle\n');
    for (var index = 0; index < sources.length; index++) {
      if (index > 0) output.writeln();
      output.writeln('%% Source ${index + 1}');
      output.writeln((sources[index].payload as MermaidPayload).source);
    }
    return output.toString().trimRight();
  }

  static String exportMarkdown(CanvasDocument document) {
    final sb = StringBuffer();
    final nodes = document.nodes.where((n) => n.visible).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final chartSourceMap = {for (final node in document.nodes) node.id: node};

    for (final node in nodes) {
      final payload = node.payload;
      switch (payload) {
        case TextPayload p:
          if (p.isRichText) {
            for (final block in p.blocks!) {
              sb.writeln(_blockToMarkdown(block));
            }
          } else {
            sb.writeln(p.text);
          }
          sb.writeln();
          break;
        case StickyNotePayload p:
          sb.writeln('> ${p.text.replaceAll('\n', '\n> ')}');
          sb.writeln();
          break;
        case DocumentPayload p:
          sb.writeln('# ${p.title}');
          sb.writeln();
          for (final block in p.blocks) {
            sb.writeln(_blockToMarkdown(block));
          }
          sb.writeln();
          break;
        case LinkPayload p:
          sb.writeln('[${p.title}](${p.url})');
          if (p.description != null && p.description!.isNotEmpty) {
            sb.writeln('> ${p.description}');
          }
          sb.writeln();
          break;
        case FilePayload p:
          final reference = p.artifactReference ?? p.storagePath;
          final suffix = reference == null || reference.trim().isEmpty
              ? ' (source unavailable)'
              : ' ($reference)';
          sb.writeln('**File:** ${p.fileName}$suffix');
          sb.writeln();
          break;
        case Model3DPayload p:
          sb.writeln('**3D Model:** ${p.displayName} (${p.fileSizeText})');
          sb.writeln();
          break;
        case TodoListPayload p:
          sb.writeln('## ${p.title}');
          for (final item in p.items) {
            sb.writeln('- [${item.isDone ? 'x' : ' '}] ${item.text}');
          }
          sb.writeln();
          break;
        case TablePayload p:
          sb.writeln('| ${p.columns.join(' | ')} |');
          sb.writeln('| ${p.columns.map((_) => '---').join(' | ')} |');
          for (final row in p.rows) {
            sb.writeln('| ${row.join(' | ')} |');
          }
          sb.writeln();
          break;
        case ColumnPayload p:
          sb.writeln('## ${p.headerTitle}');
          for (final t in p.itemTitles) {
            sb.writeln('- $t');
          }
          sb.writeln();
          break;
        case ColorSwatchPayload p:
          sb.writeln('`${p.colorHex}` ${p.label}');
          sb.writeln();
          break;
        case VideoPayload p:
          sb.writeln('**Video:** ${p.title} (${p.durationText})');
          sb.writeln();
          break;
        case AudioPayload p:
          sb.writeln(
            '**Audio:** ${p.trackName} — ${p.artist} (${p.durationText})',
          );
          sb.writeln();
          break;
        case MapPayload p:
          sb.writeln(
            '**Location:** ${p.locationTitle} — ${p.address} (${p.latitude}, ${p.longitude}, zoom ${p.zoomLevel})',
          );
          sb.writeln();
          break;
        case EmbedPayload p:
          sb.writeln('**Embed:** ${p.provider} — ${p.title ?? p.url}');
          sb.writeln();
          break;
        case SketchCardPayload p:
          sb.writeln('**Sketch:** ${p.title}');
          sb.writeln();
          break;
        case FramePayload p:
          sb.writeln('## ${p.name}');
          sb.writeln();
          break;
        case GroupPayload p:
          sb.writeln('### ${p.name}');
          sb.writeln();
          break;
        case ComponentPayload p:
          sb.writeln('**Component:** ${p.componentName}');
          sb.writeln();
          break;
        case ChartPayload p:
          final chart = _effectiveChartPayload(p, chartSourceMap);
          sb.writeln('## ${chart.title} (${chart.chartType.name} chart)');
          sb.writeln();
          if (chart.series.isNotEmpty) {
            sb.writeln(
              '| Category | ${chart.series.map((item) => item.name).join(' | ')} |',
            );
            sb.writeln(
              '| --- | ${chart.series.map((_) => '---').join(' | ')} |',
            );
            final rowCount = math.max(
              chart.categories.length,
              chart.series.fold<int>(0, (maxLength, item) {
                return math.max(maxLength, item.values.length);
              }),
            );
            for (var index = 0; index < rowCount; index++) {
              final category = index < chart.categories.length
                  ? chart.categories[index]
                  : '${index + 1}';
              final values = chart.series
                  .map((item) {
                    return index < item.values.length
                        ? _formatChartNumber(item.values[index])
                        : '';
                  })
                  .join(' | ');
              sb.writeln('| $category | $values |');
            }
            sb.writeln();
          }
          break;
        default:
          break;
      }
    }

    return sb.toString().trimRight();
  }

  static String _blockToMarkdown(RichTextBlock block) {
    final text = block.plainText;
    switch (block.type) {
      case RichTextBlockType.heading:
        return '# $text';
      case RichTextBlockType.bullet:
        return '- $text';
      case RichTextBlockType.numbered:
        return '1. $text';
      case RichTextBlockType.quote:
        return '> $text';
      case RichTextBlockType.code:
        return '```\n$text\n```';
      case RichTextBlockType.paragraph:
        return text;
    }
  }

  static String exportPlainText(CanvasDocument document) {
    final sb = StringBuffer();
    final nodes = document.nodes.where((n) => n.visible).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final chartSourceMap = {for (final node in document.nodes) node.id: node};

    for (final node in nodes) {
      final payload = node.payload;
      switch (payload) {
        case TextPayload p:
          if (p.isRichText) {
            for (final block in p.blocks!) {
              sb.writeln(block.plainText);
            }
          } else {
            sb.writeln(p.text);
          }
          sb.writeln();
          break;
        case StickyNotePayload p:
          sb.writeln(p.text);
          sb.writeln();
          break;
        case DocumentPayload p:
          sb.writeln(p.title.toUpperCase());
          sb.writeln();
          for (final block in p.blocks) {
            sb.writeln(block.plainText);
          }
          sb.writeln();
          break;
        case LinkPayload p:
          sb.writeln('${p.title} — ${p.url}');
          if (p.description != null && p.description!.isNotEmpty) {
            sb.writeln(p.description);
          }
          sb.writeln();
          break;
        case FilePayload p:
          sb.writeln(p.fileName);
          sb.writeln();
          break;
        case Model3DPayload p:
          sb.writeln('3D Model: ${p.displayName} (${p.fileSizeText})');
          sb.writeln();
          break;
        case TodoListPayload p:
          sb.writeln(p.title);
          for (final item in p.items) {
            sb.writeln('[${item.isDone ? 'x' : ' '}] ${item.text}');
          }
          sb.writeln();
          break;
        case TablePayload p:
          sb.writeln(p.columns.join('\t'));
          for (final row in p.rows) {
            sb.writeln(row.join('\t'));
          }
          sb.writeln();
          break;
        case ColumnPayload p:
          sb.writeln(p.headerTitle.toUpperCase());
          for (final t in p.itemTitles) {
            sb.writeln('- $t');
          }
          sb.writeln();
          break;
        case ColorSwatchPayload p:
          sb.writeln('${p.colorHex} ${p.label}');
          sb.writeln();
          break;
        case VideoPayload p:
          sb.writeln('Video: ${p.title} (${p.durationText})');
          sb.writeln();
          break;
        case AudioPayload p:
          sb.writeln('Audio: ${p.trackName} — ${p.artist} (${p.durationText})');
          sb.writeln();
          break;
        case MapPayload p:
          sb.writeln(
            'Location: ${p.locationTitle} — ${p.address} (${p.latitude}, ${p.longitude}, zoom ${p.zoomLevel})',
          );
          sb.writeln();
          break;
        case EmbedPayload p:
          sb.writeln('Embed: ${p.provider} — ${p.title ?? p.url}');
          sb.writeln();
          break;
        case SketchCardPayload p:
          sb.writeln('Sketch: ${p.title}');
          sb.writeln();
          break;
        case FramePayload p:
          sb.writeln(p.name.toUpperCase());
          sb.writeln();
          break;
        case GroupPayload p:
          sb.writeln(p.name);
          sb.writeln();
          break;
        case ComponentPayload p:
          sb.writeln('Component: ${p.componentName}');
          sb.writeln();
          break;
        case ChartPayload p:
          final chart = _effectiveChartPayload(p, chartSourceMap);
          sb.writeln('${chart.title} (${chart.chartType.name} chart)');
          for (
            var seriesIndex = 0;
            seriesIndex < chart.series.length;
            seriesIndex++
          ) {
            final series = chart.series[seriesIndex];
            sb.writeln(series.name);
            for (var index = 0; index < series.values.length; index++) {
              final category = index < chart.categories.length
                  ? chart.categories[index]
                  : '${index + 1}';
              sb.writeln(
                '  $category: ${_formatChartNumber(series.values[index])}',
              );
            }
          }
          sb.writeln();
          break;
        default:
          break;
      }
    }

    return sb.toString().trimRight();
  }

  static Future<Uint8List?> capturePng(RenderRepaintBoundary boundary) async {
    try {
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> exportDrawingPaperPng(
    DrawingPaperPayload payload, {
    bool fullResolution = true,
  }) => DrawingPaperRenderer.renderPng(
    payload,
    maxDimension: fullResolution
        ? null
        : DrawingPaperRenderer.defaultPreviewMaxDimension,
  );

  static String exportVectorSvg(
    CanvasDocument document, {
    List<CanvasNode>? sourceNodes,
  }) {
    final nodes = document.nodes.where((n) => n.visible).toList();
    final nodeMap = {for (final node in nodes) node.id: node};
    final chartSourceNodes = sourceNodes ?? document.nodes;
    final chartSourceMap = {for (final node in chartSourceNodes) node.id: node};
    final edgeRoutes = <String, List<Offset>>{};
    for (final edge in document.edges) {
      final points = ConnectorRouter.routePointsForEdge(edge, nodeMap);
      if (points.length >= 2 &&
          points.every((point) => point.dx.isFinite && point.dy.isFinite)) {
        edgeRoutes[edge.id] = points;
      }
    }

    if (nodes.isEmpty && edgeRoutes.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600" viewBox="0 0 800 600"></svg>';
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    void includePoint(Offset point) {
      if (point.dx < minX) minX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy > maxY) maxY = point.dy;
    }

    for (final node in nodes) {
      includePoint(Offset(node.x, node.y));
      includePoint(Offset(node.x + node.width, node.y + node.height));
    }
    for (final points in edgeRoutes.values) {
      for (final point in points) {
        includePoint(point);
      }
    }

    const padding = 40.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final width = (maxX - minX).clamp(100.0, 10000.0);
    final height = (maxY - minY).clamp(100.0, 10000.0);

    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${width.toStringAsFixed(0)}" height="${height.toStringAsFixed(0)}" viewBox="${minX.toStringAsFixed(1)} ${minY.toStringAsFixed(1)} ${width.toStringAsFixed(1)} ${height.toStringAsFixed(1)}">',
    );
    sb.writeln('  <defs>');
    sb.writeln(
      '    <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">',
    );
    sb.writeln('      <path d="M 0 0 L 10 5 L 0 10 z" fill="#94A3B8" />');
    sb.writeln('    </marker>');
    sb.writeln('  </defs>');
    sb.writeln(
      '  <rect x="${minX.toStringAsFixed(1)}" y="${minY.toStringAsFixed(1)}" width="${width.toStringAsFixed(1)}" height="${height.toStringAsFixed(1)}" fill="#191A1E" />',
    );

    for (final node in nodes) {
      sb.writeln(_nodeToSvg(node, sourceNodes: chartSourceMap));
    }

    for (final edge in document.edges) {
      final points = edgeRoutes[edge.id];
      if (points == null) continue;
      final pathD = _svgPathData(edge, points);
      if (pathD == null) continue;
      final colorHex = _colorToHex(edge.strokeColor);
      final dashAttr = edge.strokeStyle == StrokeStyle.dashed
          ? ' stroke-dasharray="6,4"'
          : edge.strokeStyle == StrokeStyle.dotted
          ? ' stroke-dasharray="2,3"'
          : '';
      final markerStart = edge.startMarker == LineMarker.arrow
          ? ' marker-start="url(#arrow)"'
          : '';
      final markerEnd = edge.endMarker == LineMarker.arrow
          ? ' marker-end="url(#arrow)"'
          : '';

      sb.writeln(
        '  <path d="$pathD" stroke="$colorHex" stroke-width="${edge.strokeWidth}" fill="none"$dashAttr$markerStart$markerEnd />',
      );
      if (edge.label != null && edge.label!.isNotEmpty) {
        final labelPoint = ConnectorRouter.pointAtRouteFraction(
          points,
          edge.normalizedLabelPosition,
        );
        sb.writeln(
          '  <text x="${labelPoint.dx}" y="${labelPoint.dy - 8}" fill="#E2E8F0" font-size="11" text-anchor="middle" font-family="sans-serif">${_escapeXml(edge.label!)}</text>',
        );
      }
    }

    sb.writeln('</svg>');
    return sb.toString();
  }

  static String? _svgPathData(CanvasEdge edge, List<Offset> points) {
    if (points.length < 2) return null;
    if (edge.routing == ConnectorRouting.curved && edge.waypoints.isEmpty) {
      final start = points.first;
      final end = points.last;
      final dx = (end.dx - start.dx).abs() * 0.5;
      final dy = (end.dy - start.dy).abs() * 0.5;
      var cp1 = start;
      var cp2 = end;
      final xOffset = dx.clamp(30.0, 1000.0);
      final yOffset = dy.clamp(30.0, 1000.0);
      switch (edge.sourceAnchor) {
        case AnchorPosition.top:
          cp1 = Offset(start.dx, start.dy - yOffset);
          break;
        case AnchorPosition.right:
          cp1 = Offset(start.dx + xOffset, start.dy);
          break;
        case AnchorPosition.bottom:
          cp1 = Offset(start.dx, start.dy + yOffset);
          break;
        case AnchorPosition.left:
          cp1 = Offset(start.dx - xOffset, start.dy);
          break;
      }
      switch (edge.targetAnchor) {
        case AnchorPosition.top:
          cp2 = Offset(end.dx, end.dy - yOffset);
          break;
        case AnchorPosition.right:
          cp2 = Offset(end.dx + xOffset, end.dy);
          break;
        case AnchorPosition.bottom:
          cp2 = Offset(end.dx, end.dy + yOffset);
          break;
        case AnchorPosition.left:
          cp2 = Offset(end.dx - xOffset, end.dy);
          break;
      }
      return 'M ${start.dx} ${start.dy} C ${cp1.dx} ${cp1.dy}, ${cp2.dx} ${cp2.dy}, ${end.dx} ${end.dy}';
    }

    final commands = StringBuffer('M ${points.first.dx} ${points.first.dy}');
    for (final point in points.skip(1)) {
      commands.write(' L ${point.dx} ${point.dy}');
    }
    return commands.toString();
  }

  /// Exports a specific Frame and its contained children to standalone SVG
  static String exportSingleFrameSvg(
    CanvasDocument document,
    CanvasNode frameNode,
  ) {
    final frameRect = Rect.fromLTWH(
      frameNode.x,
      frameNode.y,
      frameNode.width,
      frameNode.height,
    );
    final contained = document.nodes
        .where((n) {
          if (!n.visible) return false;
          if (n.id == frameNode.id) return true;
          final center = Offset(n.x + n.width / 2, n.y + n.height / 2);
          return frameRect.contains(center);
        })
        .map((n) {
          // Offset relative to frame top-left
          return n.copyWith(x: n.x - frameNode.x, y: n.y - frameNode.y);
        })
        .toList();

    final docSubset = CanvasDocument(
      projectId: document.projectId,
      canvasId: frameNode.name ?? 'frame_export',
      updatedAt: document.updatedAt,
      nodes: contained,
      edges: const [],
    );

    return exportVectorSvg(docSubset, sourceNodes: document.nodes);
  }

  /// Exports Frame nodes as a multi-page PDF document / single document PDF
  static Uint8List exportMultiPagePdf(CanvasDocument document) {
    // Generate valid standalone PDF 1.4 binary data containing document / frame pages
    final frameNodes = document.nodes
        .where((n) => n.type == NodeType.frame && n.visible)
        .toList();
    final List<List<CanvasNode>> pages = [];

    if (frameNodes.isNotEmpty) {
      // Sort frames left-to-right, top-to-bottom
      frameNodes.sort((a, b) {
        final cmpY = (a.y / 200).floor().compareTo((b.y / 200).floor());
        if (cmpY != 0) return cmpY;
        return a.x.compareTo(b.x);
      });

      for (final frame in frameNodes) {
        final frameRect = Rect.fromLTWH(
          frame.x,
          frame.y,
          frame.width,
          frame.height,
        );
        final containedNodes = document.nodes.where((n) {
          if (!n.visible) return false;
          if (n.id == frame.id) return true;
          final center = Offset(n.x + n.width / 2, n.y + n.height / 2);
          return frameRect.contains(center);
        }).toList();
        pages.add(containedNodes);
      }
    } else {
      // Single Page fallback with all visible nodes
      final allNodes = document.nodes.where((n) => n.visible).toList();
      pages.add(
        allNodes.isNotEmpty
            ? allNodes
            : [
                CanvasNode(
                  id: 'placeholder',
                  type: NodeType.rectangle,
                  x: 50,
                  y: 50,
                  width: 500,
                  height: 300,
                  payload: TextPayload(
                    text: 'Creative Canvas Studio Document',
                    fontSize: 16,
                  ),
                ),
              ],
      );
    }

    final pdfBuffer = StringBuffer();
    pdfBuffer.write('%PDF-1.4\n');
    final offsets = <int>[];

    void writeObj(int objNum, String content) {
      offsets.add(pdfBuffer.length);
      pdfBuffer.write('$objNum 0 obj\n$content\nendobj\n');
    }

    // 1: Catalog
    writeObj(1, '<< /Type /Catalog /Pages 2 0 R >>');

    // 2: Pages
    final pageObjIds = <int>[];
    int currentObj = 3;
    for (int i = 0; i < pages.length; i++) {
      pageObjIds.add(currentObj);
      currentObj += 2; // Each page uses 1 Page obj + 1 Content stream obj
    }

    final kidsStr = pageObjIds.map((id) => '$id 0 R').join(' ');
    writeObj(2, '<< /Type /Pages /Kids [ $kidsStr ] /Count ${pages.length} >>');

    for (int i = 0; i < pages.length; i++) {
      final pageObjId = pageObjIds[i];
      final contentObjId = pageObjId + 1;
      final pageNodes = pages[i];

      // Page Node
      writeObj(
        pageObjId,
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents $contentObjId 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>',
      );

      // Content stream
      final streamContent = _generatePdfPageStream(pageNodes);
      final streamLength = utf8.encode(streamContent).length;
      writeObj(
        contentObjId,
        '<< /Length $streamLength >>\nstream\n$streamContent\nendstream',
      );
    }

    // XRef table
    final xrefOffset = pdfBuffer.length;
    pdfBuffer.write('xref\n0 $currentObj\n');
    pdfBuffer.write('0000000000 65535 f \n');
    for (final offset in offsets) {
      pdfBuffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }

    // Trailer
    pdfBuffer.write('trailer\n<< /Size $currentObj /Root 1 0 R >>\n');
    pdfBuffer.write('startxref\n$xrefOffset\n%%EOF');

    return Uint8List.fromList(utf8.encode(pdfBuffer.toString()));
  }

  static String _generatePdfPageStream(List<CanvasNode> nodes) {
    final sb = StringBuffer();
    // Background
    sb.writeln('q');
    sb.writeln('0.098 0.102 0.118 rg'); // #191A1E
    sb.writeln('0 0 612 792 re');
    sb.writeln('f');
    sb.writeln('Q');

    // Title / Header
    sb.writeln('BT');
    sb.writeln('/F1 14 Tf');
    sb.writeln('0.976 0.451 0.086 rg'); // #F97316
    sb.writeln('36 756 Td');
    sb.writeln('(Creative Canvas Studio - Exported Page) Tj');
    sb.writeln('ET');

    // Draw elements
    for (final node in nodes) {
      final pdfY = 700.0 - (node.y.clamp(0.0, 600.0));
      final pdfX = (node.x + 36).clamp(36.0, 540.0);
      final pdfW = node.width.clamp(20.0, 500.0);
      final pdfH = node.height.clamp(20.0, 400.0);

      sb.writeln('q');
      if (node.type == NodeType.frame) {
        sb.writeln('0.145 0.153 0.180 rg'); // #25272E
        sb.writeln('$pdfX $pdfY $pdfW $pdfH re f');
        sb.writeln('0.216 0.227 0.267 RG 1 w');
        sb.writeln('$pdfX $pdfY $pdfW $pdfH re S');
      } else {
        sb.writeln('0.188 0.200 0.239 rg');
        sb.writeln('$pdfX $pdfY $pdfW $pdfH re f');
        sb.writeln('0.376 0.412 0.490 RG 1 w');
        sb.writeln('$pdfX $pdfY $pdfW $pdfH re S');
      }
      sb.writeln('Q');

      // Text label if present
      String? text;
      if (node.payload is TextPayload) {
        text = (node.payload as TextPayload).text;
      } else if (node.payload is StickyNotePayload) {
        text = (node.payload as StickyNotePayload).text;
      } else if (node.payload is FramePayload) {
        text = (node.payload as FramePayload).title;
      } else if (node.payload is Model3DPayload) {
        text = (node.payload as Model3DPayload).displayName;
      } else if (node.payload is ChartPayload) {
        final chart = node.payload as ChartPayload;
        text = '${chart.title} (${chart.chartType.name} chart)';
      }

      if (text != null && text.isNotEmpty) {
        final sanitized = text.replaceAll('(', '\\(').replaceAll(')', '\\)');
        sb.writeln('BT');
        sb.writeln('/F1 10 Tf');
        sb.writeln('0.95 0.95 0.95 rg');
        sb.writeln('${pdfX + 8} ${pdfY + pdfH - 16} Td');
        sb.writeln('($sanitized) Tj');
        sb.writeln('ET');
      }
    }

    return sb.toString();
  }

  static String _nodeToSvg(
    CanvasNode node, {
    Map<String, CanvasNode> sourceNodes = const {},
  }) {
    final x = node.x;
    final y = node.y;
    final w = node.width;
    final h = node.height;
    final opacity = node.opacity.clamp(0.0, 1.0);

    switch (node.type) {
      case NodeType.rectangle:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6 4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2 3"'
            : '';
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="${p.cornerRadius}" fill="${_colorToHex(p.fill)}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr opacity="$opacity" />';

      case NodeType.ellipse:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final cx = x + w / 2;
        final cy = y + h / 2;
        final rx = w / 2;
        final ry = h / 2;
        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6 4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2 3"'
            : '';
        if (p.sweepAngle >= 359.999 && p.innerRadiusRatio <= 0) {
          return '  <ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr opacity="$opacity" />';
        }
        Offset point(double angle, double ratio) {
          final radians = (angle - 90.0) * math.pi / 180.0;
          return Offset(
            cx + math.cos(radians) * rx * ratio,
            cy + math.sin(radians) * ry * ratio,
          );
        }
        final startPoint = point(p.startAngle, 1.0);
        final endPoint = point(p.startAngle + p.sweepAngle, 1.0);
        final largeArc = p.sweepAngle > 180 ? 1 : 0;
        final pathData = p.innerRadiusRatio <= 0
            ? 'M $cx $cy L ${startPoint.dx} ${startPoint.dy} A $rx $ry 0 $largeArc 1 ${endPoint.dx} ${endPoint.dy} Z'
            : () {
                final innerEnd = point(
                  p.startAngle + p.sweepAngle,
                  p.innerRadiusRatio,
                );
                final innerStart = point(p.startAngle, p.innerRadiusRatio);
                return 'M ${startPoint.dx} ${startPoint.dy} A $rx $ry 0 $largeArc 1 ${endPoint.dx} ${endPoint.dy} L ${innerEnd.dx} ${innerEnd.dy} A ${rx * p.innerRadiusRatio} ${ry * p.innerRadiusRatio} 0 $largeArc 0 ${innerStart.dx} ${innerStart.dy} Z';
              }();
        return '  <path d="$pathData" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr opacity="$opacity" />';

      case NodeType.diamond:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final points =
            '${x + w / 2},$y ${x + w},${y + h / 2} ${x + w / 2},${y + h} $x,${y + h / 2}';
        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6 4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2 3"'
            : '';
        return '  <polygon points="$points" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr opacity="$opacity" />';

      case NodeType.cylinder:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final capRatio = p.cylinderCapRatio.clamp(0.1, 0.5);
        final ch = (h * capRatio).clamp(8.0, h * 0.45);
        final rx = w / 2;
        final ry = ch / 2;
        final cx = x + rx;
        final topCy = y + ry;
        final botCy = y + h - ry;
        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6 4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2 3"'
            : '';
        final bodyPath =
            'M $x $topCy L $x $botCy A $rx $ry 0 0 0 ${x + w} $botCy L ${x + w} $topCy Z';
        return '  <g opacity="$opacity"><path d="$bodyPath" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr /><ellipse cx="$cx" cy="$topCy" rx="$rx" ry="$ry" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}" /></g>';

      case NodeType.parallelogram:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final skew = (p.skewRatio * w).clamp(-w * 0.45, w * 0.45);
        final p1x = x + (skew >= 0 ? skew : 0.0);
        final p1y = y;
        final p2x = x + (skew >= 0 ? w : w + skew);
        final p2y = y;
        final p3x = x + (skew >= 0 ? w - skew : w);
        final p3y = y + h;
        final p4x = x + (skew >= 0 ? 0.0 : -skew);
        final p4y = y + h;

        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6,4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2,3"'
            : '';

        final polyPoints = '$p1x,$p1y $p2x,$p2y $p3x,$p3y $p4x,$p4y';

        final labelEl = p.label.isNotEmpty
            ? '<text x="${x + w / 2}" y="${y + h / 2}" fill="${_colorToHex(p.labelColor)}" font-size="${p.labelFontSize}" font-family="sans-serif" font-weight="600" text-anchor="middle" dominant-baseline="middle">${_escapeXml(p.label)}</text>'
            : '';

        return '  <g opacity="$opacity"><polygon points="$polyPoints" fill="${_colorToHex(p.fill)}" fill-opacity="${p.fillOpacity}" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr />$labelEl</g>';

      case NodeType.line:
      case NodeType.arrow:
        final p = node.payload is ShapePayload
            ? node.payload as ShapePayload
            : ShapePayload();
        final x1 = x + p.startXRatio * w;
        final y1 = y + p.startYRatio * h;
        final x2 = x + p.endXRatio * w;
        final y2 = y + p.endYRatio * h;

        final dashAttr = p.strokeStyle == StrokeStyle.dashed
            ? ' stroke-dasharray="6,4"'
            : p.strokeStyle == StrokeStyle.dotted
            ? ' stroke-dasharray="2,3"'
            : '';

        final isArrow =
            node.type == NodeType.arrow || p.endMarker == LineMarker.arrow;
        final markerEnd = isArrow ? ' marker-end="url(#arrow)"' : '';
        final markerStart = p.startMarker == LineMarker.arrow
            ? ' marker-start="url(#arrow)"'
            : '';

        String lineContent;
        if (p.lineRouting == LineRouting.orthogonal) {
          final midX = (x1 + x2) / 2;
          lineContent =
              '<path d="M $x1 $y1 L $midX $y1 L $midX $y2 L $x2 $y2" fill="none" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr$markerStart$markerEnd />';
        } else if (p.lineRouting == LineRouting.curved) {
          final midX = (x1 + x2) / 2;
          final midY = (y1 + y2) / 2;
          final dx = x2 - x1;
          final dy = y2 - y1;
          final depth = p.curveDepth;
          final cx = midX - dy * depth;
          final cy = midY + dx * depth;
          lineContent =
              '<path d="M $x1 $y1 Q $cx $cy $x2 $y2" fill="none" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr$markerStart$markerEnd />';
        } else {
          lineContent =
              '<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" stroke="${_colorToHex(p.stroke)}" stroke-width="${p.strokeWidth}"$dashAttr$markerStart$markerEnd />';
        }

        final labelEl = p.label.isNotEmpty
            ? '<text x="${(x1 + x2) / 2}" y="${(y1 + y2) / 2 - 6}" fill="${_colorToHex(p.labelColor)}" font-size="${p.labelFontSize}" font-family="sans-serif" font-weight="600" text-anchor="middle">${_escapeXml(p.label)}</text>'
            : '';

        return '  <g opacity="$opacity">$lineContent$labelEl</g>';

      case NodeType.text:
        final p = node.payload is TextPayload
            ? node.payload as TextPayload
            : TextPayload();
        return '  <text x="$x" y="${y + p.fontSize}" fill="${_colorToHex(p.color)}" font-size="${p.fontSize}" font-family="sans-serif" opacity="$opacity">${_escapeXml(p.text)}</text>';

      case NodeType.stickyNote:
        final p = node.payload is StickyNotePayload
            ? node.payload as StickyNotePayload
            : StickyNotePayload();
        return '  <g opacity="$opacity"><rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="${_colorToHex(p.backgroundColor)}" /><text x="${x + 10}" y="${y + 24}" fill="${_colorToHex(p.textColor)}" font-size="13" font-family="sans-serif">${_escapeXml(p.text)}</text></g>';

      case NodeType.frame:
        final p = node.payload is FramePayload
            ? node.payload as FramePayload
            : FramePayload();
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="6" fill="${_colorToHex(p.background)}" stroke="#373A44" stroke-width="1.5" opacity="$opacity" />';

      case NodeType.vectorPath:
        final p = node.payload is VectorPathPayload
            ? node.payload as VectorPathPayload
            : VectorPathPayload();
        final subpaths = p.allSubpaths;
        if (subpaths.isEmpty) return '';
        final pathD = p.toSvgPathData(offset: Offset(x, y));
        final hasFill =
            p.fill.a > 0 && p.allSubpaths.any((subpath) => subpath.length > 1);
        final capStr = p.strokeCap.name;
        final joinStr = p.strokeJoin.name;
        final dashStr = p.dashPattern.isNotEmpty
            ? ' stroke-dasharray="${p.dashPattern.join(',')}"'
            : '';
        final dashOffsetStr = p.dashOffset == 0
            ? ''
            : ' stroke-dashoffset="${p.dashOffset}"';
        final gradientId = 'gradient_${_escapeXml(node.id)}';
        final fillVal = !hasFill
            ? 'none'
            : p.isGradientFill
            ? 'url(#$gradientId)'
            : _colorToHex(p.fill);
        final fillRule = p.fillRule == VectorFillRule.evenOdd
            ? 'evenodd'
            : 'nonzero';
        final gradientDef = p.isGradientFill && hasFill
            ? '<defs><linearGradient id="$gradientId" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${_colorToHex(p.fill)}" stop-opacity="${p.fill.a}"/><stop offset="1" stop-color="${_colorToHex(p.gradientEndColor)}" stop-opacity="${p.gradientEndColor.a}"/></linearGradient></defs>'
            : '';
        return '  $gradientDef<path d="$pathD" fill="$fillVal" fill-opacity="${p.fill.a}" fill-rule="$fillRule" stroke="${_colorToHex(p.stroke)}" stroke-opacity="${p.stroke.a}" stroke-width="${p.strokeWidth}" stroke-linecap="$capStr" stroke-linejoin="$joinStr"$dashStr$dashOffsetStr opacity="$opacity" />';

      case NodeType.drawing:
        final p = node.payload is DrawingPayload
            ? node.payload as DrawingPayload
            : DrawingPayload();
        if (p.points.length < 2) return '';
        final pathD = StringBuffer(
          'M ${x + p.points.first.dx} ${y + p.points.first.dy} ',
        );
        if (p.isSmoothed && p.points.length > 2) {
          for (int i = 1; i < p.points.length - 1; i++) {
            final p0 = p.points[i];
            final p1 = p.points[i + 1];
            final midX = x + (p0.dx + p1.dx) / 2.0;
            final midY = y + (p0.dy + p1.dy) / 2.0;
            pathD.write('Q ${x + p0.dx} ${y + p0.dy} $midX $midY ');
          }
          final last = p.points.last;
          pathD.write('L ${x + last.dx} ${y + last.dy} ');
        } else {
          for (int i = 1; i < p.points.length; i++) {
            pathD.write('L ${x + p.points[i].dx} ${y + p.points[i].dy} ');
          }
        }
        final strokeCap =
            p.brushType == BrushType.marker ||
                p.brushType == BrushType.highlighter
            ? 'square'
            : 'round';
        final effectiveWidth = p.brushType == BrushType.highlighter
            ? p.strokeWidth * 2.5
            : p.strokeWidth;
        final effectiveAlpha =
            p.brushType == BrushType.highlighter ||
                p.brushType == BrushType.airbrush
            ? opacity * 0.45
            : opacity;
        if (p.cutouts.isNotEmpty) {
          final maskId = 'mask_${node.id}';
          final maskDef = StringBuffer(
            '<mask id="$maskId"><rect width="100%" height="100%" fill="white" />',
          );
          for (final cut in p.cutouts) {
            maskDef.write(
              '<circle cx="${x + cut.position.dx}" cy="${y + cut.position.dy}" r="${cut.radius}" fill="black" />',
            );
          }
          maskDef.write('</mask>');
          return '  <defs>$maskDef</defs><path d="$pathD" fill="none" stroke="${_colorToHex(p.strokeColor)}" stroke-width="$effectiveWidth" stroke-linecap="$strokeCap" opacity="$effectiveAlpha" mask="url(#$maskId)" />';
        }
        return '  <path d="$pathD" fill="none" stroke="${_colorToHex(p.strokeColor)}" stroke-width="$effectiveWidth" stroke-linecap="$strokeCap" opacity="$effectiveAlpha" />';

      case NodeType.sketchCard:
        final sp = node.payload is SketchCardPayload
            ? node.payload as SketchCardPayload
            : SketchCardPayload();
        final cardBuf = StringBuffer();
        cardBuf.write(
          '  <rect x="$x" y="$y" width="$w" height="$h" rx="8" fill="${_colorToHex(sp.backgroundColor)}" stroke="${_colorToHex(sp.strokeColor)}" stroke-width="1.4" opacity="$opacity" />',
        );
        cardBuf.write(
          '  <text x="${x + 10}" y="${y + 18}" fill="${_colorToHex(sp.strokeColor)}" font-size="11" font-weight="bold" font-family="sans-serif">✏ ${_escapeXml(sp.title)}</text>',
        );
        for (final stroke in sp.strokes) {
          if (stroke.isEmpty) continue;
          final pathD = StringBuffer(
            'M ${x + stroke.first.dx} ${y + stroke.first.dy} ',
          );
          for (int i = 1; i < stroke.length; i++) {
            pathD.write('L ${x + stroke[i].dx} ${y + stroke[i].dy} ');
          }
          cardBuf.write(
            '  <path d="$pathD" fill="none" stroke="${_colorToHex(sp.strokeColor)}" stroke-width="${sp.strokeWidth}" stroke-linecap="round" stroke-linejoin="round" opacity="$opacity" />',
          );
        }
        return cardBuf.toString();

      case NodeType.drawingPaper:
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="0" fill="#FFFFFF" stroke="#94A3B8" stroke-width="1.5" opacity="$opacity" /><text x="${x + 8}" y="${y + 16}" fill="#64748B" font-size="10" font-family="sans-serif">Drawing Paper Studio</text>';

      case NodeType.component:
        final p = node.payload is ComponentPayload
            ? node.payload as ComponentPayload
            : ComponentPayload(
                masterComponentId: node.id,
                componentName: 'Component',
              );
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="#2563EB" stroke="#60A5FA" stroke-width="1.5" opacity="$opacity" /><text x="${x + w / 2}" y="${y + h / 2 + 4}" fill="#FFFFFF" font-size="12" text-anchor="middle" font-family="sans-serif">${_escapeXml(p.componentName)}</text>';

      case NodeType.group:
        final p = node.payload is GroupPayload
            ? node.payload as GroupPayload
            : GroupPayload();
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="2" fill="none" stroke="#D97706" stroke-width="1" stroke-dasharray="4,4" opacity="$opacity" /><text x="${x + 6}" y="${y - 4}" fill="#D97706" font-size="10" font-family="sans-serif">${_escapeXml(p.name)}</text>';

      case NodeType.model3d:
        final p = node.payload is Model3DPayload
            ? node.payload as Model3DPayload
            : Model3DPayload();
        return '  <g opacity="$opacity"><rect x="$x" y="$y" width="$w" height="$h" rx="8" fill="#151B2B" stroke="#475569" stroke-width="1" /><path d="M ${x + w / 2} ${y + 28} l 28 16 v 32 l -28 16 l -28 -16 v -32 z" fill="none" stroke="#60A5FA" stroke-width="2" /><text x="${x + w / 2}" y="${y + h - 28}" fill="#E2E8F0" font-size="11" text-anchor="middle" font-family="sans-serif">${_escapeXml(p.displayName)}</text><text x="${x + w / 2}" y="${y + h - 12}" fill="#94A3B8" font-size="9" text-anchor="middle" font-family="sans-serif">${_escapeXml(p.fileSizeText)}</text></g>';

      case NodeType.image:
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="#2B2E36" stroke="#373A44" stroke-width="1" opacity="$opacity" /><text x="${x + w / 2}" y="${y + h / 2 + 4}" fill="#9CA3AF" font-size="11" text-anchor="middle" font-family="sans-serif">Image Asset</text>';

      case NodeType.chart:
        final p = node.payload is ChartPayload
            ? node.payload as ChartPayload
            : ChartPayload();
        return _chartToSvg(node, _effectiveChartPayload(p, sourceNodes));

      case NodeType.annotatedImage:
        final ap = node.payload is AnnotatedImagePayload
            ? node.payload as AnnotatedImagePayload
            : null;
        final buffer = StringBuffer(
          '  <rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="#1E293B" stroke="#64748B" stroke-width="1" opacity="$opacity" />',
        );
        if (ap != null) {
          // Corner badge placed outside top-right corner
          if (ap.showCornerBadge && ap.pins.isNotEmpty) {
            final unresCount = ap.pins.where((p) => !p.isResolved).length;
            final badgeBg = unresCount > 0 ? '#EC4899' : '#10B981';
            final badgeW = unresCount > 9 ? 48 : 40;
            final bx = x + w - badgeW;
            final by = y - 28;
            buffer.write(
              '  <rect x="$bx" y="$by" width="$badgeW" height="22" rx="11" fill="$badgeBg" />',
            );
            buffer.write(
              '  <text x="${bx + badgeW / 2}" y="${by + 14}" fill="#FFFFFF" font-size="10" font-weight="bold" text-anchor="middle" font-family="sans-serif">${unresCount > 0 ? "PIN $unresCount" : "DONE"}</text>',
            );
          }

          for (int i = 0; i < ap.pins.length; i++) {
            final pin = ap.pins[i];
            final px = x + pin.position.dx;
            final py = y + pin.position.dy;
            final pinHex = pin.isResolved
                ? '#10B981'
                : (pin.status == AnnotationPinStatus.issue
                      ? '#EF4444'
                      : _colorToHex(pin.color));
            buffer.write(
              '  <circle cx="$px" cy="$py" r="12" fill="$pinHex" stroke="#FFFFFF" stroke-width="1.8" />',
            );
            buffer.write(
              '  <text x="$px" y="${py + 4}" fill="#FFFFFF" font-size="11" font-weight="bold" text-anchor="middle" font-family="sans-serif">${pin.isResolved ? "✓" : "${i + 1}"}</text>',
            );
          }
        }
        return buffer.toString();

      default:
        return '  <rect x="$x" y="$y" width="$w" height="$h" rx="4" fill="#22242A" stroke="#373A44" stroke-width="1" opacity="$opacity" /><text x="${x + w / 2}" y="${y + h / 2 + 4}" fill="#E2E8F0" font-size="11" text-anchor="middle" font-family="sans-serif">${node.type.name.toUpperCase()}</text>';
    }
  }

  static ChartPayload _effectiveChartPayload(
    ChartPayload payload,
    Map<String, CanvasNode> sourceNodes,
  ) {
    final sourceNode = payload.tableSourceNodeId == null
        ? null
        : sourceNodes[payload.tableSourceNodeId];
    final resolved = sourceNode?.payload is TablePayload
        ? payload.resolvedFromTable(sourceNode!.payload as TablePayload)
        : payload;
    return resolved.filteredByCategory();
  }

  static String _chartToSvg(CanvasNode node, ChartPayload payload) {
    final x = node.x;
    final y = node.y;
    final width = node.width.clamp(1.0, double.infinity).toDouble();
    final height = node.height.clamp(1.0, double.infinity).toDouble();
    final plotLeft = x + 10.0;
    final plotTop = y + (payload.title.isEmpty ? 10.0 : 30.0);
    final plotWidth = (width - 20.0).clamp(1.0, double.infinity).toDouble();
    final plotHeight = (height - (payload.title.isEmpty ? 30.0 : 50.0))
        .clamp(1.0, double.infinity)
        .toDouble();
    final plotBottom = plotTop + plotHeight;
    final opacity = node.opacity.clamp(0.0, 1.0);
    final buffer = StringBuffer(
      '  <g data-chart-type="${payload.chartType.name}" opacity="$opacity">',
    );
    buffer.write(
      '<rect x="$x" y="$y" width="$width" height="$height" rx="8" fill="#111827" stroke="#334155" stroke-width="1" />',
    );
    if (payload.title.isNotEmpty) {
      buffer.write(
        '<text x="${x + 10}" y="${y + 18}" fill="#F8FAFC" font-size="12" font-weight="600" font-family="sans-serif">${_escapeXml(payload.title)}</text>',
      );
    }

    void drawGrid() {
      if (payload.showGrid) {
        for (var index = 0; index <= 4; index++) {
          final rowY = plotTop + plotHeight * index / 4.0;
          buffer.write(
            '<line x1="$plotLeft" y1="$rowY" x2="${plotLeft + plotWidth}" y2="$rowY" stroke="#334155" stroke-width="0.7" opacity="0.7" />',
          );
        }
      }
      if (payload.showAxes) {
        buffer.write(
          '<line x1="$plotLeft" y1="$plotBottom" x2="${plotLeft + plotWidth}" y2="$plotBottom" stroke="#64748B" stroke-width="1" />',
        );
        buffer.write(
          '<line x1="$plotLeft" y1="$plotTop" x2="$plotLeft" y2="$plotBottom" stroke="#64748B" stroke-width="1" />',
        );
      }
    }

    void drawCategories({required int count}) {
      if (!payload.showAxes || count <= 0) return;
      final labels = payload.categories;
      for (var index = 0; index < count; index++) {
        if (index >= labels.length) break;
        final denominator = math.max(1, count - 1).toDouble();
        final labelX = plotLeft + plotWidth * index / denominator;
        buffer.write(
          '<text x="$labelX" y="${plotBottom + 14}" fill="#94A3B8" font-size="9" text-anchor="middle" font-family="sans-serif">${_escapeXml(labels[index])}</text>',
        );
      }
    }

    final bounds = _chartBounds(payload);
    double mapY(double value) =>
        plotBottom -
        ((value - bounds.$1) / (bounds.$2 - bounds.$1)) * plotHeight;
    double mapX(int index, int count) {
      final denominator = math.max(1, count - 1).toDouble();
      return plotLeft + plotWidth * index / denominator;
    }

    switch (payload.chartType) {
      case ChartType.line:
        drawGrid();
        final count = math.max(
          2,
          math.max(
            payload.categories.length,
            payload.series.fold<int>(0, (maxLength, item) {
              return math.max(maxLength, item.values.length);
            }),
          ),
        );
        drawCategories(count: count);
        for (
          var seriesIndex = 0;
          seriesIndex < payload.series.length;
          seriesIndex++
        ) {
          final series = payload.series[seriesIndex];
          if (series.values.isEmpty) continue;
          final points = [
            for (var index = 0; index < series.values.length; index++)
              '${mapX(index, count)},${mapY(series.values[index])}',
          ].join(' ');
          buffer.write(
            '<polyline points="$points" fill="none" stroke="${_chartSeriesColor(payload, seriesIndex)}" stroke-width="2.5"${payload.lineCurved ? ' stroke-linejoin="round"' : ''} />',
          );
          if (payload.showDots) {
            for (var index = 0; index < series.values.length; index++) {
              buffer.write(
                '<circle cx="${mapX(index, count)}" cy="${mapY(series.values[index])}" r="3" fill="${_chartSeriesColor(payload, seriesIndex)}" />',
              );
            }
          }
        }
        break;
      case ChartType.bar:
        drawGrid();
        final count = math.max(
          1,
          math.max(
            payload.categories.length,
            payload.series.fold<int>(0, (maxLength, item) {
              return math.max(maxLength, item.values.length);
            }),
          ),
        );
        drawCategories(count: count);
        final seriesCount = math.max(1, payload.series.length);
        final groupWidth = plotWidth / count;
        final barWidth = (groupWidth * 0.72 / seriesCount).clamp(2.0, 48.0);
        for (
          var seriesIndex = 0;
          seriesIndex < payload.series.length;
          seriesIndex++
        ) {
          final series = payload.series[seriesIndex];
          for (var index = 0; index < series.values.length; index++) {
            final value = series.values[index];
            final color = _chartSeriesColor(payload, seriesIndex);
            if (payload.barOrientation == ChartBarOrientation.horizontal) {
              final rowHeight = plotHeight / count;
              final barHeight = (rowHeight * 0.72 / seriesCount).clamp(
                2.0,
                48.0,
              );
              final baseline =
                  plotLeft + _chartMapZero(bounds, plotLeft, plotWidth);
              final valueX =
                  plotLeft +
                  ((value - bounds.$1) / (bounds.$2 - bounds.$1)) * plotWidth;
              final barY =
                  plotTop +
                  rowHeight * index +
                  rowHeight * 0.14 +
                  barHeight * seriesIndex;
              final left = math.min(baseline, valueX);
              buffer.write(
                '<rect x="$left" y="$barY" width="${(valueX - baseline).abs()}" height="$barHeight" rx="2" fill="$color" />',
              );
            } else {
              final zeroY = mapY(0);
              final valueY = mapY(value);
              final barX =
                  plotLeft +
                  groupWidth * index +
                  groupWidth * 0.14 +
                  barWidth * seriesIndex;
              buffer.write(
                '<rect x="$barX" y="${math.min(zeroY, valueY)}" width="$barWidth" height="${(valueY - zeroY).abs()}" rx="2" fill="$color" />',
              );
            }
            if (payload.showValues) {
              final valueX =
                  payload.barOrientation == ChartBarOrientation.horizontal
                  ? plotLeft +
                        ((value - bounds.$1) / (bounds.$2 - bounds.$1)) *
                            plotWidth
                  : plotLeft +
                        groupWidth * index +
                        groupWidth * 0.14 +
                        barWidth * seriesIndex +
                        barWidth / 2;
              final valueY =
                  payload.barOrientation == ChartBarOrientation.horizontal
                  ? plotTop +
                        plotHeight / count * index +
                        plotHeight / count * 0.14 +
                        barWidth * seriesIndex +
                        10
                  : math.min(mapY(0), mapY(value)) - 3;
              buffer.write(
                '<text x="$valueX" y="$valueY" fill="#E2E8F0" font-size="8" text-anchor="middle" font-family="sans-serif">${_formatChartNumber(value)}</text>',
              );
            }
          }
        }
        break;
      case ChartType.pie:
      case ChartType.doughnut:
        final source = payload.series.isEmpty
            ? ChartSeries(values: [1])
            : payload.series.first;
        final values = source.values.isEmpty
            ? const [1.0]
            : source.values.map((value) => value.abs()).toList();
        final total = values.fold<double>(0, (sum, value) => sum + value);
        final safeTotal = total == 0 ? values.length.toDouble() : total;
        final center = Offset(
          plotLeft + plotWidth / 2,
          plotTop + plotHeight / 2,
        );
        final radius = math.min(plotWidth, plotHeight) * 0.38;
        var angle = -math.pi / 2;
        for (var index = 0; index < values.length; index++) {
          final sweep =
              (values[index] == 0 ? 1.0 : values[index]) /
              safeTotal *
              math.pi *
              2;
          final innerRatio = payload.chartType == ChartType.doughnut
              ? payload.doughnutHoleRatio
              : 0.0;
          buffer.write(
            '<path d="${_chartArcPath(center, radius, angle, angle + sweep, innerRatio)}" fill="${_chartSeriesColor(payload, index)}" stroke="#111827" stroke-width="1" />',
          );
          if (payload.showValues) {
            final labelAngle = angle + sweep / 2;
            final labelRadius = radius * (innerRatio + 1) / 2;
            final labelX = center.dx + math.cos(labelAngle) * labelRadius;
            final labelY = center.dy + math.sin(labelAngle) * labelRadius;
            buffer.write(
              '<text x="$labelX" y="$labelY" fill="#FFFFFF" font-size="8" text-anchor="middle" dominant-baseline="middle" font-family="sans-serif">${_formatChartNumber(values[index])}</text>',
            );
          }
          angle += sweep;
        }
        break;
      case ChartType.scatter:
        final points = <ChartPoint>[];
        for (final series in payload.series) {
          points.addAll(
            series.points.isEmpty
                ? [
                    for (var index = 0; index < series.values.length; index++)
                      ChartPoint(x: index.toDouble(), y: series.values[index]),
                  ]
                : series.points,
          );
        }
        drawGrid();
        if (points.isNotEmpty) {
          final minX = points.map((point) => point.x).reduce(math.min);
          final maxX = points.map((point) => point.x).reduce(math.max);
          final rangeX = maxX == minX ? 1.0 : maxX - minX;
          for (
            var seriesIndex = 0;
            seriesIndex < payload.series.length;
            seriesIndex++
          ) {
            final series = payload.series[seriesIndex];
            final seriesPoints = series.points.isEmpty
                ? [
                    for (var index = 0; index < series.values.length; index++)
                      ChartPoint(x: index.toDouble(), y: series.values[index]),
                  ]
                : series.points;
            for (final point in seriesPoints) {
              final pointX = plotLeft + (point.x - minX) / rangeX * plotWidth;
              buffer.write(
                '<circle cx="$pointX" cy="${mapY(point.y)}" r="4" fill="${_chartSeriesColor(payload, seriesIndex)}" />',
              );
            }
          }
        }
        break;
      case ChartType.radar:
        final count = math.max(
          3,
          math.max(
            payload.categories.length,
            payload.series.fold<int>(0, (maxLength, item) {
              return math.max(maxLength, item.values.length);
            }),
          ),
        );
        final center = Offset(
          plotLeft + plotWidth / 2,
          plotTop + plotHeight / 2,
        );
        final radius = math.min(plotWidth, plotHeight) * 0.38;
        final maxValue = payload.series
            .expand((series) => series.values)
            .fold<double>(1.0, (maxValue, value) {
              return math.max(maxValue, value.abs());
            });
        for (var ring = 1; ring <= 4; ring++) {
          final points = _radarPoints(center, radius * ring / 4, count);
          buffer.write(
            '<polygon points="${points.map((point) => '${point.dx},${point.dy}').join(' ')}" fill="none" stroke="#334155" stroke-width="0.7" />',
          );
        }
        for (
          var seriesIndex = 0;
          seriesIndex < payload.series.length;
          seriesIndex++
        ) {
          final series = payload.series[seriesIndex];
          final points = [
            for (var index = 0; index < count; index++)
              _radarPoint(
                center,
                radius *
                    (index < series.values.length
                        ? series.values[index].abs() / maxValue
                        : 0.0),
                index,
                count,
              ),
          ];
          final color = _chartSeriesColor(payload, seriesIndex);
          buffer.write(
            '<polygon points="${points.map((point) => '${point.dx},${point.dy}').join(' ')}" fill="$color" fill-opacity="0.18" stroke="$color" stroke-width="2" />',
          );
        }
        if (payload.showAxes) {
          for (var index = 0; index < count; index++) {
            final point = _radarPoint(center, radius, index, count);
            buffer.write(
              '<line x1="${center.dx}" y1="${center.dy}" x2="${point.dx}" y2="${point.dy}" stroke="#334155" stroke-width="0.7" />',
            );
            if (index < payload.categories.length) {
              buffer.write(
                '<text x="${point.dx}" y="${point.dy}" fill="#94A3B8" font-size="8" text-anchor="middle" font-family="sans-serif">${_escapeXml(payload.categories[index])}</text>',
              );
            }
          }
        }
        break;
    }

    if (payload.showLegend && payload.series.isNotEmpty) {
      var legendX = x + 10.0;
      final legendY = y + height - 10.0;
      for (var index = 0; index < payload.series.length; index++) {
        final name = _escapeXml(payload.series[index].name);
        final color = _chartSeriesColor(payload, index);
        buffer.write(
          '<rect x="$legendX" y="${legendY - 7}" width="7" height="7" fill="$color" /><text x="${legendX + 10}" y="$legendY" fill="#CBD5E1" font-size="8" font-family="sans-serif">$name</text>',
        );
        legendX += 12.0 + name.length * 5.0;
      }
    }
    buffer.write('</g>');
    return buffer.toString();
  }

  static (double, double) _chartBounds(ChartPayload payload) {
    final values = payload.series.expand((series) => series.values).toList();
    if (values.isEmpty) values.addAll(const [0.0, 1.0]);
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if (payload.minY != null) minValue = payload.minY!;
    if (payload.maxY != null) maxValue = payload.maxY!;
    if (!minValue.isFinite || !maxValue.isFinite) return (0.0, 1.0);
    if (minValue == maxValue) {
      final padding = minValue.abs() < 1 ? 1.0 : minValue.abs() * 0.2;
      minValue -= padding;
      maxValue += padding;
    }
    if (minValue > maxValue) (minValue, maxValue) = (maxValue, minValue);
    return (minValue, maxValue);
  }

  static double _chartMapZero(
    (double, double) bounds,
    double left,
    double width,
  ) {
    if (bounds.$1 >= 0) return left;
    if (bounds.$2 <= 0) return left + width;
    return left + (-bounds.$1 / (bounds.$2 - bounds.$1)) * width;
  }

  static String _chartSeriesColor(ChartPayload payload, int index) {
    if (index < payload.series.length) {
      return _colorToHex(payload.series[index].color);
    }
    return _colorToHex(payload.colors[index % payload.colors.length]);
  }

  static String _formatChartNumber(double value) =>
      value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  static Offset _chartArcPoint(Offset center, double radius, double angle) =>
      Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );

  static String _chartArcPath(
    Offset center,
    double radius,
    double start,
    double end,
    double innerRatio,
  ) {
    final outerStart = _chartArcPoint(center, radius, start);
    final outerEnd = _chartArcPoint(center, radius, end);
    final largeArc = end - start > math.pi ? 1 : 0;
    if (innerRatio <= 0) {
      return 'M ${center.dx} ${center.dy} L ${outerStart.dx} ${outerStart.dy} A $radius $radius 0 $largeArc 1 ${outerEnd.dx} ${outerEnd.dy} Z';
    }
    final innerRadius = radius * innerRatio;
    final innerEnd = _chartArcPoint(center, innerRadius, end);
    final innerStart = _chartArcPoint(center, innerRadius, start);
    return 'M ${outerStart.dx} ${outerStart.dy} A $radius $radius 0 $largeArc 1 ${outerEnd.dx} ${outerEnd.dy} L ${innerEnd.dx} ${innerEnd.dy} A $innerRadius $innerRadius 0 $largeArc 0 ${innerStart.dx} ${innerStart.dy} Z';
  }

  static Offset _radarPoint(
    Offset center,
    double radius,
    int index,
    int count,
  ) {
    final angle = -math.pi / 2 + math.pi * 2 * index / count;
    return _chartArcPoint(center, radius, angle);
  }

  static List<Offset> _radarPoints(Offset center, double radius, int count) => [
    for (var index = 0; index < count; index++)
      _radarPoint(center, radius, index, count),
  ];

  static String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
