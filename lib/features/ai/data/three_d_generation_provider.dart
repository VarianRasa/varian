import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../domain/models/ai_artifact.dart';
import '../../../domain/models/ai_job.dart';
import '../../../domain/models/durable_asset_reference.dart';

abstract interface class ThreeDGenerationProvider {
  Future<AIArtifact> generate({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  });

  Future<(bool, String?)> testConnection();
}

abstract interface class ThreeDGenerationRetryProvider {
  Future<AIArtifact> retry({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  });
}

class ThreeDGenerationException implements Exception {
  final String message;
  final String? code;

  const ThreeDGenerationException(this.message, {this.code});

  @override
  String toString() => code == null ? message : '$code: $message';
}

class HttpThreeDGenerationProvider
    implements ThreeDGenerationProvider, ThreeDGenerationRetryProvider {
  final String baseUrl;
  final String apiKey;
  final http.Client? _injectedClient;
  final Future<void> Function(Duration) _pollDelay;
  final int maxPolls;

  HttpThreeDGenerationProvider({
    required this.baseUrl,
    String? apiKey,
    http.Client? client,
    Future<void> Function(Duration)? pollDelay,
    this.maxPolls = 120,
  }) : apiKey = apiKey?.trim() ?? '',
       _injectedClient = client,
       _pollDelay = pollDelay ?? Future<void>.delayed;

  @override
  Future<AIArtifact> generate({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async {
    return _withClient((client) async {
      final response = await client
          .post(
            _uri('/3d/jobs'),
            headers: _headers(json: true),
            body: jsonEncode(
              _createBody(job, sourceImageBase64, sourceImageUrl),
            ),
          )
          .timeout(const Duration(seconds: 30));
      final created = _decodeResponse(response, '3D job creation');
      return _waitForArtifact(client, created, '3D job creation');
    });
  }

  @override
  Future<AIArtifact> retry({
    required AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  }) async {
    return _withClient((client) async {
      final response = await client
          .post(
            _uri('/3d/jobs/${Uri.encodeComponent(job.id)}/retry'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 30));
      final retried = _decodeResponse(response, '3D job retry');
      return _waitForArtifact(client, retried, '3D job retry');
    });
  }

  Future<AIArtifact> _withClient(
    Future<AIArtifact> Function(http.Client client) action,
  ) async {
    final client = _injectedClient ?? http.Client();
    try {
      return await action(client);
    } on ThreeDGenerationException {
      rethrow;
    } on TimeoutException {
      throw const ThreeDGenerationException(
        '3D provider request timed out.',
        code: 'PROVIDER_TIMEOUT',
      );
    } on http.ClientException catch (error) {
      throw ThreeDGenerationException(
        '3D provider is unreachable: ${error.message}',
        code: 'PROVIDER_UNREACHABLE',
      );
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  Future<AIArtifact> _waitForArtifact(
    http.Client client,
    Map<String, dynamic> created,
    String operation,
  ) async {
    final providerJobId = _readRequiredString(created, const [
      'jobId',
      'requestId',
      'id',
    ], '3D provider did not return a job ID.');
    final initialStatus = _readStatus(created);
    if (initialStatus == 'completed') return _artifactFromJob(created);
    if (initialStatus == 'failed' || initialStatus == 'canceled') {
      throw ThreeDGenerationException(
        _readError(created) ?? '3D provider failed during $operation.',
        code: initialStatus == 'canceled'
            ? 'PROVIDER_JOB_CANCELED'
            : 'PROVIDER_JOB_FAILED',
      );
    }

    for (var poll = 0; poll < maxPolls; poll++) {
      if (poll > 0) await _pollDelay(const Duration(seconds: 2));
      final pollResponse = await client
          .get(
            _uri('/3d/jobs/${Uri.encodeComponent(providerJobId)}'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 30));
      final current = _decodeResponse(pollResponse, '3D job polling');
      final status = _readStatus(current);
      if (status == 'completed') return _artifactFromJob(current);
      if (status == 'failed' || status == 'canceled') {
        throw ThreeDGenerationException(
          _readError(current) ?? '3D provider failed the job.',
          code: status == 'canceled'
              ? 'PROVIDER_JOB_CANCELED'
              : 'PROVIDER_JOB_FAILED',
        );
      }
      if (status != 'queued' && status != 'processing') {
        throw const ThreeDGenerationException(
          '3D provider returned an invalid job status.',
          code: 'INVALID_PROVIDER_RESPONSE',
        );
      }
    }
    throw const ThreeDGenerationException(
      '3D generation timed out while waiting for the provider.',
      code: 'PROVIDER_TIMEOUT',
    );
  }

  @override
  Future<(bool, String?)> testConnection() async {
    final client = _injectedClient ?? http.Client();
    try {
      final response = await client
          .get(_uri('/health'), headers: _headers())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (true, null);
      }
      return (
        false,
        '3D worker rejected the health check (HTTP ${response.statusCode}).',
      );
    } on TimeoutException {
      return (false, '3D worker health check timed out.');
    } on http.ClientException {
      return (false, '3D worker is unreachable.');
    } finally {
      if (_injectedClient == null) client.close();
    }
  }

  Map<String, dynamic> _createBody(
    AIJob job,
    String? sourceImageBase64,
    String? sourceImageUrl,
  ) {
    final params = job.creativeParams;
    final body = <String, dynamic>{
      'jobId': job.id,
      'projectId': job.projectId,
      'capability': job.capability.name,
      'prompt': job.prompt,
      'negativePrompt': params?.negativePrompt,
      'sourceImageBase64': sourceImageBase64 ?? params?.sourceImageBase64,
      'sourceImageUrl': sourceImageUrl ?? params?.sourceImageUrl,
      'sourceModelReference': params?.sourceModelReference,
      'provider': params?.threeDProvider,
      'meshQuality': params?.meshQuality,
      'textureMode': params?.textureMode,
      'targetFormat': params?.targetFormat ?? 'glb',
      'triangleBudget': params?.triangleBudget,
      'seed': params?.seed,
      'generatePreview': params?.generatePreview ?? true,
    };
    body.removeWhere((key, value) => value == null);
    return body;
  }

  AIArtifact _artifactFromJob(Map<String, dynamic> job) {
    final raw = job['artifact'] ?? job['result'] ?? job;
    if (raw is! Map) {
      throw const ThreeDGenerationException(
        '3D provider did not return an artifact.',
        code: 'INVALID_PROVIDER_RESPONSE',
      );
    }
    final json = Map<String, dynamic>.from(raw);
    json['kind'] ??= 'model3d';
    final rawReference = json['reference']?.toString().trim();
    final durableReference =
        validModel3DArtifactReference(rawReference) ??
        durableAssetReference(rawReference);
    if (durableReference == null) {
      throw const ThreeDGenerationException(
        '3D provider returned an invalid artifact reference.',
        code: 'INVALID_PROVIDER_RESPONSE',
      );
    }
    json['reference'] = durableReference;
    final artifact = AIArtifact.fromJson(json);
    final mime = artifact.mimeType?.toLowerCase();
    final fileName = artifact.fileName?.toLowerCase() ?? '';
    final isGlb =
        mime == null ||
        mime == 'model/gltf-binary' ||
        fileName.endsWith('.glb');
    if (artifact.kind != AIArtifactKind.model3d ||
        !artifact.hasSource ||
        !isGlb) {
      throw const ThreeDGenerationException(
        '3D provider returned an invalid GLB artifact.',
        code: 'INVALID_PROVIDER_RESPONSE',
      );
    }
    return artifact;
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response,
    String operation,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ThreeDGenerationException(
        '$operation failed (HTTP ${response.statusCode}).',
        code: 'PROVIDER_HTTP_ERROR',
      );
    }
    if (response.body.length > 2 * 1024 * 1024) {
      throw const ThreeDGenerationException(
        '3D provider response is too large.',
        code: 'INVALID_PROVIDER_RESPONSE',
      );
    }
    try {
      final value = jsonDecode(response.body);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    throw ThreeDGenerationException(
      '$operation returned invalid JSON.',
      code: 'INVALID_PROVIDER_RESPONSE',
    );
  }

  String _readStatus(Map<String, dynamic> response) =>
      response['status']?.toString().trim().toLowerCase() ?? 'queued';

  String? _readError(Map<String, dynamic> response) {
    final value = response['error'] ?? response['message'];
    if (value is Map) return value['message']?.toString();
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _readRequiredString(
    Map<String, dynamic> response,
    List<String> keys,
    String message,
  ) {
    for (final key in keys) {
      final value = response[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    throw ThreeDGenerationException(message, code: 'INVALID_PROVIDER_RESPONSE');
  }

  Uri _uri(String path) {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse('$root$path');
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty) {
      throw const ThreeDGenerationException(
        '3D worker base URL is invalid.',
        code: 'CONFIGURATION_ERROR',
      );
    }
    return parsed;
  }

  Map<String, String> _headers({bool json = false}) {
    if (apiKey.isEmpty && !json) return const {'Accept': 'application/json'};
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
    };
  }
}
