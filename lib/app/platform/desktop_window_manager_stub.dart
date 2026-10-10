typedef WindowStateListener = void Function(bool maximized);

class DesktopWindowManager {
  Future<void> ensureInitialized() async {}

  Future<bool> isMaximized() async => false;

  Future<void> minimize() async {}

  Future<void> toggleMaximize() async {}

  Future<void> close() async {}

  Future<void> startDragging() async {}

  void addListener(WindowStateListener listener) {}

  void removeListener(WindowStateListener listener) {}
}

final desktopWindowManager = DesktopWindowManager();
