import 'package:flutter/foundation.dart';

/// Coordinates visibility of panels owned by an embedded canvas surface.
class CanvasEditorPanelController extends ChangeNotifier {
  CanvasEditorPanelController({
    bool initialShowLayers = false,
    bool initialShowInspector = true,
  }) : _showLayers = initialShowLayers,
       _showInspector = initialShowInspector;

  bool _showLayers;
  bool _showInspector;

  bool get showLayers => _showLayers;
  bool get showInspector => _showInspector;

  void toggleLayers() => setLayers(!_showLayers);

  void toggleInspector() => setInspector(!_showInspector);

  void setLayers(bool value) {
    if (_showLayers == value) return;
    _showLayers = value;
    notifyListeners();
  }

  void setInspector(bool value) {
    if (_showInspector == value) return;
    _showInspector = value;
    notifyListeners();
  }
}
