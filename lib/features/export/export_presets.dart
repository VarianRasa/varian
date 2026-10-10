import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as image;

import '../../domain/models/document.dart';
import 'export_service.dart';
import 'export_capabilities.dart';
import 'domain/portable_asset_collector.dart';

enum ExportPresetFormat {
  json,
  projectPackage,
  portablePackage,
  presentation,
  video,
  svg,
  png,
  jpeg,
  webp,
  markdown,
  plainText,
  mermaid,
  drawio,
  pdf,
}

/// A typed result from one of the document export presets.
///
/// Text formats expose [text], while binary formats expose [bytes]. The
/// [data] getter keeps file-writing integrations format agnostic without
/// changing the existing exporter APIs.
class ExportPresetResult {
  final ExportPreset preset;
  final String? text;
  final Uint8List? bytes;
  final String? error;
  final ExportCapability? capability;

  const ExportPresetResult.text(this.preset, this.text, {this.capability})
    : bytes = null,
      error = null;

  const ExportPresetResult.bytes(this.preset, this.bytes, {this.capability})
    : text = null,
      error = null;

  const ExportPresetResult.failure(
    this.preset, {
    required this.error,
    this.capability,
  }) : text = null,
       bytes = null;

  bool get isBinary => bytes != null;
  bool get isFailure => error != null;

  Uint8List get data {
    if (isFailure) throw StateError(error!);
    final binary = bytes;
    if (binary != null) return binary;
    return Uint8List.fromList(utf8.encode(text ?? ''));
  }
}

/// A stable, user-facing export option backed by [ExportService].
class ExportPreset {
  final String id;
  final String label;
  final String extension;
  final String mimeType;
  final ExportPresetFormat format;

  const ExportPreset({
    required this.id,
    required this.label,
    required this.extension,
    required this.mimeType,
    required this.format,
  });

  bool get isBinary =>
      format == ExportPresetFormat.png ||
      format == ExportPresetFormat.jpeg ||
      format == ExportPresetFormat.webp ||
      format == ExportPresetFormat.pdf;

  bool get requiresRenderBoundary =>
      format == ExportPresetFormat.png ||
      format == ExportPresetFormat.jpeg ||
      format == ExportPresetFormat.webp;

  /// Runs the existing exporter selected by this preset.
  ///
  /// PNG capture retains [ExportService.capturePng]'s nullable failure result.
  /// A render boundary is required only for PNG; all other formats use the
  /// document-only exporters.
  Future<ExportPresetResult?> export(
    CanvasDocument document, {
    RenderRepaintBoundary? boundary,
    Map<String, Uint8List> assetBytes = const {},
    PortableAssetCollector? portableAssetCollector,
    String? password,
  }) async {
    switch (format) {
      case ExportPresetFormat.json:
        return ExportPresetResult.text(
          this,
          ExportService.exportNativeJson(document),
        );
      case ExportPresetFormat.projectPackage:
        return ExportPresetResult.text(
          this,
          ExportService.exportProjectPackage(document),
        );
      case ExportPresetFormat.portablePackage:
        final collector = portableAssetCollector;
        if (collector == null) {
          return ExportPresetResult.bytes(
            this,
            ExportService.exportPortablePackage(
              document,
              assetBytes: assetBytes,
              password: password,
            ),
          );
        }
        return ExportPresetResult.bytes(
          this,
          await ExportService.exportPortablePackageWithAssets(
            document,
            collector: collector,
            assetBytes: assetBytes,
            password: password,
          ),
        );
      case ExportPresetFormat.presentation:
        return ExportPresetResult.text(
          this,
          ExportService.exportPresentationContract(document),
          capability: ExportCapabilityRegistry.presentation,
        );
      case ExportPresetFormat.video:
        return ExportPresetResult.failure(
          this,
          error: ExportCapabilityRegistry.video.reason,
          capability: ExportCapabilityRegistry.video,
        );
      case ExportPresetFormat.svg:
        return ExportPresetResult.text(
          this,
          ExportService.exportVectorSvg(document),
        );
      case ExportPresetFormat.png:
      case ExportPresetFormat.jpeg:
      case ExportPresetFormat.webp:
        if (boundary == null) {
          throw ArgumentError.value(
            boundary,
            'boundary',
            'PNG export requires a RenderRepaintBoundary.',
          );
        }
        final bytes = await ExportService.capturePng(boundary);
        if (bytes == null) return null;
        if (format == ExportPresetFormat.png) {
          return ExportPresetResult.bytes(this, bytes);
        }
        return ExportPresetResult.bytes(
          this,
          encodeRasterExport(bytes, format: format),
        );
      case ExportPresetFormat.markdown:
        return ExportPresetResult.text(
          this,
          ExportService.exportMarkdown(document),
        );
      case ExportPresetFormat.plainText:
        return ExportPresetResult.text(
          this,
          ExportService.exportPlainText(document),
        );
      case ExportPresetFormat.mermaid:
        return ExportPresetResult.text(
          this,
          ExportService.exportMermaid(document),
        );
      case ExportPresetFormat.drawio:
        return ExportPresetResult.text(
          this,
          ExportService.exportDrawioXml(document),
        );
      case ExportPresetFormat.pdf:
        return ExportPresetResult.bytes(
          this,
          ExportService.exportMultiPagePdf(document),
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExportPreset && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ExportPreset($id)';
}

Uint8List encodeRasterExport(
  Uint8List pngBytes, {
  required ExportPresetFormat format,
}) {
  if (format == ExportPresetFormat.png) return pngBytes;
  if (format != ExportPresetFormat.jpeg && format != ExportPresetFormat.webp) {
    throw ArgumentError.value(format, 'format', 'Expected a raster format.');
  }
  final decoded = image.decodePng(pngBytes);
  if (decoded == null) {
    throw StateError('Rendered PNG could not be decoded for export.');
  }
  final encoded = format == ExportPresetFormat.jpeg
      ? image.encodeJpg(decoded, quality: 92)
      : image.encodeWebP(decoded);
  return Uint8List.fromList(encoded);
}

/// Canonical export presets used by the canvas and other integrations.
class ExportPresetRegistry {
  ExportPresetRegistry._();

  static const json = ExportPreset(
    id: 'json',
    label: 'Export JSON',
    extension: 'json',
    mimeType: 'application/json',
    format: ExportPresetFormat.json,
  );
  static const projectPackage = ExportPreset(
    id: 'varian-package',
    label: 'Export Varian Project Package',
    extension: 'varian.json',
    mimeType: 'application/vnd.varian.canvas+json',
    format: ExportPresetFormat.projectPackage,
  );
  static const portablePackage = ExportPreset(
    id: 'varian-archive',
    label: 'Export Portable Varian Archive',
    extension: 'varian',
    mimeType: 'application/vnd.varian.canvas+zip',
    format: ExportPresetFormat.portablePackage,
  );
  static const presentation = ExportPreset(
    id: 'presentation-contract',
    label: 'Export Presentation Contract',
    extension: 'presentation.json',
    mimeType: 'application/vnd.varian.presentation+json',
    format: ExportPresetFormat.presentation,
  );
  static const video = ExportPreset(
    id: 'video',
    label: 'Export Video',
    extension: 'mp4',
    mimeType: 'video/mp4',
    format: ExportPresetFormat.video,
  );
  static const svg = ExportPreset(
    id: 'svg',
    label: 'Export SVG Vector',
    extension: 'svg',
    mimeType: 'image/svg+xml',
    format: ExportPresetFormat.svg,
  );
  static const png = ExportPreset(
    id: 'png',
    label: 'Export PNG Image',
    extension: 'png',
    mimeType: 'image/png',
    format: ExportPresetFormat.png,
  );
  static const jpeg = ExportPreset(
    id: 'jpeg',
    label: 'Export JPEG Image',
    extension: 'jpg',
    mimeType: 'image/jpeg',
    format: ExportPresetFormat.jpeg,
  );
  static const webp = ExportPreset(
    id: 'webp',
    label: 'Export WebP Image',
    extension: 'webp',
    mimeType: 'image/webp',
    format: ExportPresetFormat.webp,
  );
  static const markdown = ExportPreset(
    id: 'markdown',
    label: 'Export Markdown',
    extension: 'md',
    mimeType: 'text/markdown',
    format: ExportPresetFormat.markdown,
  );
  static const plainText = ExportPreset(
    id: 'text',
    label: 'Export Plain Text',
    extension: 'txt',
    mimeType: 'text/plain',
    format: ExportPresetFormat.plainText,
  );
  static const mermaid = ExportPreset(
    id: 'mermaid',
    label: 'Export Mermaid',
    extension: 'mmd',
    mimeType: 'text/vnd.mermaid',
    format: ExportPresetFormat.mermaid,
  );
  static const drawio = ExportPreset(
    id: 'drawio',
    label: 'Export Draw.io XML',
    extension: 'drawio',
    mimeType: 'application/xml',
    format: ExportPresetFormat.drawio,
  );
  static const pdf = ExportPreset(
    id: 'pdf',
    label: 'Export PDF Document',
    extension: 'pdf',
    mimeType: 'application/pdf',
    format: ExportPresetFormat.pdf,
  );

  static const List<ExportPreset> all = [
    svg,
    png,
    jpeg,
    webp,
    markdown,
    plainText,
    mermaid,
    drawio,
    json,
    projectPackage,
    portablePackage,
    presentation,
    video,
    pdf,
  ];

  static ExportPreset? lookup(String id) {
    final normalized = id.trim().toLowerCase();
    for (final preset in all) {
      if (preset.id == normalized) return preset;
    }
    return null;
  }

  static ExportPreset? byFormat(ExportPresetFormat format) {
    for (final preset in all) {
      if (preset.format == format) return preset;
    }
    return null;
  }

  static ExportPreset require(String id) {
    final preset = lookup(id);
    if (preset == null) {
      throw ArgumentError.value(id, 'id', 'Unknown export preset.');
    }
    return preset;
  }
}
