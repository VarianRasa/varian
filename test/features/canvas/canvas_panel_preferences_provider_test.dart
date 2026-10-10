import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/features/canvas/state/canvas_panel_preferences_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enables all panel buttons by default', () {
    final notifier = CanvasPanelPreferencesNotifier();
    addTearDown(notifier.dispose);

    expect(notifier.state.showLayersButton, isTrue);
    expect(notifier.state.showInspectorButton, isTrue);
    expect(notifier.state.showAiStudioButton, isTrue);
  });

  test('loads saved visibility and persists updates', () async {
    SharedPreferences.setMockInitialValues({
      'canvas_show_layers_button': false,
      'canvas_show_inspector_button': true,
      'canvas_show_ai_studio_button': false,
    });
    final notifier = CanvasPanelPreferencesNotifier();
    addTearDown(notifier.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.showLayersButton, isFalse);
    expect(notifier.state.showInspectorButton, isTrue);
    expect(notifier.state.showAiStudioButton, isFalse);

    await notifier.setLayersButtonEnabled(true);
    await notifier.setInspectorButtonEnabled(false);
    await notifier.setAiStudioButtonEnabled(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('canvas_show_layers_button'), isTrue);
    expect(prefs.getBool('canvas_show_inspector_button'), isFalse);
    expect(prefs.getBool('canvas_show_ai_studio_button'), isTrue);
  });
}
