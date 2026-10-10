import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'video_media_validation.dart';

enum VideoProviderMode {
  openAiVideos,
  comfyUiBridge,
  wanGradio,
  ffmpeg,
  invalid,
}

const _allowedVideoStatuses = {
  'queued',
  'in_progress',
  'completed',
  'failed',
  'canceled',
  'cancelled',
};
const _allowedImageMimeTypes = {'image/png', 'image/jpeg', 'image/webp'};
const _allowedVideoDurations = {'4', '8', '12'};

const _maxImageBytes = 8 * 1024 * 1024;
const _maxJsonBytes = 256 * 1024;
const _maxVideoBytes = 100 * 1024 * 1024;

class VideoProviderException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final String? providerRequestId;

  const VideoProviderException(
    this.code,
    this.message, {
    this.statusCode,
    this.providerRequestId,
  });

  @override
  String toString() => message;
}

class VideoProviderJob {
  final String requestId;
  final String status;
  final double? progress;
  final String? videoUrl;
  final String? errorMessage;

  const VideoProviderJob({
    required this.requestId,
    required this.status,
    this.progress,
    this.videoUrl,
    this.errorMessage,
  });

  factory VideoProviderJob.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final status = json['status']?.toString().trim().toLowerCase();
    if (id == null || id.isEmpty || status == null || status.isEmpty) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Video provider returned an invalid job response.',
      );
    }
    if (!_allowedVideoStatuses.contains(status)) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Video provider returned an unsupported job status.',
      );
    }

    final rawProgress = json['progress'];
    final progress = rawProgress is num
        ? rawProgress.toDouble().clamp(0, 100).toDouble()
        : null;
    final rawUrl = json['video_url'] ?? json['videoUrl'] ?? json['url'];
    final videoUrl = rawUrl is String && _isHttpsUrl(rawUrl)
        ? rawUrl.trim()
        : null;
    final rawError = json['error'];
    final errorMessage = rawError is Map
        ? rawError['message']?.toString().trim()
        : rawError is String
        ? rawError.trim()
        : json['error_message']?.toString().trim();

    return VideoProviderJob(
      requestId: id,
      status: status,
      progress: progress,
      videoUrl: videoUrl,
      errorMessage: errorMessage?.isEmpty == true ? null : errorMessage,
    );
  }
}

abstract interface class VideoProviderClient {
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  });

  Future<VideoProviderJob> poll(String requestId);

  Future<Uint8List> downloadContent(String requestId);

  Future<(bool, String?)> testConnection();
}

class ComfyUiBridgeVideoProviderClient implements VideoProviderClient {
  final OpenAiVideosProviderClient _delegate;
  final Future<void> Function() _ensureReady;

  factory ComfyUiBridgeVideoProviderClient({
    required OpenAiVideosProviderClient delegate,
    required Future<void> Function() ensureReady,
  }) => ComfyUiBridgeVideoProviderClient._(delegate, ensureReady);

  ComfyUiBridgeVideoProviderClient._(this._delegate, this._ensureReady);

  @override
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  }) async {
    await _ensureReady();
    await _delegate.ensureVideoSupport();
    return _delegate.createImageToVideo(
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
      prompt: prompt,
      duration: duration,
      aspectRatio: aspectRatio,
    );
  }

  @override
  Future<VideoProviderJob> poll(String requestId) => _delegate.poll(requestId);

  @override
  Future<Uint8List> downloadContent(String requestId) =>
      _delegate.downloadContent(requestId);

  @override
  Future<(bool, String?)> testConnection() async {
    try {
      await _ensureReady();
      return await _delegate.testConnection();
    } on VideoProviderException catch (error) {
      return (false, error.message);
    } on TimeoutException {
      return (false, 'ComfyUI bridge startup timed out.');
    } catch (_) {
      return (false, 'ComfyUI bridge could not be started.');
    }
  }
}

class OpenAiVideosProviderClient implements VideoProviderClient {
  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;
  final Duration requestTimeout;

  OpenAiVideosProviderClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  @override
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  }) async {
    _validateConfiguration();
    if (imageBytes.isEmpty || imageBytes.length > _maxImageBytes) {
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'The selected image is empty or too large.',
      );
    }
    if (!isValidImageBytes(imageBytes)) {
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'The selected image bytes are not a valid PNG, JPEG, or WebP image.',
      );
    }
    final normalizedMimeType = imageMimeType
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (!_allowedImageMimeTypes.contains(normalizedMimeType)) {
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'Use a PNG, JPEG, or WebP image as the video reference.',
      );
    }
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty || trimmedPrompt.length > 4000) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Video prompt must contain 1 to 4000 characters.',
      );
    }
    if (!_allowedVideoDurations.contains(duration)) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Video duration must be 4, 8, or 12 seconds.',
      );
    }

    final size = _sizeForAspectRatio(aspectRatio);
    final image = await _prepareImageReference(imageBytes, size);
    final request = http.MultipartRequest('POST', _endpoint('videos'))
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..fields['model'] = model.trim()
      ..fields['prompt'] = trimmedPrompt
      ..fields['seconds'] = duration
      ..fields['size'] = size
      ..files.add(
        http.MultipartFile.fromBytes(
          'input_reference',
          image.bytes,
          filename: image.fileName,
          contentType: image.contentType,
        ),
      );

    final response = await _send(request, maxBytes: _maxJsonBytes);
    _throwForStatus(response.statusCode, response.bytes, response.headers);
    return _parseJob(response.bytes);
  }

  @override
  Future<VideoProviderJob> poll(String requestId) async {
    final id = _validateRequestId(requestId);
    final request = http.Request('GET', _endpoint('videos/$id'))
      ..headers.addAll(_jsonHeaders());
    final response = await _send(request, maxBytes: _maxJsonBytes);
    _throwForStatus(response.statusCode, response.bytes, response.headers);
    return _parseJob(response.bytes);
  }

  @override
  Future<Uint8List> downloadContent(String requestId) async {
    final id = _validateRequestId(requestId);
    final request = http.Request('GET', _endpoint('videos/$id/content'))
      ..headers.addAll({
        ..._jsonHeaders(),
        'Accept': 'video/mp4, application/octet-stream',
      });
    final response = await _send(request, maxBytes: _maxVideoBytes);
    _throwForStatus(response.statusCode, response.bytes, response.headers);

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('json')) {
      final map = _decodeJson(response.bytes);
      final rawUrl = map['url'] ?? map['videoUrl'] ?? map['video_url'];
      if (rawUrl is! String || !_isHttpsUrl(rawUrl)) {
        throw const VideoProviderException(
          'VIDEO_DOWNLOAD_ERROR',
          'Video provider returned an invalid video download URL.',
        );
      }
      final uri = Uri.parse(rawUrl);
      return _downloadUrl(uri, authenticated: _sameOrigin(uri));
    }

    _validateMp4(response.bytes, contentType);
    return response.bytes;
  }

  Future<void> ensureVideoSupport() async {
    _validateConfiguration();
    final request = http.Request('GET', _endpoint('videos'))
      ..headers.addAll(_jsonHeaders());
    final response = await _send(request, maxBytes: _maxJsonBytes);
    _throwForStatus(response.statusCode, response.bytes, response.headers);
  }

  @override
  Future<(bool, String?)> testConnection() async {
    try {
      await ensureVideoSupport();
      final request = http.Request('GET', _endpoint('models'))
        ..headers.addAll(_jsonHeaders());
      final response = await _send(request, maxBytes: _maxJsonBytes);
      if (response.statusCode == 404 || response.statusCode == 405) {
        return (
          true,
          'Videos endpoint is reachable, but /models is unavailable; verify the configured video model.',
        );
      }
      _throwForStatus(response.statusCode, response.bytes, response.headers);
      final map = _decodeJson(response.bytes);
      final data = map['data'];
      if (data is! List) {
        throw const VideoProviderException(
          'VIDEO_UNSUPPORTED_PROVIDER',
          'Video provider returned a malformed /models response.',
        );
      }
      final models = data
          .whereType<Map>()
          .map((item) => item['id']?.toString().trim())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      if (models.isNotEmpty && !models.contains(model.trim())) {
        return (
          false,
          'Configured video model "${model.trim()}" was not advertised by the provider.',
        );
      }
      if (models.isEmpty) {
        return (
          true,
          'Videos endpoint is reachable, but the model list is empty; verify the configured video model.',
        );
      }
      return (true, null);
    } on VideoProviderException catch (error) {
      return (false, error.message);
    } on TimeoutException {
      return (false, 'Video provider request timed out.');
    } on http.ClientException {
      return (false, 'Video provider could not be reached.');
    } catch (_) {
      return (false, 'Video provider connection failed.');
    }
  }

  Uri _endpoint(String suffix) {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root/$suffix');
  }

  Map<String, String> _jsonHeaders() => {
    'Authorization': 'Bearer ${apiKey.trim()}',
    'Accept': 'application/json',
  };

  void _validateConfiguration() {
    final parsed = Uri.tryParse(baseUrl.trim());
    if (apiKey.trim().isEmpty || model.trim().isEmpty) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Configure a video API key and video model first.',
      );
    }
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Video API base URL must be a valid HTTP(S) URL without query parameters.',
      );
    }
  }

  String _validateRequestId(String value) {
    final id = value.trim();
    if (id.isEmpty ||
        id.length > 256 ||
        id.contains('/') ||
        id.contains('\\')) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Video provider returned an invalid request ID.',
      );
    }
    return id;
  }

  Future<_RawResponse> _send(
    http.BaseRequest request, {
    required int maxBytes,
  }) async {
    final streamed = await _client.send(request).timeout(requestTimeout);
    final bytes = await _readResponseBody(
      streamed.stream,
      maxBytes,
    ).timeout(requestTimeout);
    return _RawResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      bytes: bytes,
    );
  }

  Future<Uint8List> _readResponseBody(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes) {
        throw VideoProviderException(
          maxBytes == _maxJsonBytes
              ? 'VIDEO_UNSUPPORTED_PROVIDER'
              : 'VIDEO_DOWNLOAD_ERROR',
          'Video provider response is too large.',
        );
      }
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  bool _sameOrigin(Uri uri) {
    final base = Uri.tryParse(baseUrl.trim());
    return base != null &&
        uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port;
  }

  Future<Uint8List> _downloadUrl(Uri uri, {required bool authenticated}) async {
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'video/mp4, application/octet-stream';
    if (authenticated) {
      request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final response = await _send(request, maxBytes: _maxVideoBytes);
    _throwForStatus(response.statusCode, response.bytes);
    _validateMp4(
      response.bytes,
      response.headers['content-type']?.toLowerCase() ?? '',
    );
    return response.bytes;
  }

  VideoProviderJob _parseJob(Uint8List bytes) {
    final map = _decodeJson(bytes);
    return VideoProviderJob.fromJson(map);
  }

  Map<String, dynamic> _decodeJson(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const VideoProviderException(
      'VIDEO_UNSUPPORTED_PROVIDER',
      'Video provider returned malformed JSON.',
    );
  }

  void _throwForStatus(
    int statusCode, [
    Uint8List? responseBytes,
    Map<String, String>? responseHeaders,
  ]) {
    if (statusCode >= 200 && statusCode < 300) return;
    if (statusCode == 401 || statusCode == 403) {
      throw VideoProviderException(
        'VIDEO_AUTH_ERROR',
        'Video provider rejected the configured API key.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 429) {
      throw VideoProviderException(
        'VIDEO_RATE_LIMITED',
        'Video provider rate limit reached. Try again later.',
        statusCode: statusCode,
      );
    }
    if (statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 415 ||
        statusCode == 501) {
      throw VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Video provider does not support the configured Videos API endpoint.',
        statusCode: statusCode,
        providerRequestId: _providerRequestId(responseBytes, responseHeaders),
      );
    }
    final detail = _safeProviderError(responseBytes);
    final requestId = _providerRequestId(responseBytes, responseHeaders);
    final code = statusCode == 400 || statusCode == 422
        ? 'VIDEO_CONFIGURATION_ERROR'
        : 'VIDEO_GENERATION_FAILED';
    throw VideoProviderException(
      code,
      detail == null
          ? 'Video provider request failed (HTTP $statusCode)${requestId == null ? '.' : ' Request ID: $requestId.'}'
          : 'Video provider request failed (HTTP $statusCode): $detail${requestId == null ? '' : ' Request ID: $requestId.'}',
      statusCode: statusCode,
      providerRequestId: requestId,
    );
  }

  String? _providerRequestId(Uint8List? bytes, Map<String, String>? headers) {
    final headerValue = _headerRequestId(headers);
    if (headerValue != null) return headerValue;
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final error = decoded['error'];
      final raw =
          decoded['request_id'] ??
          decoded['requestId'] ??
          (error is Map ? error['request_id'] ?? error['requestId'] : null);
      return _normalizeRequestId(raw);
    } catch (_) {
      return null;
    }
  }

  String? _headerRequestId(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'x-request-id' ||
          key == 'request-id' ||
          key == 'openai-request-id') {
        final value = _normalizeRequestId(entry.value);
        if (value != null) return value;
      }
    }
    return null;
  }

  String? _normalizeRequestId(dynamic raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty || value.length > 256 ? null : value;
  }

  String? _safeProviderError(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final rawError = decoded['error'];
      final rawCode = rawError is Map ? rawError['code'] : decoded['code'];
      final rawMessage = rawError is Map
          ? rawError['message']
          : rawError is String
          ? rawError
          : decoded['message'];
      final code = rawCode?.toString().trim();
      final message = rawMessage?.toString().trim();
      if ((code == null || code.isEmpty) &&
          (message == null || message.isEmpty)) {
        return null;
      }
      final detail = [
        if (code != null && code.isNotEmpty) code,
        if (message != null && message.isNotEmpty) message,
      ].join(': ');
      final sanitized = _sanitizeProviderText(detail);
      return sanitized.length > 240
          ? '${sanitized.substring(0, 240)}…'
          : sanitized;
    } catch (_) {
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      final sanitized = _sanitizeProviderText(text);
      return sanitized.length > 240
          ? '${sanitized.substring(0, 240)}…'
          : sanitized;
    }
  }

  void _validateMp4(Uint8List bytes, String contentType) {
    if (bytes.isEmpty || bytes.length > _maxVideoBytes) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Video provider returned an empty or oversized video.',
      );
    }
    if (contentType.isNotEmpty &&
        !contentType.contains('video/mp4') &&
        !contentType.contains('application/octet-stream')) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Video provider returned a non-MP4 content type.',
      );
    }
    if (!isValidMp4Bytes(bytes)) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Video provider returned invalid MP4 content.',
      );
    }
  }

  Future<_PreparedImageReference> _prepareImageReference(
    Uint8List bytes,
    String size,
  ) async {
    final dimensions = size.split('x');
    final targetWidth = int.parse(dimensions[0]);
    final targetHeight = int.parse(dimensions[1]);
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: true,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const VideoProviderException(
          'VIDEO_SOURCE_ERROR',
          'The selected image could not be prepared for video generation.',
        );
      }
      return _PreparedImageReference(
        bytes: data.buffer.asUint8List(),
        fileName: 'input.png',
        contentType: http.MediaType('image', 'png'),
      );
    } catch (error) {
      if (error is VideoProviderException) rethrow;
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'The selected image could not be prepared for video generation.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static String _sizeForAspectRatio(String aspectRatio) {
    switch (aspectRatio) {
      case '9:16':
        return '720x1280';
      case '16:9':
        return '1280x720';
      default:
        throw const VideoProviderException(
          'VIDEO_CONFIGURATION_ERROR',
          'Video aspect ratio is not supported.',
        );
    }
  }
}

class WanGradioVideoProviderClient implements VideoProviderClient {
  static const defaultSpaceUrl = 'https://multimodalart-wan2-1-fast.hf.space';
  static const _defaultNegativePrompt =
      'static, blurry, distorted, low quality, watermark, text';
  static final _requestIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$',
  );

  final String spaceUrl;
  final String hfToken;
  final http.Client _client;
  final Duration requestTimeout;
  final Map<String, String> _completedVideoUrls = {};

  WanGradioVideoProviderClient({
    this.spaceUrl = defaultSpaceUrl,
    this.hfToken = '',
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 120),
  }) : _client = client ?? http.Client();

  @override
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String duration,
    required String aspectRatio,
  }) async {
    final space = _validatedSpace();
    _validateImage(imageBytes, imageMimeType);
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty || trimmedPrompt.length > 4000) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Video prompt must contain 1 to 4000 characters.',
      );
    }
    if (!_allowedVideoDurations.contains(duration)) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Video duration must be 4, 8, or 12 seconds.',
      );
    }

    final (height, width) = _dimensionsForAspectRatio(aspectRatio);
    final normalizedMimeType = imageMimeType
        .split(';')
        .first
        .trim()
        .toLowerCase();
    final fileData = {
      'path': null,
      'url': 'data:$normalizedMimeType;base64,${base64Encode(imageBytes)}',
      'size': imageBytes.length,
      'orig_name': 'input.${_extensionForMime(normalizedMimeType)}',
      'mime_type': normalizedMimeType,
      'is_stream': false,
      'meta': {'_type': 'gradio.FileData'},
    };
    final request =
        http.Request('POST', _endpoint(space, '/call/generate_video'))
          ..headers.addAll({
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'data': [
              fileData,
              trimmedPrompt,
              height,
              width,
              _defaultNegativePrompt,
              _durationForWan(duration),
              1.0,
              4,
              42,
              true,
            ],
          });
    _addAuthorization(request);
    final response = await _send(request, maxBytes: _maxJsonBytes);
    _throwForStatus(response);
    final eventId = _eventId(response.bytes);
    return VideoProviderJob(requestId: eventId, status: 'queued');
  }

  @override
  Future<VideoProviderJob> poll(String requestId) async {
    final id = _validateRequestId(requestId);
    final space = _validatedSpace();
    final request = http.Request(
      'GET',
      _endpoint(space, '/call/generate_video/$id'),
    )..headers['Accept'] = 'text/event-stream';
    _addAuthorization(request);
    final response = await _send(request, maxBytes: _maxJsonBytes);
    _throwForStatus(response);
    return _parseEventStream(response.bytes, id, space);
  }

  @override
  Future<Uint8List> downloadContent(String requestId) async {
    final id = _validateRequestId(requestId);
    final url = _completedVideoUrls[id];
    if (url == null) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Wan2.1 did not return a downloadable video.',
      );
    }
    final space = _validatedSpace();
    final response = await _downloadResponse(Uri.parse(url), space);
    _validateMp4(
      response.bytes,
      response.headers['content-type']?.toLowerCase() ?? '',
    );
    _completedVideoUrls.remove(id);
    return response.bytes;
  }

  @override
  Future<(bool, String?)> testConnection() async {
    try {
      final space = _validatedSpace();
      final request = http.Request('GET', _endpoint(space, '/info'))
        ..headers['Accept'] = 'application/json';
      _addAuthorization(request);
      final response = await _send(request, maxBytes: _maxJsonBytes);
      _throwForStatus(response);
      final decoded = _decodeJson(response.bytes);
      final namedEndpoints = decoded['named_endpoints'];
      if (namedEndpoints is! Map ||
          !namedEndpoints.keys.any(
            (key) => key.toString().replaceFirst('/', '') == 'generate_video',
          )) {
        return (false, 'Wan2.1 Space does not expose /generate_video.');
      }
      return (true, null);
    } on VideoProviderException catch (error) {
      return (false, error.message);
    } on TimeoutException {
      return (false, 'Wan2.1 Space request timed out.');
    } on http.ClientException {
      return (false, 'Wan2.1 Space could not be reached.');
    } catch (_) {
      return (false, 'Wan2.1 Space connection failed.');
    }
  }

  Uri _validatedSpace() {
    final uri = Uri.tryParse(spaceUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port != 443 && uri.port != 0 ||
        !uri.host.toLowerCase().endsWith('.hf.space')) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Wan2.1 Space URL must be a valid HTTPS Hugging Face Space URL.',
      );
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  Uri _endpoint(Uri space, String path) => Uri.parse(
    '${space.toString().replaceFirst(RegExp(r'/+$'), '')}/gradio_api$path',
  );

  void _addAuthorization(http.BaseRequest request) {
    final token = hfToken.trim();
    if (token.isEmpty) return;
    if (token.length > 512 || token.contains(RegExp(r'\s'))) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Hugging Face access token is invalid.',
      );
    }
    request.headers['Authorization'] = 'Bearer $token';
  }

  Future<_RawResponse> _downloadResponse(Uri uri, Uri space) async {
    var currentUri = uri;
    for (var redirectCount = 0; redirectCount <= 3; redirectCount++) {
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..headers['Accept'] = 'video/mp4, application/octet-stream';
      if (_hasSameOrigin(currentUri, space)) _addAuthorization(request);
      final response = await _send(request, maxBytes: _maxVideoBytes);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        final redirectUri = location == null
            ? null
            : currentUri.resolve(location);
        if (redirectUri == null ||
            !_isTrustedDownloadRedirect(redirectUri, space)) {
          throw const VideoProviderException(
            'VIDEO_DOWNLOAD_ERROR',
            'Wan2.1 returned an unsafe video download redirect.',
          );
        }
        currentUri = redirectUri;
        continue;
      }
      _throwForStatus(response);
      return response;
    }
    throw const VideoProviderException(
      'VIDEO_DOWNLOAD_ERROR',
      'Wan2.1 video download exceeded the redirect limit.',
    );
  }

  bool _hasSameOrigin(Uri first, Uri second) =>
      first.scheme == second.scheme &&
      first.host.toLowerCase() == second.host.toLowerCase() &&
      first.port == second.port;

  bool _isTrustedDownloadRedirect(Uri uri, Uri space) {
    final host = uri.host.toLowerCase();
    final trustedHost =
        _hasSameOrigin(uri, space) ||
        host.endsWith('.hf.space') ||
        host == 'huggingface.co' ||
        host.endsWith('.huggingface.co') ||
        host == 'hf.co' ||
        host.endsWith('.hf.co');
    return uri.scheme == 'https' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        trustedHost;
  }

  Future<_RawResponse> _send(
    http.BaseRequest request, {
    required int maxBytes,
  }) async {
    final streamed = await _client.send(request).timeout(requestTimeout);
    final bytes = <int>[];
    await for (final chunk in streamed.stream.timeout(requestTimeout)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw VideoProviderException(
          maxBytes == _maxVideoBytes
              ? 'VIDEO_DOWNLOAD_ERROR'
              : 'VIDEO_UNSUPPORTED_PROVIDER',
          'Wan2.1 provider response is too large.',
        );
      }
      bytes.addAll(chunk);
    }
    return _RawResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      bytes: Uint8List.fromList(bytes),
    );
  }

  void _throwForStatus(_RawResponse response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw VideoProviderException(
        'VIDEO_AUTH_ERROR',
        'Hugging Face rejected the access token or this Space does not allow access.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 429) {
      throw VideoProviderException(
        'VIDEO_RATE_LIMITED',
        'Wan2.1 public quota or rate limit reached. Try again later.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 404 || response.statusCode == 405) {
      throw VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 Space does not support the requested Gradio endpoint.',
        statusCode: response.statusCode,
      );
    }
    final detail = _safeResponseText(response.bytes);
    throw VideoProviderException(
      response.statusCode == 400 || response.statusCode == 422
          ? 'VIDEO_CONFIGURATION_ERROR'
          : 'VIDEO_GENERATION_FAILED',
      detail == null
          ? 'Wan2.1 provider request failed (HTTP ${response.statusCode}).'
          : 'Wan2.1 provider request failed (HTTP ${response.statusCode}): $detail',
      statusCode: response.statusCode,
    );
  }

  String _eventId(Uint8List bytes) {
    final decoded = _decodeJson(bytes);
    final raw = decoded['event_id'] ?? decoded['eventId'];
    final value = raw?.toString().trim();
    if (value == null || !_requestIdPattern.hasMatch(value)) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned an invalid event ID.',
      );
    }
    return value;
  }

  VideoProviderJob _parseEventStream(
    Uint8List bytes,
    String requestId,
    Uri space,
  ) {
    final body = utf8.decode(bytes, allowMalformed: true);
    final events = body.replaceAll('\r\n', '\n').split('\n\n');
    for (final block in events) {
      var eventName = 'message';
      final dataLines = <String>[];
      for (final line in block.split('\n')) {
        if (line.startsWith('event:')) {
          eventName = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring('data:'.length).trimLeft());
        }
      }
      if (eventName == 'error') {
        final detail = _sanitizeProviderText(_eventDetail(dataLines));
        throw VideoProviderException(
          'VIDEO_GENERATION_FAILED',
          detail.isEmpty
              ? 'Wan2.1 failed while generating the video. The public Space returned no error detail; it may be busy, out of GPU quota, or unable to process this image.'
              : 'Wan2.1 failed while generating the video$detail.',
        );
      }
      if (eventName == 'complete') {
        final url = _completedUrl(dataLines, space);
        _completedVideoUrls[requestId] = url;
        return VideoProviderJob(
          requestId: requestId,
          status: 'completed',
          videoUrl: url,
        );
      }
      if (eventName == 'generating' || eventName == 'process_starts') {
        continue;
      }
    }
    return VideoProviderJob(requestId: requestId, status: 'in_progress');
  }

  String _completedUrl(List<String> dataLines, Uri space) {
    if (dataLines.isEmpty) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned an empty completion event.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(dataLines.join('\\n'));
    } catch (_) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned malformed completion data.',
      );
    }
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned an invalid completion result.',
      );
    }
    final video = (decoded.first as Map)['video'];
    final rawUrl = video is Map ? video['url']?.toString().trim() : null;
    final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != space.host.toLowerCase() ||
        uri.port != space.port ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        rawUrl != rawUrl?.trim()) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned an unsafe video URL.',
      );
    }
    return uri.toString();
  }

  String _eventDetail(List<String> dataLines) {
    if (dataLines.isEmpty) return '';
    final text = dataLines.join(' ').trim();
    if (text.isEmpty ||
        text.length > 160 ||
        text.toLowerCase() == 'null' ||
        text == '[]') {
      return '';
    }
    return ': $text';
  }

  Map<String, dynamic> _decodeJson(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const VideoProviderException(
      'VIDEO_UNSUPPORTED_PROVIDER',
      'Wan2.1 provider returned malformed JSON.',
    );
  }

  String? _safeResponseText(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return null;
    final sanitized = _sanitizeProviderText(text);
    return sanitized.length > 240
        ? '${sanitized.substring(0, 240)}…'
        : sanitized;
  }

  String _validateRequestId(String value) {
    final id = value.trim();
    if (!_requestIdPattern.hasMatch(id)) {
      throw const VideoProviderException(
        'VIDEO_UNSUPPORTED_PROVIDER',
        'Wan2.1 provider returned an invalid event ID.',
      );
    }
    return id;
  }

  void _validateImage(Uint8List bytes, String mimeType) {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'The selected image is empty or too large.',
      );
    }
    if (!isValidImageBytes(bytes) ||
        !_allowedImageMimeTypes.contains(normalized)) {
      throw const VideoProviderException(
        'VIDEO_SOURCE_ERROR',
        'Use a valid PNG, JPEG, or WebP image as the video reference.',
      );
    }
  }

  static String _sanitizeProviderText(String value) => value
      .replaceAll(
        RegExp(
          r'\b(?:https?|blob|content|memory|file|varian-[a-z0-9-]+)://[^\s<>]+',
          caseSensitive: false,
        ),
        '[redacted URL]',
      )
      .replaceAll(
        RegExp(r'\bdata:[^\s<>]+', caseSensitive: false),
        '[redacted data URI]',
      )
      .replaceAll(
        RegExp(
          r'\b(?:bearer|token|api[_-]?key|authorization|signature|sig|access_token|refresh_token)\s*[:=]?\s*[^\s,;]+',
          caseSensitive: false,
        ),
        '[redacted credential]',
      )
      .replaceAll(
        RegExp(
          r'(?<![A-Za-z0-9])(?:[A-Za-z]:[\\/]|/(?:Users|home|tmp|data)/)[^\s<>]+',
          caseSensitive: false,
        ),
        '[redacted path]',
      )
      .trim();

  void _validateMp4(Uint8List bytes, String contentType) {
    if (bytes.isEmpty || bytes.length > _maxVideoBytes) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Wan2.1 returned an empty or oversized video.',
      );
    }
    if (contentType.isNotEmpty &&
        !contentType.contains('video/mp4') &&
        !contentType.contains('application/octet-stream')) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Wan2.1 returned a non-MP4 content type.',
      );
    }
    if (!isValidMp4Bytes(bytes)) {
      throw const VideoProviderException(
        'VIDEO_DOWNLOAD_ERROR',
        'Wan2.1 returned invalid MP4 content.',
      );
    }
  }

  static (int, int) _dimensionsForAspectRatio(String aspectRatio) {
    switch (aspectRatio) {
      case '9:16':
        return (896, 512);
      case '16:9':
        return (512, 896);
      default:
        throw const VideoProviderException(
          'VIDEO_CONFIGURATION_ERROR',
          'Video aspect ratio is not supported by Wan2.1.',
        );
    }
  }

  static double _durationForWan(String duration) => switch (duration) {
    '4' => 2.0,
    '8' => 3.0,
    '12' => 3.4,
    _ => 2.0,
  };

  static String _extensionForMime(String mimeType) => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    _ => 'png',
  };
}

class _PreparedImageReference {
  final Uint8List bytes;
  final String fileName;
  final http.MediaType contentType;

  const _PreparedImageReference({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });
}

class _RawResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;

  const _RawResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });
}

String _sanitizeProviderText(String value) => value
    .replaceAll(
      RegExp(
        r'\b(?:https?|blob|content|memory|file|varian-[a-z0-9-]+)://[^\s<>]+',
        caseSensitive: false,
      ),
      '[redacted URL]',
    )
    .replaceAll(
      RegExp(r'\bdata:[^\s<>]+', caseSensitive: false),
      '[redacted data URI]',
    )
    .replaceAll(
      RegExp(
        r'\b(?:bearer|token|api[_-]?key|authorization|signature|sig|access_token|refresh_token)\s*[:=]?\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[redacted credential]',
    )
    .replaceAll(
      RegExp(
        r'(?<![A-Za-z0-9])(?:[A-Za-z]:[\\/]|/(?:Users|home|tmp|data)/)[^\s<>]+',
        caseSensitive: false,
      ),
      '[redacted path]',
    )
    .trim();

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      value == value.trim();
}
