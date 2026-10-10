# High-Fidelity Document Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect Office/ODF files, convert them safely to cached PDFs with LibreOffice, and open them in the existing Acrobat-style PDF viewer.

**Architecture:** Keep `openFilePreview` as the single router. Route documents to a conversion screen backed by a conditional IO service; the IO service resolves bytes, checks a SHA-256 cache, runs LibreOffice headless, validates PDF output, and returns a local PDF payload. Windows packaging consumes a checksum-verified LibreOffice archive supplied by the release environment.

**Tech Stack:** Flutter 3.44.8, Dart 3.12.2, `path_provider`, `path`, `crypto`, `dart:io`, LibreOffice headless, PowerShell, CMake.

**Spec:** `docs/superpowers/specs/2026-08-20-high-fidelity-document-preview-design.md`

## Global Constraints

- Read-only preview; never execute macros or active document content.
- Support DOC, DOCX, RTF, XLS, XLSX, PPT, PPTX, ODT, ODS, and ODP.
- Bundle LibreOffice only in Windows release artifacts; macOS/Linux use system LibreOffice.
- Web/mobile never upload local documents automatically.
- Use process argument lists, isolated temporary directories/profiles, timeout, and PDF signature validation.
- Cache limit is 1 GB and maximum age is 30 days.
- Workspace is not a Git repository; omit commit steps.

---

### Task 1: Document Classification and Routing

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/file_preview/file_preview_type.dart`
- Modify: `lib/features/canvas/presentation/widgets/file_preview/file_preview_router.dart`
- Test: `test/features/file_card/file_preview_type_test.dart`
- Test: `test/features/file_card/file_preview_router_test.dart`

**Interfaces:**
- Consumes: `FilePayload`, `normalizedFileExtension`, `FilePreviewType.document`.
- Produces: all ten formats classified as `document`; document routes construct `DocumentConversionScreen(payload: payload)`.

- [ ] Add table-driven failing tests for `doc`, `docx`, `rtf`, `xls`, `xlsx`, `ppt`, `pptx`, `odt`, `ods`, and `odp`, including uppercase and filename inference.
- [ ] Add a failing router widget test asserting DOCX opens `DocumentConversionScreen`, not `FilePreviewScreen` or OS fallback.
- [ ] Run `flutter test test/features/file_card/file_preview_type_test.dart test/features/file_card/file_preview_router_test.dart` and confirm failure for missing routing/screen.
- [ ] Expand `_documentExtensions` and add the router branch before generic preview routing.
- [ ] Run the same tests and confirm pass.

### Task 2: Conversion Models, Cache, and Source Resolution

**Files:**
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart`
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_cache.dart`
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_source_resolver.dart`
- Modify: `pubspec.yaml`
- Test: `test/features/file_card/document_conversion_cache_test.dart`
- Test: `test/features/file_card/document_source_resolver_test.dart`

**Interfaces:**
- Produces: `DocumentConversionResult`, `DocumentConversionFailure`, `ResolvedDocumentSource`, `DocumentPreviewCache`, and `resolveDocumentSource(FilePayload payload)`.
- `DocumentConversionResult` contains `String pdfPath` and `bool fromCache`.
- Cache key is `sha256(bytes + normalized extension + 'document-preview-v1')`.

- [ ] Add `crypto` as a direct dependency with `flutter pub add crypto`.
- [ ] Write failing resolver tests for valid base64 precedence, malformed base64 fallback to local bytes, remote HTTP(S) fallback, invalid URL, missing source, unsupported extension, and maximum-size rejection.
- [ ] Write failing cache tests for stable hash, `%PDF-` validation, cache hit, 30-day expiry, and LRU eviction under an injected small size limit.
- [ ] Run both test files and confirm missing symbols fail.
- [ ] Implement immutable result/failure/source models with typed failure codes.
- [ ] Implement source resolution using injectable local-reader and HTTP-reader callbacks so tests do not perform network IO.
- [ ] Implement cache read/write metadata, atomic temporary-file rename, hit access-time update, expiry, and LRU cleanup.
- [ ] Run both test files and confirm pass.

### Task 3: LibreOffice Conversion Service

**Files:**
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_service.dart`
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_service_io.dart`
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_service_stub.dart`
- Test: `test/features/file_card/document_conversion_service_test.dart`

**Interfaces:**
- Produces: `abstract interface class DocumentConversionService { Future<DocumentConversionResult> convertToPdf(FilePayload payload); }` and `createDocumentConversionService()`.
- IO implementation accepts injected source resolver, cache, executable locator, process runner, temp-directory factory, and `Duration timeout`.

- [ ] Write failing tests for Windows bundled executable discovery, macOS/Linux executable names, exact headless argument list, cache short-circuit, successful `%PDF-` output, non-zero exit, timeout, missing output, invalid output, and temporary-directory cleanup.
- [ ] Run the service test and confirm missing symbols fail.
- [ ] Implement conditional export: stub returns `unsupportedPlatform`; IO performs resolution, cache lookup, unique working/profile directories, `Process.start` with argument list, timeout/kill, output validation, cache store, and cleanup in `finally`.
- [ ] Use these LibreOffice arguments: `--headless`, `--nologo`, `--nodefault`, `--nolockcheck`, `--norestore`, `--nofirststartwizard`, `-env:UserInstallation=file:///<encoded-profile-path>`, `--convert-to`, `pdf`, `--outdir`, `<output-dir>`, `<input-file>`.
- [ ] Run the service test and confirm pass.

### Task 4: Conversion Screen and PDF Transition

**Files:**
- Create: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_screen.dart`
- Modify: `lib/features/canvas/presentation/widgets/file_preview/file_preview_router.dart`
- Test: `test/features/file_card/document_conversion_screen_test.dart`
- Test: `test/features/file_card/file_preview_router_test.dart`

**Interfaces:**
- Produces: `DocumentConversionScreen({required FilePayload payload, DocumentConversionService? service, ExternalFileOpener? openExternal})`.
- Success creates a new `FilePayload(fileName: '<stem>.pdf', fileExtension: 'pdf', fileSizeText: original.fileSizeText, localPath: result.pdfPath)` and replaces the route with `PdfViewerScreen`.

- [ ] Write failing widget tests for converting progress, cached success transition, retry after failure, unsupported platform, external fallback, and web-viewer disclosure only for valid public HTTP(S) URLs.
- [ ] Run screen/router tests and confirm failure.
- [ ] Implement lifecycle-safe async conversion, progress copy, retry, back/cancel, and error actions.
- [ ] Use `Navigator.pushReplacement` to open `PdfViewerScreen` with a fresh PDF-only payload; do not retain Office base64 or URL.
- [ ] Update router injection seam so tests can provide a fake service.
- [ ] Run screen/router tests and confirm pass.

### Task 5: Windows LibreOffice Packaging

**Files:**
- Create: `tool/package_libreoffice_windows.ps1`
- Create: `windows/libreoffice.cmake`
- Modify: `windows/CMakeLists.txt`

**Interfaces:**
- Consumes environment/build inputs `LIBREOFFICE_ARCHIVE` and `LIBREOFFICE_SHA256`.
- Produces staged runtime at `windows/libreoffice/runtime/program/soffice.exe`, licenses under `windows/libreoffice/runtime/licenses/`, and installed bundle path `libreoffice/program/soffice.exe`.

- [ ] Implement PowerShell validation: require both inputs, verify archive exists, compare `Get-FileHash -Algorithm SHA256`, extract into a clean staging directory, locate `program/soffice.exe`, require license/notices, run `soffice.exe --version`, and fail on any mismatch.
- [ ] Implement CMake install rules that fail release configuration when staged runtime is absent and copy runtime into `${INSTALL_BUNDLE_DATA_DIR}/../libreoffice`.
- [ ] Include `windows/libreoffice.cmake` from the non-generated root `windows/CMakeLists.txt`.
- [ ] Run the packaging script against an intentionally wrong checksum and confirm non-zero exit.
- [ ] If controlled LibreOffice archive/checksum inputs are available, run successful staging and `flutter build windows`; otherwise report packaging verification blocked by missing release input without inventing a download URL.

### Task 6: Final Verification

**Files:**
- Verify all files above.

**Interfaces:**
- Produces analyzer-clean, test-passing source and a packaging verification result.

- [ ] Run `dart format lib/features/canvas/presentation/widgets/document_conversion lib/features/canvas/presentation/widgets/file_preview test/features/file_card`.
- [ ] Run `flutter analyze` and require `No issues found!`.
- [ ] Run `flutter test` and require all tests pass.
- [ ] Run `flutter build windows` when the bundled runtime has been staged.
- [ ] Smoke-convert one DOCX, XLSX, PPTX, ODT, ODS, and ODP fixture when LibreOffice is available; validate every output starts with `%PDF-`.
- [ ] Record any environment-only blocker precisely; do not claim Windows bundling complete without checksum-verified runtime evidence.
