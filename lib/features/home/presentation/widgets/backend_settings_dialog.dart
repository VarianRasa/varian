import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_app_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/ai/data/comfy_ui_bridge_manager.dart';
import 'package:varian/features/ai/data/comfy_ui_setup.dart';
import 'package:varian/features/ai/data/three_d_generation_provider.dart';
import 'package:varian/features/ai/data/video_provider.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/auth/state/auth_provider.dart';

class BackendSettingsDialog extends ConsumerStatefulWidget {
  const BackendSettingsDialog({super.key});

  @override
  ConsumerState<BackendSettingsDialog> createState() =>
      _BackendSettingsDialogState();
}

class _BackendSettingsDialogState extends ConsumerState<BackendSettingsDialog> {
  late final TextEditingController _supabaseUrlCtrl;
  late final TextEditingController _supabaseKeyCtrl;
  late final TextEditingController _openAiKeyCtrl;
  late final TextEditingController _openAiBaseCtrl;
  late final TextEditingController _openAiModelCtrl;
  late final TextEditingController _openAiImageModelCtrl;
  late final TextEditingController _videoKeyCtrl;
  late final TextEditingController _videoBaseCtrl;
  late final TextEditingController _videoBridgeTokenCtrl;
  late final TextEditingController _wanHfSpaceUrlCtrl;
  late final TextEditingController _wanHfTokenCtrl;
  late final TextEditingController _videoModelCtrl;
  late final TextEditingController _comfyUiPathCtrl;
  late final TextEditingController _comfyUiPortCtrl;
  late final TextEditingController _threeDBaseCtrl;
  late final TextEditingController _threeDTokenCtrl;
  late final ComfyUiSetupService _comfyUiSetupService;
  late ImageApiMode _imageApiMode;
  late ImageEditApiMode _imageEditApiMode;
  late VideoProviderMode _videoProviderMode;
  late bool _threeDEnabled;
  late String _threeDProvider;
  late final TextEditingController _userNameCtrl;

  bool _isTestingSupabase = false;
  String? _supabaseTestResult;
  bool? _supabaseTestSuccess;
  bool _isTestingOpenAi = false;
  String? _openAiTestResult;
  bool? _openAiTestSuccess;
  bool _isTestingVideo = false;
  String? _videoTestResult;
  bool _isInstallingComfyUi = false;
  double _comfyUiInstallProgress = 0;
  String? _comfyUiSetupResult;
  bool? _comfyUiSetupSuccess;
  ComfyUiSetupCancellation? _comfyUiCancellation;
  bool? _videoTestSuccess;
  bool _isTestingThreeD = false;
  String? _threeDTestResult;
  bool? _threeDTestSuccess;
  List<String> _discoveredImageModels = const [];
  bool _configBound = false;

  bool get _canEditSupabase =>
      kDebugMode || SupabaseAppConfig.allowRuntimeConfiguration;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(backendConfigProvider);
    _supabaseUrlCtrl = TextEditingController(text: cfg.supabaseUrl);
    _supabaseKeyCtrl = TextEditingController(text: cfg.supabaseAnonKey);
    _openAiKeyCtrl = TextEditingController(text: cfg.openAiApiKey);
    _openAiBaseCtrl = TextEditingController(text: cfg.openAiBaseUrl);
    _openAiModelCtrl = TextEditingController(text: cfg.openAiModel);
    _openAiImageModelCtrl = TextEditingController(text: cfg.openAiImageModel);
    _videoKeyCtrl = TextEditingController(text: cfg.videoApiKey);
    _videoBaseCtrl = TextEditingController(text: cfg.videoApiBaseUrl);
    _videoBridgeTokenCtrl = TextEditingController(text: cfg.videoBridgeToken);
    _wanHfSpaceUrlCtrl = TextEditingController(text: cfg.wanHfSpaceUrl);
    _wanHfTokenCtrl = TextEditingController(text: cfg.wanHfToken);
    _videoModelCtrl = TextEditingController(
      text: cfg.videoProviderMode == VideoProviderMode.comfyUiBridge
          ? comfyUiBridgeModel
          : cfg.videoModel,
    );
    _comfyUiPathCtrl = TextEditingController(text: cfg.comfyUiPath);
    _comfyUiPortCtrl = TextEditingController(text: cfg.comfyUiPort.toString());
    _threeDBaseCtrl = TextEditingController(text: cfg.threeDBaseUrl);
    _threeDTokenCtrl = TextEditingController(text: cfg.threeDApiKey);
    _comfyUiSetupService = createComfyUiSetupService();
    _imageApiMode = cfg.imageApiMode;
    _imageEditApiMode = cfg.imageEditApiMode;
    _videoProviderMode = cfg.videoProviderMode;
    _threeDEnabled = cfg.threeDEnabled;
    _threeDProvider = cfg.threeDProvider;
    final client = ref.read(supabaseClientProvider);
    final stableId =
        client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        'local-device';
    _userNameCtrl = TextEditingController(
      text: CollaborationDisplayNameGenerator.resolve(
        stableId: stableId,
        preferredName: cfg.currentUserName,
      ),
    );
    _configBound = false;
  }

  void _bindConfig(BackendConfig cfg) {
    if (_configBound) return;
    _supabaseUrlCtrl.text = cfg.supabaseUrl;
    _supabaseKeyCtrl.text = cfg.supabaseAnonKey;
    _openAiKeyCtrl.text = cfg.openAiApiKey;
    _openAiBaseCtrl.text = cfg.openAiBaseUrl;
    _openAiModelCtrl.text = cfg.openAiModel;
    _openAiImageModelCtrl.text = cfg.openAiImageModel;
    _videoKeyCtrl.text = cfg.videoApiKey;
    _videoBaseCtrl.text = cfg.videoApiBaseUrl;
    _videoBridgeTokenCtrl.text = cfg.videoBridgeToken;
    _wanHfSpaceUrlCtrl.text = cfg.wanHfSpaceUrl;
    _wanHfTokenCtrl.text = cfg.wanHfToken;
    _videoModelCtrl.text =
        cfg.videoProviderMode == VideoProviderMode.comfyUiBridge
        ? comfyUiBridgeModel
        : cfg.videoModel;
    _comfyUiPathCtrl.text = cfg.comfyUiPath;
    _comfyUiPortCtrl.text = cfg.comfyUiPort.toString();
    _threeDBaseCtrl.text = cfg.threeDBaseUrl;
    _threeDTokenCtrl.text = cfg.threeDApiKey;
    _userNameCtrl.text = cfg.currentUserName;
    _imageApiMode = cfg.imageApiMode;
    _imageEditApiMode = cfg.imageEditApiMode;
    _videoProviderMode = cfg.videoProviderMode;
    _threeDEnabled = cfg.threeDEnabled;
    _threeDProvider = cfg.threeDProvider;
    _configBound = true;
  }

  @override
  void dispose() {
    _comfyUiCancellation?.cancel();
    _supabaseUrlCtrl.dispose();
    _supabaseKeyCtrl.dispose();
    if (kIsWeb) {
      _openAiKeyCtrl.clear();
      _videoKeyCtrl.clear();
      _videoBridgeTokenCtrl.clear();
      _wanHfTokenCtrl.clear();
      _threeDTokenCtrl.clear();
    }
    _openAiKeyCtrl.dispose();
    _openAiBaseCtrl.dispose();
    _openAiModelCtrl.dispose();
    _openAiImageModelCtrl.dispose();
    _videoKeyCtrl.dispose();
    _videoBaseCtrl.dispose();
    _videoBridgeTokenCtrl.dispose();
    _wanHfSpaceUrlCtrl.dispose();
    _wanHfTokenCtrl.dispose();
    _videoModelCtrl.dispose();
    _comfyUiPathCtrl.dispose();
    _comfyUiPortCtrl.dispose();
    _threeDBaseCtrl.dispose();
    _threeDTokenCtrl.dispose();
    _userNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSupabaseTest() async {
    setState(() {
      _isTestingSupabase = true;
      _supabaseTestResult = null;
      _supabaseTestSuccess = null;
    });
    final (ok, error) = await testSupabaseConnection(
      url: _supabaseUrlCtrl.text,
      publishableKey: _supabaseKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _isTestingSupabase = false;
      _supabaseTestSuccess = ok;
      _supabaseTestResult = ok
          ? 'Connected successfully'
          : (error ?? 'Connection failed');
    });
  }

  Future<void> _runOpenAiTest() async {
    setState(() {
      _isTestingOpenAi = true;
      _openAiTestResult = null;
      _openAiTestSuccess = null;
      _discoveredImageModels = const [];
    });
    final tempConfig = BackendConfig(
      openAiApiKey: _openAiKeyCtrl.text.trim(),
      openAiBaseUrl: _openAiBaseCtrl.text.trim().isEmpty
          ? 'https://api.openai.com/v1'
          : _openAiBaseCtrl.text.trim(),
      openAiModel: _openAiModelCtrl.text.trim().isEmpty
          ? 'gpt-4o-mini'
          : _openAiModelCtrl.text.trim(),
      openAiImageModel: _openAiImageModelCtrl.text.trim().isEmpty
          ? 'gpt-image-2'
          : _openAiImageModelCtrl.text.trim(),
      imageApiMode: _imageApiMode,
      imageEditApiMode: _imageEditApiMode,
    );

    final (ok, error) = await tempConfig.testOpenAiConnection();
    final imageModels = ok
        ? await tempConfig.discoverImageModels()
        : const <String>[];
    if (!mounted) return;
    setState(() {
      _isTestingOpenAi = false;
      _discoveredImageModels = imageModels;
      _openAiTestSuccess = ok;
      _openAiTestResult = ok
          ? imageModels.isEmpty
                ? 'Chat API connected. The endpoint did not advertise image models; the manual image model name will be used.'
                : 'Chat API connected. Found ${imageModels.length} advertised image model(s).'
          : (error ?? 'API test failed');
    });
  }

  Future<void> _installComfyUi() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      setState(() {
        _comfyUiSetupSuccess = false;
        _comfyUiSetupResult = 'ComfyUI setup is supported only on Windows.';
      });
      return;
    }
    var destination = _comfyUiPathCtrl.text.trim();
    if (destination.isEmpty) {
      destination = await _comfyUiSetupService.defaultInstallationPath();
      if (!mounted) return;
      _comfyUiPathCtrl.text = destination;
    }
    if (!mounted) return;
    final downloadSources = comfyUiSetupManifest.assets
        .where((asset) => !asset.isBundled)
        .map((asset) => '${asset.fileName}: ${asset.source}')
        .join('\n');
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Install local ComfyUI provider',
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 640,
          maxHeight: 680,
        ),
        builder: (context, style) => ConstrainedBox(
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 640,
            maxHeight: 680,
          ),
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Install local ComfyUI provider?',
                    style: style.titleTextStyle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'This downloads approximately ${_formatBytes(comfyUiSetupManifest.totalDownloadBytes)} of pinned ComfyUI and LTX-Video assets, then installs them at:\n\n$destination\n\nVersion: ${comfyUiSetupManifest.comfyUiVersion}\nProfile: ${comfyUiSetupManifest.profile}\nRequired free space: ${_formatBytes(comfyUiSetupManifest.requiredDiskBytes)}\nLicense: ${comfyUiSetupManifest.licenseSummary}\nLicense details:\n${comfyUiSetupManifest.licenseUrls.join('\n')}\n\nSources:\n$downloadSources\n\nNo download starts until you confirm.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        variant: UiButtonVariant.ghost,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Download and install'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final cancellation = ComfyUiSetupCancellation();
    setState(() {
      _isInstallingComfyUi = true;
      _comfyUiInstallProgress = 0;
      _comfyUiCancellation = cancellation;
      _comfyUiSetupSuccess = null;
      _comfyUiSetupResult = 'Downloading and verifying pinned assets...';
    });
    try {
      await _comfyUiSetupService.install(
        destination: destination,
        confirmed: true,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _comfyUiInstallProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _isInstallingComfyUi = false;
        _comfyUiCancellation = null;
        _comfyUiInstallProgress = 1;
        _comfyUiSetupSuccess = true;
        _comfyUiSetupResult = 'ComfyUI and the LTX workflow are installed.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInstallingComfyUi = false;
        _comfyUiCancellation = null;
        _comfyUiSetupSuccess = false;
        _comfyUiSetupResult = error is VideoProviderException
            ? error.message
            : error.toString();
      });
    }
  }

  void _cancelComfyUiInstall() {
    _comfyUiCancellation?.cancel();
  }

  String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  Future<void> _runVideoTest() async {
    setState(() {
      _isTestingVideo = true;
      _videoTestResult = null;
      _videoTestSuccess = null;
    });
    try {
      final tempConfig = BackendConfig(
        openAiApiKey: _openAiKeyCtrl.text.trim(),
        openAiBaseUrl: _openAiBaseCtrl.text.trim().isEmpty
            ? 'https://api.openai.com/v1'
            : _openAiBaseCtrl.text.trim(),
        videoApiKey: _videoKeyCtrl.text.trim(),
        videoApiBaseUrl: _videoBaseCtrl.text.trim(),
        videoBridgeToken: _videoBridgeTokenCtrl.text.trim(),
        wanHfSpaceUrl: _wanHfSpaceUrlCtrl.text.trim(),
        wanHfToken: _wanHfTokenCtrl.text.trim(),
        videoModel: _videoModelCtrl.text.trim(),
        videoProviderMode: _videoProviderMode,
        comfyUiPath: _comfyUiPathCtrl.text.trim(),
        comfyUiPort: int.tryParse(_comfyUiPortCtrl.text.trim()) ?? 8188,
      );
      if (!tempConfig.isVideoConfigured) {
        throw const FormatException(
          'Configure a video API key, valid video base URL, and video model first.',
        );
      }
      if (_videoProviderMode == VideoProviderMode.ffmpeg) {
        throw const FormatException(
          'FFmpeg fallback is not available in this build.',
        );
      }
      final VideoProviderClient provider;
      if (_videoProviderMode == VideoProviderMode.wanGradio) {
        provider = WanGradioVideoProviderClient(
          spaceUrl: tempConfig.wanHfSpaceUrl,
          hfToken: tempConfig.wanHfToken,
        );
      } else if (_videoProviderMode == VideoProviderMode.comfyUiBridge) {
        final bridge = createComfyUiBridgeManager();
        provider = ComfyUiBridgeVideoProviderClient(
          delegate: OpenAiVideosProviderClient(
            baseUrl: tempConfig.effectiveVideoBaseUrl,
            apiKey: tempConfig.effectiveVideoApiKey,
            model: tempConfig.videoModel,
          ),
          ensureReady: () => bridge.ensureReady(
            installationPath: tempConfig.comfyUiPath,
            comfyUiPort: tempConfig.comfyUiPort,
            bridgeToken: tempConfig.videoBridgeToken,
          ),
        );
      } else {
        provider = OpenAiVideosProviderClient(
          baseUrl: tempConfig.effectiveVideoBaseUrl,
          apiKey: tempConfig.effectiveVideoApiKey,
          model: tempConfig.videoModel,
        );
      }
      final (ok, error) = await provider.testConnection();
      if (!mounted) return;
      setState(() {
        _isTestingVideo = false;
        _videoTestSuccess = ok;
        _videoTestResult = ok
            ? (error ??
                  (_videoProviderMode == VideoProviderMode.wanGradio
                      ? 'Wan2.1 Space reachable. No video job was created.'
                      : _videoProviderMode == VideoProviderMode.comfyUiBridge
                      ? 'ComfyUI bridge reachable. No video job was created.'
                      : 'Video API reachable. No video job was created.'))
            : (error ?? 'Video API test failed.');
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _isTestingVideo = false;
        _videoTestSuccess = false;
        _videoTestResult = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isTestingVideo = false;
        _videoTestSuccess = false;
        _videoTestResult = error.toString();
      });
    }
  }

  Future<void> _runThreeDTest() async {
    setState(() {
      _isTestingThreeD = true;
      _threeDTestResult = null;
      _threeDTestSuccess = null;
    });
    try {
      final provider = HttpThreeDGenerationProvider(
        baseUrl: _threeDBaseCtrl.text.trim().isEmpty
            ? 'http://127.0.0.1:20130/v1'
            : _threeDBaseCtrl.text.trim(),
        apiKey: _threeDTokenCtrl.text.trim(),
      );
      final (ok, error) = await provider.testConnection();
      if (!mounted) return;
      setState(() {
        _isTestingThreeD = false;
        _threeDTestSuccess = ok;
        _threeDTestResult = ok
            ? '3D worker reachable. No model job was created.'
            : (error ?? '3D worker health check failed.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isTestingThreeD = false;
        _threeDTestSuccess = false;
        _threeDTestResult = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(backendConfigReadyProvider);
    if (readiness.isLoading) {
      return _buildReadinessDialog(context, loading: true);
    }
    if (readiness.hasError) {
      return _buildReadinessDialog(context, loading: false);
    }
    _bindConfig(ref.read(backendConfigProvider));
    final tokens = context.appTokens;
    final width = AppResponsive.dialogWidth(context, preferred: 540);
    return UiDialog(
      semanticsLabel: 'Backend and live integrations',
      constraints: AppResponsive.dialogConstraints(context, maxWidth: 540),
      builder: (context, style) => SizedBox(
        width: width,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings_ethernet,
                      color: tokens.accent,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        'BACKEND & LIVE INTEGRATIONS',
                        style: style.titleTextStyle,
                      ),
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close backend settings',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.pageWide),
                _buildSectionHeader('COLLABORATION USER IDENTITY'),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  'Your Display Name',
                  _userNameCtrl,
                  'e.g. Alex Doe',
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_canEditSupabase) ...[
                  _buildSectionHeaderWithAction(
                    'SUPABASE BACKEND (REALTIME & CLOUD DB)',
                    'Test Connection',
                    _isTestingSupabase ? null : _runSupabaseTest,
                    _isTestingSupabase,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField(
                    'Supabase Project URL',
                    _supabaseUrlCtrl,
                    'https://your-project.supabase.co',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField(
                    'Anon Public Key',
                    _supabaseKeyCtrl,
                    'eyJhbGciOi...',
                    obscure: true,
                  ),
                  if (_supabaseTestResult != null) ...[
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    _buildTestBanner(
                      _supabaseTestSuccess == true,
                      _supabaseTestResult!,
                    ),
                  ],
                ] else ...[
                  Text(
                    'Supabase connection is managed by this app build. Ask the publisher to update the application configuration.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (kIsWeb) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    child: UiSurface(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      color: tokens.warning.withValues(alpha: 0.12),
                      child: Text(
                        'Browser-session provider keys can be inspected by you and browser extensions, and are sent directly to the selected provider. They are not protected from same-origin script compromise.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall!.copyWith(color: tokens.warning),
                      ),
                    ),
                  ),
                ],
                _buildSectionHeaderWithAction(
                  'AI SYNTHESIS PROVIDER (OPENAI / OLLAMA)',
                  'Test AI API',
                  _isTestingOpenAi ? null : _runOpenAiTest,
                  _isTestingOpenAi,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  'API Key',
                  _openAiKeyCtrl,
                  'sk-proj-...',
                  obscure: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  'API Base URL',
                  _openAiBaseCtrl,
                  'https://api.openai.com/v1 or http://localhost:11434/v1',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  'Chat Model Identifier',
                  _openAiModelCtrl,
                  'gpt-4o-mini / llama3.2',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  'Image Generator Model',
                  _openAiImageModelCtrl,
                  'gpt-image-2 / dall-e-3 / flux / custom-combo',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This checks endpoint connectivity and model names only; it does not verify image generation or editing support.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                UiSelect<ImageApiMode>(
                  label: 'Image Generation API Mode',
                  hint: 'Choose how the provider receives image requests',
                  items: const {
                    'Auto (recommended)': ImageApiMode.auto,
                    'Responses': ImageApiMode.responses,
                    'Chat Completions': ImageApiMode.chatCompletions,
                    'Images Generations': ImageApiMode.imagesGenerations,
                  },

                  value: _imageApiMode,
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() {
                      _imageApiMode = mode;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                UiSelect<ImageEditApiMode>(
                  label: 'Image Editing API Route',
                  hint: 'Choose the route used for image-to-image edits',
                  items: const {
                    'Auto (fallback on unsupported route)':
                        ImageEditApiMode.auto,
                    'Images Edits': ImageEditApiMode.imagesEdits,
                    'Responses': ImageEditApiMode.responses,
                    'Chat Completions': ImageEditApiMode.chatCompletions,
                  },
                  value: _imageEditApiMode,
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() {
                      _imageEditApiMode = mode;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                Text(
                  'OpenAI-compatible providers differ. A successful API connection does not confirm that the selected route and model can return edited images.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
                if (_discoveredImageModels.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  UiSelect<String>(
                    label: 'Detected Image Models',
                    hint: 'Select a detected image model',
                    items: {
                      for (final model in _discoveredImageModels) model: model,
                    },
                    value:
                        _discoveredImageModels.contains(
                          _openAiImageModelCtrl.text.trim(),
                        )
                        ? _openAiImageModelCtrl.text.trim()
                        : null,
                    onChanged: (model) {
                      if (model == null) return;
                      setState(() {
                        _openAiImageModelCtrl.text = model;
                      });
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildSectionHeaderWithAction(
                  'VIDEO GENERATION PROVIDER',
                  'Test Video API',
                  _isTestingVideo ? null : _runVideoTest,
                  _isTestingVideo,
                ),
                const SizedBox(height: AppSpacing.sm),
                UiSelect<VideoProviderMode>(
                  label: 'Video Provider Mode',
                  hint: 'Choose the image-to-video provider',
                  items: const {
                    'OpenAI-compatible Videos API':
                        VideoProviderMode.openAiVideos,
                    'ComfyUI local bridge (LTX 0.9.5 2B)':
                        VideoProviderMode.comfyUiBridge,
                    'Wan2.1 Fast (Hugging Face BYOK; no subscription)':
                        VideoProviderMode.wanGradio,
                    'Invalid saved mode (select again)':
                        VideoProviderMode.invalid,
                  },

                  value: _videoProviderMode,
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() {
                      _videoProviderMode = mode;
                      if (mode == VideoProviderMode.comfyUiBridge) {
                        _videoModelCtrl.text = comfyUiBridgeModel;
                      }
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_videoProviderMode == VideoProviderMode.wanGradio) ...[
                  _buildField(
                    'Hugging Face Space URL',
                    _wanHfSpaceUrlCtrl,
                    WanGradioVideoProviderClient.defaultSpaceUrl,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField(
                    'Hugging Face Access Token (BYOK)',
                    _wanHfTokenCtrl,
                    'Optional for public Space; hf_… token',
                    obscure: true,
                  ),
                ] else if (_videoProviderMode ==
                    VideoProviderMode.comfyUiBridge) ...[
                  _buildField(
                    'Local Bridge Token',
                    _videoBridgeTokenCtrl,
                    '24+ characters; never use an OpenAI key',
                    obscure: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField(
                    'ComfyUI Installation Path',
                    _comfyUiPathCtrl,
                    r'C:\AI\ComfyUI_windows_portable',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField('ComfyUI Port', _comfyUiPortCtrl, '8188'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildSectionHeaderWithAction(
                    'LOCAL COMFYUI SETUP',
                    _isInstallingComfyUi
                        ? 'Downloading...'
                        : 'Install pinned assets',
                    _isInstallingComfyUi ? null : _installComfyUi,
                    _isInstallingComfyUi,
                  ),
                  const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                  Text(
                    'Windows only. Downloads ${_formatBytes(comfyUiSetupManifest.totalDownloadBytes)} plus temporary extraction space. The path above must not exist yet, or must be an existing completed installation.',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                  ),
                  if (_isInstallingComfyUi) ...[
                    const SizedBox(height: AppSpacing.sm),
                    UiLinearProgressIndicator(
                      value: _comfyUiInstallProgress,
                      height: 4,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: UiButton(
                        variant: UiButtonVariant.ghost,
                        size: UiButtonSize.sm,
                        onPressed: _cancelComfyUiInstall,
                        child: const Text('Cancel download'),
                      ),
                    ),
                  ],
                  if (_comfyUiSetupResult != null) ...[
                    const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                    _buildTestBanner(
                      _comfyUiSetupSuccess == true,
                      _comfyUiSetupResult!,
                    ),
                  ],
                ] else ...[
                  _buildField(
                    'Video API Key (optional override)',
                    _videoKeyCtrl,
                    'Uses general API key when empty',
                    obscure: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildField(
                    'Video API Base URL (optional override)',
                    _videoBaseCtrl,
                    'Uses general base URL when empty',
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (_videoProviderMode != VideoProviderMode.wanGradio)
                  _buildField(
                    'Video Model Identifier',
                    _videoModelCtrl,
                    _videoProviderMode == VideoProviderMode.comfyUiBridge
                        ? comfyUiBridgeModel
                        : 'sora-2 / provider-video-model',
                    readOnly:
                        _videoProviderMode == VideoProviderMode.comfyUiBridge,
                  ),
                const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                Text(
                  _videoProviderMode == VideoProviderMode.comfyUiBridge
                      ? 'ComfyUI bridge keeps the OpenAI-compatible /v1/videos contract and runs the allowlisted LTX-Video 0.9.5 2B workflow locally. It uses the separate local bridge token, not an OpenAI key. Setup downloads only after confirmation. RTX 4050 6 GB is best-effort and may be slow or run out of memory.'
                      : _videoProviderMode == VideoProviderMode.wanGradio
                      ? 'Wan2.1 is an open-weight image-to-video model served through the selected Hugging Face Space. No paid video API subscription is required. The optional HF token is sent only to this Space API; video downloads never receive it. Public Spaces have shared queues and quotas. The generated clip is short (about 2–3.4 seconds).'
                      : 'OpenAI-compatible does not guarantee video support. The provider must implement POST /videos with input_reference, seconds, and size. Empty video key/base uses the general AI settings. Web API keys remain visible in the browser session.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.warning),
                ),
                if (_videoTestResult != null) ...[
                  const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                  _buildTestBanner(
                    _videoTestSuccess == true,
                    _videoTestResult!,
                  ),
                ],
                if (ref.watch(backendConfigProvider).webEndpointWarning
                    case final warning?) ...[
                  const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                  _buildTestBanner(false, warning),
                ],
                if (_openAiTestResult != null) ...[
                  const SizedBox(height: AppSpacing.sm - AppSpacing.xxs),
                  _buildTestBanner(
                    _openAiTestSuccess == true,
                    _openAiTestResult!,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _buildSectionHeaderWithAction(
                  '3D MODEL GENERATION WORKER',
                  'Test 3D worker',
                  _isTestingThreeD ? null : _runThreeDTest,
                  _isTestingThreeD,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _threeDEnabled
                            ? '3D generation enabled'
                            : '3D generation disabled',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall!.copyWith(color: tokens.text),
                      ),
                    ),
                    UiSwitch(
                      value: _threeDEnabled,
                      onChange: (value) => setState(() {
                        _threeDEnabled = value;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                UiSelect<String>(
                  label: '3D Provider',
                  hint: 'Choose the worker provider',
                  items: const {
                    'TripoSR (image → 3D)': 'triposr',
                    'TRELLIS (text/image → 3D)': 'trellis',
                    'FAL TRELLIS.2 (hosted, metered)': 'fal-trellis2',
                    'Hunyuan3D (text/image → 3D)': 'hunyuan3d',
                    'ComfyUI workflow (text/image → 3D)': 'comfyui',
                  },
                  value:
                      const [
                        'triposr',
                        'trellis',
                        'fal-trellis2',
                        'hunyuan3d',
                        'comfyui',
                      ].contains(_threeDProvider)
                      ? _threeDProvider
                      : 'triposr',
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _threeDProvider = value;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  '3D Worker Base URL',
                  _threeDBaseCtrl,
                  'http://127.0.0.1:20130/v1 or https://worker.example/v1',
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildField(
                  '3D Worker Token (optional)',
                  _threeDTokenCtrl,
                  'Required only when the worker is protected',
                  obscure: true,
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  'The worker must expose GET /health and the async /3d/jobs contract. TripoSR needs a reference image; TRELLIS or Hunyuan3D can handle text input when installed on the worker. Do not put model-provider keys in canvas metadata.',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.warning),
                ),
                if (_threeDTestResult != null) ...[
                  const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                  _buildTestBanner(
                    _threeDTestSuccess == true,
                    _threeDTestResult!,
                  ),
                ],
                const SizedBox(height: AppSpacing.pageWide),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    UiButton(
                      onPressed: () => Navigator.pop(context),
                      variant: UiButtonVariant.ghost,
                      child: const Text('Cancel'),
                    ),
                    UiButton(
                      onPressed: _isInstallingComfyUi
                          ? null
                          : () async {
                              try {
                                await ref
                                    .read(backendConfigProvider.notifier)
                                    .waitUntilReady();
                                final currentConfig = ref.read(
                                  backendConfigProvider,
                                );
                                final updatedConfig = BackendConfig(
                                  supabaseUrl: _canEditSupabase
                                      ? _supabaseUrlCtrl.text.trim()
                                      : currentConfig.supabaseUrl,
                                  supabaseAnonKey: _canEditSupabase
                                      ? _supabaseKeyCtrl.text.trim()
                                      : currentConfig.supabaseAnonKey,
                                  openAiApiKey: _openAiKeyCtrl.text.trim(),
                                  openAiBaseUrl:
                                      _openAiBaseCtrl.text.trim().isEmpty
                                      ? 'https://api.openai.com/v1'
                                      : _openAiBaseCtrl.text.trim(),
                                  openAiModel:
                                      _openAiModelCtrl.text.trim().isEmpty
                                      ? 'gpt-4o-mini'
                                      : _openAiModelCtrl.text.trim(),
                                  openAiImageModel:
                                      _openAiImageModelCtrl.text.trim().isEmpty
                                      ? 'gpt-image-2'
                                      : _openAiImageModelCtrl.text.trim(),
                                  imageApiMode: _imageApiMode,
                                  imageEditApiMode: _imageEditApiMode,
                                  videoApiKey: _videoKeyCtrl.text.trim(),
                                  videoApiBaseUrl: _videoBaseCtrl.text.trim(),
                                  videoBridgeToken: _videoBridgeTokenCtrl.text
                                      .trim(),
                                  wanHfSpaceUrl: _wanHfSpaceUrlCtrl.text.trim(),
                                  wanHfToken: _wanHfTokenCtrl.text.trim(),
                                  videoModel: _videoModelCtrl.text.trim(),
                                  videoProviderMode: _videoProviderMode,
                                  comfyUiPath: _comfyUiPathCtrl.text.trim(),
                                  comfyUiPort:
                                      int.tryParse(
                                        _comfyUiPortCtrl.text.trim(),
                                      ) ??
                                      8188,
                                  threeDEnabled: _threeDEnabled,
                                  threeDBaseUrl: _threeDBaseCtrl.text.trim(),
                                  threeDApiKey: _threeDTokenCtrl.text.trim(),
                                  threeDProvider: _threeDProvider,
                                  currentUserName:
                                      CollaborationDisplayNameGenerator.validate(
                                        _userNameCtrl.text,
                                      ),
                                );
                                final supabaseConfigChanged =
                                    _canEditSupabase &&
                                    (updatedConfig.supabaseUrl !=
                                            currentConfig.supabaseUrl ||
                                        updatedConfig.supabaseAnonKey !=
                                            currentConfig.supabaseAnonKey);
                                await ref
                                    .read(backendConfigProvider.notifier)
                                    .saveConfig(updatedConfig);
                                if (supabaseConfigChanged) {
                                  await initializeSupabaseFromConfig(
                                    url: updatedConfig.supabaseUrl,
                                    publishableKey:
                                        updatedConfig.supabaseAnonKey,
                                  );
                                  defaultSupabaseBootstrap.markReady();
                                  invalidateAuthProviders(ref);
                                  ref.invalidate(supabaseSyncServiceProvider);
                                }
                                if (!context.mounted) return;

                                showUiToast(
                                  context,
                                  'Backend configuration saved and applied.',
                                  variant: UiToastVariant.success,
                                );
                                Navigator.pop(context);
                              } on FormatException catch (error) {
                                if (!context.mounted) return;
                                setState(() {
                                  _videoTestSuccess = false;
                                  _videoTestResult = error.message;
                                });
                              } on StateError catch (error) {
                                if (!context.mounted) return;
                                setState(() {
                                  _videoTestSuccess = false;
                                  _videoTestResult = error.message;
                                });
                              } catch (_) {
                                if (!context.mounted) return;
                                setState(() {
                                  _videoTestSuccess = false;
                                  _videoTestResult =
                                      'Backend configuration could not be applied. Verify the values and try again.';
                                });
                              }
                            },
                      prefix: const Icon(Icons.save_outlined),
                      child: const Text('Save & Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadinessDialog(BuildContext context, {required bool loading}) {
    final tokens = context.appTokens;
    return UiDialog(
      semanticsLabel: 'Backend settings readiness',
      constraints: AppResponsive.dialogConstraints(context, maxWidth: 540),
      builder: (context, style) => Padding(
        padding: AppResponsive.dialogPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              loading ? Icons.hourglass_top_outlined : Icons.cloud_off_outlined,
              color: loading ? tokens.info : tokens.danger,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              loading
                  ? 'Backend settings are loading'
                  : 'Backend settings are unavailable',
              textAlign: TextAlign.center,
              style: style.titleTextStyle,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              loading
                  ? 'Saved configuration will appear when local settings are ready.'
                  : 'Saved values were not changed. Retry when local storage is available.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(
              height: AppSpacing.md + AppSpacing.sm - AppSpacing.xxs,
            ),
            if (loading)
              const Center(child: UiProgressIndicator())
            else
              UiButton(
                onPressed: () async {
                  await ref.read(backendConfigProvider.notifier).reload();
                  ref.invalidate(backendConfigReadyProvider);
                },
                prefix: const Icon(Icons.refresh_outlined),
                child: const Text('RETRY'),
              ),
            const SizedBox(height: AppSpacing.sm),
            UiButton(
              onPressed: () => Navigator.of(context).pop(),
              variant: UiButtonVariant.ghost,
              child: const Text('CLOSE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) => UiSectionHeader(title: title);

  Widget _buildSectionHeaderWithAction(
    String title,
    String action,
    VoidCallback? onPressed,
    bool loading,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final button = UiButton(
        onPressed: onPressed,
        variant: UiButtonVariant.ghost,
        size: UiButtonSize.sm,
        prefix: loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: UiProgressIndicator(),
              )
            : const Icon(Icons.speed_outlined),
        child: Text(action),
      );
      if (constraints.maxWidth < 380) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiSectionHeader(title: title),
            button,
          ],
        );
      }
      return UiSectionHeader(title: title, trailing: button);
    },
  );

  Widget _buildField(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    bool readOnly = false,
  }) {
    return UiTextField(
      controller: controller,
      label: label,
      hint: hint,
      obscureText: obscure,
      readOnly: readOnly,
    );
  }

  Widget _buildTestBanner(bool success, String message) {
    final tokens = context.appTokens;
    final color = success ? tokens.success : tokens.danger;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${success ? 'Connection test succeeded' : 'Connection test failed'}: $message',
      child: UiSurface(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + AppSpacing.xxs,
          vertical: AppSpacing.xs + AppSpacing.xxs,
        ),
        color: color.withValues(alpha: 0.12),
        child: Row(
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              size: 14,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
