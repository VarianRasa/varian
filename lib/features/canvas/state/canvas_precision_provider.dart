import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/canvas_precision.dart';

final canvasPrecisionProvider =
    StateNotifierProvider.family<
      CanvasPrecisionNotifier,
      CanvasPrecisionState,
      String
    >((ref, projectId) => CanvasPrecisionNotifier(projectId));

class CanvasPrecisionNotifier extends StateNotifier<CanvasPrecisionState> {
  final String projectId;
  late final Future<void> ready;
  bool _hasLocalChange = false;

  CanvasPrecisionNotifier(this.projectId)
    : super(const CanvasPrecisionState()) {
    ready = _load();
  }

  void setGridVisible(bool value) =>
      _update(state.copyWith(gridVisible: value));

  void setRulersVisible(bool value) =>
      _update(state.copyWith(rulersVisible: value));

  void setGuidesVisible(bool value) =>
      _update(state.copyWith(guidesVisible: value));

  void setSmartGuidesEnabled(bool value) =>
      _update(state.copyWith(smartGuidesEnabled: value));

  void setMeasurementsVisible(bool value) =>
      _update(state.copyWith(measurementsVisible: value));

  void setGridPreset(CanvasGridPreset value) =>
      _update(state.copyWith(gridPreset: value));

  void setGridSpacing(double value) => _update(
    state.copyWith(gridSpacing: CanvasPrecisionMath.clampGridSpacing(value)),
  );

  void setGridSubdivisions(int value) =>
      _update(state.copyWith(gridSubdivisions: value.clamp(1, 16)));

  void setSnapMode(CanvasSnapMode value) =>
      _update(state.copyWith(snapMode: value));

  void setLayoutPreset(CanvasLayoutPreset value) =>
      _update(state.copyWith(layoutPreset: value));

  void addGuide(CanvasGuide guide) {
    if (guide.id.isEmpty || !guide.position.isFinite) return;
    _update(state.copyWith(guides: [...state.guides, guide]));
  }

  void updateGuide(CanvasGuide guide) {
    _update(
      state.copyWith(
        guides: state.guides
            .map((item) => item.id == guide.id ? guide : item)
            .toList(growable: false),
      ),
    );
  }

  void removeGuide(String guideId) {
    _update(
      state.copyWith(
        guides: state.guides
            .where((guide) => guide.id != guideId || guide.locked)
            .toList(growable: false),
      ),
    );
  }

  void _update(CanvasPrecisionState next) {
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
      state = CanvasPrecisionState.fromJson(jsonDecode(raw));
    } catch (_) {
      state = const CanvasPrecisionState();
    }
  }

  Future<void> _persist(CanvasPrecisionState value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(value.toJson()));
    } catch (_) {
      return;
    }
  }

  String get _key => 'canvas_precision_v1_$projectId';
}
