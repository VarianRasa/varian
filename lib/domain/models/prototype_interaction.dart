enum PrototypeTrigger { tap, hover, press, drag }

enum PrototypeAction { navigate, overlay, setState, openUrl, back }

enum PrototypeTransition {
  instant,
  dissolve,
  smartAnimate,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  push,
}

class PrototypeInteraction {
  final String id;
  final PrototypeTrigger trigger;
  final PrototypeAction action;
  final String? targetFrameId;
  final String? targetNodeId;
  final String? stateId;
  final String? url;
  final PrototypeTransition transition;
  final int durationMs;
  final bool preserveScroll;
  final bool enabled;

  const PrototypeInteraction({
    required this.id,
    this.trigger = PrototypeTrigger.tap,
    this.action = PrototypeAction.navigate,
    this.targetFrameId,
    this.targetNodeId,
    this.stateId,
    this.url,
    this.transition = PrototypeTransition.instant,
    this.durationMs = 300,
    this.preserveScroll = false,
    this.enabled = true,
  });

  bool get isValid {
    switch (action) {
      case PrototypeAction.navigate:
        return targetFrameId?.trim().isNotEmpty == true;
      case PrototypeAction.overlay:
        return targetNodeId?.trim().isNotEmpty == true;
      case PrototypeAction.setState:
        return stateId?.trim().isNotEmpty == true;
      case PrototypeAction.openUrl:
        return url?.trim().isNotEmpty == true;
      case PrototypeAction.back:
        return true;
    }
  }

  PrototypeInteraction normalized() => PrototypeInteraction(
    id: id.trim().isEmpty ? 'interaction' : id.trim(),
    trigger: trigger,
    action: action,
    targetFrameId: _clean(targetFrameId),
    targetNodeId: _clean(targetNodeId),
    stateId: _clean(stateId),
    url: _clean(url),
    transition: transition,
    durationMs: durationMs.clamp(0, 10_000).toInt(),
    preserveScroll: preserveScroll,
    enabled: enabled,
  );

  factory PrototypeInteraction.fromJson(Map<String, dynamic> json) =>
      PrototypeInteraction(
        id: json['id'] as String? ?? 'interaction',
        trigger: PrototypeTrigger.values.firstWhere(
          (value) => value.name == json['trigger'],
          orElse: () => PrototypeTrigger.tap,
        ),
        action: PrototypeAction.values.firstWhere(
          (value) => value.name == json['action'],
          orElse: () => PrototypeAction.navigate,
        ),
        targetFrameId: json['targetFrameId'] as String?,
        targetNodeId: json['targetNodeId'] as String?,
        stateId: json['stateId'] as String?,
        url: json['url'] as String?,
        transition: PrototypeTransition.values.firstWhere(
          (value) => value.name == json['transition'],
          orElse: () => PrototypeTransition.instant,
        ),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 300,
        preserveScroll: json['preserveScroll'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
      ).normalized();

  Map<String, dynamic> toJson() => {
    'id': id,
    'trigger': trigger.name,
    'action': action.name,
    'targetFrameId': targetFrameId,
    'targetNodeId': targetNodeId,
    'stateId': stateId,
    'url': url,
    'transition': transition.name,
    'durationMs': durationMs,
    'preserveScroll': preserveScroll,
    'enabled': enabled,
  };

  PrototypeInteraction copyWith({
    String? id,
    PrototypeTrigger? trigger,
    PrototypeAction? action,
    Object? targetFrameId = _sentinel,
    Object? targetNodeId = _sentinel,
    Object? stateId = _sentinel,
    Object? url = _sentinel,
    PrototypeTransition? transition,
    int? durationMs,
    bool? preserveScroll,
    bool? enabled,
  }) => PrototypeInteraction(
    id: id ?? this.id,
    trigger: trigger ?? this.trigger,
    action: action ?? this.action,
    targetFrameId: targetFrameId == _sentinel
        ? this.targetFrameId
        : targetFrameId as String?,
    targetNodeId: targetNodeId == _sentinel
        ? this.targetNodeId
        : targetNodeId as String?,
    stateId: stateId == _sentinel ? this.stateId : stateId as String?,
    url: url == _sentinel ? this.url : url as String?,
    transition: transition ?? this.transition,
    durationMs: durationMs ?? this.durationMs,
    preserveScroll: preserveScroll ?? this.preserveScroll,
    enabled: enabled ?? this.enabled,
  );

  static const Object _sentinel = Object();

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}

class PrototypeDevicePreset {
  final String id;
  final String label;
  final double width;
  final double height;
  final double devicePixelRatio;

  const PrototypeDevicePreset({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    this.devicePixelRatio = 1.0,
  });

  PrototypeDevicePreset get portrait => this;

  PrototypeDevicePreset get landscape => PrototypeDevicePreset(
    id: '$id-landscape',
    label: '$label Landscape',
    width: height,
    height: width,
    devicePixelRatio: devicePixelRatio,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'width': width,
    'height': height,
    'devicePixelRatio': devicePixelRatio,
  };
}

const prototypeDevicePresets = <PrototypeDevicePreset>[
  PrototypeDevicePreset(
    id: 'desktop',
    label: 'Desktop',
    width: 1440,
    height: 900,
    devicePixelRatio: 1,
  ),
  PrototypeDevicePreset(
    id: 'tablet',
    label: 'Tablet',
    width: 1024,
    height: 1366,
    devicePixelRatio: 2,
  ),
  PrototypeDevicePreset(
    id: 'mobile',
    label: 'Mobile',
    width: 390,
    height: 844,
    devicePixelRatio: 3,
  ),
];
