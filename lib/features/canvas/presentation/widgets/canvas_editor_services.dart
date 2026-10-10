import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/media/data/media_artifact_store.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store.dart';

/// Root-only capabilities that can be composed around the shared canvas editor.
///
/// The editor surface owns document editing. Hosts choose which project-level
/// services should be active without asking the editor to infer its role from a
/// boolean mode flag.
class CanvasEditorServices {
  final bool showProjectHeader;
  final bool showLayersByDefault;
  final bool enableAutosave;
  final bool enableCloudSync;
  final bool enableCollaboration;
  final bool enableAiStudio;
  final bool trackVideoObjectUrls;
  final bool enableExport;
  final bool stackPanelsOnCompact;
  final Future<AssetPickerResult?> Function({String? projectId})? pickImage;
  final Future<AssetPickerResult?> Function({String? projectId})? pickAnyFile;
  final Future<AssetPickerResult?> Function()? pickGlb;
  final ImageArtifactStore? imageArtifactStore;
  final FileArtifactStore? fileArtifactStore;
  final MediaArtifactStore? mediaArtifactStore;
  final VideoArtifactStore? videoArtifactStore;
  final Model3DArtifactStore? model3DArtifactStore;

  const CanvasEditorServices({
    required this.showProjectHeader,
    required this.showLayersByDefault,
    required this.enableAutosave,
    this.enableCloudSync = true,
    required this.enableCollaboration,
    required this.enableAiStudio,
    required this.trackVideoObjectUrls,
    this.enableExport = true,
    this.stackPanelsOnCompact = false,
    this.pickImage,
    this.pickAnyFile,
    this.pickGlb,
    this.imageArtifactStore,
    this.fileArtifactStore,
    this.mediaArtifactStore,
    this.videoArtifactStore,
    this.model3DArtifactStore,
  });

  CanvasEditorServices copyWith({
    bool? enableExport,
    bool? enableCloudSync,
    bool? enableCollaboration,
    bool? stackPanelsOnCompact,
    Future<AssetPickerResult?> Function({String? projectId})? pickImage,
    Future<AssetPickerResult?> Function({String? projectId})? pickAnyFile,
    Future<AssetPickerResult?> Function()? pickGlb,
    ImageArtifactStore? imageArtifactStore,
    FileArtifactStore? fileArtifactStore,
    MediaArtifactStore? mediaArtifactStore,
    VideoArtifactStore? videoArtifactStore,
    Model3DArtifactStore? model3DArtifactStore,
  }) => CanvasEditorServices(
    showProjectHeader: showProjectHeader,
    showLayersByDefault: showLayersByDefault,
    enableAutosave: enableAutosave,
    enableCloudSync: enableCloudSync ?? this.enableCloudSync,
    enableCollaboration: enableCollaboration ?? this.enableCollaboration,
    enableAiStudio: enableAiStudio,
    trackVideoObjectUrls: trackVideoObjectUrls,
    enableExport: enableExport ?? this.enableExport,
    stackPanelsOnCompact: stackPanelsOnCompact ?? this.stackPanelsOnCompact,
    pickImage: pickImage ?? this.pickImage,
    pickAnyFile: pickAnyFile ?? this.pickAnyFile,
    pickGlb: pickGlb ?? this.pickGlb,
    imageArtifactStore: imageArtifactStore ?? this.imageArtifactStore,
    fileArtifactStore: fileArtifactStore ?? this.fileArtifactStore,
    mediaArtifactStore: mediaArtifactStore ?? this.mediaArtifactStore,
    videoArtifactStore: videoArtifactStore ?? this.videoArtifactStore,
    model3DArtifactStore: model3DArtifactStore ?? this.model3DArtifactStore,
  );

  static const root = CanvasEditorServices(
    showProjectHeader: true,
    showLayersByDefault: false,
    enableAutosave: true,
    enableCollaboration: true,
    enableAiStudio: true,
    trackVideoObjectUrls: true,
  );

  static const embedded = CanvasEditorServices(
    showProjectHeader: false,
    showLayersByDefault: true,
    enableAutosave: false,
    enableCollaboration: false,
    enableAiStudio: false,
    trackVideoObjectUrls: false,
    stackPanelsOnCompact: true,
  );

  static const sharedReadOnly = CanvasEditorServices(
    showProjectHeader: false,
    showLayersByDefault: false,
    enableAutosave: false,
    enableCollaboration: false,
    enableAiStudio: false,
    trackVideoObjectUrls: true,
  );
}
