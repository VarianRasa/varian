import 'package:window_manager/window_manager.dart';

typedef WindowStateListener = void Function(bool maximized);

class DesktopWindowManager {
  final _listeners = <WindowStateListener, _WindowListenerAdapter>{};

  Future<void> ensureInitialized() => windowManager.ensureInitialized();

  Future<bool> isMaximized() => windowManager.isMaximized();

  Future<void> minimize() => windowManager.minimize();

  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> close() => windowManager.close();

  Future<void> startDragging() => windowManager.startDragging();

  void addListener(WindowStateListener listener) {
    if (_listeners.containsKey(listener)) return;
    final adapter = _WindowListenerAdapter(listener);
    _listeners[listener] = adapter;
    windowManager.addListener(adapter);
  }

  void removeListener(WindowStateListener listener) {
    final adapter = _listeners.remove(listener);
    if (adapter != null) windowManager.removeListener(adapter);
  }
}

class _WindowListenerAdapter with WindowListener {
  final WindowStateListener onStateChanged;

  _WindowListenerAdapter(this.onStateChanged);

  @override
  void onWindowMaximize() => onStateChanged(true);

  @override
  void onWindowUnmaximize() => onStateChanged(false);
}

final desktopWindowManager = DesktopWindowManager();
