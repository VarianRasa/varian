import 'package:flutter/material.dart';

import '../../../domain/models/component_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';

/// Factories for small, reusable canvas building blocks.
class ReusableKits {
  const ReusableKits._();

  /// Creates a self-contained primary button component payload.
  ///
  /// Child nodes use stable source IDs. The template registry remaps those
  /// IDs whenever the kit is inserted into a document.
  static ComponentPayload primaryButton({
    String masterComponentId = 'primary_button_master',
    String label = 'Continue',
  }) {
    return ComponentPayload(
      masterComponentId: masterComponentId,
      componentName: 'Primary Button',
      description: 'Reusable primary action button',
      isMaster: true,
      properties: const [
        ComponentProperty(
          id: 'label',
          name: 'Label',
          type: ComponentPropType.text,
          defaultValue: 'Continue',
        ),
      ],
      propertyValues: {'label': label},
      templateChildren: [
        CanvasNode(
          id: 'primary_button_background',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 180,
          height: 56,
          payload: ShapePayload(fill: const Color(0xFF2563EB)),
        ),
        CanvasNode(
          id: 'primary_button_label',
          type: NodeType.text,
          name: 'label',
          x: 48,
          y: 17,
          width: 84,
          height: 22,
          payload: TextPayload(
            text: label,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  /// Alias for callers that prefer factory-style naming.
  static ComponentPayload createPrimaryButtonPayload({
    String masterComponentId = 'primary_button_master',
    String label = 'Continue',
  }) {
    return primaryButton(masterComponentId: masterComponentId, label: label);
  }
}
