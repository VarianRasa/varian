import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';

void main() {
  test('prototype interaction round-trips and normalizes values', () {
    const interaction = PrototypeInteraction(
      id: '  primary  ',
      trigger: PrototypeTrigger.hover,
      action: PrototypeAction.openUrl,
      url: '  https://example.test  ',
      transition: PrototypeTransition.dissolve,
      durationMs: 20_000,
    );

    final restored = PrototypeInteraction.fromJson(interaction.toJson());

    expect(restored.id, 'primary');
    expect(restored.trigger, PrototypeTrigger.hover);
    expect(restored.action, PrototypeAction.openUrl);
    expect(restored.url, 'https://example.test');
    expect(restored.transition, PrototypeTransition.dissolve);
    expect(restored.durationMs, 10_000);
    expect(restored.isValid, isTrue);
  });

  test('CanvasNode persists prototype interactions and state', () {
    final node = CanvasNode(
      id: 'button',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 120,
      height: 48,
      prototypeStateId: 'default',
      prototypeInteractions: [
        const PrototypeInteraction(
          id: 'go-home',
          action: PrototypeAction.navigate,
          targetFrameId: 'home',
        ),
      ],
      payload: ShapePayload(),
    );

    final restored = CanvasNode.fromJson(node.toJson());

    expect(restored.prototypeStateId, 'default');
    expect(restored.prototypeInteractions, hasLength(1));
    expect(restored.prototypeInteractions.single.targetFrameId, 'home');
    expect(
      restored.prototypeInteractions.single.action,
      PrototypeAction.navigate,
    );
  });
}
