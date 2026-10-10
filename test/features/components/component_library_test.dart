import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/components/domain/component_library.dart';

CanvasNode _master() => CanvasNode(
  id: 'master-node',
  type: NodeType.component,
  x: 0,
  y: 0,
  width: 180,
  height: 56,
  payload: ComponentPayload(
    masterComponentId: 'button',
    componentName: 'Primary button',
    description: 'Primary action',
    isMaster: true,
    properties: const [
      ComponentProperty(
        id: 'label',
        name: 'Label',
        type: ComponentPropType.text,
        defaultValue: 'Continue',
      ),
    ],
    propertyValues: const {'label': 'Continue'},
    templateChildren: [
      CanvasNode(
        id: 'child',
        type: NodeType.text,
        x: 10,
        y: 10,
        width: 80,
        height: 20,
        payload: TextPayload(text: 'Continue'),
      ),
    ],
  ),
);

void main() {
  test('discovers searchable publishable component entries', () {
    final library = ComponentLibrary.discover([_master()]);
    expect(library.entries['button']?.name, 'Primary button');
    expect(library.search('primary'), hasLength(1));
    expect(library.search('missing'), isEmpty);
  });

  test('merges discovered nodes without losing publish state', () {
    final discovered = ComponentLibrary.discover([_master()]);
    final published = discovered.setPublished('button', true);
    final refreshed = published.merge(
      ComponentLibrary.discover([_master().copyWith(x: 240)]),
    );

    expect(refreshed.entries['button']?.published, isTrue);
    expect(refreshed.entries['button']?.sourceNodeId, 'master-node');
  });

  test('creates isolated instances and supports override reset', () {
    final master = _master();
    final instance = ComponentInstanceFactory.createInstance(
      master,
      origin: const Offset(100, 120),
      instanceId: 'instance',
      idFactory: () {
        var index = 0;
        return () => 'child-${index++}';
      }(),
    );
    final payload = instance.payload as ComponentPayload;
    expect(instance.id, 'instance');
    expect(instance.x, 100);
    expect(instance.y, 120);
    expect(payload.isMaster, isFalse);
    expect(payload.overrides, isEmpty);
    expect(payload.templateChildren.single.id, 'child-0');

    final overridden = ComponentInstanceFactory.setOverride(
      payload,
      'label',
      'Buy now',
    );
    expect(
      ComponentInstanceFactory.resolvedValue(overridden, 'label'),
      'Buy now',
    );
    final reset = ComponentInstanceFactory.resetOverride(overridden, 'label');
    expect(ComponentInstanceFactory.resolvedValue(reset, 'label'), 'Continue');
  });
}
