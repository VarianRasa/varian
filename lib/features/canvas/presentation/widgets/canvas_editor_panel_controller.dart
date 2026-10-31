import 'package:flutter/foundation.dart';

/// Coordinates visibility of panels owned by an embedded canvas surface.
class CanvasEditorPanelController extends ChangeNotifier {
  CanvasEditorPanelController({
    bool initialShowLayers = false,
    bool initialShowInspector = true,
    bool initialShowWorkspace = true,
  }) : _showLayers = initialShowLayers,
       _showInspector = initialShowInspector,
       _showWorkspace = initialShowWorkspace;

  bool _showLayers;
  bool _showInspector;
  bool _showWorkspace;

  bool get showLayers => _showLayers;
  bool get showInspector => _showInspector;
  bool get showWorkspace => _showWorkspace;

  void toggleLayers() => setLayers(!_showLayers);

  void toggleInspector() => setInspector(!_showInspector);

  void toggleWorkspace() => setWorkspace(!_showWorkspace);

  void setWorkspace(bool value) {
    if (_showWorkspace == value) return;
    _showWorkspace = value;
    notifyListeners();
  }

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
