import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../data/local/local_storage_service.dart';
import '../../../data/remote/backend_config.dart';
import '../../../domain/models/ai_artifact.dart';
import '../../../domain/models/ai_job.dart';
import '../../../domain/models/durable_asset_reference.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../data/ai_service.dart';
import '../domain/ai_workflow_contract.dart';
import '../domain/ai_copilot_context.dart';
import 'ai_canvas_transaction_provider.dart';

class AICreativeEngineState {
  final List<AIJob> jobs;
  final AICreativeCategory activeCategory;
  final AICapability activeCapability;
  final String prompt;
  final String negativePrompt;
  final String selectedStylePreset;
  final double denoisingStrength;
  final double guidanceScale;
  final String? controlNetType;
  final double controlNetStrength;
  final int upscaleFactor;
  final String selectedMaterial;
  final String selectedRelighting;
  final String selectedEntourage;
  final String selectedCameraMotion;
  final String selectedThreeDProvider;
  final String selectedMeshQuality;
  final String selectedTextureMode;
  final int triangleBudget;
  final AICopilotContextScope selectedCopilotScope;
  final AIOutputMode outputMode;
  final AIMaskDocument? maskDocument;
  final bool isProcessing;
  final AIJob? activeJob;

  const AICreativeEngineState({
    this.jobs = const [],
    this.activeCategory = AICreativeCategory.generation,
    this.activeCapability = AICapability.textToImage,
    this.prompt = '',
    this.negativePrompt =
        'blurry, low quality, distorted, bad geometry, artifacts',
    this.selectedStylePreset = 'Photorealistic Architecture',
    this.denoisingStrength = 0.75,
    this.guidanceScale = 7.5,
    this.controlNetType = 'canny',
    this.controlNetStrength = 1.0,
    this.upscaleFactor = 4,
    this.selectedMaterial = 'Travertine Marble & Glass',
    this.selectedRelighting = 'Golden Hour Sunset',
    this.selectedEntourage = 'Modern Architectural Entourage (People & Trees)',
    this.selectedCameraMotion = 'Drone Orbit Flythrough',
    this.selectedThreeDProvider = 'triposr',
    this.selectedMeshQuality = 'balanced',
    this.selectedTextureMode = 'pbr',
    this.triangleBudget = 100000,
    this.selectedCopilotScope = AICopilotContextScope.project,
    this.outputMode = AIOutputMode.insert,
    this.maskDocument,
    this.isProcessing = false,
    this.activeJob,
  });

  AICreativeEngineState copyWith({
    List<AIJob>? jobs,
    AICreativeCategory? activeCategory,
    AICapability? activeCapability,
    String? prompt,
    String? negativePrompt,
    String? selectedStylePreset,
    double? denoisingStrength,
    double? guidanceScale,
    String? controlNetType,
    double? controlNetStrength,
    int? upscaleFactor,
    String? selectedMaterial,
    String? selectedRelighting,
    String? selectedEntourage,
    String? selectedCameraMotion,
    String? selectedThreeDProvider,
    String? selectedMeshQuality,
    String? selectedTextureMode,
    int? triangleBudget,
    AICopilotContextScope? selectedCopilotScope,
    AIOutputMode? outputMode,
    Object? maskDocument = _sentinel,
    bool? isProcessing,
    AIJob? activeJob,
  }) {
    return AICreativeEngineState(
      jobs: jobs ?? this.jobs,
      activeCategory: activeCategory ?? this.activeCategory,
      activeCapability: activeCapability ?? this.activeCapability,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      selectedStylePreset: selectedStylePreset ?? this.selectedStylePreset,
      denoisingStrength: denoisingStrength ?? this.denoisingStrength,
      guidanceScale: guidanceScale ?? this.guidanceScale,
      controlNetType: controlNetType ?? this.controlNetType,
      controlNetStrength: controlNetStrength ?? this.controlNetStrength,
      upscaleFactor: upscaleFactor ?? this.upscaleFactor,
      selectedMaterial: selectedMaterial ?? this.selectedMaterial,
      selectedRelighting: selectedRelighting ?? this.selectedRelighting,
      selectedEntourage: selectedEntourage ?? this.selectedEntourage,
      selectedCameraMotion: selectedCameraMotion ?? this.selectedCameraMotion,
      selectedThreeDProvider:
          selectedThreeDProvider ?? this.selectedThreeDProvider,
      selectedMeshQuality: selectedMeshQuality ?? this.selectedMeshQuality,
      selectedTextureMode: selectedTextureMode ?? this.selectedTextureMode,
      triangleBudget: triangleBudget ?? this.triangleBudget,
      selectedCopilotScope: selectedCopilotScope ?? this.selectedCopilotScope,
      outputMode: outputMode ?? this.outputMode,
      maskDocument: maskDocument == _sentinel
          ? this.maskDocument
          : maskDocument as AIMaskDocument?,
      isProcessing: isProcessing ?? this.isProcessing,
      activeJob: activeJob ?? this.activeJob,
    );
  }

  static const Object _sentinel = Object();
}

class AICreativeEngineNotifier extends StateNotifier<AICreativeEngineState> {
  final Ref _ref;
  final LocalStorageService _localStorage = LocalStorageService();
  final Set<String> _restoredProjects = {};
  final Set<String> _cancelledJobs = {};
  int _runGeneration = 0;

  void invalidatePendingRuns() {
    _runGeneration++;
  }

  AICreativeEngineNotifier(this._ref) : super(const AICreativeEngineState());

  Future<void> restoreJobHistory(String projectId) async {
    if (!_restoredProjects.add(projectId)) return;
    try {
      final jobs = await _localStorage.loadAIJobHistory(projectId);
      if (jobs.isEmpty) return;
      final restoredJobs = jobs
          .map(_withDefaultVariantSet)
          .toList(growable: false);
      final activeJob = restoredJobs.first;
      final maskPayload = activeJob.creativeParams?.maskPayload;
      state = state.copyWith(
        jobs: restoredJobs,
        activeJob: activeJob,
        maskDocument: maskPayload == null
            ? null
            : AIMaskDocument.fromJson(maskPayload),
      );
    } catch (error) {
      debugPrint('[AI] Job history restore failed: $error');
    }
  }

  Future<void> _persistJobHistory(String projectId) async {
    try {
      await _localStorage.saveAIJobHistory(projectId, state.jobs);
    } catch (error) {
      debugPrint('[AI] Job history save failed: $error');
    }
  }

  Future<AIJob?> saveVariantSet({
    required String jobId,
    required AIVariantSet variants,
  }) async {
    final job = state.jobs.where((item) => item.id == jobId).firstOrNull;
    if (job == null) return null;
    final updated = job.copyWith(
      variantGroupId: variants.id,
      variantSetPayload: variants.toJson(),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      activeJob: state.activeJob?.id == jobId ? updated : state.activeJob,
      jobs: state.jobs
          .map((item) => item.id == jobId ? updated : item)
          .toList(growable: false),
    );
    await _persistJobHistory(job.projectId);
    return updated;
  }

  void setMaskDocument(AIMaskDocument mask) {
    state = state.copyWith(maskDocument: mask);
  }

  void clearMaskDocument() {
    state = state.copyWith(maskDocument: null);
  }

  void setCategory(AICreativeCategory category) {
    AICapability defCap = AICapability.textToImage;
    switch (category) {
      case AICreativeCategory.generation:
        defCap = AICapability.textToImage;
        break;
      case AICreativeCategory.generativeEditing:
        defCap = AICapability.inpainting;
        break;
      case AICreativeCategory.visualTransformation:
        defCap = AICapability.relighting;
        break;
      case AICreativeCategory.enhancement:
        defCap = AICapability.upscale;
        break;
      case AICreativeCategory.compositionAI:
        defCap = AICapability.populate;
        break;
      case AICreativeCategory.videoAI:
        defCap = AICapability.imageToVideo;
        break;
      case AICreativeCategory.aiAssistant:
        defCap = AICapability.understandCanvas;
        break;
    }
    state = state.copyWith(activeCategory: category, activeCapability: defCap);
  }

  void setCapability(AICapability capability) {
    state = state.copyWith(
      activeCapability: capability,
      activeCategory: _categoryForCapability(capability),
    );
  }

  AICreativeCategory _categoryForCapability(AICapability cap) {
    final job = AIJob(
      id: '',
      projectId: '',
      capability: cap,
      prompt: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    return job.category;
  }

  void setPrompt(String prompt) {
    if (state.prompt == prompt) return;
    state = state.copyWith(prompt: prompt);
  }

  void setNegativePrompt(String val) {
    if (state.negativePrompt == val) return;
    state = state.copyWith(negativePrompt: val);
  }

  void setStylePreset(String preset) {
    if (state.selectedStylePreset == preset) return;
    state = state.copyWith(selectedStylePreset: preset);
  }

  void setDenoising(double val) {
    if ((state.denoisingStrength - val).abs() < 0.0001) return;
    state = state.copyWith(denoisingStrength: val);
  }

  void setGuidance(double val) {
    if ((state.guidanceScale - val).abs() < 0.0001) return;
    state = state.copyWith(guidanceScale: val);
  }

  void setUpscaleFactor(int factor) {
    if (state.upscaleFactor == factor) return;
    state = state.copyWith(upscaleFactor: factor);
  }

  void setMaterial(String material) =>
      state = state.copyWith(selectedMaterial: material);
  void setRelighting(String preset) =>
      state = state.copyWith(selectedRelighting: preset);
  void setEntourage(String category) =>
      state = state.copyWith(selectedEntourage: category);
  void setCameraMotion(String motion) =>
      state = state.copyWith(selectedCameraMotion: motion);
  void setThreeDProvider(String provider) =>
      state = state.copyWith(selectedThreeDProvider: provider);
  void setMeshQuality(String quality) =>
      state = state.copyWith(selectedMeshQuality: quality);
  void setTextureMode(String mode) =>
      state = state.copyWith(selectedTextureMode: mode);
  void setTriangleBudget(int budget) =>
      state = state.copyWith(triangleBudget: budget);

  void setCopilotScope(AICopilotContextScope scope) =>
      state = state.copyWith(selectedCopilotScope: scope);

  void setOutputMode(AIOutputMode mode) {
    if (state.outputMode == mode) return;
    state = state.copyWith(outputMode: mode);
  }

  Future<void> cancelJob(String jobId) async {
    final job = state.jobs.where((item) => item.id == jobId).firstOrNull;
    if (job == null || job.status != AIJobStatus.processing) return;
    _cancelledJobs.add(jobId);
    final canceled = job.copyWith(
      status: AIJobStatus.canceled,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      isProcessing: false,
      activeJob: canceled,
      jobs: state.jobs
          .map((item) => item.id == jobId ? canceled : item)
          .toList(),
    );
    unawaited(_persistJobHistory(job.projectId));
  }

  Future<AIJob> runJob({
    required String projectId,
    required AICapability capability,
    required String prompt,
  }) {
    setCapability(capability);
    setPrompt(prompt);
    return executeSequence(projectId: projectId);
  }

  Future<AIJob> executeSequence({
    required String projectId,
    String? sourceImageBase64,
    String? sourceImageUrl,
    String? sourceImageArtifactReference,
    String? sourceImageStoragePath,
    String? sourceImageMimeType,
    int? sourceImageByteLength,
    String? variantOfNodeId,
    String? maskImageBase64,
    Map<String, dynamic>? maskPayload,
    Offset? spawnCanvasPosition,
    void Function(CanvasNode node)? onNodeCreated,
    bool Function()? canEditCanvas,
    Map<String, dynamic>? copilotContext,
  }) async {
    final runGeneration = _runGeneration;
    await _ref.read(backendConfigProvider.notifier).waitUntilReady();
    if (runGeneration != _runGeneration) {
      return AIJob(
        id: const Uuid().v4(),
        projectId: projectId,
        capability: state.activeCapability,
        prompt: state.prompt.trim().isNotEmpty
            ? state.prompt.trim()
            : state.activeCapability.name,
        status: AIJobStatus.canceled,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    final aiService = _ref.read(aiServiceProvider);
    final currentNodes = _ref.read(documentNodesProvider);
    if (variantOfNodeId != null &&
        !currentNodes.any((node) => node.id == variantOfNodeId)) {
      throw ArgumentError.value(
        variantOfNodeId,
        'variantOfNodeId',
        'The source node no longer exists.',
      );
    }

    final params = AICreativeParams(
      negativePrompt: state.negativePrompt,
      stylePreset: state.selectedStylePreset,
      denoisingStrength: state.denoisingStrength,
      guidanceScale: state.guidanceScale,
      sourceImageBase64: sourceImageBase64,
      sourceImageUrl: sourceImageUrl,
      sourceImageArtifactReference: validImageArtifactReference(
        sourceImageArtifactReference,
      ),
      sourceImageStoragePath: durableAssetReference(sourceImageStoragePath),
      sourceImageMimeType: sourceImageMimeType,
      sourceImageByteLength: sourceImageByteLength,
      maskImageBase64: maskImageBase64,
      maskPayload: maskPayload ?? state.maskDocument?.toJson(),
      upscaleFactor: state.upscaleFactor,
      materialType: state.selectedMaterial,
      relightingPreset: state.selectedRelighting,
      entourageCategory: state.selectedEntourage,
      cameraMotionType: state.selectedCameraMotion,
      threeDProvider: state.selectedThreeDProvider,
      meshQuality: state.selectedMeshQuality,
      textureMode: state.selectedTextureMode,
      triangleBudget: state.triangleBudget,
      extraConfig: {'copilotContext': ?copilotContext},
    );

    final newJob = AIJob(
      id: const Uuid().v4(),
      projectId: projectId,
      capability: state.activeCapability,
      prompt: state.prompt.trim().isNotEmpty
          ? state.prompt.trim()
          : state.activeCapability.name,
      creativeParams: params,
      status: AIJobStatus.processing,
      outputMode: state.outputMode,
      sourceNodeIds: variantOfNodeId == null ? const [] : [variantOfNodeId],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      isProcessing: true,
      activeJob: newJob,
      jobs: [newJob, ...state.jobs],
    );

    try {
      final completedJob = await aiService.executeJob(newJob, currentNodes);
      if (runGeneration != _runGeneration) {
        final canceledJob = newJob.copyWith(
          status: AIJobStatus.canceled,
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(
          isProcessing: false,
          activeJob: canceledJob,
          jobs: state.jobs
              .map((job) => job.id == canceledJob.id ? canceledJob : job)
              .toList(),
        );
        return canceledJob;
      }
      if (_cancelledJobs.remove(newJob.id)) {
        final canceledJob = newJob.copyWith(
          status: AIJobStatus.canceled,
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(
          isProcessing: false,
          activeJob: canceledJob,
          jobs: state.jobs
              .map((job) => job.id == canceledJob.id ? canceledJob : job)
              .toList(),
        );
        unawaited(_persistJobHistory(projectId));
        return canceledJob;
      }

      var persistedJob = _withDefaultVariantSet(completedJob);
      if (completedJob.status == AIJobStatus.completed) {
        // Keep the completed result usable if its source was deleted while
        // the asynchronous request was pending.
        final linkedSourceId =
            variantOfNodeId != null &&
                _ref
                    .read(documentNodesProvider)
                    .any((node) => node.id == variantOfNodeId)
            ? variantOfNodeId
            : null;
        persistedJob = await _placeCompletedOutput(
          persistedJob,
          sourceNodeId: linkedSourceId,
          position: spawnCanvasPosition,
          onNodeCreated: onNodeCreated,
          canEditCanvas: canEditCanvas,
        );
      }

      state = state.copyWith(
        isProcessing: false,
        activeJob: persistedJob,
        jobs: state.jobs
            .map((j) => j.id == persistedJob.id ? persistedJob : j)
            .toList(),
      );
      unawaited(_persistJobHistory(projectId));

      return persistedJob;
    } catch (err) {
      final failedJob = newJob.copyWith(
        status: AIJobStatus.failed,
        errorMessage: err.toString(),
        updatedAt: DateTime.now(),
      );

      state = state.copyWith(
        isProcessing: false,
        activeJob: failedJob,
        jobs: state.jobs
            .map((j) => j.id == failedJob.id ? failedJob : j)
            .toList(),
      );
      unawaited(_persistJobHistory(projectId));

      return failedJob;
    }
  }

  Future<AIJob> retryJob({
    required AIJob job,
    void Function(CanvasNode node)? onNodeCreated,
    bool Function()? canEditCanvas,
  }) async {
    if (state.isProcessing ||
        (job.status != AIJobStatus.failed &&
            job.status != AIJobStatus.canceled)) {
      return job;
    }

    await _ref.read(backendConfigProvider.notifier).waitUntilReady();
    final aiService = _ref.read(aiServiceProvider);
    final currentNodes = _ref.read(documentNodesProvider);
    final retryingJob = job.copyWith(
      status: AIJobStatus.processing,
      progress: 0,
      clearErrorMessage: true,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      isProcessing: true,
      activeJob: retryingJob,
      jobs: state.jobs.any((item) => item.id == retryingJob.id)
          ? state.jobs
                .map((item) => item.id == retryingJob.id ? retryingJob : item)
                .toList()
          : [retryingJob, ...state.jobs],
    );

    try {
      final completedJob = _withDefaultVariantSet(
        await aiService.retryJob(retryingJob, currentNodes),
      );
      if (_cancelledJobs.remove(retryingJob.id)) {
        final canceledJob = retryingJob.copyWith(
          status: AIJobStatus.canceled,
          updatedAt: DateTime.now(),
        );
        state = state.copyWith(
          isProcessing: false,
          activeJob: canceledJob,
          jobs: state.jobs
              .map((item) => item.id == canceledJob.id ? canceledJob : item)
              .toList(),
        );
        unawaited(_persistJobHistory(canceledJob.projectId));
        return canceledJob;
      }
      var persistedJob = completedJob;
      if (completedJob.status == AIJobStatus.completed) {
        final linkedSourceId = completedJob.sourceNodeIds
            .where(
              (sourceId) => currentNodes.any((node) => node.id == sourceId),
            )
            .firstOrNull;
        persistedJob = await _placeCompletedOutput(
          completedJob,
          sourceNodeId: linkedSourceId,
          position: const Offset(200, 200),
          onNodeCreated: onNodeCreated,
          canEditCanvas: canEditCanvas,
        );
      }
      state = state.copyWith(
        isProcessing: false,
        activeJob: persistedJob,
        jobs: state.jobs
            .map((item) => item.id == persistedJob.id ? persistedJob : item)
            .toList(),
      );
      unawaited(_persistJobHistory(persistedJob.projectId));
      return persistedJob;
    } catch (err) {
      final failedJob = retryingJob.copyWith(
        status: AIJobStatus.failed,
        errorMessage: err.toString(),
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(
        isProcessing: false,
        activeJob: failedJob,
        jobs: state.jobs
            .map((item) => item.id == failedJob.id ? failedJob : item)
            .toList(),
      );
      unawaited(_persistJobHistory(failedJob.projectId));
      return failedJob;
    }
  }

  Future<AIJob> _placeCompletedOutput(
    AIJob job, {
    required String? sourceNodeId,
    required Offset? position,
    void Function(CanvasNode node)? onNodeCreated,
    bool Function()? canEditCanvas,
  }) async {
    final hasOutput = job.resultArtifact?.kind == AIArtifactKind.model3d
        ? validModel3DArtifactReference(job.resultArtifact?.reference) != null
        : job.category == AICreativeCategory.videoAI
        ? validVideoArtifactReference(
                job.resultArtifact?.kind == AIArtifactKind.video
                    ? job.resultArtifact?.reference
                    : job.resultVideoReference,
              ) !=
              null
        : job.resultArtifact?.kind == AIArtifactKind.image &&
              validImageArtifactReference(job.resultArtifact?.reference) !=
                  null;
    if (!hasOutput) return job;

    var placementJob = job;
    final sourceNode = sourceNodeId == null
        ? null
        : _ref
              .read(documentNodesProvider)
              .where((node) => node.id == sourceNodeId)
              .firstOrNull;
    if (job.outputMode == AIOutputMode.replace &&
        !_canReplaceCompletedOutput(sourceNode, job)) {
      placementJob = job.copyWith(
        outputMode: AIOutputMode.insert,
        sourceNodeIds: const [],
      );
    }
    final transactions = _ref.read(
      aiCanvasTransactionProvider(placementJob.projectId).notifier,
    );
    final entry = await transactions.stageGeneratedJob(
      placementJob,
      position: position,
      onNodeCreated: onNodeCreated,
    );
    if (entry == null || !entry.canApply) return placementJob;

    if (placementJob.outputMode == AIOutputMode.replace) {
      await transactions.replace(entry.id, canEditCanvas: canEditCanvas);
    } else {
      await transactions.insert(entry.id, canEditCanvas: canEditCanvas);
    }
    return placementJob;
  }

  AIJob _withDefaultVariantSet(AIJob job) {
    if (job.variantSetPayload != null) return job;
    final reference = job.resultArtifact?.kind == AIArtifactKind.image
        ? validImageArtifactReference(job.resultArtifact?.reference)
        : null;
    final references = [?reference];
    if (references.isEmpty) return job;
    final groupId = job.variantGroupId ?? job.id;
    return job.copyWith(
      variantGroupId: groupId,
      variantSetPayload: {
        'id': groupId,
        'variants': [
          for (var index = 0; index < references.length; index++)
            {
              'id': '$groupId-$index',
              'artifactReference': references[index],
              'index': index,
              'favorite': false,
              'selectedForCompare': false,
              'license': job.provenance['license'],
              'metadata': {
                if (job.provider != null) 'provider': job.provider,
                if (job.model != null) 'model': job.model,
              },
            },
        ],
      },
    );
  }
}

bool _canReplaceCompletedOutput(CanvasNode? source, AIJob job) {
  if (source == null) return false;
  if (job.resultArtifact?.kind == AIArtifactKind.model3d) {
    return source.type == NodeType.model3d;
  }
  if (job.category == AICreativeCategory.videoAI) {
    return source.type == NodeType.videoCard;
  }
  return job.resultArtifact?.kind == AIArtifactKind.image &&
      source.type == NodeType.image;
}

final aiCreativeEngineProvider =
    StateNotifierProvider<AICreativeEngineNotifier, AICreativeEngineState>((
      ref,
    ) {
      return AICreativeEngineNotifier(ref);
    });

class AIJobsNotifier extends StateNotifier<List<AIJob>> {
  final Ref _ref;

  AIJobsNotifier(this._ref) : super(const []);

  Future<AIJob> runJob({
    required String projectId,
    required AICapability capability,
    required String prompt,
  }) async {
    final job = await _ref
        .read(aiCreativeEngineProvider.notifier)
        .runJob(projectId: projectId, capability: capability, prompt: prompt);
    state = _ref.read(aiCreativeEngineProvider).jobs;
    return job;
  }
}

final aiJobsProvider = StateNotifierProvider<AIJobsNotifier, List<AIJob>>((
  ref,
) {
  return AIJobsNotifier(ref);
});
