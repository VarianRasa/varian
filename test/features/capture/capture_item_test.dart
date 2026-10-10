import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/capture/domain/capture_item.dart';

void main() {
  test('classifies an HTTPS value as a link', () {
    final input = CaptureInput.text('https://example.com/design');
    expect(input.kind, CaptureKind.link);
    expect(input.text, 'https://example.com/design');
  });

  test('keeps ordinary text as text', () {
    final input = CaptureInput.text('A loose idea for the next board');
    expect(input.kind, CaptureKind.text);
  });

  test('round trips optional fields and defaults missing fields', () {
    final item = CaptureItem(
      id: 'capture-1',
      kind: CaptureKind.link,
      createdAt: DateTime(2026, 8, 27, 10),
      updatedAt: DateTime(2026, 8, 27, 10),
      title: 'Idea',
      text: 'Build a visual journal',
      sourceUri: 'https://example.com/reference',
      assetId: 'capture-asset://one',
      mimeType: 'text/plain',
      extension: 'txt',
      byteSize: 12,
      thumbnailRef: 'capture-asset://thumbnail',
      extractedText: 'Extracted reference',
      linkMetadata: CaptureLinkMetadata(
        title: 'Example',
        description: 'Reference page',
        siteName: 'Example',
        imageRef: 'capture-asset://image',
        mediaType: 'text/html',
      ),
      status: CaptureStatus.syncPending,
      syncState: CaptureSyncState.pending,
      origin: CaptureOrigin.clipboard,
      isRead: true,
      isFavorite: true,
      syncErrorCode: 'CAPTURE_SYNC_ERROR',
    );
    final restored = CaptureItem.fromJson(item.toJson());
    expect(restored.id, item.id);
    expect(restored.kind, item.kind);
    expect(restored.createdAt, item.createdAt);
    expect(restored.updatedAt, item.updatedAt);
    expect(restored.title, item.title);
    expect(restored.text, item.text);
    expect(restored.sourceUri, item.sourceUri);
    expect(restored.assetId, item.assetId);
    expect(restored.mimeType, item.mimeType);
    expect(restored.extension, item.extension);
    expect(restored.byteSize, item.byteSize);
    expect(restored.thumbnailRef, item.thumbnailRef);
    expect(restored.extractedText, item.extractedText);
    expect(restored.linkMetadata?.title, item.linkMetadata?.title);
    expect(restored.linkMetadata?.description, item.linkMetadata?.description);
    expect(restored.linkMetadata?.siteName, item.linkMetadata?.siteName);
    expect(restored.linkMetadata?.imageRef, item.linkMetadata?.imageRef);
    expect(restored.linkMetadata?.mediaType, item.linkMetadata?.mediaType);
    expect(restored.status, item.status);
    expect(restored.syncState, item.syncState);
    expect(restored.origin, CaptureOrigin.clipboard);
    expect(restored.isRead, item.isRead);
    expect(restored.isFavorite, item.isFavorite);
    expect(restored.syncErrorCode, item.syncErrorCode);

    final legacy = CaptureItem.fromJson({
      'id': 'legacy',
      'kind': 'text',
      'createdAt': '2026-08-27T10:00:00.000',
      'updatedAt': '2026-08-27T10:00:00.000',
    });
    expect(legacy.status, CaptureStatus.ready);
    expect(legacy.syncState, CaptureSyncState.localOnly);
    expect(legacy.isRead, isFalse);
    expect(legacy.isFavorite, isFalse);
  });

  test('rejects empty text and malformed HTTP input with exact codes', () {
    expect(
      () => CaptureInput.text('  '),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_EMPTY',
        ),
      ),
    );
    expect(
      () => CaptureInput.text('https://'),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_INVALID_URL',
        ),
      ),
    );
  });

  test('enforces the exact 50 MiB file boundary and rejects blank MIME', () {
    final input = CaptureInput.file(
      name: 'reference.png',
      path: r'C:\Users\private\fixture.pdf',
      bytes: Uint8List(50 * 1024 * 1024),
      mimeType: 'image/png',
    );
    expect(input.path, r'C:\Users\private\fixture.pdf');
    expect(input.byteSize, 50 * 1024 * 1024);
    expect(input.kind, CaptureKind.image);

    expect(
      () => CaptureInput.file(
        name: 'reference.png',
        bytes: Uint8List(50 * 1024 * 1024 + 1),
        mimeType: 'image/png',
      ),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
    for (final input in [
      () => CaptureInput.file(
        name: '',
        bytes: Uint8List(1),
        mimeType: 'image/png',
      ),
      () => CaptureInput.file(
        name: 'reference.png',
        bytes: Uint8List(0),
        mimeType: 'image/png',
      ),
      () => CaptureInput.file(
        name: 'reference.png',
        bytes: Uint8List(1),
        mimeType: '  ',
      ),
    ]) {
      expect(
        input,
        throwsA(
          isA<CaptureFailure>().having(
            (failure) => failure.code,
            'code',
            'CAPTURE_EMPTY',
          ),
        ),
      );
    }
  });

  test('bounds captured text by UTF-8 bytes', () {
    final boundary = 'é' * (256 * 1024 ~/ 2);
    expect(utf8.encode(boundary).length, 256 * 1024);
    expect(CaptureInput.text(boundary).text, boundary);
    expect(
      () => CaptureInput.text('${boundary}a'),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
    expect(
      () => CaptureInput.text('Text', title: '${boundary}a'),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
  });

  test('bounds title and link metadata strings by UTF-8 bytes', () {
    final value = 'é' * (256 * 1024 ~/ 2);
    final item = CaptureItem(
      id: 'capture-1',
      kind: CaptureKind.link,
      createdAt: DateTime(2026, 8, 27, 10),
      updatedAt: DateTime(2026, 8, 27, 10),
      title: value,
      sourceUri: 'https://example.com',
      extractedText: value,
      linkMetadata: CaptureLinkMetadata(
        title: value,
        description: value,
        siteName: value,
        imageRef: value,
        mediaType: value,
      ),
    );
    expect(item.toJson()['title'], value);
    expect(item.toJson()['extractedText'], value);
    expect(
      (item.toJson()['linkMetadata'] as Map<String, dynamic>)['mediaType'],
      value,
    );
    expect(
      () => CaptureItem(
        id: 'capture-2',
        kind: CaptureKind.text,
        createdAt: DateTime(2026, 8, 27, 10),
        updatedAt: DateTime(2026, 8, 27, 10),
        title: '${value}a',
      ),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
    expect(
      () => CaptureItem(
        id: 'capture-3',
        kind: CaptureKind.text,
        createdAt: DateTime(2026, 8, 27, 10),
        updatedAt: DateTime(2026, 8, 27, 10),
        extractedText: '${value}a',
      ),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
    expect(
      () => CaptureLinkMetadata(description: '${value}a'),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_SIZE_LIMIT',
        ),
      ),
    );
  });

  test('excludes transient paths and validates persisted source URIs', () {
    final item = CaptureItem(
      id: 'capture-1',
      kind: CaptureKind.file,
      createdAt: DateTime(2026, 8, 27, 10),
      updatedAt: DateTime(2026, 8, 27, 10),
      sourceUri: 'https://example.com/file.pdf',
      assetId: 'capture-asset://one',
    );
    final json = item.toJson();
    expect(json.containsKey('path'), isFalse);
    expect(json.containsValue(r'C:\Users\private\fixture.pdf'), isFalse);
    expect(CaptureItem.fromJson(json).sourceUri, item.sourceUri);

    for (final sourceUri in [
      'file:///private/fixture.pdf',
      'https://user:pass@example.com/file.pdf',
      'http://127.0.0.1/file.pdf',
    ]) {
      expect(
        () => CaptureItem(
          id: 'capture-2',
          kind: CaptureKind.file,
          createdAt: DateTime(2026, 8, 27, 10),
          updatedAt: DateTime(2026, 8, 27, 10),
          sourceUri: sourceUri,
        ),
        throwsA(
          isA<CaptureFailure>().having(
            (failure) => failure.code,
            'code',
            'CAPTURE_INVALID_URL',
          ),
        ),
      );
    }
  });

  test('enforces byteSize invariants and maps malformed stored data', () {
    final base = {
      'id': 'capture-1',
      'kind': 'file',
      'createdAt': '2026-08-27T10:00:00.000',
      'updatedAt': '2026-08-27T10:00:00.000',
    };
    expect(
      () => CaptureItem(
        id: 'capture-2',
        kind: CaptureKind.file,
        createdAt: DateTime(2026, 8, 27, 10),
        updatedAt: DateTime(2026, 8, 27, 10),
        byteSize: -1,
      ),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
    expect(
      () => CaptureItem.fromJson({...base, 'byteSize': 50 * 1024 * 1024 + 1}),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
    expect(
      () => CaptureItem.fromJson({...base, 'byteSize': 'not-a-number'}),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
    expect(
      () => CaptureItem.fromJson({...base, 'createdAt': 'not-a-date'}),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
    expect(
      () => CaptureItem.fromJson({...base, 'kind': 'unknown'}),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
    expect(
      () => CaptureItem.fromJson({
        ...base,
        'sourceUri': 'https://user:pass@example.com/private',
      }),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_INVALID_URL',
        ),
      ),
    );
  });

  test('copyWith clears nullable fields with clear flags', () {
    final item = CaptureItem(
      id: 'capture-1',
      kind: CaptureKind.link,
      createdAt: DateTime(2026, 8, 27, 10),
      updatedAt: DateTime(2026, 8, 27, 10),
      title: 'Title',
      text: 'Text',
      sourceUri: 'https://example.com',
      linkMetadata: CaptureLinkMetadata(title: 'Link'),
      syncErrorCode: 'CAPTURE_SYNC_ERROR',
    );
    final cleared = item.copyWith(
      clearTitle: true,
      clearText: true,
      clearSourceUri: true,
      clearLinkMetadata: true,
      clearSyncErrorCode: true,
    );
    expect(cleared.title, isNull);
    expect(cleared.text, isNull);
    expect(cleared.sourceUri, isNull);
    expect(cleared.linkMetadata, isNull);
    expect(cleared.syncErrorCode, isNull);
  });

  test('rejects malformed metadata with exact storage error code', () {
    expect(
      () => CaptureItem.fromJson({
        'id': 'capture-1',
        'kind': 'text',
        'createdAt': '2026-08-27T10:00:00.000',
        'updatedAt': '2026-08-27T10:00:00.000',
        'linkMetadata': 'not-a-map',
      }),
      throwsA(
        isA<CaptureFailure>().having(
          (failure) => failure.code,
          'code',
          'CAPTURE_STORAGE_ERROR',
        ),
      ),
    );
  });
}
