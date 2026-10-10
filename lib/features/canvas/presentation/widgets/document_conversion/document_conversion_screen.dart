import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/pdf_annotation.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_service.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';

class DocumentConversionScreen extends StatefulWidget {
  const DocumentConversionScreen({
    super.key,
    required this.payload,
    this.service,
    this.sourceResolver = const TransientFileSourceResolver(),
    this.fileArtifactStore,
    this.onAnnotationsChanged,
  });

  final FilePayload payload;
  final DocumentConversionService? service;
  final TransientFileSourceResolver sourceResolver;
  final FileArtifactStore? fileArtifactStore;
  final ValueChanged<PdfAnnotationData>? onAnnotationsChanged;

  @override
  State<DocumentConversionScreen> createState() =>
      _DocumentConversionScreenState();
}

class _DocumentConversionScreenState extends State<DocumentConversionScreen> {
  String _status = 'Preparing document preview…';
  DocumentConversionFailure? _failure;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  Future<void> _convert() async {
    setState(() {
      _failure = null;
      _status = 'Converting document with LibreOffice…';
    });
    try {
      final result = await (widget.service ?? createDocumentConversionService())
          .convertToPdf(widget.payload, sourceResolver: widget.sourceResolver);
      if (!mounted) return;
      final name = widget.payload.fileName;
      final dot = name.lastIndexOf('.');
      final pdfName = '${dot > 0 ? name.substring(0, dot) : name}.pdf';
      final store =
          widget.fileArtifactStore ??
          widget.sourceResolver.fileArtifactStore ??
          createFileArtifactStore();
      final artifact = await store.save(result.pdfBytes, fileName: pdfName);
      final artifactReference = validFileArtifactReference(artifact.reference);
      if (artifactReference == null) {
        throw const DocumentConversionFailure(
          DocumentConversionFailureCode.invalidPdf,
          'The converted PDF could not be stored.',
        );
      }
      if (!mounted) return;
      final previewResolver = widget.sourceResolver.fileArtifactStore == store
          ? widget.sourceResolver
          : TransientFileSourceResolver(
              storageResolver: widget.sourceResolver.storageResolver,
              projectId: widget.sourceResolver.projectId,
              expectedUserId: widget.sourceResolver.expectedUserId,
              storageReader: widget.sourceResolver.storageReader,
              httpClient: widget.sourceResolver.httpClient,
              fileArtifactStore: store,
              artifactStoreBundle: widget.sourceResolver.artifactStoreBundle,
            );
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            payload: FilePayload(
              fileName: pdfName,
              fileExtension: 'pdf',
              fileSizeText: widget.payload.fileSizeText,
              artifactReference: artifactReference,
              pdfAnnotations: widget.payload.pdfAnnotations,
            ),
            sourceResolver: previewResolver,
            onAnnotationsChanged: widget.onAnnotationsChanged,
          ),
        ),
      );
    } on DocumentConversionFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } catch (_) {
      if (mounted) {
        setState(
          () => _failure = const DocumentConversionFailure(
            DocumentConversionFailureCode.processFailure,
            'The document could not be converted.',
          ),
        );
      }
    }
  }

  Future<void> _openExternal() async {
    final bytes = await widget.sourceResolver.resolveBytes(widget.payload);
    if (bytes == null || bytes.isEmpty) return;
    await ExportFileSaver().save(
      fileName: widget.payload.fileName,
      bytes: bytes,
      mimeType: 'application/octet-stream',
      dialogTitle: 'Save document',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiPageScaffold(
      title: Text(widget.payload.fileName),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.page * 2),
          child: _failure == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const UiProgressIndicator(
                      semanticsLabel: 'Converting document',
                    ),
                    const SizedBox(height: AppSpacing.pageWide),
                    Text(_status),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 64,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Document preview unavailable',
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(_failure!.message, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.pageWide),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        UiButton(
                          onPressed: _convert,
                          prefix: const Icon(Icons.refresh),
                          child: const Text('RETRY'),
                        ),
                        UiButton(
                          onPressed: _openExternal,
                          variant: UiButtonVariant.outline,
                          prefix: const Icon(Icons.open_in_new),
                          child: const Text('OPEN EXTERNALLY'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
