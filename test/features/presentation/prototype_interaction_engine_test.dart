import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/prototype_interaction.dart';
import 'package:varian/features/presentation/domain/prototype_interaction_engine.dart';

CanvasNode _node({
  required String id,
  required NodeType type,
  required double x,
  List<PrototypeInteraction> interactions = const [],
}) => CanvasNode(
  id: id,
  type: type,
  x: x,
  y: 0,
  width: 120,
  height: 80,
  prototypeInteractions: interactions,
  payload: type == NodeType.frame ? FramePayload(name: id) : ShapePayload(),
);

void main() {
  test('resolves enabled interaction and validates its target', () {
    final nodes = [
      _node(id: 'home', type: NodeType.frame, x: 0),
      _node(id: 'details', type: NodeType.frame, x: 300),
      _node(
        id: 'button',
        type: NodeType.rectangle,
        x: 20,
        interactions: const [
          PrototypeInteraction(
            id: 'open-details',
            action: PrototypeAction.navigate,
            targetFrameId: 'details',
            transition: PrototypeTransition.slideLeft,
            durationMs: 450,
            preserveScroll: true,
          ),
        ],
      ),
    ];

    final result = PrototypeInteractionEngine(
      nodes,
    ).resolve(nodeId: 'button', trigger: PrototypeTrigger.tap);

    expect(result.applied, isTrue);
    expect(result.action, PrototypeAction.navigate);
    expect(result.targetFrameId, 'details');
    expect(result.transition, PrototypeTransition.slideLeft);
    expect(result.durationMs, 450);
    expect(result.preserveScroll, isTrue);
  });

  test(
    'returns a diagnostic for missing targets and ignores disabled entries',
    () {
      final nodes = [
        _node(id: 'home', type: NodeType.frame, x: 0),
        _node(
          id: 'button',
          type: NodeType.rectangle,
          x: 20,
          interactions: const [
            PrototypeInteraction(
              id: 'disabled',
              enabled: false,
              targetFrameId: 'home',
            ),
            PrototypeInteraction(id: 'missing', targetFrameId: 'missing-frame'),
          ],
        ),
      ];

      final result = PrototypeInteractionEngine(
        nodes,
      ).resolve(nodeId: 'button', trigger: PrototypeTrigger.tap);

      expect(result.applied, isFalse);
      expect(result.interactionId, 'missing');
      expect(result.error, contains('does not exist'));
    },
  );

  test('supports back, state, overlay, and URL actions', () {
    final nodes = [
      _node(id: 'home', type: NodeType.frame, x: 0),
      _node(id: 'panel', type: NodeType.rectangle, x: 20),
      _node(
        id: 'back',
        type: NodeType.rectangle,
        x: 40,
        interactions: const [
          PrototypeInteraction(id: 'back-action', action: PrototypeAction.back),
        ],
      ),
      _node(
        id: 'state',
        type: NodeType.rectangle,
        x: 60,
        interactions: const [
          PrototypeInteraction(
            id: 'state-action',
            action: PrototypeAction.setState,
            stateId: 'pressed',
          ),
        ],
      ),
      _node(
        id: 'overlay',
        type: NodeType.rectangle,
        x: 80,
        interactions: const [
          PrototypeInteraction(
            id: 'overlay-action',
            action: PrototypeAction.overlay,
            targetNodeId: 'panel',
          ),
        ],
      ),
      _node(
        id: 'url',
        type: NodeType.rectangle,
        x: 100,
        interactions: const [
          PrototypeInteraction(
            id: 'url-action',
            action: PrototypeAction.openUrl,
            url: 'https://example.test',
          ),
        ],
      ),
    ];
    final engine = PrototypeInteractionEngine(nodes);

    expect(
      engine.resolve(nodeId: 'back', trigger: PrototypeTrigger.tap).goBack,
      isTrue,
    );
    expect(
      engine.resolve(nodeId: 'state', trigger: PrototypeTrigger.tap).stateId,
      'pressed',
    );
    expect(
      engine
          .resolve(nodeId: 'overlay', trigger: PrototypeTrigger.tap)
          .targetNodeId,
      'panel',
    );
    expect(
      engine.resolve(nodeId: 'url', trigger: PrototypeTrigger.tap).url,
      'https://example.test',
    );
  });
}
