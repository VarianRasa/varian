# Design Spec: High-Fidelity Office and OpenDocument Preview

## 1. Overview

Upgrade File Card document preview from extracted text into a read-only, page-accurate viewer for Microsoft Office and OpenDocument files. The system detects the file format automatically, converts supported documents to PDF through LibreOffice, caches the result, and opens the existing Acrobat-style `PdfViewerScreen` on double-click or **Open / Preview**.

Supported conversion formats:

- Microsoft Word: DOC, DOCX, RTF
- Microsoft Excel: XLS, XLSX
- Microsoft PowerPoint: PPT, PPTX
- OpenDocument: ODT, ODS, ODP

PDF remains routed directly to `PdfViewerScreen`. Images, text, audio, video, HTML, archives, and unknown files retain their existing preview or external fallback behavior.

## 2. Platform Strategy

### 2.1 Windows

Bundle a portable, redistributable LibreOffice runtime with the application. The app discovers it relative to the executable and invokes it without requiring a system installation.

The bundle must include its license and notices. Packaging scripts must copy the LibreOffice runtime into the Windows release artifact. The runtime is not stored as source code in Dart files.

### 2.2 macOS and Linux

Use a system-installed LibreOffice executable. Search standard executable names and locations. If unavailable, show a clear installation-required state and retain external/web fallback actions.

### 2.3 Web, Android, and iOS

Local LibreOffice execution is unavailable. If the payload has a valid public HTTP(S) `remoteUrl`, offer a web document viewer. If no usable remote URL exists, show metadata and an external/download action.

Documents are never uploaded automatically by the client. A future private conversion service is outside this scope.

## 3. Architecture

### 3.1 File Classification

Extend file classification with a high-fidelity document conversion category covering DOC/DOCX/RTF, XLS/XLSX, PPT/PPTX, and ODT/ODS/ODP. Classification uses normalized extension from `fileExtension`, falling back to `fileName`.

`openFilePreview` remains the single entry point used by Canvas double-click and Inspector **Open / Preview**.

Routing order:

1. PDF opens directly in `PdfViewerScreen`.
2. Convertible document opens `DocumentConversionScreen`.
3. Existing generic preview types open `FilePreviewScreen`.
4. Unsupported formats use external fallback.

### 3.2 Conversion Service

Create a platform-neutral interface:

```dart
abstract interface class DocumentConversionService {
  Future<DocumentConversionResult> convertToPdf(FilePayload payload);
}
```

The IO implementation performs:

1. Resolve source in order: valid `base64Data`, readable `localPath`, then downloaded `remoteUrl`.
2. Validate source size and extension before execution.
3. Compute SHA-256 from source bytes plus conversion schema version.
4. Return a valid cached PDF when present.
5. Write source bytes to a unique temporary working directory.
6. Invoke LibreOffice headless with a dedicated temporary user profile and PDF export.
7. Enforce a conversion timeout.
8. Validate process exit code and generated PDF signature.
9. Atomically move the PDF and metadata into cache.
10. Delete the temporary working directory in `finally`.

The Web implementation cannot convert locally and returns a typed unsupported-platform result.

### 3.3 Process Isolation and Safety

LibreOffice receives arguments as a process argument list, never through a shell command string. User-controlled filenames are not interpolated into commands.

Each conversion uses:

- A unique input/output directory.
- A unique LibreOffice user profile.
- Headless, no-first-start, no-restore flags.
- A configurable hard timeout with process termination.
- A maximum input file size.
- No macro execution or editing capability.

Conversion errors expose user-safe messages. Raw process output is available only to diagnostics and must not include document contents.

## 4. Automatic Cache

Use the application cache directory under `document-preview-v1/`.

Each entry contains:

- `<hash>.pdf`
- `<hash>.json` metadata with source extension, source size, created time, last-access time, PDF size, and converter version

Cache behavior:

- Key: SHA-256 of source bytes, normalized extension, and converter schema version.
- Validate `%PDF-` signature and non-zero file size before reuse.
- Update last-access metadata on cache hit.
- Default limits: 1 GB total and 30 days maximum age.
- Evict expired entries first, then least recently used entries until below the size limit.
- Failed or partial conversions never enter the cache.

Cache settings are internal constants for this release. User-configurable cache settings are deferred.

## 5. Document Conversion Screen

`DocumentConversionScreen` owns conversion progress and transition into the PDF viewer.

States:

1. **Resolving source**
2. **Checking cache**
3. **Converting document**
4. **Opening preview**
5. **Error / unsupported platform**

The screen displays file metadata, progress state, cancel/back action, retry, web viewer when available, and external-open fallback. On success it replaces itself with `PdfViewerScreen` using the converted local PDF source, avoiding an extra back-navigation layer.

The resulting document uses all existing PDF viewer features: page rendering, thumbnails/outline where available, search, zoom, page navigation, rotation, fullscreen, selection, drawing/highlighting, notes, and external/download actions. Document editing and saving back to the original Office/ODF file are not supported.

## 6. Web Viewer Fallback

A valid public HTTP(S) `remoteUrl` may be opened through an approved Office-compatible web viewer. The UI must disclose that the document URL is sent to a third-party viewer before opening it.

Local files and base64-only documents cannot use the web viewer because they do not have a public URL. They retain download/external actions.

The initial implementation uses local conversion whenever supported. Web viewing is a fallback, not the default.

## 7. LibreOffice Distribution

Windows release packaging must:

1. Download or consume a pinned LibreOffice portable runtime from a controlled build input.
2. Verify its checksum.
3. Place it at the path expected by runtime discovery.
4. Include LibreOffice license and third-party notices.
5. Verify `soffice --version` during packaging.
6. Run a smoke conversion for DOCX, XLSX, PPTX, ODT, ODS, and ODP.

The exact LibreOffice version and checksum belong in the packaging configuration, not application logic. Updating LibreOffice requires rebuilding the Windows release and rerunning the conversion corpus.

## 8. Error Handling

Typed failures cover:

- Missing or invalid source
- Unsupported extension
- LibreOffice unavailable
- Conversion timeout
- Converter process failure
- Invalid or missing PDF output
- Cache read/write failure
- Unsupported platform
- Invalid web viewer URL

Cache failures do not block preview: conversion may continue without caching. Converter failures show retry, web viewer when eligible, and external-open fallback. No failure may crash the canvas.

## 9. Testing

### 9.1 Unit Tests

- Extension classification for every supported Office/ODF format and uppercase/name-inferred variants.
- Source resolution precedence and malformed source fallback.
- Stable cache hash generation and cache validation.
- Age and LRU eviction.
- Process argument construction without shell interpolation.
- Timeout, non-zero exit, missing output, and invalid PDF handling.

### 9.2 Widget and Router Tests

- Double-click/router sends every supported document format to `DocumentConversionScreen`.
- Cached conversion replaces the conversion screen with `PdfViewerScreen`.
- Conversion progress and failure states expose retry and fallback actions.
- Web/mobile unsupported state offers web viewer only for valid HTTP(S) remote URLs.

### 9.3 Integration and Packaging Tests

Use a small checked-in fixture corpus for DOCX, XLSX, PPTX, ODT, ODS, and ODP. Verify each converts to a valid PDF and opens in the PDF viewer. Windows packaging CI verifies the bundled executable and smoke conversions.

Final verification runs `dart format`, `flutter analyze`, `flutter test`, Windows build, and the LibreOffice conversion corpus.

## 10. Explicit Non-Goals

- Editing Office/ODF content.
- Saving PDF annotations back into Office/ODF files.
- Pixel-identical output for fonts unavailable to LibreOffice.
- Macro execution, embedded application execution, or active content.
- Bundling LibreOffice on macOS or Linux.
- Uploading private local documents to a conversion server.
