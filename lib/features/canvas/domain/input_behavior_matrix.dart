enum CanvasPlatform { web, windows, android }

enum CanvasInputModality { mouse, trackpad, touch, stylus, keyboard }

class ShortcutBinding {
  final String command;
  final String key;
  final bool control;
  final bool meta;
  final bool shift;
  final bool alt;

  const ShortcutBinding({
    required this.command,
    required this.key,
    this.control = false,
    this.meta = false,
    this.shift = false,
    this.alt = false,
  });

  String get signature => [
    if (control) 'Ctrl',
    if (meta) 'Meta',
    if (shift) 'Shift',
    if (alt) 'Alt',
    key.toUpperCase(),
  ].join('+');

  ShortcutBinding copyWith({
    String? key,
    bool? control,
    bool? meta,
    bool? shift,
    bool? alt,
  }) => ShortcutBinding(
    command: command,
    key: key ?? this.key,
    control: control ?? this.control,
    meta: meta ?? this.meta,
    shift: shift ?? this.shift,
    alt: alt ?? this.alt,
  );

  Map<String, dynamic> toJson() => {
    'command': command,
    'key': key,
    'control': control,
    'meta': meta,
    'shift': shift,
    'alt': alt,
  };

  factory ShortcutBinding.fromJson(Map<String, dynamic> json) =>
      ShortcutBinding(
        command: json['command'] as String? ?? '',
        key: json['key'] as String? ?? '',
        control: json['control'] as bool? ?? false,
        meta: json['meta'] as bool? ?? false,
        shift: json['shift'] as bool? ?? false,
        alt: json['alt'] as bool? ?? false,
      );
}

class InputBehavior {
  final CanvasPlatform platform;
  final CanvasInputModality modality;
  final String action;
  final String description;
  final bool supported;
  final bool requiresPrimaryButton;
  final bool supportsPressure;

  const InputBehavior({
    required this.platform,
    required this.modality,
    required this.action,
    required this.description,
    this.supported = true,
    this.requiresPrimaryButton = false,
    this.supportsPressure = false,
  });
}

class InputBehaviorMatrix {
  final List<InputBehavior> behaviors;
  final List<ShortcutBinding> shortcuts;

  const InputBehaviorMatrix({
    this.behaviors = const [],
    this.shortcuts = const [],
  });

  factory InputBehaviorMatrix.defaults() {
    final behaviors = <InputBehavior>[];
    for (final platform in CanvasPlatform.values) {
      behaviors.addAll([
        InputBehavior(
          platform: platform,
          modality: CanvasInputModality.keyboard,
          action: 'nudge',
          description: 'Arrow keys nudge the active selection.',
        ),
        InputBehavior(
          platform: platform,
          modality: CanvasInputModality.keyboard,
          action: 'undo',
          description: 'The platform primary modifier plus Z undoes a command.',
        ),
        InputBehavior(
          platform: platform,
          modality: CanvasInputModality.keyboard,
          action: 'redo',
          description:
              'The platform primary modifier plus Shift plus Z redoes a command.',
        ),
      ]);
      behaviors.add(
        InputBehavior(
          platform: platform,
          modality: CanvasInputModality.mouse,
          action: 'pan',
          description: 'Middle-button drag pans the canvas.',
          requiresPrimaryButton: false,
        ),
      );
      behaviors.add(
        InputBehavior(
          platform: platform,
          modality: CanvasInputModality.touch,
          action: 'pan',
          description: 'Two-finger drag pans without changing selection.',
        ),
      );
    }
    behaviors.add(
      const InputBehavior(
        platform: CanvasPlatform.windows,
        modality: CanvasInputModality.stylus,
        action: 'draw',
        description: 'Stylus pressure controls raster stroke width.',
        supportsPressure: true,
      ),
    );
    behaviors.add(
      const InputBehavior(
        platform: CanvasPlatform.android,
        modality: CanvasInputModality.stylus,
        action: 'draw',
        description:
            'Stylus pressure controls raster stroke width when reported by the OS.',
        supportsPressure: true,
      ),
    );
    return InputBehaviorMatrix(
      behaviors: behaviors,
      shortcuts: const [
        ShortcutBinding(command: 'select_all', key: 'A', control: true),
        ShortcutBinding(command: 'undo', key: 'Z', control: true),
        ShortcutBinding(command: 'redo', key: 'Z', control: true, shift: true),
        ShortcutBinding(command: 'copy', key: 'C', control: true),
        ShortcutBinding(command: 'paste', key: 'V', control: true),
        ShortcutBinding(command: 'duplicate', key: 'D', control: true),
        ShortcutBinding(command: 'command_palette', key: 'K', control: true),
      ],
    );
  }

  List<InputBehavior> forPlatform(CanvasPlatform platform) => behaviors
      .where((behavior) => behavior.platform == platform)
      .toList(growable: false);

  List<String> validate() {
    final errors = <String>[];
    final signatures = <String, String>{};
    for (final shortcut in shortcuts) {
      if (shortcut.command.trim().isEmpty || shortcut.key.trim().isEmpty) {
        errors.add('Shortcut command and key are required.');
        continue;
      }
      final previous = signatures[shortcut.signature];
      if (previous != null && previous != shortcut.command) {
        errors.add(
          'Shortcut ${shortcut.signature} is assigned to both $previous and ${shortcut.command}.',
        );
      }
      signatures[shortcut.signature] = shortcut.command;
    }
    return errors;
  }

  InputBehaviorMatrix remap(String command, ShortcutBinding binding) {
    final next = shortcuts
        .where((shortcut) => shortcut.command != command)
        .toList();
    next.add(binding.copyWith());
    return InputBehaviorMatrix(behaviors: behaviors, shortcuts: next);
  }
}
