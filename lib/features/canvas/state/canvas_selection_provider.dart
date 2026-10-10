import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/canvas_selection.dart';

final canvasSelectionPreferencesProvider =
    StateNotifierProvider.family<
      CanvasSelectionPreferencesNotifier,
      CanvasSelectionPreferences,
      String
    >((ref, projectId) => CanvasSelectionPreferencesNotifier(projectId));

class CanvasSelectionPreferencesNotifier
    extends StateNotifier<CanvasSelectionPreferences> {
  final String projectId;
  late final Future<void> ready;
  bool _hasLocalChange = false;

  CanvasSelectionPreferencesNotifier(this.projectId)
    : super(const CanvasSelectionPreferences()) {
    ready = _load();
  }

  void setMode(CanvasSelectionMode mode) => _update(state.copyWith(mode: mode));

  void setShowLocked(bool value) => _update(state.copyWith(showLocked: value));

  void setShowHidden(bool value) => _update(state.copyWith(showHidden: value));

  void setIsolateNode(String? nodeId) =>
      _update(state.copyWith(isolateNodeId: nodeId));

  void clearIsolate() => setIsolateNode(null);

  void _update(CanvasSelectionPreferences next) {
    _hasLocalChange = true;
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasLocalChange) return;
      final raw = prefs.getString(_key);
      if (raw == null) return;
      state = CanvasSelectionPreferences.fromJson(jsonDecode(raw));
    } catch (_) {
      state = const CanvasSelectionPreferences();
    }
  }

  Future<void> _persist(CanvasSelectionPreferences value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(value.toJson()));
    } catch (_) {
      return;
    }
  }

  String get _key => 'canvas_selection_v1_$projectId';
}
