import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/ai/data/comfy_ui_bridge_manager.dart';
import '../../features/ai/data/video_provider.dart';
import 'supabase_app_config.dart';

String _webOpenAiApiKeySession = '';
String _webVideoApiKeySession = '';
String _webVideoBridgeTokenSession = '';
String _webWanHfTokenSession = '';
String _webThreeDApiKeySession = '';

void clearWebBackendConfigSession() {
  _webOpenAiApiKeySession = '';
  _webVideoApiKeySession = '';
  _webVideoBridgeTokenSession = '';
  _webWanHfTokenSession = '';
  _webThreeDApiKeySession = '';
}

Future<void>? _backendConfigWriteQueue;

Future<T> _enqueueBackendConfigWrite<T>(Future<T> Function() operation) async {
  final previous = _backendConfigWriteQueue ?? Future<void>.value();
  final next = previous.then((_) => operation());
  final queued = next.then<void>((_) {}).catchError((_) {});
  _backendConfigWriteQueue = queued;
  try {
    return await next;
  } finally {
    if (identical(_backendConfigWriteQueue, queued)) {
      _backendConfigWriteQueue = null;
    }
  }
}

Future<void> _waitForBackendConfigWrites() async {
  final pending = _backendConfigWriteQueue;
  if (pending != null) await pending;
}

enum ImageApiMode { auto, responses, chatCompletions, imagesGenerations }

enum ImageEditApiMode { auto, imagesEdits, responses, chatCompletions }

class BackendConfig {
  static const supportedThreeDProviders = <String>{
    'triposr',
    'trellis',
    'fal-trellis2',
    'hunyuan3d',
    'comfyui',
  };

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String openAiApiKey;
  final String openAiBaseUrl;
  final String openAiModel;
  final String openAiImageModel;
  final ImageApiMode imageApiMode;
  final ImageEditApiMode imageEditApiMode;
  final String videoApiBaseUrl;
  final String videoApiKey;
  final String videoBridgeToken;
  final String wanHfSpaceUrl;
  final String wanHfToken;
  final String videoModel;
  final VideoProviderMode videoProviderMode;
  final String comfyUiPath;
  final int comfyUiPort;
  final bool threeDEnabled;
  final String threeDBaseUrl;
  final String threeDApiKey;
  final String threeDProvider;
  final String currentUserName;

  const BackendConfig({
    this.supabaseUrl = SupabaseAppConfig.url,
    this.supabaseAnonKey = SupabaseAppConfig.publishableKey,
    this.openAiApiKey = '',
    this.openAiBaseUrl = 'https://api.openai.com/v1',
    this.openAiModel = 'gpt-4o-mini',
    this.openAiImageModel = 'gpt-image-2',
    this.imageApiMode = ImageApiMode.auto,
    this.imageEditApiMode = ImageEditApiMode.auto,
    this.videoApiBaseUrl = '',
    this.videoApiKey = '',
    this.videoBridgeToken = '',
    this.wanHfSpaceUrl = WanGradioVideoProviderClient.defaultSpaceUrl,
    this.wanHfToken = '',
    this.videoModel = '',
    this.videoProviderMode = VideoProviderMode.openAiVideos,
    this.comfyUiPath = '',
    this.comfyUiPort = 8188,
    this.threeDEnabled = false,
    this.threeDBaseUrl = 'http://127.0.0.1:20130/v1',
    this.threeDApiKey = '',
    this.threeDProvider = 'triposr',
    this.currentUserName = 'Architect',
  });

  bool get isSupabaseConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  bool get isOpenAiConfigured {
    if (openAiApiKey.trim().isEmpty || openAiModel.trim().isEmpty) {
      return false;
    }
    try {
      normalizeOpenAiBaseUrl(openAiBaseUrl);
      return true;
    } on FormatException {
      return false;
    }
  }

  String get effectiveVideoApiKey {
    if (videoProviderMode == VideoProviderMode.comfyUiBridge) {
      return videoBridgeToken.trim();
    }
    if (videoProviderMode == VideoProviderMode.wanGradio) {
      return wanHfToken.trim();
    }
    return videoApiKey.trim().isEmpty
        ? openAiApiKey.trim()
        : videoApiKey.trim();
  }

  String get effectiveVideoBaseUrl {
    if (videoProviderMode == VideoProviderMode.wanGradio) {
      return wanHfSpaceUrl.trim();
    }
    final value = videoProviderMode == VideoProviderMode.comfyUiBridge
        ? 'http://127.0.0.1:20129/v1'
        : videoApiBaseUrl.trim().isEmpty
        ? openAiBaseUrl
        : videoApiBaseUrl;
    final normalized = normalizeOpenAiBaseUrl(value);
    if (!kIsWeb) return normalized;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.toLowerCase() != 'localhost') {
      return normalized;
    }
    return uri.replace(host: '127.0.0.1').toString();
  }

  bool get isVideoConfigured {
    if (videoProviderMode == VideoProviderMode.invalid) return false;
    if (videoProviderMode == VideoProviderMode.ffmpeg) return true;
    if (videoProviderMode == VideoProviderMode.wanGradio) {
      return wanHfSpaceUrl.trim().isNotEmpty;
    }
    if (videoProviderMode == VideoProviderMode.comfyUiBridge) {
      return effectiveVideoApiKey.isNotEmpty &&
          videoModel.trim() == comfyUiBridgeModel;
    }
    if (effectiveVideoApiKey.isEmpty || videoModel.trim().isEmpty) return false;
    try {
      effectiveVideoBaseUrl;
      return true;
    } on FormatException {
      return false;
    }
  }

  bool get isThreeDConfigured {
    if (!threeDEnabled ||
        !supportedThreeDProviders.contains(
          threeDProvider.trim().toLowerCase(),
        )) {
      return false;
    }
    try {
      normalizeOpenAiBaseUrl(threeDBaseUrl);
      return true;
    } on FormatException {
      return false;
    }
  }

  String get effectiveThreeDBaseUrl {
    final normalized = normalizeOpenAiBaseUrl(threeDBaseUrl);
    if (!kIsWeb) return normalized;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.toLowerCase() != 'localhost') {
      return normalized;
    }
    return uri.replace(host: '127.0.0.1').toString();
  }

  String? get webEndpointWarning {
    if (!kIsWeb) return null;
    final uri = Uri.tryParse(effectiveVideoBaseUrl);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return 'Browser memakai localhost pada komputer pengguna. Pastikan server video berjalan di komputer ini dan mengizinkan CORS.';
    }
    if (uri.scheme == 'http' && Uri.base.scheme == 'https') {
      return 'Browser Web membutuhkan HTTPS atau same-origin proxy untuk endpoint video saat aplikasi dibuka melalui HTTPS.';
    }
    return null;
  }

  String _requestBaseUrl() {
    final baseUrl = normalizeOpenAiBaseUrl(openAiBaseUrl);
    if (!kIsWeb) return baseUrl;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.toLowerCase() != 'localhost') return baseUrl;
    return uri.replace(host: '127.0.0.1').toString();
  }

  static String normalizeOpenAiBaseUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return 'https://api.openai.com/v1';
    }

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'AI base URL must be an http(s) URL without credentials, query parameters, or fragments.',
      );
    }
    final host = uri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (uri.scheme != 'https' && !isLoopback) {
      throw const FormatException(
        'AI provider URLs must use HTTPS unless they target localhost.',
      );
    }

    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty) path = '/v1';
    return uri.replace(path: path).toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static ImageApiMode parseImageApiMode(String? value) =>
      ImageApiMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ImageApiMode.auto,
      );

  static ImageEditApiMode parseImageEditApiMode(String? value) =>
      ImageEditApiMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ImageEditApiMode.auto,
      );

  static VideoProviderMode parseVideoProviderMode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return VideoProviderMode.openAiVideos;
    }
    return VideoProviderMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => VideoProviderMode.invalid,
    );
  }

  BackendConfig normalized() => copyWith(
    openAiBaseUrl: normalizeOpenAiBaseUrl(openAiBaseUrl),
    openAiApiKey: openAiApiKey.trim(),
    openAiModel: openAiModel.trim(),
    openAiImageModel: openAiImageModel.trim().isEmpty
        ? 'gpt-image-2'
        : openAiImageModel.trim(),
    imageApiMode: imageApiMode,
    imageEditApiMode: imageEditApiMode,
    videoApiBaseUrl: videoApiBaseUrl.trim().isEmpty
        ? ''
        : normalizeOpenAiBaseUrl(videoApiBaseUrl),
    videoApiKey: videoApiKey.trim(),
    videoBridgeToken: videoBridgeToken.trim(),
    wanHfSpaceUrl: wanHfSpaceUrl.trim(),
    wanHfToken: wanHfToken.trim(),
    videoModel: videoModel.trim(),
    videoProviderMode: videoProviderMode,
    comfyUiPath: comfyUiPath.trim(),
    comfyUiPort: comfyUiPort,
    threeDEnabled: threeDEnabled,
    threeDBaseUrl: normalizeOpenAiBaseUrl(threeDBaseUrl),
    threeDApiKey: threeDApiKey.trim(),
    threeDProvider: threeDProvider.trim().isEmpty
        ? 'triposr'
        : threeDProvider.trim().toLowerCase(),
    supabaseUrl: supabaseUrl.trim(),
    supabaseAnonKey: supabaseAnonKey.trim(),
    currentUserName: currentUserName.trim().isEmpty
        ? 'Architect'
        : currentUserName.trim(),
  );

  BackendConfig copyWith({
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? openAiApiKey,
    String? openAiBaseUrl,
    String? openAiModel,
    String? openAiImageModel,
    ImageApiMode? imageApiMode,
    ImageEditApiMode? imageEditApiMode,
    String? videoApiBaseUrl,
    String? videoApiKey,
    String? videoBridgeToken,
    String? wanHfSpaceUrl,
    String? wanHfToken,
    String? videoModel,
    VideoProviderMode? videoProviderMode,
    String? comfyUiPath,
    int? comfyUiPort,
    bool? threeDEnabled,
    String? threeDBaseUrl,
    String? threeDApiKey,
    String? threeDProvider,
    String? currentUserName,
  }) {
    return BackendConfig(
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseAnonKey: supabaseAnonKey ?? this.supabaseAnonKey,
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openAiBaseUrl: openAiBaseUrl ?? this.openAiBaseUrl,
      openAiModel: openAiModel ?? this.openAiModel,
      openAiImageModel: openAiImageModel ?? this.openAiImageModel,
      imageApiMode: imageApiMode ?? this.imageApiMode,
      imageEditApiMode: imageEditApiMode ?? this.imageEditApiMode,
      videoApiBaseUrl: videoApiBaseUrl ?? this.videoApiBaseUrl,
      videoApiKey: videoApiKey ?? this.videoApiKey,
      videoBridgeToken: videoBridgeToken ?? this.videoBridgeToken,
      wanHfSpaceUrl: wanHfSpaceUrl ?? this.wanHfSpaceUrl,
      wanHfToken: wanHfToken ?? this.wanHfToken,
      videoModel: videoModel ?? this.videoModel,
      videoProviderMode: videoProviderMode ?? this.videoProviderMode,
      comfyUiPath: comfyUiPath ?? this.comfyUiPath,
      comfyUiPort: comfyUiPort ?? this.comfyUiPort,
      threeDEnabled: threeDEnabled ?? this.threeDEnabled,
      threeDBaseUrl: threeDBaseUrl ?? this.threeDBaseUrl,
      threeDApiKey: threeDApiKey ?? this.threeDApiKey,
      threeDProvider: threeDProvider ?? this.threeDProvider,
      currentUserName: currentUserName ?? this.currentUserName,
    );
  }

  /// Test an OpenAI-compatible endpoint and the configured chat model.
  Future<List<String>> discoverImageModels([
    http.Client? injectedClient,
  ]) async {
    if (openAiApiKey.trim().isEmpty) return const [];

    final client = injectedClient ?? http.Client();
    try {
      final baseUrl = _requestBaseUrl();
      final response = await client
          .get(
            Uri.parse('$baseUrl/models'),
            headers: {'Authorization': 'Bearer ${openAiApiKey.trim()}'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) return const [];

      final models = <String>[];
      for (final item in decoded['data'] as List) {
        if (item is! Map) continue;
        final id = item['id']?.toString().trim();
        final capabilities = item['capabilities'];
        final advertisesImage =
            capabilities is List &&
            capabilities.any(
              (value) => value.toString().toLowerCase().contains('image'),
            );
        if (id != null &&
            id.isNotEmpty &&
            (advertisesImage || _looksLikeImageModel(id))) {
          models.add(id);
        }
      }
      return models.toSet().toList()..sort();
    } catch (_) {
      return const [];
    } finally {
      if (injectedClient == null) client.close();
    }
  }

  static bool _looksLikeImageModel(String modelId) {
    final id = modelId.toLowerCase();
    return id.contains('gpt-image') ||
        id.contains('image') ||
        id.contains('dall-e') ||
        id.contains('flux') ||
        id.contains('stable-diffusion') ||
        id.contains('stable_diffusion') ||
        id.contains('sdxl') ||
        id.contains('imagen') ||
        id.contains('ideogram') ||
        id.contains('midjourney');
  }

  Future<(bool, String?)> testOpenAiConnection() async {
    if (openAiApiKey.trim().isEmpty) {
      return (false, 'OpenAI API Key is empty.');
    }

    final String baseUrl;
    try {
      baseUrl = _requestBaseUrl();
    } on FormatException catch (error) {
      return (false, error.message);
    }

    final client = http.Client();
    try {
      final headers = {
        'Authorization': 'Bearer ${openAiApiKey.trim()}',
        'Content-Type': 'application/json',
      };
      final modelsResponse = await client
          .get(Uri.parse('$baseUrl/models'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (modelsResponse.statusCode >= 200 && modelsResponse.statusCode < 300) {
        return (true, null);
      }

      // Some local providers do not implement /models. Verify the configured
      // model through the smallest chat request instead.
      final chatResponse = await client
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: headers,
            body: jsonEncode({
              'model': openAiModel.trim(),
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 1,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (chatResponse.statusCode >= 200 && chatResponse.statusCode < 300) {
        return (true, null);
      }

      final detail = chatResponse.body.trim().isEmpty
          ? 'HTTP ${chatResponse.statusCode}'
          : 'HTTP ${chatResponse.statusCode}: ${chatResponse.body.trim()}';
      return (false, 'AI endpoint rejected the configured model. $detail');
    } catch (error) {
      if (error is TimeoutException) {
        return (
          false,
          'AI endpoint timed out. Verify the server is reachable.',
        );
      }
      if (error is http.ClientException) {
        return (
          false,
          'Browser could not reach the AI endpoint. Verify CORS, HTTPS, and localhost reachability.',
        );
      }
      return (
        false,
        'AI endpoint connection failed. Verify the URL and server.',
      );
    } finally {
      client.close();
    }
  }
}

String? _currentBackendAccountId() {
  try {
    final client = Supabase.instance.client;
    return client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;
  } catch (_) {
    return null;
  }
}

Future<void> clearAccountScopedBackendConfig({
  String? expectedAccountId,
  bool Function()? shouldClear,
}) {
  return _enqueueBackendConfigWrite(() async {
    if (shouldClear != null && !shouldClear()) return;
    final prefs = await SharedPreferences.getInstance();
    if (shouldClear != null && !shouldClear()) return;
    final expectedOwner = expectedAccountId?.trim();
    final owner = prefs.getString('cfg_user_name_owner')?.trim();
    if (expectedOwner != null &&
        expectedOwner.isNotEmpty &&
        owner != null &&
        owner.isNotEmpty &&
        owner != expectedOwner) {
      return;
    }
    await prefs.remove('cfg_user_name');
    await prefs.remove('cfg_user_name_owner');
  });
}

final backendConfigProvider =
    StateNotifierProvider<BackendConfigNotifier, BackendConfig>((ref) {
      return BackendConfigNotifier();
    });

final backendConfigReadyProvider = FutureProvider<void>((ref) {
  final notifier = ref.watch(backendConfigProvider.notifier);
  return notifier.waitUntilReady();
});

class BackendConfigNotifier extends StateNotifier<BackendConfig> {
  late Future<void> ready;

  BackendConfigNotifier() : super(const BackendConfig()) {
    ready = loadConfig();
  }

  Future<void> waitUntilReady() => ready;

  Future<void> reload() {
    ready = loadConfig();
    return ready;
  }

  static const _videoApiKeyStorageKey = 'video_api_key';
  static const _videoBridgeTokenStorageKey = 'video_bridge_token';
  static const _wanHfTokenStorageKey = 'wan_hf_token';
  static const _threeDApiKeyStorageKey = 'three_d_api_key';
  static const _secureStorage = FlutterSecureStorage();

  Future<void> loadConfig() async {
    await _waitForBackendConfigWrites();
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      // Legacy browser-stored provider secrets are deleted, never restored.
      await prefs.remove('cfg_openai_key');
      await prefs.remove('cfg_video_key');
      await prefs.remove('cfg_video_bridge_token');
      await prefs.remove('cfg_wan_hf_token');
      await prefs.remove('cfg_three_d_api_key');
    }
    final openAiApiKey = kIsWeb
        ? _webOpenAiApiKeySession
        : await _readNativeKey(
            prefs,
            secureKey: 'openai_api_key',
            legacyKey: 'cfg_openai_key',
          );
    final videoApiKey = kIsWeb
        ? _webVideoApiKeySession
        : await _readNativeKey(
            prefs,
            secureKey: _videoApiKeyStorageKey,
            legacyKey: 'cfg_video_key',
          );
    final videoBridgeToken = kIsWeb
        ? _webVideoBridgeTokenSession
        : await _readNativeKey(
            prefs,
            secureKey: _videoBridgeTokenStorageKey,
            legacyKey: 'cfg_video_bridge_token',
          );
    final wanHfToken = kIsWeb
        ? _webWanHfTokenSession
        : await _readNativeKey(
            prefs,
            secureKey: _wanHfTokenStorageKey,
            legacyKey: 'cfg_wan_hf_token',
          );
    final threeDApiKey = kIsWeb
        ? _webThreeDApiKeySession
        : await _readNativeKey(
            prefs,
            secureKey: _threeDApiKeyStorageKey,
            legacyKey: 'cfg_three_d_api_key',
          );
    const useSavedSupabaseConfig =
        kDebugMode || SupabaseAppConfig.allowRuntimeConfiguration;
    final savedSupabaseUrl = useSavedSupabaseConfig
        ? prefs.getString('cfg_supabase_url') ?? ''
        : '';
    final savedSupabaseKey = useSavedSupabaseConfig
        ? prefs.getString('cfg_supabase_anon_key') ?? ''
        : '';
    final savedUserName = prefs.getString('cfg_user_name') ?? '';
    final savedUserOwner = prefs.getString('cfg_user_name_owner')?.trim();
    final currentAccountId = _currentBackendAccountId();
    final scopedUserName = savedUserName.isEmpty
        ? 'Architect'
        : savedUserOwner == null || savedUserOwner.isEmpty
        ? currentAccountId == null
              ? savedUserName
              : 'Architect'
        : savedUserOwner == currentAccountId
        ? savedUserName
        : 'Architect';
    final loaded = BackendConfig(
      supabaseUrl: savedSupabaseUrl.trim().isEmpty
          ? SupabaseAppConfig.url
          : savedSupabaseUrl,
      supabaseAnonKey: savedSupabaseKey.trim().isEmpty
          ? SupabaseAppConfig.publishableKey
          : savedSupabaseKey,
      openAiApiKey: openAiApiKey,
      openAiBaseUrl:
          prefs.getString('cfg_openai_base') ?? 'https://api.openai.com/v1',
      openAiModel: prefs.getString('cfg_openai_model') ?? 'gpt-4o-mini',
      openAiImageModel:
          prefs.getString('cfg_openai_image_model') ?? 'gpt-image-2',
      imageApiMode: BackendConfig.parseImageApiMode(
        prefs.getString('cfg_openai_image_api_mode'),
      ),
      imageEditApiMode: BackendConfig.parseImageEditApiMode(
        prefs.getString('cfg_openai_image_edit_api_mode'),
      ),
      videoApiBaseUrl: prefs.getString('cfg_video_base') ?? '',
      videoApiKey: videoApiKey,
      videoBridgeToken: videoBridgeToken,
      wanHfSpaceUrl:
          prefs.getString('cfg_wan_hf_space_url') ??
          WanGradioVideoProviderClient.defaultSpaceUrl,
      wanHfToken: wanHfToken,
      videoModel: prefs.getString('cfg_video_model') ?? '',
      videoProviderMode: BackendConfig.parseVideoProviderMode(
        prefs.getString('cfg_video_mode'),
      ),
      comfyUiPath: prefs.getString('cfg_comfyui_path') ?? '',
      comfyUiPort: prefs.getInt('cfg_comfyui_port') ?? 8188,
      threeDEnabled: prefs.getBool('cfg_three_d_enabled') ?? false,
      threeDBaseUrl:
          prefs.getString('cfg_three_d_base_url') ??
          'http://127.0.0.1:20130/v1',
      threeDApiKey: threeDApiKey,
      threeDProvider: prefs.getString('cfg_three_d_provider') ?? 'triposr',
      currentUserName: scopedUserName,
    );
    state = loaded.normalized();
  }

  Future<String> _readNativeKey(
    SharedPreferences prefs, {
    required String secureKey,
    required String legacyKey,
  }) async {
    try {
      final secureValue = await _secureStorage.read(key: secureKey);
      if (secureValue != null && secureValue.isNotEmpty) return secureValue;
      final legacyValue = prefs.getString(legacyKey) ?? '';
      if (legacyValue.isNotEmpty) {
        await _secureStorage.write(key: secureKey, value: legacyValue);
        await prefs.remove(legacyKey);
      }
      return legacyValue;
    } catch (_) {
      return '';
    }
  }

  Future<void> saveConfig(BackendConfig newConfig) =>
      _enqueueBackendConfigWrite(() => _saveConfigUnlocked(newConfig));

  Future<void> _saveConfigUnlocked(BackendConfig newConfig) async {
    final normalized = newConfig.normalized();
    final prefs = await SharedPreferences.getInstance();
    const useRuntimeSupabaseConfig =
        kDebugMode || SupabaseAppConfig.allowRuntimeConfiguration;
    await prefs.setString(
      'cfg_supabase_url',
      useRuntimeSupabaseConfig ? normalized.supabaseUrl : SupabaseAppConfig.url,
    );
    await prefs.setString(
      'cfg_supabase_anon_key',
      useRuntimeSupabaseConfig
          ? normalized.supabaseAnonKey
          : SupabaseAppConfig.publishableKey,
    );
    if (kIsWeb) {
      _webOpenAiApiKeySession = normalized.openAiApiKey;
      _webVideoApiKeySession = normalized.videoApiKey;
      _webVideoBridgeTokenSession = normalized.videoBridgeToken;
      _webWanHfTokenSession = normalized.wanHfToken;
      _webThreeDApiKeySession = normalized.threeDApiKey;
    } else {
      try {
        await _secureStorage.write(
          key: 'openai_api_key',
          value: normalized.openAiApiKey,
        );
        await _secureStorage.write(
          key: _videoApiKeyStorageKey,
          value: normalized.videoApiKey,
        );
        await _secureStorage.write(
          key: _videoBridgeTokenStorageKey,
          value: normalized.videoBridgeToken,
        );
        await _secureStorage.write(
          key: _wanHfTokenStorageKey,
          value: normalized.wanHfToken,
        );
        await _secureStorage.write(
          key: _threeDApiKeyStorageKey,
          value: normalized.threeDApiKey,
        );
      } catch (_) {}
    }
    await prefs.setString('cfg_openai_base', normalized.openAiBaseUrl);
    await prefs.setString('cfg_openai_model', normalized.openAiModel);
    await prefs.setString(
      'cfg_openai_image_model',
      normalized.openAiImageModel,
    );
    await prefs.setString(
      'cfg_openai_image_api_mode',
      normalized.imageApiMode.name,
    );
    await prefs.setString(
      'cfg_openai_image_edit_api_mode',
      normalized.imageEditApiMode.name,
    );
    await prefs.setString('cfg_video_base', normalized.videoApiBaseUrl);
    await prefs.setString('cfg_wan_hf_space_url', normalized.wanHfSpaceUrl);
    await prefs.setString('cfg_video_model', normalized.videoModel);
    await prefs.setString('cfg_video_mode', normalized.videoProviderMode.name);
    await prefs.setString('cfg_comfyui_path', normalized.comfyUiPath);
    await prefs.setInt('cfg_comfyui_port', normalized.comfyUiPort);
    await prefs.setBool('cfg_three_d_enabled', normalized.threeDEnabled);
    await prefs.setString('cfg_three_d_base_url', normalized.threeDBaseUrl);
    await prefs.setString('cfg_three_d_provider', normalized.threeDProvider);
    await prefs.setString('cfg_user_name', normalized.currentUserName);
    final accountId = _currentBackendAccountId();
    if (accountId == null || accountId.isEmpty) {
      await prefs.remove('cfg_user_name_owner');
    } else {
      await prefs.setString('cfg_user_name_owner', accountId);
    }
    state = normalized;
  }
}
