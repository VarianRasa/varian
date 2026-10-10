import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/design_tokens.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/components/domain/component_library.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

CanvasNode _textNode(String id, {String text = 'Fallback'}) => CanvasNode(
  id: id,
  type: NodeType.text,
  x: 4,
  y: 4,
  width: 120,
  height: 24,
  payload: TextPayload(text: text),
);

ComponentPayload _payload() => ComponentPayload(
  masterComponentId: 'button',
  componentName: 'Button',
  isMaster: true,
  properties: const [
    ComponentProperty(
      id: 'label',
      name: 'Label',
      type: ComponentPropType.text,
      defaultValue: 'Continue',
    ),
    ComponentProperty(
      id: 'variant',
      name: 'Variant',
      type: ComponentPropType.variant,
      defaultValue: 'Primary',
      options: ['Primary', 'Secondary'],
    ),
  ],
  propertyValues: const {'label': 'Continue', 'variant': 'Primary'},
  variants: const [
    ComponentVariant(
      id: 'primary',
      name: 'Primary',
      isDefault: true,
      propertyValues: {'variant': 'Primary'},
    ),
    ComponentVariant(
      id: 'secondary',
      name: 'Secondary',
      propertyValues: {'variant': 'Secondary'},
    ),
  ],
  slots: [
    ComponentSlot(
      id: 'body',
      name: 'Body',
      width: 160,
      height: 40,
      allowedNodeTypes: [NodeType.text],
      fallbackChildren: [_textNode('fallback')],
    ),
  ],
  templateChildren: [_textNode('label-layer', text: 'Continue')],
  tokenBindings: const {'label': 'content.label'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('J4 component contracts', () {
    test('round trips variants, slots, token bindings, and children', () {
      final original = _payload();
      final restored = ComponentPayload.fromJson(original.toJson());

      expect(restored.variants.map((variant) => variant.id), [
        'primary',
        'secondary',
      ]);
      expect(restored.slots.single.id, 'body');
      expect(restored.slots.single.fallbackChildren.single.id, 'fallback');
      expect(restored.tokenBindings['label'], 'content.label');
      expect(restored.templateChildren.single.id, 'label-layer');
    });

    test('resolves legacy names, variants, tokens, and instance overrides', () {
      final tokenSet = DesignTokenSet(
        entries: {
          'content.label': DesignToken(
            id: 'content.label',
            name: 'Content label',
            type: DesignTokenType.string,
            value: 'From token',
            updatedAt: DateTime.utc(2026, 9, 13),
          ),
        },
      );
      final payload = _payload().copyWith(variants: const []);
      expect(
        payload.resolvedPropertyValue('label', designTokens: tokenSet),
        'From token',
      );

      final variantPayload = _payload().copyWith(variantId: 'secondary');
      expect(variantPayload.resolvedPropertyValue('variant'), 'Secondary');

      final overridden = ComponentInstanceFactory.setOverride(
        variantPayload,
        'Label',
        'Instance label',
      );
      expect(
        ComponentInstanceFactory.resolvedValue(overridden, 'label'),
        'Instance label',
      );
      expect(overridden.overrides.keys, ['label']);

      final reset = ComponentInstanceFactory.resetOverride(overridden, 'Label');
      expect(reset.overrides, isEmpty);
      expect(reset.resolvedPropertyValue('label'), 'Continue');
    });

    test('validates slot content and supports explicit fallback reset', () {
      final payload = _payload();
      final content = ComponentInstanceFactory.setSlotContent(payload, 'body', [
        _textNode('content'),
      ]);
      expect(content.resolvedSlotChildren('body').single.id, 'content');

      final cleared = ComponentInstanceFactory.clearSlotContent(
        content,
        'body',
      );
      expect(cleared.slotContent, isEmpty);
      expect(cleared.resolvedSlotChildren('body').single.id, 'fallback');

      expect(
        () => ComponentInstanceFactory.setSlotContent(payload, 'body', [
          CanvasNode(
            id: 'bad',
            type: NodeType.rectangle,
            x: 0,
            y: 0,
            width: 20,
            height: 20,
            payload: ShapePayload(),
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('creates isolated instance trees and preserves variant metadata', () {
      final master = CanvasNode(
        id: 'master-node',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 180,
        height: 80,
        payload: _payload(),
      );
      var sequence = 0;
      final instance = ComponentInstanceFactory.createInstance(
        master,
        origin: const Offset(200, 120),
        instanceId: 'instance',
        idFactory: () => 'generated-${sequence++}',
      );
      final payload = instance.payload as ComponentPayload;

      expect(instance.x, 200);
      expect(instance.y, 120);
      expect(payload.isMaster, isFalse);
      expect(payload.variants.length, 2);
      expect(payload.templateChildren.single.id, 'generated-0');
      expect(payload.slots.single.fallbackChildren.single.id, 'generated-1');
      expect(payload.propertyValues['label'], 'Continue');
    });

    test('pins entries and finds nested instance usages', () {
      final master = CanvasNode(
        id: 'master-node',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 180,
        height: 80,
        payload: _payload(),
      );
      final instance = ComponentInstanceFactory.createInstance(
        master,
        origin: const Offset(10, 10),
        instanceId: 'instance',
      );
      final library = ComponentLibrary.discover([master, instance]);
      final pinned = library.setPinned('button', true);

      expect(pinned.entries['button']?.pinned, isTrue);
      expect(pinned.pinnedEntries.single.id, 'button');
      expect(ComponentLibrary.usageCount([master, instance], 'button'), 1);
      expect(
        ComponentLibrary.usageCount(
          [master, instance],
          'button',
          includeMaster: true,
        ),
        2,
      );
    });

    test('renders token-bound component and slot content without errors', () {
      final tokenSet = DesignTokenSet(
        entries: {
          'surface.button': DesignToken(
            id: 'surface.button',
            name: 'Button surface',
            type: DesignTokenType.color,
            value: 0xFF0F766E,
            updatedAt: DateTime.utc(2026, 9, 13),
          ),
        },
      );
      final payload = _payload().copyWith(
        tokenBindings: const {'backgroundColor': 'surface.button'},
        slotContent: {
          'body': [_textNode('slot-content', text: 'Injected')],
        },
      );
      final node = CanvasNode(
        id: 'render-node',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 180,
        height: 100,
        payload: payload,
      );
      final recorder = ui.PictureRecorder();
      expect(
        () => NodePainter.paint(
          ui.Canvas(recorder),
          node,
          designTokens: tokenSet,
        ),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });
  });
}
