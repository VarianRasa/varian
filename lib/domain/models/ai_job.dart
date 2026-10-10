import 'ai_artifact.dart';
import 'durable_asset_reference.dart';

enum AIJobStatus { queued, processing, completed, failed, canceled }

enum AIOutputMode { insert, replace, compare }

enum AICreativeCategory {
  generation,
  generativeEditing,
  visualTransformation,
  enhancement,
  compositionAI,
  videoAI,
  aiAssistant,
}

enum AICapability {
  // 1. Generation
  textToImage,
  sketchToImage,
  imageToImage,
  imageToVideo,
  referenceToImage,
  textTo3D,
  imageTo3D,

  // 2. Generative Editing
  inpainting,
  outpainting,
  replaceObject,
  removeObject,
  addObject,
  backgroundReplace,

  // 3. Visual Transformation
  styleTransfer,
  materialTransfer,
  relighting,
  recolor,
  restyle,

  // 4. Enhancement
  upscale,
  denoise,
  sharpen,
  restore,
  detailEnhancement,

  // 5. Composition AI
  populate,
  compositionRemove,
  rearrange,
  expandScene,
  smartCutout,

  // 6. Video AI
  videoFromImage,
  firstLastFrame,
  cameraMotion,
  animateObject,
  videoRestyle,

  // 7. AI Assistant
  understandCanvas,
  understandSelection,
  callTools,
  agentGenerate,
  agentEdit,
  agentArrange,

  // Legacy / Workflow
  summarizeNotes,
  promptToDiagram,
}

class AICreativeParams {
  final String? negativePrompt;
  final String? stylePreset;
  final double denoisingStrength;
  final double guidanceScale;
  final int seed;
  final String? controlNetType;
  final double controlNetStrength;

  /// Runtime-only wire input. Durable job serializers omit this value.
  final String? sourceImageBase64;

  /// Runtime-only delivery input. Durable job serializers omit this value.
  final String? sourceImageUrl;

  /// Durable identity for the selected source image. Bytes are hydrated only
  /// at the provider boundary.
  final String? sourceImageArtifactReference;
  final String? sourceImageStoragePath;
  final String? sourceImageMimeType;
  final int? sourceImageByteLength;
  final String? maskImageBase64;
  final Map<String, dynamic>? maskPayload;
  final String? referenceImageUrl;
  final String? secondFrameImageUrl;
  final String? cameraMotionType;
  final int upscaleFactor;
  final String? materialType;
  final String? relightingPreset;
  final String? entourageCategory;
  final String? threeDProvider;
  final String meshQuality;
  final String textureMode;
  final String targetFormat;
  final String? sourceModelReference;
  final int triangleBudget;
  final bool generatePreview;
  final Map<String, dynamic> extraConfig;

  const AICreativeParams({
    this.negativePrompt,
    this.stylePreset,
    this.denoisingStrength = 0.75,
    this.guidanceScale = 7.5,
    this.seed = -1,
    this.controlNetType,
    this.controlNetStrength = 1.0,
    this.sourceImageBase64,
    this.sourceImageUrl,
    this.sourceImageArtifactReference,
    this.sourceImageStoragePath,
    this.sourceImageMimeType,
    this.sourceImageByteLength,
    this.maskImageBase64,
    this.maskPayload,
    this.referenceImageUrl,
    this.secondFrameImageUrl,
    this.cameraMotionType,
    this.upscaleFactor = 2,
    this.materialType,
    this.relightingPreset,
    this.entourageCategory,
    this.threeDProvider,
    this.meshQuality = 'balanced',
    this.textureMode = 'pbr',
    this.targetFormat = 'glb',
    this.sourceModelReference,
    this.triangleBudget = 100000,
    this.generatePreview = true,
    this.extraConfig = const {},
  });

  Map<String, dynamic> toJson() => {
    'negativePrompt': negativePrompt,
    'stylePreset': stylePreset,
    'denoisingStrength': denoisingStrength,
    'guidanceScale': guidanceScale,
    'seed': seed,
    'controlNetType': controlNetType,
    'controlNetStrength': controlNetStrength,
    'sourceImageBase64': sourceImageBase64,
    'sourceImageUrl': sourceImageUrl,
    'sourceImageArtifactReference': sourceImageArtifactReference,
    'sourceImageStoragePath': sourceImageStoragePath,
    'sourceImageMimeType': sourceImageMimeType,
    'sourceImageByteLength': sourceImageByteLength,
    'maskImageBase64': maskImageBase64,
    'maskPayload': maskPayload,
    'referenceImageUrl': referenceImageUrl,
    'secondFrameImageUrl': secondFrameImageUrl,
    'cameraMotionType': cameraMotionType,
    'upscaleFactor': upscaleFactor,
    'materialType': materialType,
    'relightingPreset': relightingPreset,
    'entourageCategory': entourageCategory,
    'threeDProvider': threeDProvider,
    'meshQuality': meshQuality,
    'textureMode': textureMode,
    'targetFormat': targetFormat,
    'sourceModelReference': sourceModelReference,
    'triangleBudget': triangleBudget,
    'generatePreview': generatePreview,
    'extraConfig': extraConfig,
  };

  /// Serializes only metadata that is safe to retain in job history, action
  /// records, and cloud/export envelopes. Render inputs stay in memory.
  Map<String, dynamic> toPersistenceJson() => {
    if (negativePrompt != null) 'negativePrompt': negativePrompt,
    if (stylePreset != null) 'stylePreset': stylePreset,
    'denoisingStrength': denoisingStrength,
    'guidanceScale': guidanceScale,
    'seed': seed,
    if (controlNetType != null) 'controlNetType': controlNetType,
    'controlNetStrength': controlNetStrength,
    'sourceImageArtifactReference': ?validImageArtifactReference(
      sourceImageArtifactReference,
    ),
    'sourceImageStoragePath': ?durableAssetReference(sourceImageStoragePath),
    if (sourceImageMimeType?.trim().toLowerCase() case final value?
        when value.startsWith('image/'))
      'sourceImageMimeType': value,
    if (sourceImageByteLength case final value? when value > 0)
      'sourceImageByteLength': value,
    'maskPayload': ?_safeMap(maskPayload),
    if (cameraMotionType != null) 'cameraMotionType': cameraMotionType,
    'upscaleFactor': upscaleFactor,
    if (materialType != null) 'materialType': materialType,
    if (relightingPreset != null) 'relightingPreset': relightingPreset,
    if (entourageCategory != null) 'entourageCategory': entourageCategory,
    if (threeDProvider != null) 'threeDProvider': threeDProvider,
    'meshQuality': meshQuality,
    'textureMode': textureMode,
    'targetFormat': targetFormat,
    'triangleBudget': triangleBudget,
    'generatePreview': generatePreview,
    'extraConfig': _safeMap(extraConfig) ?? const <String, dynamic>{},
  };

  AICreativeParams copyWith({
    String? sourceImageBase64,
    bool clearSourceImageBase64 = false,
    String? sourceImageUrl,
    bool clearSourceImageUrl = false,
    String? sourceImageArtifactReference,
    String? sourceImageStoragePath,
    String? sourceImageMimeType,
    int? sourceImageByteLength,
  }) => AICreativeParams(
    negativePrompt: negativePrompt,
    stylePreset: stylePreset,
    denoisingStrength: denoisingStrength,
    guidanceScale: guidanceScale,
    seed: seed,
    controlNetType: controlNetType,
    controlNetStrength: controlNetStrength,
    sourceImageBase64: clearSourceImageBase64
        ? null
        : sourceImageBase64 ?? this.sourceImageBase64,
    sourceImageUrl: clearSourceImageUrl
        ? null
        : sourceImageUrl ?? this.sourceImageUrl,
    sourceImageArtifactReference:
        sourceImageArtifactReference ?? this.sourceImageArtifactReference,
    sourceImageStoragePath:
        sourceImageStoragePath ?? this.sourceImageStoragePath,
    sourceImageMimeType: sourceImageMimeType ?? this.sourceImageMimeType,
    sourceImageByteLength: sourceImageByteLength ?? this.sourceImageByteLength,
    maskImageBase64: maskImageBase64,
    maskPayload: maskPayload,
    referenceImageUrl: referenceImageUrl,
    secondFrameImageUrl: secondFrameImageUrl,
    cameraMotionType: cameraMotionType,
    upscaleFactor: upscaleFactor,
    materialType: materialType,
    relightingPreset: relightingPreset,
    entourageCategory: entourageCategory,
    threeDProvider: threeDProvider,
    meshQuality: meshQuality,
    textureMode: textureMode,
    targetFormat: targetFormat,
    sourceModelReference: sourceModelReference,
    triangleBudget: triangleBudget,
    generatePreview: generatePreview,
    extraConfig: extraConfig,
  );

  static Map<String, dynamic>? _safeMap(Map<String, dynamic>? value) {
    if (value == null) return null;
    final sanitized = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || _unsafeKey(key)) continue;
      final safeValue = _safeValue(entry.value);
      if (safeValue != null) sanitized[key] = safeValue;
    }
    return sanitized;
  }

  static Object? _safeValue(Object? value) {
    if (value is Map) {
      return _safeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(_safeValue).where((item) => item != null).toList();
    }
    if (value is String) return _safeText(value);
    if (value is num || value is bool) return value;
    return null;
  }

  static String? _safeText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (isTransientAssetReference(normalized)) return null;
    final scrubbed = normalized
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
            r'\b(?:bearer|token|api[_-]?key|authorization|signature|sig|access_token|refresh_token)\s*[:=]\s*[^\s,;]+',
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
    if (scrubbed.isEmpty) return null;
    return scrubbed.length > 4000 ? scrubbed.substring(0, 4000) : scrubbed;
  }

  static bool _unsafeKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('base64') ||
        lower.contains('secret') ||
        lower.contains('token') ||
        lower.contains('password') ||
        lower.contains('authorization') ||
        lower.contains('api_key') ||
        lower.contains('apikey') ||
        lower.contains('url') ||
        lower.contains('path') ||
        lower.contains('reference');
  }

  factory AICreativeParams.fromJson(
    Map<String, dynamic> json,
  ) => AICreativeParams(
    negativePrompt: json['negativePrompt'] as String?,
    stylePreset: json['stylePreset'] as String?,
    denoisingStrength: (json['denoisingStrength'] as num?)?.toDouble() ?? 0.75,
    guidanceScale: (json['guidanceScale'] as num?)?.toDouble() ?? 7.5,
    seed: (json['seed'] as num?)?.toInt() ?? -1,
    controlNetType: json['controlNetType'] as String?,
    controlNetStrength: (json['controlNetStrength'] as num?)?.toDouble() ?? 1.0,
    sourceImageBase64: json['sourceImageBase64'] as String?,
    sourceImageUrl: json['sourceImageUrl'] as String?,
    sourceImageArtifactReference: validImageArtifactReference(
      json['sourceImageArtifactReference'] as String?,
    ),
    sourceImageStoragePath: durableAssetReference(
      json['sourceImageStoragePath'] as String?,
    ),
    sourceImageMimeType: json['sourceImageMimeType'] as String?,
    sourceImageByteLength: (json['sourceImageByteLength'] as num?)?.toInt(),
    maskImageBase64: json['maskImageBase64'] as String?,
    maskPayload: json['maskPayload'] is Map
        ? Map<String, dynamic>.from(json['maskPayload'] as Map)
        : null,
    referenceImageUrl: json['referenceImageUrl'] as String?,
    secondFrameImageUrl: json['secondFrameImageUrl'] as String?,
    cameraMotionType: json['cameraMotionType'] as String?,
    upscaleFactor: (json['upscaleFactor'] as num?)?.toInt() ?? 2,
    materialType: json['materialType'] as String?,
    relightingPreset: json['relightingPreset'] as String?,
    entourageCategory: json['entourageCategory'] as String?,
    threeDProvider: json['threeDProvider'] as String?,
    meshQuality: json['meshQuality'] as String? ?? 'balanced',
    textureMode: json['textureMode'] as String? ?? 'pbr',
    targetFormat: json['targetFormat'] as String? ?? 'glb',
    sourceModelReference: json['sourceModelReference'] as String?,
    triangleBudget: (json['triangleBudget'] as num?)?.toInt() ?? 100000,
    generatePreview: json['generatePreview'] as bool? ?? true,
    extraConfig: json['extraConfig'] as Map<String, dynamic>? ?? const {},
  );
}

class AIAssistantAction {
  final String
  actionType; // 'create_node', 'transform_node', 'delete_node', 'add_layer', 'apply_filter'
  final Map<String, dynamic> payload;
  final String description;

  const AIAssistantAction({
    required this.actionType,
    required this.payload,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'actionType': actionType,
    'payload': payload,
    'description': description,
  };

  Map<String, dynamic> toPersistenceJson() => {
    'actionType': actionType,
    'payload': AIJob._safePersistenceMap(payload) ?? const <String, dynamic>{},
    'description': AIJob._safePersistenceText(description) ?? '',
  };

  factory AIAssistantAction.fromJson(Map<String, dynamic> json) =>
      AIAssistantAction(
        actionType: json['actionType'] as String? ?? '',
        payload: json['payload'] as Map<String, dynamic>? ?? const {},
        description: json['description'] as String? ?? '',
      );
}

class AIJob {
  final String id;
  final String projectId;
  final AICapability capability;
  final String prompt;
  final AICreativeParams? creativeParams;
  final AIJobStatus status;
  final bool isSimulated;
  final String? resultText;
  final String? resultAssetUrl;
  final String? resultVideoPath;
  final String? resultVideoUrl;
  final String? resultVideoReference;
  final List<String> resultImageUrls;
  final AIArtifact? resultArtifact;
  final String? providerJobId;
  final String? provider;
  final String? model;
  final double? estimatedCost;
  final double? actualCost;
  final List<String> sourceAssetIds;
  final List<String> sourceNodeIds;
  final String? variantGroupId;
  final int? variantIndex;
  final Map<String, dynamic>? variantSetPayload;
  final bool favorite;
  final AIOutputMode outputMode;
  final Map<String, dynamic> provenance;
  final double? progress;
  final List<AIAssistantAction> proposedActions;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const Object _sentinel = Object();

  const AIJob({
    required this.id,
    required this.projectId,
    required this.capability,
    required this.prompt,
    this.creativeParams,
    this.status = AIJobStatus.queued,
    this.isSimulated = false,
    this.resultText,
    this.resultAssetUrl,
    this.resultVideoPath,
    this.resultVideoUrl,
    this.resultVideoReference,
    this.resultImageUrls = const [],
    this.resultArtifact,
    this.providerJobId,
    this.provider,
    this.model,
    this.estimatedCost,
    this.actualCost,
    this.sourceAssetIds = const [],
    this.sourceNodeIds = const [],
    this.variantGroupId,
    this.variantIndex,
    this.variantSetPayload,
    this.favorite = false,
    this.outputMode = AIOutputMode.insert,
    this.provenance = const {},
    this.progress,
    this.proposedActions = const [],
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  AICreativeCategory get category {
    switch (capability) {
      case AICapability.textToImage:
      case AICapability.sketchToImage:
      case AICapability.imageToImage:
      case AICapability.referenceToImage:
      case AICapability.textTo3D:
      case AICapability.imageTo3D:
        return AICreativeCategory.generation;

      case AICapability.inpainting:
      case AICapability.outpainting:
      case AICapability.replaceObject:
      case AICapability.removeObject:
      case AICapability.addObject:
      case AICapability.backgroundReplace:
        return AICreativeCategory.generativeEditing;

      case AICapability.styleTransfer:
      case AICapability.materialTransfer:
      case AICapability.relighting:
      case AICapability.recolor:
      case AICapability.restyle:
        return AICreativeCategory.visualTransformation;

      case AICapability.upscale:
      case AICapability.denoise:
      case AICapability.sharpen:
      case AICapability.restore:
      case AICapability.detailEnhancement:
        return AICreativeCategory.enhancement;

      case AICapability.populate:
      case AICapability.compositionRemove:
      case AICapability.rearrange:
      case AICapability.expandScene:
      case AICapability.smartCutout:
        return AICreativeCategory.compositionAI;

      case AICapability.imageToVideo:
      case AICapability.videoFromImage:
      case AICapability.firstLastFrame:
      case AICapability.cameraMotion:
      case AICapability.animateObject:
      case AICapability.videoRestyle:
        return AICreativeCategory.videoAI;

      case AICapability.understandCanvas:
      case AICapability.understandSelection:
      case AICapability.callTools:
      case AICapability.agentGenerate:
      case AICapability.agentEdit:
      case AICapability.agentArrange:
      case AICapability.summarizeNotes:
      case AICapability.promptToDiagram:
        return AICreativeCategory.aiAssistant;
    }
  }

  AIJob copyWith({
    String? id,
    String? projectId,
    AICapability? capability,
    String? prompt,
    AICreativeParams? creativeParams,
    AIJobStatus? status,
    bool? isSimulated,
    String? resultText,
    String? resultAssetUrl,
    bool clearResultAssetUrl = false,
    String? resultVideoPath,
    bool clearResultVideoPath = false,
    String? resultVideoUrl,
    bool clearResultVideoUrl = false,
    String? resultVideoReference,
    bool clearResultVideoReference = false,
    List<String>? resultImageUrls,
    bool clearResultImageUrls = false,
    AIArtifact? resultArtifact,
    bool clearResultArtifact = false,
    String? providerJobId,
    String? provider,
    String? model,
    double? estimatedCost,
    double? actualCost,
    List<String>? sourceAssetIds,
    List<String>? sourceNodeIds,
    String? variantGroupId,
    int? variantIndex,
    Object? variantSetPayload = _sentinel,
    bool? favorite,
    AIOutputMode? outputMode,
    Map<String, dynamic>? provenance,
    double? progress,
    List<AIAssistantAction>? proposedActions,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AIJob(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      capability: capability ?? this.capability,
      prompt: prompt ?? this.prompt,
      creativeParams: creativeParams ?? this.creativeParams,
      status: status ?? this.status,
      isSimulated: isSimulated ?? this.isSimulated,
      resultText: resultText ?? this.resultText,
      resultAssetUrl: clearResultAssetUrl
          ? null
          : resultAssetUrl ?? this.resultAssetUrl,
      resultVideoPath: clearResultVideoPath
          ? null
          : resultVideoPath ?? this.resultVideoPath,
      resultVideoUrl: clearResultVideoUrl
          ? null
          : resultVideoUrl ?? this.resultVideoUrl,
      resultVideoReference: clearResultVideoReference
          ? null
          : resultVideoReference ?? this.resultVideoReference,
      resultImageUrls: clearResultImageUrls
          ? const []
          : resultImageUrls ?? this.resultImageUrls,
      resultArtifact: clearResultArtifact
          ? null
          : resultArtifact ?? this.resultArtifact,
      providerJobId: providerJobId ?? this.providerJobId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      actualCost: actualCost ?? this.actualCost,
      sourceAssetIds: sourceAssetIds ?? this.sourceAssetIds,
      sourceNodeIds: sourceNodeIds ?? this.sourceNodeIds,
      variantGroupId: variantGroupId ?? this.variantGroupId,
      variantIndex: variantIndex ?? this.variantIndex,
      variantSetPayload: variantSetPayload == _sentinel
          ? this.variantSetPayload
          : variantSetPayload as Map<String, dynamic>?,
      favorite: favorite ?? this.favorite,
      outputMode: outputMode ?? this.outputMode,
      provenance: provenance ?? this.provenance,
      progress: progress ?? this.progress,
      proposedActions: proposedActions ?? this.proposedActions,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Runtime representation used while a job is executing or being rendered.
  /// It may contain ephemeral paths, URLs, and inline bytes, so callers must
  /// not use it for history, collaboration, recovery, or export.
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'capability': capability.name,
    'prompt': prompt,
    'creativeParams': creativeParams?.toJson(),
    'status': status.name,
    'isSimulated': isSimulated,
    'resultText': resultText,
    'resultAssetUrl': resultAssetUrl,
    'resultVideoPath': resultVideoPath,
    'resultVideoUrl': resultVideoUrl,
    'resultVideoReference': resultVideoReference,
    'resultImageUrls': resultImageUrls,
    'resultArtifact': resultArtifact?.toJson(),
    'providerJobId': providerJobId,
    'provider': provider,
    'model': model,
    'estimatedCost': estimatedCost,
    'actualCost': actualCost,
    'sourceAssetIds': sourceAssetIds,
    'sourceNodeIds': sourceNodeIds,
    'variantGroupId': variantGroupId,
    'variantIndex': variantIndex,
    'variantSet': variantSetPayload,
    'favorite': favorite,
    'outputMode': outputMode.name,
    'provenance': provenance,
    'progress': progress,
    'proposedActions': proposedActions.map((a) => a.toJson()).toList(),
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Persistence/export representation. Runtime delivery values are omitted;
  /// renderers hydrate them from stable artifact metadata at the edge.
  Map<String, dynamic> toPersistenceJson() => {
    'id': id,
    'projectId': projectId,
    'capability': capability.name,
    'prompt': _safePersistenceText(prompt),
    'creativeParams': ?creativeParams?.toPersistenceJson(),
    'status': status.name,
    'isSimulated': isSimulated,
    'resultText': ?_safePersistenceText(resultText),
    if (resultArtifact != null) 'resultArtifact': resultArtifact!.toJson(),
    if (resultArtifact == null)
      'resultVideoReference': ?validVideoArtifactReference(
        resultVideoReference,
      ),
    'provider': ?_safePersistenceText(provider),
    'model': ?_safePersistenceText(model),
    if (estimatedCost?.isFinite == true) 'estimatedCost': estimatedCost,
    if (actualCost?.isFinite == true) 'actualCost': actualCost,
    'sourceAssetIds': _safeIds(sourceAssetIds),
    'sourceNodeIds': _safeIds(sourceNodeIds),
    'variantGroupId': ?_safePersistenceText(variantGroupId),
    if (variantIndex != null && variantIndex! >= 0)
      'variantIndex': variantIndex,
    if (variantSetPayload != null)
      'variantSet': _safePersistenceMap(variantSetPayload!),
    'favorite': favorite,
    'outputMode': outputMode.name,
    'provenance': _safePersistenceMap(provenance) ?? const <String, dynamic>{},
    if (progress?.isFinite == true) 'progress': progress,
    'proposedActions': proposedActions
        .map((action) => action.toPersistenceJson())
        .toList(growable: false),
    'errorMessage': ?_safePersistenceText(errorMessage),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static List<String> _safeIds(Iterable<String> values) => values
      .map(_safePersistenceText)
      .whereType<String>()
      .where((value) => value.length <= 200)
      .toList(growable: false);

  static String? _safePersistenceText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (validImageArtifactReference(normalized) != null ||
        validVideoArtifactReference(normalized) != null ||
        validModel3DArtifactReference(normalized) != null) {
      return normalized;
    }
    if (isTransientAssetReference(normalized)) return null;
    final scrubbed = normalized
        .replaceAll(
          RegExp(
            r'''\b(?:https?|blob|content|memory|file|varian-[a-z0-9-]+)://[^\s<>"']+''',
            caseSensitive: false,
          ),
          '[redacted URL]',
        )
        .replaceAll(
          RegExp(r'''\bdata:[^\s<>"']+''', caseSensitive: false),
          '[redacted data URI]',
        )
        .replaceAll(
          RegExp(
            r'''\b(?:bearer|token|api[_-]?key|authorization|signature|sig|access_token|refresh_token)\s*[:=]\s*[^\s,;]+''',
            caseSensitive: false,
          ),
          '[redacted credential]',
        )
        .replaceAll(
          RegExp(
            r'''(?<![A-Za-z0-9])(?:[A-Za-z]:[\\/]|/(?:Users|home|tmp|data)/)[^\s<>"']+''',
            caseSensitive: false,
          ),
          '[redacted path]',
        )
        .trim();
    if (scrubbed.isEmpty) return null;
    return scrubbed.length > 4000 ? scrubbed.substring(0, 4000) : scrubbed;
  }

  static Map<String, dynamic>? _safePersistenceMap(
    Map<String, dynamic>? source,
  ) {
    if (source == null) return null;
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || _unsafePersistenceKey(key)) continue;
      final value = _safePersistenceValue(entry.value);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static Object? _safePersistenceValue(Object? value) {
    if (value is Map) {
      return _safePersistenceMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value
          .map(_safePersistenceValue)
          .whereType<Object>()
          .toList(growable: false);
    }
    if (value is String) return _safePersistenceText(value);
    if (value is num || value is bool) return value;
    return null;
  }

  static bool _unsafePersistenceKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('base64') ||
        lower.contains('secret') ||
        lower.contains('token') ||
        lower.contains('password') ||
        lower.contains('authorization') ||
        lower.contains('api_key') ||
        lower.contains('apikey') ||
        lower.contains('url') ||
        lower.contains('path') ||
        lower.contains('reference');
  }

  factory AIJob.fromJson(Map<String, dynamic> json) {
    return AIJob(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      capability: AICapability.values.firstWhere(
        (e) => e.name == json['capability'],
        orElse: () => AICapability.textToImage,
      ),
      prompt: json['prompt'] as String? ?? '',
      creativeParams: json['creativeParams'] != null
          ? AICreativeParams.fromJson(
              json['creativeParams'] as Map<String, dynamic>,
            )
          : null,
      status: AIJobStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AIJobStatus.queued,
      ),
      isSimulated: json['isSimulated'] as bool? ?? false,
      resultText: json['resultText'] as String?,
      resultAssetUrl: json['resultAssetUrl'] as String?,
      resultVideoPath: json['resultVideoPath'] as String?,
      resultVideoUrl: json['resultVideoUrl'] as String?,
      resultVideoReference: json['resultVideoReference'] as String?,
      resultImageUrls:
          (json['resultImageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      resultArtifact: json['resultArtifact'] is Map
          ? AIArtifact.fromJson(
              Map<String, dynamic>.from(json['resultArtifact'] as Map),
            )
          : null,
      providerJobId: json['providerJobId'] as String?,
      provider: json['provider'] as String?,
      model: json['model'] as String?,
      estimatedCost: (json['estimatedCost'] as num?)?.toDouble(),
      actualCost: (json['actualCost'] as num?)?.toDouble(),
      sourceAssetIds:
          (json['sourceAssetIds'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      sourceNodeIds:
          (json['sourceNodeIds'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      variantGroupId: json['variantGroupId'] as String?,
      variantIndex: (json['variantIndex'] as num?)?.toInt(),
      variantSetPayload:
          (json['variantSet'] ?? json['variantSetPayload']) is Map
          ? Map<String, dynamic>.from(
              (json['variantSet'] ?? json['variantSetPayload']) as Map,
            )
          : null,
      favorite: json['favorite'] as bool? ?? false,
      outputMode: AIOutputMode.values.firstWhere(
        (mode) => mode.name == json['outputMode'],
        orElse: () => AIOutputMode.insert,
      ),
      provenance: json['provenance'] is Map
          ? Map<String, dynamic>.from(json['provenance'] as Map)
          : const {},
      progress: (json['progress'] as num?)?.toDouble(),
      proposedActions:
          (json['proposedActions'] as List<dynamic>?)
              ?.map(
                (a) => AIAssistantAction.fromJson(a as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
