import '../../../domain/models/ai_job.dart';

enum AICapabilityAvailability {
  implemented,
  configured,
  experimental,
  unavailable,
}

class AICapabilityDescriptor {
  final AICapability capability;
  final AICapabilityAvailability availability;
  final List<String> providers;
  final String? note;

  const AICapabilityDescriptor({
    required this.capability,
    required this.availability,
    this.providers = const [],
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'capability': capability.name,
    'availability': availability.name,
    'providers': providers,
    if (note != null) 'note': note,
  };
}

class AICapabilityMatrix {
  final Map<AICapability, AICapabilityDescriptor> entries;

  const AICapabilityMatrix({this.entries = const {}});

  AICapabilityDescriptor operator [](AICapability capability) =>
      entries[capability] ??
      AICapabilityDescriptor(
        capability: capability,
        availability: AICapabilityAvailability.unavailable,
        note: 'No provider is configured for this capability.',
      );

  bool canRun(AICapability capability) {
    final status = this[capability].availability;
    return status == AICapabilityAvailability.implemented ||
        status == AICapabilityAvailability.configured;
  }

  List<AICapabilityDescriptor> get descriptors =>
      AICapability.values.map((capability) => this[capability]).toList();

  static AICapabilityMatrix fromProviderConfig({
    required bool hasImageProvider,
    required bool hasVideoProvider,
    required bool hasThreeDProvider,
    bool hasChatProvider = false,
  }) {
    final entries = <AICapability, AICapabilityDescriptor>{};
    for (final capability in AICapability.values) {
      final isTextTo3D = capability == AICapability.textTo3D;
      final isImageTo3D = capability == AICapability.imageTo3D;
      final isVideo = capability == AICapability.imageToVideo;
      final isChat =
          capability == AICapability.understandCanvas ||
          capability == AICapability.understandSelection ||
          capability == AICapability.summarizeNotes;
      final isImage = switch (capability) {
        AICapability.textToImage ||
        AICapability.sketchToImage ||
        AICapability.imageToImage ||
        AICapability.referenceToImage ||
        AICapability.inpainting ||
        AICapability.outpainting ||
        AICapability.replaceObject ||
        AICapability.removeObject ||
        AICapability.addObject ||
        AICapability.backgroundReplace ||
        AICapability.styleTransfer ||
        AICapability.materialTransfer ||
        AICapability.relighting ||
        AICapability.recolor ||
        AICapability.restyle ||
        AICapability.populate ||
        AICapability.compositionRemove ||
        AICapability.rearrange ||
        AICapability.expandScene ||
        AICapability.smartCutout => true,
        _ => false,
      };
      final configured = isTextTo3D
          ? hasThreeDProvider && hasImageProvider
          : isImageTo3D
          ? hasThreeDProvider
          : isVideo
          ? hasVideoProvider
          : isChat
          ? hasChatProvider
          : isImage && hasImageProvider;
      final providerNames = <String>[
        if (isTextTo3D && hasImageProvider) 'image',
        if (isTextTo3D || isImageTo3D)
          if (hasThreeDProvider) '3d',
        if (isVideo && hasVideoProvider) 'video',
        if (isChat && hasChatProvider) 'chat',
        if (isImage && hasImageProvider) 'image',
      ];
      entries[capability] = AICapabilityDescriptor(
        capability: capability,
        availability: configured
            ? AICapabilityAvailability.configured
            : AICapabilityAvailability.unavailable,
        providers: providerNames,
        note: !configured
            ? isImage || isTextTo3D || isImageTo3D || isVideo || isChat
                  ? 'Configure a compatible provider before running this action.'
                  : 'No supported provider contract is implemented for this action.'
            : null,
      );
    }
    return AICapabilityMatrix(entries: entries);
  }
}
