import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/pdf_annotation.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_type.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';
import 'package:varian/features/export/data/export_file_saver.dart';

typedef ExternalFileOpener =
    Future<bool> Function(Uint8List bytes, String fileName);

Future<void> openFilePreview(
  BuildContext context,
  FilePayload payload, {
  ExternalFileOpener? openExternal,
  ValueChanged<PdfAnnotationData>? onAnnotationsChanged,
  TransientFileSourceResolver? sourceResolver,
  FileArtifactStore? fileArtifactStore,
  ArtifactStoreBundle? artifactStoreBundle,
}) async {
  final previewType = classifyFilePreview(payload);
  final resolver =
      sourceResolver ??
      TransientFileSourceResolver(
        fileArtifactStore: fileArtifactStore,
        artifactStoreBundle: artifactStoreBundle,
      );
  if (previewType == FilePreviewType.pdf) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          payload: payload,
          sourceResolver: resolver,
          onAnnotationsChanged: onAnnotationsChanged,
        ),
      ),
    );
    return;
  }
  if (previewType == FilePreviewType.document) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DocumentConversionScreen(
          payload: payload,
          sourceResolver: resolver,
          fileArtifactStore: fileArtifactStore,
          onAnnotationsChanged: onAnnotationsChanged,
        ),
      ),
    );
    return;
  }
  if (previewType != FilePreviewType.external) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FilePreviewScreen(
          payload: payload,
          previewType: previewType,
          sourceResolver: resolver,
          openExternal: openExternal,
        ),
      ),
    );
    return;
  }

  final bytes = await resolver.resolveBytes(payload);
  final opened = bytes != null && bytes.isNotEmpty
      ? await (openExternal ?? _openExternal)(bytes, payload.fileName)
      : false;
  if (!opened && context.mounted) {
    showUiToast(
      context,
      'No usable file source was found.',
      variant: UiToastVariant.error,
    );
  }
}

Future<bool> _openExternal(Uint8List bytes, String fileName) async {
  try {
    final outcome = await ExportFileSaver().save(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/octet-stream',
      dialogTitle: 'Save file',
    );
    return outcome == ExportSaveOutcome.saved;
  } catch (_) {
    return false;
  }
}
