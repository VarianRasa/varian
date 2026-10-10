import 'node_payload.dart';
import 'model3d_studio.dart';
import 'durable_asset_reference.dart';

enum Model3DViewportMode { threeD, threeDAndTwoD, twoD }

enum Model3DRenderMode { finalRender, noPostProcessing }

enum Model3DMaterialChannel {
  baseColor,
  metalness,
  roughness,
  normalMap,
  aoMap,
  cavity,
  opacity,
  specularF0,
  clearCoat,
  clearCoatRoughness,
  clearCoatNormalMap,
}

enum Model3DGeometryMode {
  none,
  matcap,
  matcapSurface,
  wireframe,
  vertexNormals,
}

enum Model3DInspectorSelection {
  finalRender,
  noPostProcessing,
  baseColor,
  metalness,
  roughness,
  normalMap,
  aoMap,
  cavity,
  opacity,
  specularF0,
  clearCoat,
  clearCoatRoughness,
  clearCoatNormalMap,
  matcap,
  matcapSurface,
  wireframe,
  vertexNormals,
  uvChecker,
}

/// Persisted metadata and display settings for a GLB canvas node.
class Model3DPayload extends NodePayload {
  final String fileName;
  final String fileSizeText;

  /// Stable manifest identity for the attached model artifact.
  final String? assetId;

  /// Stable project-scoped Storage metadata for the model source.
  final String? storagePath;
  final String? modelPath;
  final String? modelUrl;
  final String? artifactReference;
  final String? sourceError;
  final bool autoRotate;
  final bool isTemporary;
  final Model3DViewportMode viewportMode;
  final Model3DRenderMode renderMode;
  final Model3DMaterialChannel materialChannel;
  final Model3DGeometryMode geometryMode;
  final int wireframeColor;
  final bool doubleSided;
  final bool uvChecker;
  final bool transparentBackground;
  final Model3DInspectorSelection inspectorSelection;
  final List<Model3DCameraBookmark> cameraBookmarks;
  final String? activeCameraBookmarkId;
  final List<Model3DAnnotation> annotations;
  final Model3DLightingPreset lightingPreset;
  final List<Model3DSnapshot> snapshots;

  Model3DPayload({
    this.fileName = 'Model.glb',
    this.fileSizeText = '0 B',
    this.assetId,
    this.storagePath,
    this.modelPath,
    this.modelUrl,
    this.artifactReference,
    this.sourceError,
    this.autoRotate = false,
    this.isTemporary = false,
    this.viewportMode = Model3DViewportMode.threeD,
    this.renderMode = Model3DRenderMode.finalRender,
    this.materialChannel = Model3DMaterialChannel.baseColor,
    this.geometryMode = Model3DGeometryMode.none,
    this.wireframeColor = 0xFFFFFFFF,
    this.doubleSided = false,
    this.uvChecker = false,
    this.transparentBackground = false,
    this.cameraBookmarks = const [],
    this.activeCameraBookmarkId,
    this.annotations = const [],
    this.lightingPreset = Model3DLightingPreset.studio,
    this.snapshots = const [],
    Model3DInspectorSelection? inspectorSelection,
  }) : inspectorSelection =
           inspectorSelection ??
           _selectionForFields(
             renderMode: renderMode,
             materialChannel: materialChannel,
             geometryMode: geometryMode,
             uvChecker: uvChecker,
           );

  factory Model3DPayload.fromJson(Map<String, dynamic> json) => Model3DPayload(
    fileName: json['fileName'] as String? ?? 'Model.glb',
    fileSizeText: json['fileSizeText'] as String? ?? '0 B',
    assetId: json['assetId'] as String?,
    storagePath: durableAssetReference(json['storagePath'] as String?),
    // Native paths, delivery URLs, and app-owned artifact handles are
    // runtime-only. A local artifact manifest or Storage path hydrates them
    // after the durable document has been loaded.
    modelPath: null,
    modelUrl: null,
    artifactReference: validModel3DArtifactReference(
      json['artifactReference'] as String?,
    ),
    sourceError: null,
    autoRotate: json['autoRotate'] as bool? ?? false,
    isTemporary: false,
    viewportMode: _enumValue(
      Model3DViewportMode.values,
      json['viewportMode'],
      Model3DViewportMode.threeD,
    ),
    renderMode: _enumValue(
      Model3DRenderMode.values,
      json['renderMode'],
      Model3DRenderMode.finalRender,
    ),
    materialChannel: _enumValue(
      Model3DMaterialChannel.values,
      json['materialChannel'],
      Model3DMaterialChannel.baseColor,
    ),
    geometryMode: _enumValue(
      Model3DGeometryMode.values,
      json['geometryMode'],
      Model3DGeometryMode.none,
    ),
    wireframeColor: _colorValue(json['wireframeColor']),
    doubleSided: json['doubleSided'] as bool? ?? false,
    uvChecker: json['uvChecker'] as bool? ?? false,
    transparentBackground: json['transparentBackground'] as bool? ?? false,
    cameraBookmarks: [
      for (final raw in (json['cameraBookmarks'] as List<dynamic>? ?? const []))
        if (raw is Map)
          Model3DCameraBookmark.fromJson(Map<String, dynamic>.from(raw)),
    ],
    activeCameraBookmarkId: json['activeCameraBookmarkId'] as String?,
    annotations: [
      for (final raw in (json['annotations'] as List<dynamic>? ?? const []))
        if (raw is Map)
          Model3DAnnotation.fromJson(Map<String, dynamic>.from(raw)),
    ],
    lightingPreset: _enumValue(
      Model3DLightingPreset.values,
      json['lightingPreset'],
      Model3DLightingPreset.studio,
    ),
    snapshots: [
      for (final raw in (json['snapshots'] as List<dynamic>? ?? const []))
        if (raw is Map)
          Model3DSnapshot.fromJson(Map<String, dynamic>.from(raw)),
    ],
    inspectorSelection: _enumValue(
      Model3DInspectorSelection.values,
      json['inspectorSelection'],
      _legacyInspectorSelection(json),
    ),
  );

  bool get hasArtifactReference =>
      validModel3DArtifactReference(artifactReference) != null;

  /// A Storage path is durable metadata, but this payload cannot hydrate it
  /// without an account/project-fenced byte reader. The owning editor must
  /// materialize it into [artifactReference] before interactive preview.
  bool get hasStorageOnlySource =>
      !hasArtifactReference && durableAssetReference(storagePath) != null;

  bool get hasSource => hasArtifactReference || hasStorageOnlySource;

  String get displayName => fileName.trim().isEmpty ? 'Model.glb' : fileName;

  @override
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileSizeText': fileSizeText,
    if (assetId != null) 'assetId': assetId,
    'storagePath': ?durableAssetReference(storagePath),
    'artifactReference': ?validModel3DArtifactReference(artifactReference),
    // Native paths, delivery URLs, app-owned artifact handles, source errors,
    // and temporary state are runtime-only.
    'autoRotate': autoRotate,
    'viewportMode': viewportMode.name,
    'renderMode': renderMode.name,
    'materialChannel': materialChannel.name,
    'geometryMode': geometryMode.name,
    'wireframeColor': wireframeColor,
    'doubleSided': doubleSided,
    'uvChecker': uvChecker,
    'transparentBackground': transparentBackground,
    'inspectorSelection': inspectorSelection.name,
    'cameraBookmarks': cameraBookmarks
        .map((bookmark) => bookmark.toJson())
        .toList(growable: false),
    'activeCameraBookmarkId': activeCameraBookmarkId,
    'annotations': annotations
        .map((annotation) => annotation.toJson())
        .toList(growable: false),
    'lightingPreset': lightingPreset.name,
    'snapshots': snapshots
        .map((snapshot) => snapshot.toJson())
        .toList(growable: false),
  };

  @override
  Map<String, dynamic> toPersistenceJson() => toJson();

  @override
  Model3DPayload clone() => Model3DPayload(
    fileName: fileName,
    fileSizeText: fileSizeText,
    assetId: assetId,
    storagePath: storagePath,
    modelPath: modelPath,
    modelUrl: modelUrl,
    artifactReference: artifactReference,
    sourceError: sourceError,
    autoRotate: autoRotate,
    isTemporary: isTemporary,
    viewportMode: viewportMode,
    renderMode: renderMode,
    materialChannel: materialChannel,
    geometryMode: geometryMode,
    wireframeColor: wireframeColor,
    doubleSided: doubleSided,
    uvChecker: uvChecker,
    transparentBackground: transparentBackground,
    inspectorSelection: inspectorSelection,
    cameraBookmarks: cameraBookmarks,
    activeCameraBookmarkId: activeCameraBookmarkId,
    annotations: annotations,
    lightingPreset: lightingPreset,
    snapshots: snapshots,
  );

  Model3DPayload copyWith({
    String? fileName,
    String? fileSizeText,
    String? assetId,
    Object? storagePath = _sentinel,
    Object? modelPath = _sentinel,
    Object? modelUrl = _sentinel,
    Object? artifactReference = _sentinel,
    Object? sourceError = _sentinel,
    bool? autoRotate,
    bool? isTemporary,
    Model3DViewportMode? viewportMode,
    Model3DRenderMode? renderMode,
    Model3DMaterialChannel? materialChannel,
    Model3DGeometryMode? geometryMode,
    int? wireframeColor,
    bool? doubleSided,
    bool? uvChecker,
    bool? transparentBackground,
    Model3DInspectorSelection? inspectorSelection,
    List<Model3DCameraBookmark>? cameraBookmarks,
    Object? activeCameraBookmarkId = _sentinel,
    List<Model3DAnnotation>? annotations,
    Model3DLightingPreset? lightingPreset,
    List<Model3DSnapshot>? snapshots,
  }) {
    final nextRenderMode = renderMode ?? this.renderMode;
    final nextMaterialChannel = materialChannel ?? this.materialChannel;
    final nextGeometryMode = geometryMode ?? this.geometryMode;
    final nextUvChecker = uvChecker ?? this.uvChecker;
    final nextSelection =
        inspectorSelection ??
        (renderMode != null ||
                materialChannel != null ||
                geometryMode != null ||
                uvChecker != null
            ? _selectionForFields(
                renderMode: nextRenderMode,
                materialChannel: nextMaterialChannel,
                geometryMode: nextGeometryMode,
                uvChecker: nextUvChecker,
              )
            : this.inspectorSelection);
    return Model3DPayload(
      fileName: fileName ?? this.fileName,
      fileSizeText: fileSizeText ?? this.fileSizeText,
      assetId: assetId ?? this.assetId,
      storagePath: storagePath == _sentinel
          ? this.storagePath
          : durableAssetReference(storagePath as String?),
      modelPath: modelPath == _sentinel ? this.modelPath : modelPath as String?,
      modelUrl: modelUrl == _sentinel ? this.modelUrl : modelUrl as String?,
      artifactReference: artifactReference == _sentinel
          ? this.artifactReference
          : artifactReference as String?,
      sourceError: sourceError == _sentinel
          ? this.sourceError
          : sourceError as String?,
      autoRotate: autoRotate ?? this.autoRotate,
      isTemporary: isTemporary ?? this.isTemporary,
      viewportMode: viewportMode ?? this.viewportMode,
      renderMode: nextRenderMode,
      materialChannel: nextMaterialChannel,
      geometryMode: nextGeometryMode,
      wireframeColor: wireframeColor ?? this.wireframeColor,
      doubleSided: doubleSided ?? this.doubleSided,
      uvChecker: nextUvChecker,
      transparentBackground:
          transparentBackground ?? this.transparentBackground,
      inspectorSelection: nextSelection,
      cameraBookmarks: cameraBookmarks ?? this.cameraBookmarks,
      activeCameraBookmarkId: activeCameraBookmarkId == _sentinel
          ? this.activeCameraBookmarkId
          : activeCameraBookmarkId as String?,
      annotations: annotations ?? this.annotations,
      lightingPreset: lightingPreset ?? this.lightingPreset,
      snapshots: snapshots ?? this.snapshots,
    );
  }

  Model3DPayload upsertCameraBookmark(Model3DCameraBookmark bookmark) {
    final next = [
      for (final item in cameraBookmarks)
        if (item.id != bookmark.id) item,
      bookmark.normalized(),
    ];
    return copyWith(cameraBookmarks: List.unmodifiable(next));
  }

  Model3DPayload removeCameraBookmark(String bookmarkId) {
    final next = cameraBookmarks
        .where((bookmark) => bookmark.id != bookmarkId)
        .toList(growable: false);
    return copyWith(
      cameraBookmarks: List.unmodifiable(next),
      activeCameraBookmarkId: activeCameraBookmarkId == bookmarkId
          ? null
          : activeCameraBookmarkId,
    );
  }

  Model3DPayload upsertAnnotation(Model3DAnnotation annotation) {
    final next = [
      for (final item in annotations)
        if (item.id != annotation.id) item,
      annotation.normalized(),
    ];
    return copyWith(annotations: List.unmodifiable(next));
  }

  Model3DPayload removeAnnotation(String annotationId) => copyWith(
    annotations: List.unmodifiable(
      annotations.where((annotation) => annotation.id != annotationId),
    ),
  );

  Model3DPayload upsertSnapshot(Model3DSnapshot snapshot) {
    final next = [
      for (final item in snapshots)
        if (item.id != snapshot.id) item,
      snapshot.normalized(),
    ];
    return copyWith(snapshots: List.unmodifiable(next));
  }

  List<String> get diagnostics {
    final messages = <String>[];
    if (!hasSource) messages.add('GLB source is unavailable.');
    if (cameraBookmarks.map((item) => item.id).toSet().length !=
        cameraBookmarks.length) {
      messages.add('Camera bookmark IDs are duplicated.');
    }
    if (activeCameraBookmarkId != null &&
        !cameraBookmarks.any((item) => item.id == activeCameraBookmarkId)) {
      messages.add('Active camera bookmark does not exist.');
    }
    if (annotations.map((item) => item.id).toSet().length !=
        annotations.length) {
      messages.add('3D annotation IDs are duplicated.');
    }
    if (snapshots.any(
      (snapshot) =>
          snapshot.artifactReference?.trim().isEmpty == true ||
          snapshot.width < 0 ||
          snapshot.height < 0,
    )) {
      messages.add('A snapshot contains invalid artifact metadata.');
    }
    return List.unmodifiable(messages);
  }

  Model3DPayload copyWithInspectorSelection(
    Model3DInspectorSelection selection, {
    int? wireframeColor,
  }) {
    var nextRenderMode = Model3DRenderMode.finalRender;
    var nextMaterialChannel = Model3DMaterialChannel.baseColor;
    var nextGeometryMode = Model3DGeometryMode.none;
    var nextUvChecker = false;

    switch (selection) {
      case Model3DInspectorSelection.finalRender:
        break;
      case Model3DInspectorSelection.noPostProcessing:
        nextRenderMode = Model3DRenderMode.noPostProcessing;
        break;
      case Model3DInspectorSelection.baseColor:
        nextMaterialChannel = Model3DMaterialChannel.baseColor;
        break;
      case Model3DInspectorSelection.metalness:
        nextMaterialChannel = Model3DMaterialChannel.metalness;
        break;
      case Model3DInspectorSelection.roughness:
        nextMaterialChannel = Model3DMaterialChannel.roughness;
        break;
      case Model3DInspectorSelection.normalMap:
        nextMaterialChannel = Model3DMaterialChannel.normalMap;
        break;
      case Model3DInspectorSelection.aoMap:
        nextMaterialChannel = Model3DMaterialChannel.aoMap;
        break;
      case Model3DInspectorSelection.cavity:
        nextMaterialChannel = Model3DMaterialChannel.cavity;
        break;
      case Model3DInspectorSelection.opacity:
        nextMaterialChannel = Model3DMaterialChannel.opacity;
        break;
      case Model3DInspectorSelection.specularF0:
        nextMaterialChannel = Model3DMaterialChannel.specularF0;
        break;
      case Model3DInspectorSelection.clearCoat:
        nextMaterialChannel = Model3DMaterialChannel.clearCoat;
        break;
      case Model3DInspectorSelection.clearCoatRoughness:
        nextMaterialChannel = Model3DMaterialChannel.clearCoatRoughness;
        break;
      case Model3DInspectorSelection.clearCoatNormalMap:
        nextMaterialChannel = Model3DMaterialChannel.clearCoatNormalMap;
        break;
      case Model3DInspectorSelection.matcap:
        nextGeometryMode = Model3DGeometryMode.matcap;
        break;
      case Model3DInspectorSelection.matcapSurface:
        nextGeometryMode = Model3DGeometryMode.matcapSurface;
        break;
      case Model3DInspectorSelection.wireframe:
        nextGeometryMode = Model3DGeometryMode.wireframe;
        break;
      case Model3DInspectorSelection.vertexNormals:
        nextGeometryMode = Model3DGeometryMode.vertexNormals;
        break;
      case Model3DInspectorSelection.uvChecker:
        nextUvChecker = true;
        break;
    }

    return copyWith(
      renderMode: nextRenderMode,
      materialChannel: nextMaterialChannel,
      geometryMode: nextGeometryMode,
      uvChecker: nextUvChecker,
      wireframeColor: wireframeColor,
      inspectorSelection: selection,
    );
  }

  static Model3DInspectorSelection _legacyInspectorSelection(
    Map<String, dynamic> json,
  ) => _selectionForFields(
    renderMode: _enumValue(
      Model3DRenderMode.values,
      json['renderMode'],
      Model3DRenderMode.finalRender,
    ),
    materialChannel: _enumValue(
      Model3DMaterialChannel.values,
      json['materialChannel'],
      Model3DMaterialChannel.baseColor,
    ),
    geometryMode: _enumValue(
      Model3DGeometryMode.values,
      json['geometryMode'],
      Model3DGeometryMode.none,
    ),
    uvChecker: json['uvChecker'] as bool? ?? false,
  );

  static Model3DInspectorSelection _selectionForFields({
    required Model3DRenderMode renderMode,
    required Model3DMaterialChannel materialChannel,
    required Model3DGeometryMode geometryMode,
    required bool uvChecker,
  }) {
    if (renderMode == Model3DRenderMode.finalRender &&
        materialChannel == Model3DMaterialChannel.baseColor &&
        geometryMode == Model3DGeometryMode.none &&
        !uvChecker) {
      return Model3DInspectorSelection.finalRender;
    }
    if (uvChecker) return Model3DInspectorSelection.uvChecker;
    switch (geometryMode) {
      case Model3DGeometryMode.matcap:
        return Model3DInspectorSelection.matcap;
      case Model3DGeometryMode.matcapSurface:
        return Model3DInspectorSelection.matcapSurface;
      case Model3DGeometryMode.wireframe:
        return Model3DInspectorSelection.wireframe;
      case Model3DGeometryMode.none:
        break;
      case Model3DGeometryMode.vertexNormals:
        return Model3DInspectorSelection.vertexNormals;
    }
    switch (materialChannel) {
      case Model3DMaterialChannel.baseColor:
        break;
      case Model3DMaterialChannel.metalness:
        return Model3DInspectorSelection.metalness;
      case Model3DMaterialChannel.roughness:
        return Model3DInspectorSelection.roughness;
      case Model3DMaterialChannel.normalMap:
        return Model3DInspectorSelection.normalMap;
      case Model3DMaterialChannel.aoMap:
        return Model3DInspectorSelection.aoMap;
      case Model3DMaterialChannel.cavity:
        return Model3DInspectorSelection.cavity;
      case Model3DMaterialChannel.opacity:
        return Model3DInspectorSelection.opacity;
      case Model3DMaterialChannel.specularF0:
        return Model3DInspectorSelection.specularF0;
      case Model3DMaterialChannel.clearCoat:
        return Model3DInspectorSelection.clearCoat;
      case Model3DMaterialChannel.clearCoatRoughness:
        return Model3DInspectorSelection.clearCoatRoughness;
      case Model3DMaterialChannel.clearCoatNormalMap:
        return Model3DInspectorSelection.clearCoatNormalMap;
    }
    return renderMode == Model3DRenderMode.noPostProcessing
        ? Model3DInspectorSelection.noPostProcessing
        : Model3DInspectorSelection.finalRender;
  }

  static T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    return fallback;
  }

  static int _colorValue(Object? raw) {
    final value = raw is num ? raw.toInt() : 0xFFFFFFFF;
    return value.clamp(0, 0xFFFFFFFF).toInt();
  }

  static const Object _sentinel = Object();
}
