import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/assets/data/asset_service.dart';

String _testKey() => 'test-key';

Future<void> _authenticate(SupabaseClient client, String userId) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': userId, 'exp': expiration})}.signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

final class _FakePlatformFile extends PlatformFile {
  final String fileName;
  final Uint8List fileBytes;

  _FakePlatformFile(this.fileName, this.fileBytes);

  @override
  String get name => fileName;

  @override
  Uri get uri => Uri.parse('file:///tmp/$fileName');

  @override
  XFile get xFile => XFile.fromData(fileBytes, name: fileName);

  @override
  Future<int> length() async => fileBytes.length;

  @override
  int lengthSync() => fileBytes.length;

  @override
  Future<Uint8List> readAsBytes() async => fileBytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(fileBytes);
}

final class _FakePickerPlatform extends FilePickerPlatform {
  bool usedMultiPicker = false;
  Future<void> Function()? beforePick;
  String fileName = 'one.png';
  Uint8List fileBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    usedMultiPicker = true;
    await beforePick?.call();
    if (type == FileType.custom && allowedExtensions?.contains('png') != true) {
      return [_FakePlatformFile(fileName, fileBytes)];
    }
    return [
      _FakePlatformFile('one.png', fileBytes),
      _FakePlatformFile('two.png', fileBytes),
    ];
  }
}

void main() {
  test(
    'bounds streamed PlatformFile reads before allocating the result',
    () async {
      final file = _FakePlatformFile(
        'payload.bin',
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      expect(
        await readPlatformFileBytes(file, maxBytes: 4),
        orderedEquals(<int>[1, 2, 3, 4]),
      );
      expect(await readPlatformFileBytes(file, maxBytes: 3), isNull);
    },
  );

  test('detects MIME from the explicit extension and formats previews', () {
    final result = AssetPickerResult(
      name: 'thumbnail',
      extension: 'PNG',
      bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
    );

    expect(result.detectedMimeType, 'image/png');
    expect(result.previewUrl, startsWith('data:image/png;base64,'));
  });

  test('validates common magic bytes before storage upload', () {
    expect(
      assetBytesMatchMimeSignature(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        'image/png',
      ),
      isTrue,
    );
    expect(
      assetBytesMatchMimeSignature(
        Uint8List.fromList([1, 2, 3, 4]),
        'image/png',
      ),
      isFalse,
    );
    expect(
      assetBytesMatchMimeSignature(
        Uint8List.fromList([1, 2, 3, 4]),
        'application/octet-stream',
      ),
      isTrue,
    );
    expect(
      assetBytesMatchMimeSignature(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        'IMAGE/PNG',
      ),
      isTrue,
    );
  });

  test('does not treat file URI syntax as a durable local path', () {
    final result = AssetPickerResult(
      name: 'image.png',
      path: 'file:/tmp/image.png',
    );

    expect(result.durableReference, isNull);
  });

  test(
    'rejects unmanaged Storage namespaces before opening the picker',
    () async {
      await expectLater(
        AssetService().pickAnyFiles(
          projectId: 'project-1',
          storageFolder: 'collaboration',
        ),
        throwsArgumentError,
      );
      await expectLater(
        AssetService().pickAnyFiles(
          projectId: 'project-1',
          storageFolder: ' library',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'keeps local asset bytes and skips upload when project ownership fails',
    () async {
      final previous = FilePickerPlatform.instance;
      final fake = _FakePickerPlatform();
      FilePickerPlatform.instance = fake;
      addTearDown(() => FilePickerPlatform.instance = previous);
      var uploadRequests = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith('/storage/v1/object/')) {
            uploadRequests++;
            fail('Asset upload must not occur before ownership verification.');
          }
          expect(request.method, 'GET');
          expect(request.url.path, '/rest/v1/projects');
          expect(request.url.queryParameters['id'], 'eq.project-1');
          expect(request.url.queryParameters['select'], 'owner_id');
          return http.Response(
            jsonEncode({'owner_id': 'another-account'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'asset-user');

      final results = await AssetService(
        SupabaseSyncService(client),
      ).pickImages(projectId: 'project-1');

      expect(results, hasLength(2));
      expect(results.every((result) => result.bytes!.isNotEmpty), isTrue);
      expect(results.every((result) => result.storagePath == null), isTrue);
      expect(
        results.every(
          (result) =>
              result.errorMessage!.contains('ownership could not be verified'),
        ),
        isTrue,
      );
      expect(uploadRequests, 0);
    },
  );

  test('uses the native multi-file picker for library batches', () async {
    final previous = FilePickerPlatform.instance;
    final fake = _FakePickerPlatform();
    FilePickerPlatform.instance = fake;
    addTearDown(() => FilePickerPlatform.instance = previous);

    final progress = <(int, int)>[];
    final results = await AssetService().pickImages(
      projectId: 'project-1',
      onProgress: (completed, total) => progress.add((completed, total)),
    );

    expect(fake.usedMultiPicker, isTrue);
    expect(results, hasLength(2));
    expect(results.every((result) => result.errorMessage == null), isTrue);
    expect(progress, [(1, 2), (2, 2)]);
  });
}
