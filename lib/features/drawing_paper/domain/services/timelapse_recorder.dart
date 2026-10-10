import 'dart:async';
import 'package:varian/domain/models/drawing_paper_payload.dart';

class TimelapseFrame {
  final int frameIndex;
  final int timestamp;
  final String action;
  final List<DrawingLayer> layerSnapshot;

  const TimelapseFrame({
    required this.frameIndex,
    required this.timestamp,
    required this.action,
    required this.layerSnapshot,
  });
}

class TimelapseRecorder {
  final List<TimelapseFrame> _frames = [];
  bool _isRecording = true;
  int _lastRecordTime = 0;
  static const int minFrameIntervalMs = 80;

  bool get isRecording => _isRecording;
  int get frameCount => _frames.length;
  List<TimelapseFrame> get frames => List.unmodifiable(_frames);

  void start() {
    _isRecording = true;
  }

  void pause() {
    _isRecording = false;
  }

  void clear() {
    _frames.clear();
  }

  void captureStep({
    required String action,
    required List<DrawingLayer> layers,
  }) {
    if (!_isRecording) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRecordTime < minFrameIntervalMs && _frames.isNotEmpty) {
      return;
    }
    _lastRecordTime = now;

    // Simpan snapshot layer terkompresi
    final snapshot = layers.map((l) => l.copyWith()).toList();
    _frames.add(
      TimelapseFrame(
        frameIndex: _frames.length,
        timestamp: now,
        action: action,
        layerSnapshot: snapshot,
      ),
    );
  }

  Stream<List<DrawingLayer>> playTimelapse({int intervalMs = 100}) async* {
    for (final frame in _frames) {
      await Future.delayed(Duration(milliseconds: intervalMs));
      yield frame.layerSnapshot;
    }
  }
}
