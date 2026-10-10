import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'comfy_ui_setup_contract.dart';
import 'video_provider.dart';

ComfyUiSetupService createComfyUiSetupService() =>
    _WindowsComfyUiSetupService();

class _WindowsComfyUiSetupService implements ComfyUiSetupService {
  static const _allowedHosts = {
    'github.com',
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
    'huggingface.co',
    'cdn-lfs.huggingface.co',
    'cdn-lfs.hf.co',
    'cdn-lfs-us-1.hf.co',
    'cdn-lfs-eu-1.hf.co',
    'us.aws.cdn.hf.co',
    'eu.aws.cdn.hf.co',
    'cas-bridge.xethub.hf.co',
  };
  static const _markerName = '.varian-comfyui-install.json';
  static const _maxArchiveOutputBytes = 8 * 1024 * 1024;

  @override
  Future<String> defaultInstallationPath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'comfyui-runtime');
  }

  @override
  Future<void> install({
    required String destination,
    required bool confirmed,
    ComfyUiSetupCancellation? cancellation,
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'ComfyUI setup is supported only on Windows.',
      );
    }
    if (!confirmed) {
      throw const VideoProviderException(
        'VIDEO_SETUP_CONFIRMATION_REQUIRED',
        'ComfyUI setup requires explicit confirmation before downloading assets.',
      );
    }
    final cancellationToken = cancellation ?? ComfyUiSetupCancellation();
    _throwIfAlreadyCancelled(cancellationToken);
    final installPath = _normalizeDestination(destination);
    final existingType = await FileSystemEntity.type(
      installPath,
      followLinks: false,
    );
    if (existingType != FileSystemEntityType.notFound) {
      if (existingType == FileSystemEntityType.directory &&
          await _isCompleteInstall(Directory(installPath))) {
        return;
      }
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The selected ComfyUI destination already exists. Choose an empty destination or remove it manually.',
      );
    }
    _throwIfAlreadyCancelled(cancellationToken);
    await _checkDiskSpace(installPath);
    _validateManifest();
    final work = Directory(
      p.join(
        p.dirname(installPath),
        '.varian-comfyui-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      ),
    );
    final downloads = Directory(p.join(work.path, 'downloads'));
    final extracted = Directory(p.join(work.path, 'extracted'));
    await work.create(recursive: true);
    var progressBytes = 0;
    final totalBytes = comfyUiSetupManifest.totalDownloadBytes;
    void reportProgress() {
      onProgress?.call(
        totalBytes == 0 ? 1 : (progressBytes / totalBytes).clamp(0, 1),
      );
    }

    final client = http.Client();
    try {
      await downloads.create(recursive: true);
      await extracted.create(recursive: true);
      reportProgress();
      _throwIfCancelled(cancellationToken);

      final archiveAsset = _asset('comfyui-portable-nvidia');
      final archive = File(p.join(downloads.path, archiveAsset.fileName));
      await _download(
        client,
        archiveAsset,
        archive,
        onBytes: (count) {
          progressBytes += count;
          reportProgress();
        },
        cancellation: cancellationToken,
      );
      _throwIfCancelled(cancellationToken);
      await _extractArchive(archive, extracted, cancellationToken);
      await _rejectExtractedLinks(extracted);
      final sourceRoot = await _findComfyUiRoot(extracted);
      final comfyUiRoot = _applicationRoot(sourceRoot);

      for (final asset in comfyUiSetupManifest.assets) {
        if (asset.isBundled || asset.id == archiveAsset.id) continue;
        _throwIfCancelled(cancellationToken);
        final downloaded = File(p.join(downloads.path, asset.fileName));
        await _download(
          client,
          asset,
          downloaded,
          onBytes: (count) {
            progressBytes += count;
            reportProgress();
          },
          cancellation: cancellationToken,
        );
        final destinationFile = _safeJoin(
          comfyUiRoot.path,
          _comfyUiRelativePath(asset.relativeDestination),
          asset.fileName,
        );
        await Directory(p.dirname(destinationFile)).create(recursive: true);
        await downloaded.rename(destinationFile);
      }

      _throwIfCancelled(cancellationToken);
      final workflowAsset = _asset('ltx-workflow');
      final workflowTarget = _safeJoin(
        comfyUiRoot.path,
        _comfyUiRelativePath(workflowAsset.relativeDestination),
        workflowAsset.fileName,
      );
      final workflowData = await rootBundle.load(
        workflowAsset.source.substring('asset://'.length),
      );
      final workflowBytes = workflowData.buffer.asUint8List(
        workflowData.offsetInBytes,
        workflowData.lengthInBytes,
      );
      _verifyBytes(workflowBytes, workflowAsset);
      await File(workflowTarget).writeAsBytes(workflowBytes, flush: true);
      onProgress?.call(1);

      final marker = File(p.join(sourceRoot.path, _markerName));
      await marker.writeAsString(
        jsonEncode({
          'profile': comfyUiSetupManifest.profile,
          'comfyui_version': comfyUiSetupManifest.comfyUiVersion,
          'installed_at': DateTime.now().toUtc().toIso8601String(),
          'assets': {
            for (final asset in comfyUiSetupManifest.assets)
              asset.id: {'size_bytes': asset.sizeBytes, 'sha256': asset.sha256},
          },
        }),
        flush: true,
      );
      final destinationType = await FileSystemEntity.type(
        installPath,
        followLinks: false,
      );
      if (destinationType != FileSystemEntityType.notFound) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The selected ComfyUI destination changed during setup.',
        );
      }
      await Directory(sourceRoot.path).rename(installPath);
    } on _SetupCancelled {
      throw const VideoProviderException(
        'VIDEO_SETUP_CANCELLED',
        'ComfyUI setup was cancelled. No partial installation was kept.',
      );
    } on VideoProviderException {
      rethrow;
    } on TimeoutException {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'A ComfyUI asset download timed out.',
      );
    } on SocketException {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'A ComfyUI asset could not be downloaded.',
      );
    } on FormatException {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The downloaded ComfyUI archive is invalid.',
      );
    } on ProcessException catch (error) {
      throw VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'ComfyUI setup could not run the archive extractor: ${error.message}',
      );
    } on FileSystemException catch (error) {
      throw VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'ComfyUI could not be installed in the selected destination: ${error.message}',
      );
    } finally {
      client.close();
      if (await work.exists()) {
        try {
          await work.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  ComfyUiSetupAsset _asset(String id) =>
      comfyUiSetupManifest.assets.firstWhere((asset) => asset.id == id);

  Future<bool> _isCompleteInstall(Directory root) async {
    try {
      final markerData = jsonDecode(
        await File(p.join(root.path, _markerName)).readAsString(),
      );
      if (markerData is! Map ||
          markerData['profile'] != comfyUiSetupManifest.profile ||
          markerData['comfyui_version'] !=
              comfyUiSetupManifest.comfyUiVersion) {
        return false;
      }
      final markerAssets = markerData['assets'];
      if (markerAssets is! Map) return false;
      final sourceRoot = await _findComfyUiRoot(root);
      await _rejectExtractedLinks(sourceRoot);
      final comfyUiRoot = _applicationRoot(sourceRoot);
      for (final asset in comfyUiSetupManifest.assets) {
        final recorded = markerAssets[asset.id];
        if (recorded is! Map ||
            recorded['size_bytes'] != asset.sizeBytes ||
            recorded['sha256'] != asset.sha256) {
          return false;
        }
        if (asset.id == 'comfyui-portable-nvidia') continue;
        final file = File(
          _safeJoin(
            comfyUiRoot.path,
            _comfyUiRelativePath(asset.relativeDestination),
            asset.fileName,
          ),
        );
        if (!await file.exists() || await file.length() != asset.sizeBytes) {
          return false;
        }
        if (!await verifyComfyUiSetupAssetStream(file.openRead(), asset)) {
          return false;
        }
      }
      return true;
    } on Object {
      return false;
    }
  }

  void _validateManifest() {
    for (final asset in comfyUiSetupManifest.assets) {
      if (asset.fileName.isEmpty ||
          p.basename(asset.fileName) != asset.fileName ||
          asset.fileName.contains(RegExp(r'[\\/]')) ||
          asset.sizeBytes <= 0 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(asset.sha256)) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The pinned ComfyUI setup manifest is invalid.',
        );
      }
      if (asset.isBundled) continue;
      final uri = Uri.tryParse(asset.source);
      if (uri == null) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The pinned ComfyUI setup source is not an allowed HTTPS URL.',
        );
      }
      _validateNetworkUri(uri, allowQuery: false);
    }
  }

  bool _isAllowedHost(String host) => _allowedHosts.contains(host);

  void _validateNetworkUri(Uri uri, {required bool allowQuery}) {
    if (uri.scheme != 'https' ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        (!allowQuery && uri.query.isNotEmpty) ||
        uri.fragment.isNotEmpty ||
        !_isAllowedHost(uri.host.toLowerCase())) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The pinned ComfyUI setup source is not an allowed HTTPS URL.',
      );
    }
  }

  String _normalizeDestination(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'Choose a ComfyUI installation destination first.',
      );
    }
    final absolute = p.normalize(p.absolute(trimmed));
    if (absolute == p.rootPrefix(absolute) || p.basename(absolute).isEmpty) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The ComfyUI installation destination cannot be a drive root.',
      );
    }
    return absolute;
  }

  Future<void> _checkDiskSpace(String destination) async {
    final parent = Directory(p.dirname(destination));
    await parent.create(recursive: true);
    final freeBytes = _freeBytes(parent.path);
    if (freeBytes != null &&
        freeBytes < comfyUiSetupManifest.requiredDiskBytes) {
      throw VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'At least ${_formatBytes(comfyUiSetupManifest.requiredDiskBytes)} of free disk space is required. ${_formatBytes(freeBytes)} is available.',
      );
    }
  }

  int? _freeBytes(String path) {
    if (!Platform.isWindows) return null;
    final directory = path.toNativeUtf16();
    final available = calloc<Uint64>();
    final total = calloc<Uint64>();
    final free = calloc<Uint64>();
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getDiskSpace = kernel32
          .lookupFunction<_GetDiskFreeSpaceExNative, _GetDiskFreeSpaceExDart>(
            'GetDiskFreeSpaceExW',
          );
      final success = getDiskSpace(directory, available, total, free);
      return success == 0 ? null : available.value;
    } on Object {
      return null;
    } finally {
      calloc.free(directory);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
  }

  Future<void> _download(
    http.Client client,
    ComfyUiSetupAsset asset,
    File target, {
    required void Function(int bytes) onBytes,
    required ComfyUiSetupCancellation cancellation,
  }) async {
    var uri = Uri.parse(asset.source);
    late http.StreamedResponse response;
    for (var redirect = 0; redirect <= 5; redirect++) {
      _validateNetworkUri(uri, allowQuery: redirect > 0);
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/octet-stream';
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 300 || response.statusCode >= 400) break;
      final location = response.headers['location'];
      if (location == null || location.isEmpty || redirect == 5) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The pinned asset returned an unsafe redirect.',
        );
      }
      await response.stream.listen((_) {}).cancel();
      uri = uri.resolve(location);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The pinned asset ${asset.fileName} returned HTTP ${response.statusCode}.',
      );
    }
    final contentLength = response.contentLength;
    if (contentLength != null &&
        contentLength >= 0 &&
        contentLength != asset.sizeBytes) {
      throw VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The pinned asset ${asset.fileName} has an unexpected size.',
      );
    }

    final sink = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(sink);
    final output = await target.open(mode: FileMode.write);
    var bytes = 0;
    var digestClosed = false;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        _throwIfCancelled(cancellation);
        bytes += chunk.length;
        if (bytes > asset.sizeBytes) {
          throw VideoProviderException(
            'VIDEO_SETUP_ERROR',
            'The pinned asset ${asset.fileName} is larger than expected.',
          );
        }
        digestInput.add(chunk);
        await output.writeFrom(chunk);
        onBytes(chunk.length);
      }
      digestInput.close();
      digestClosed = true;
    } finally {
      await output.close();
      if (digestClosed &&
          (bytes != asset.sizeBytes ||
              sink.events.single.toString() != asset.sha256)) {
        try {
          await target.delete();
        } catch (_) {}
        throw VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The downloaded asset ${asset.fileName} failed its size or SHA-256 check.',
        );
      }
    }
  }

  Future<ProcessResult> _runArchiveCommand(
    String executable,
    List<String> arguments,
    ComfyUiSetupCancellation cancellation,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    final stdout = _readBoundedProcessOutput(process.stdout);
    final stderr = _readBoundedProcessOutput(process.stderr);
    final exitCode = process.exitCode;
    while (true) {
      if (cancellation.isCancelled) {
        process.kill();
        await exitCode;
        await Future.wait([stdout, stderr]);
        throw const _SetupCancelled();
      }
      final completed = await Future.any<Object>([
        exitCode.then((code) => _ArchiveProcessExit(code)),
        Future<Object>.delayed(
          const Duration(milliseconds: 250),
          () => Object(),
        ),
      ]);
      if (completed is _ArchiveProcessExit) {
        final stdoutResult = await stdout;
        final stderrResult = await stderr;
        if (stdoutResult.truncated || stderrResult.truncated) {
          throw const FormatException('archive output exceeded the limit');
        }
        return ProcessResult(
          process.pid,
          completed.code,
          stdoutResult.text,
          stderrResult.text,
        );
      }
    }
  }

  Future<_BoundedProcessOutput> _readBoundedProcessOutput(
    Stream<List<int>> stream,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var size = 0;
    var truncated = false;
    await for (final chunk in stream) {
      final remaining = _maxArchiveOutputBytes - size;
      final take = min(chunk.length, max(remaining, 0));
      if (take > 0) {
        bytes.add(chunk.sublist(0, take));
        size += take;
      }
      if (take < chunk.length) truncated = true;
    }
    return _BoundedProcessOutput(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
      truncated,
    );
  }

  Future<void> _extractArchive(
    File archive,
    Directory destination,
    ComfyUiSetupCancellation cancellation,
  ) async {
    final extractor = await _findExtractor();
    final listArgs = _isTarExtractor(extractor)
        ? ['-tf', archive.path]
        : ['l', '-slt', archive.path];
    final listing = await _runArchiveCommand(extractor, listArgs, cancellation);
    if (listing.exitCode != 0) {
      throw const FormatException('archive listing failed');
    }
    _validateArchiveListing(listing.stdout.toString(), extractor);
    if (_isTarExtractor(extractor)) {
      final details = await _runArchiveCommand(extractor, [
        '-tvf',
        archive.path,
      ], cancellation);
      if (details.exitCode != 0) {
        throw const FormatException('archive details failed');
      }
      _rejectArchiveLinks(details.stdout.toString());
    } else {
      _rejectArchiveLinks(listing.stdout.toString());
    }
    _throwIfCancelled(cancellation);
    final extractArgs = _isTarExtractor(extractor)
        ? ['-xf', archive.path, '-C', destination.path]
        : ['x', archive.path, '-o${destination.path}', '-y'];
    final result = await _runArchiveCommand(
      extractor,
      extractArgs,
      cancellation,
    );
    if (result.exitCode != 0) {
      throw const FormatException('archive extraction failed');
    }
  }

  Future<String> _findExtractor() async {
    final candidates = <String>[];
    final seen = <String>{};
    void addCandidate(String? path) {
      if (path == null || path.isEmpty || !seen.add(path)) return;
      if (File(path).existsSync()) candidates.add(path);
    }

    for (final key in ['ProgramW6432', 'ProgramFiles', 'ProgramFiles(x86)']) {
      final programFiles = Platform.environment[key];
      if (programFiles == null) continue;
      addCandidate(p.join(programFiles, '7-Zip', '7z.exe'));
      addCandidate(p.join(programFiles, '7-Zip', '7za.exe'));
      addCandidate(p.join(programFiles, '7-Zip', '7zz.exe'));
    }
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    addCandidate(p.join(systemRoot, 'System32', 'tar.exe'));

    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          _isTarExtractor(candidate) ? ['--version'] : ['-h'],
        );
        if (result.exitCode == 0) return candidate;
      } on ProcessException {
        continue;
      }
    }
    throw const VideoProviderException(
      'VIDEO_SETUP_ERROR',
      'No archive extractor was found. Windows tar.exe or 7-Zip is required for ComfyUI setup.',
    );
  }

  bool _isTarExtractor(String executable) =>
      p.basename(executable).toLowerCase() == 'tar.exe';

  void _validateArchiveListing(String output, String extractor) {
    final entries = _isTarExtractor(extractor)
        ? output.split(RegExp(r'\r?\n'))
        : _sevenZipPaths(output);
    for (final rawEntry in entries) {
      final entry = rawEntry.trim();
      if (entry.isEmpty) continue;
      final normalized = entry.replaceAll('\\', '/');
      if (normalized.startsWith('/') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(normalized) ||
          normalized.split('/').any((part) => part == '..') ||
          normalized.contains('\u0000')) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The ComfyUI archive contains an unsafe path.',
        );
      }
    }
  }

  Iterable<String> _sevenZipPaths(String output) sync* {
    var inEntries = false;
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line == '----------') {
        inEntries = true;
        continue;
      }
      if (inEntries && line.startsWith('Path = ')) {
        yield line.substring('Path = '.length);
      }
    }
  }

  void _rejectArchiveLinks(String output) {
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trimLeft();
      if (line.startsWith('lrwx') ||
          line.startsWith('hrw') ||
          (line.startsWith('Attributes = ') &&
              line.substring('Attributes = '.length).contains('L'))) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The ComfyUI archive contains a link and was rejected.',
        );
      }
    }
  }

  Future<void> _rejectExtractedLinks(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const VideoProviderException(
          'VIDEO_SETUP_ERROR',
          'The ComfyUI archive contains a link and was rejected.',
        );
      }
    }
  }

  Future<Directory> _findComfyUiRoot(Directory extracted) async {
    final candidates = <Directory>[extracted];
    await for (final entity in extracted.list(followLinks: false)) {
      if (entity is Directory) candidates.add(entity);
    }
    for (final candidate in candidates) {
      final hasPython = await File(
        p.join(candidate.path, 'python_embeded', 'python.exe'),
      ).exists();
      final hasMain = await File(p.join(candidate.path, 'main.py')).exists();
      final nestedMain = await File(
        p.join(candidate.path, 'ComfyUI', 'main.py'),
      ).exists();
      if (hasPython && (hasMain || nestedMain)) return candidate;
    }
    throw const VideoProviderException(
      'VIDEO_SETUP_ERROR',
      'The ComfyUI archive did not contain the expected portable runtime.',
    );
  }

  Directory _applicationRoot(Directory installRoot) {
    final nested = Directory(p.join(installRoot.path, 'ComfyUI'));
    return Directory(
      File(p.join(installRoot.path, 'main.py')).existsSync()
          ? installRoot.path
          : nested.path,
    );
  }

  String _comfyUiRelativePath(String relative) {
    if (relative == 'ComfyUI') return '.';
    const prefix = 'ComfyUI/';
    if (relative.startsWith(prefix)) return relative.substring(prefix.length);
    return relative;
  }

  String _safeJoin(String base, String relative, String fileName) {
    if (p.isAbsolute(relative) ||
        relative.split(RegExp(r'[\\/]')).any((part) => part == '..') ||
        p.basename(fileName) != fileName) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The ComfyUI setup manifest contains an unsafe destination.',
      );
    }
    final basePath = p.normalize(p.absolute(base));
    final target = p.normalize(p.join(basePath, relative, fileName));
    if (target != basePath && !p.isWithin(basePath, target)) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The ComfyUI setup destination escaped its staging directory.',
      );
    }
    return target;
  }

  void _verifyBytes(Uint8List bytes, ComfyUiSetupAsset asset) {
    if (bytes.length != asset.sizeBytes ||
        sha256.convert(bytes).toString() != asset.sha256) {
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'The bundled workflow failed its integrity check.',
      );
    }
  }

  void _throwIfCancelled(ComfyUiSetupCancellation cancellation) {
    if (cancellation.isCancelled) throw const _SetupCancelled();
  }

  void _throwIfAlreadyCancelled(ComfyUiSetupCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const VideoProviderException(
        'VIDEO_SETUP_CANCELLED',
        'ComfyUI setup was cancelled. No partial installation was kept.',
      );
    }
  }

  String _formatBytes(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    return '${gib.toStringAsFixed(1)} GB';
  }
}

typedef _GetDiskFreeSpaceExNative =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );
typedef _GetDiskFreeSpaceExDart =
    int Function(
      Pointer<Utf16>,
      Pointer<Uint64>,
      Pointer<Uint64>,
      Pointer<Uint64>,
    );

class _BoundedProcessOutput {
  final String text;
  final bool truncated;

  const _BoundedProcessOutput(this.text, this.truncated);
}

class _ArchiveProcessExit {
  final int code;

  const _ArchiveProcessExit(this.code);
}

class _SetupCancelled implements Exception {
  const _SetupCancelled();
}
