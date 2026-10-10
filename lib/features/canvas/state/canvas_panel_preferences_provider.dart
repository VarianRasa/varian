import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls which panel buttons are available in the canvas top bar.
class CanvasPanelPreferences {
  final bool showLayersButton;
  final bool showInspectorButton;
  final bool showAiStudioButton;

  const CanvasPanelPreferences({
    this.showLayersButton = true,
    this.showInspectorButton = true,
    this.showAiStudioButton = true,
  });

  CanvasPanelPreferences copyWith({
    bool? showLayersButton,
    bool? showInspectorButton,
    bool? showAiStudioButton,
  }) => CanvasPanelPreferences(
    showLayersButton: showLayersButton ?? this.showLayersButton,
    showInspectorButton: showInspectorButton ?? this.showInspectorButton,
    showAiStudioButton: showAiStudioButton ?? this.showAiStudioButton,
  );
}

final canvasPanelPreferencesProvider =
    StateNotifierProvider<
      CanvasPanelPreferencesNotifier,
      CanvasPanelPreferences
    >((ref) => CanvasPanelPreferencesNotifier());

class CanvasPanelPreferencesNotifier
    extends StateNotifier<CanvasPanelPreferences> {
  CanvasPanelPreferencesNotifier() : super(const CanvasPanelPreferences()) {
    _load();
  }

  static const _layersKey = 'canvas_show_layers_button';
  static const _inspectorKey = 'canvas_show_inspector_button';
  static const _aiStudioKey = 'canvas_show_ai_studio_button';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = state.copyWith(
        showLayersButton: prefs.getBool(_layersKey) ?? true,
        showInspectorButton: prefs.getBool(_inspectorKey) ?? true,
        showAiStudioButton: prefs.getBool(_aiStudioKey) ?? true,
      );
    } catch (error) {
      debugPrint('[CanvasPanelPreferences] Could not load preferences: $error');
    }
  }

  Future<void> setLayersButtonEnabled(bool enabled) =>
      _set(state.copyWith(showLayersButton: enabled), _layersKey, enabled);

  Future<void> setInspectorButtonEnabled(bool enabled) => _set(
    state.copyWith(showInspectorButton: enabled),
    _inspectorKey,
    enabled,
  );

  Future<void> setAiStudioButtonEnabled(bool enabled) =>
      _set(state.copyWith(showAiStudioButton: enabled), _aiStudioKey, enabled);

  Future<void> _set(CanvasPanelPreferences next, String key, bool value) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('[CanvasPanelPreferences] Could not save $key: $error');
    }
  }
}
