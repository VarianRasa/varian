import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'design_tokens.dart';
import 'node.dart';
import 'node_payload.dart';

enum ComponentPropType { text, boolean, variant }

class ComponentProperty {
  final String id;
  final String name;
  final ComponentPropType type;
  final dynamic defaultValue;
  final List<String> options;
  final String? tokenId;

  const ComponentProperty({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultValue,
    this.options = const [],
    this.tokenId,
  });

  factory ComponentProperty.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'text';
    final propType = switch (typeStr) {
      'boolean' => ComponentPropType.boolean,
      'variant' => ComponentPropType.variant,
      _ => ComponentPropType.text,
    };

    return ComponentProperty(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: propType,
      defaultValue: json['defaultValue'],
      options:
          (json['options'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const [],
      tokenId: json['tokenId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'defaultValue': defaultValue,
    'options': options,
    if (tokenId != null) 'tokenId': tokenId,
  };

  ComponentProperty copyWith({
    String? id,
    String? name,
    ComponentPropType? type,
    Object? defaultValue = _sentinel,
    List<String>? options,
    Object? tokenId = _sentinel,
  }) {
    return ComponentProperty(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      defaultValue: defaultValue == _sentinel
          ? this.defaultValue
          : defaultValue,
      options: options ?? this.options,
      tokenId: tokenId == _sentinel ? this.tokenId : tokenId as String?,
    );
  }

  static const Object _sentinel = Object();
}

class ComponentVariant {
  final String id;
  final String name;
  final String description;
  final bool isDefault;
  final Map<String, dynamic> propertyValues;

  const ComponentVariant({
    required this.id,
    required this.name,
    this.description = '',
    this.isDefault = false,
    this.propertyValues = const {},
  });

  factory ComponentVariant.fromJson(Map<String, dynamic> json) {
    final rawValues = json['propertyValues'];
    return ComponentVariant(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Variant',
      description: json['description'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      propertyValues: rawValues is Map
          ? Map<String, dynamic>.from(rawValues)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'isDefault': isDefault,
    'propertyValues': propertyValues,
  };

  ComponentVariant copyWith({
    String? id,
    String? name,
    String? description,
    bool? isDefault,
    Map<String, dynamic>? propertyValues,
  }) => ComponentVariant(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    isDefault: isDefault ?? this.isDefault,
    propertyValues: propertyValues ?? this.propertyValues,
  );
}

class ComponentSlot {
  final String id;
  final String name;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool required;
  final List<NodeType> allowedNodeTypes;
  final List<CanvasNode> fallbackChildren;

  const ComponentSlot({
    required this.id,
    required this.name,
    this.x = 0,
    this.y = 0,
    this.width = 100,
    this.height = 40,
    this.required = false,
    this.allowedNodeTypes = const [],
    this.fallbackChildren = const [],
  });

  factory ComponentSlot.fromJson(Map<String, dynamic> json) {
    final rawTypes = json['allowedNodeTypes'];
    final allowedTypes = rawTypes is List
        ? rawTypes
              .whereType<String>()
              .map(
                (value) => NodeType.values.where((type) => type.name == value),
              )
              .expand((matches) => matches)
              .toList(growable: false)
        : const <NodeType>[];
    final rawFallback = json['fallbackChildren'];
    final fallbackChildren = rawFallback is List
        ? rawFallback
              .whereType<Map>()
              .map(
                (child) =>
                    CanvasNode.fromJson(Map<String, dynamic>.from(child)),
              )
              .toList(growable: false)
        : const <CanvasNode>[];
    return ComponentSlot(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Slot',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 100,
      height: (json['height'] as num?)?.toDouble() ?? 40,
      required: json['required'] as bool? ?? false,
      allowedNodeTypes: allowedTypes,
      fallbackChildren: fallbackChildren,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'required': required,
    'allowedNodeTypes': allowedNodeTypes.map((type) => type.name).toList(),
    'fallbackChildren': fallbackChildren
        .map((child) => child.toJson())
        .toList(),
  };

  ComponentSlot copyWith({
    String? id,
    String? name,
    double? x,
    double? y,
    double? width,
    double? height,
    bool? required,
    List<NodeType>? allowedNodeTypes,
    List<CanvasNode>? fallbackChildren,
  }) => ComponentSlot(
    id: id ?? this.id,
    name: name ?? this.name,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    required: required ?? this.required,
    allowedNodeTypes: allowedNodeTypes ?? this.allowedNodeTypes,
    fallbackChildren: fallbackChildren ?? this.fallbackChildren,
  );
}

class ComponentPayload extends NodePayload {
  final String masterComponentId;
  final String componentName;
  final String description;
  final bool isMaster;
  final Map<String, dynamic> overrides;
  final List<ComponentProperty> properties;
  final Map<String, dynamic> propertyValues;
  final List<ComponentVariant> variants;
  final String? variantId;
  final List<ComponentSlot> slots;
  final Map<String, List<CanvasNode>> slotContent;
  final Map<String, String> tokenBindings;
  final List<CanvasNode> templateChildren;
  final Color themeColor;
  final Color backgroundColor;
  final double cornerRadius;
  final double borderWidth;
  final Color borderColor;
  final bool showBadge;

  ComponentPayload({
    required this.masterComponentId,
    required this.componentName,
    this.description = '',
    this.isMaster = false,
    this.overrides = const {},
    this.properties = const [],
    this.propertyValues = const {},
    this.variants = const [],
    this.variantId,
    this.slots = const [],
    this.slotContent = const {},
    this.tokenBindings = const {},
    this.templateChildren = const [],
    this.themeColor = const Color(0xFF9333EA),
    this.backgroundColor = const Color(0xFF1E1B4B),
    this.cornerRadius = 8.0,
    this.borderWidth = 1.5,
    this.borderColor = const Color(0xFFA855F7),
    this.showBadge = true,
  });

  factory ComponentPayload.fromJson(Map<String, dynamic> json) {
    final rawProps = json['properties'];
    final parsedProps = rawProps is List
        ? rawProps
              .whereType<Map>()
              .map(
                (value) => ComponentProperty.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false)
        : const <ComponentProperty>[];
    final rawVariants = json['variants'];
    final parsedVariants = rawVariants is List
        ? rawVariants
              .whereType<Map>()
              .map(
                (value) =>
                    ComponentVariant.fromJson(Map<String, dynamic>.from(value)),
              )
              .toList(growable: false)
        : const <ComponentVariant>[];
    final rawSlots = json['slots'];
    final parsedSlots = rawSlots is List
        ? rawSlots
              .whereType<Map>()
              .map(
                (value) =>
                    ComponentSlot.fromJson(Map<String, dynamic>.from(value)),
              )
              .toList(growable: false)
        : const <ComponentSlot>[];
    final rawChildren = json['templateChildren'];
    final parsedChildren = rawChildren is List
        ? rawChildren
              .whereType<Map>()
              .map(
                (value) =>
                    CanvasNode.fromJson(Map<String, dynamic>.from(value)),
              )
              .toList(growable: false)
        : const <CanvasNode>[];
    final rawSlotContent = json['slotContent'];
    final parsedSlotContent = <String, List<CanvasNode>>{};
    if (rawSlotContent is Map) {
      for (final entry in rawSlotContent.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        parsedSlotContent[entry.key as String] = (entry.value as List)
            .whereType<Map>()
            .map(
              (value) => CanvasNode.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(growable: false);
      }
    }
    final rawPropertyValues = json['propertyValues'];
    final rawOverrides = json['overrides'];
    final rawTokenBindings = json['tokenBindings'];
    return ComponentPayload(
      masterComponentId: json['masterComponentId'] as String? ?? '',
      componentName: json['componentName'] as String? ?? 'Component',
      description: json['description'] as String? ?? '',
      isMaster: json['isMaster'] as bool? ?? false,
      overrides: rawOverrides is Map
          ? Map<String, dynamic>.from(rawOverrides)
          : const {},
      properties: parsedProps,
      propertyValues: rawPropertyValues is Map
          ? Map<String, dynamic>.from(rawPropertyValues)
          : const {},
      variants: parsedVariants,
      variantId: json['variantId'] as String?,
      slots: parsedSlots,
      slotContent: parsedSlotContent,
      tokenBindings: rawTokenBindings is Map
          ? rawTokenBindings.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
      templateChildren: parsedChildren,
      themeColor: json['themeColor'] != null
          ? Color(json['themeColor'] as int)
          : const Color(0xFF9333EA),
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : const Color(0xFF1E1B4B),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 8.0,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.5,
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : const Color(0xFFA855F7),
      showBadge: json['showBadge'] as bool? ?? true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'masterComponentId': masterComponentId,
    'componentName': componentName,
    'description': description,
    'isMaster': isMaster,
    'overrides': overrides,
    'properties': properties.map((property) => property.toJson()).toList(),
    'propertyValues': propertyValues,
    'variants': variants.map((variant) => variant.toJson()).toList(),
    if (variantId != null) 'variantId': variantId,
    'slots': slots.map((slot) => slot.toJson()).toList(),
    'slotContent': {
      for (final entry in slotContent.entries)
        entry.key: entry.value.map((child) => child.toJson()).toList(),
    },
    'tokenBindings': tokenBindings,
    'templateChildren': templateChildren
        .map((child) => child.toJson())
        .toList(),
    'themeColor': themeColor.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'cornerRadius': cornerRadius,
    'borderWidth': borderWidth,
    'borderColor': borderColor.toARGB32(),
    'showBadge': showBadge,
  };

  @override
  Map<String, dynamic> toPersistenceJson() => {
    'masterComponentId': masterComponentId,
    'componentName': componentName,
    'description': description,
    'isMaster': isMaster,
    'overrides': overrides,
    'properties': properties.map((property) => property.toJson()).toList(),
    'propertyValues': propertyValues,
    'variants': variants.map((variant) => variant.toJson()).toList(),
    if (variantId != null) 'variantId': variantId,
    'slots': slots
        .map(
          (slot) => {
            'id': slot.id,
            'name': slot.name,
            'x': slot.x,
            'y': slot.y,
            'width': slot.width,
            'height': slot.height,
            'required': slot.required,
            'allowedNodeTypes': slot.allowedNodeTypes
                .map((type) => type.name)
                .toList(),
            'fallbackChildren': slot.fallbackChildren
                .map((child) => child.toPersistenceJson())
                .toList(growable: false),
          },
        )
        .toList(growable: false),
    'slotContent': {
      for (final entry in slotContent.entries)
        entry.key: entry.value
            .map((child) => child.toPersistenceJson())
            .toList(growable: false),
    },
    'tokenBindings': tokenBindings,
    'templateChildren': templateChildren
        .map((child) => child.toPersistenceJson())
        .toList(growable: false),
    'themeColor': themeColor.toARGB32(),
    'backgroundColor': backgroundColor.toARGB32(),
    'cornerRadius': cornerRadius,
    'borderWidth': borderWidth,
    'borderColor': borderColor.toARGB32(),
    'showBadge': showBadge,
  };

  @override
  ComponentPayload clone() => copyWith(
    overrides: Map<String, dynamic>.from(overrides),
    properties: List<ComponentProperty>.from(properties),
    propertyValues: Map<String, dynamic>.from(propertyValues),
    variants: variants
        .map(
          (variant) => variant.copyWith(
            propertyValues: Map<String, dynamic>.from(variant.propertyValues),
          ),
        )
        .toList(growable: false),
    slots: slots
        .map(
          (slot) => slot.copyWith(
            allowedNodeTypes: List<NodeType>.from(slot.allowedNodeTypes),
            fallbackChildren: slot.fallbackChildren
                .map(_cloneNodeTree)
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
    slotContent: {
      for (final entry in slotContent.entries)
        entry.key: entry.value.map(_cloneNodeTree).toList(growable: false),
    },
    tokenBindings: Map<String, String>.from(tokenBindings),
    templateChildren: templateChildren
        .map(_cloneNodeTree)
        .toList(growable: false),
  );

  ComponentPayload copyWith({
    String? masterComponentId,
    String? componentName,
    String? description,
    bool? isMaster,
    Map<String, dynamic>? overrides,
    List<ComponentProperty>? properties,
    Map<String, dynamic>? propertyValues,
    List<ComponentVariant>? variants,
    Object? variantId = _sentinel,
    List<ComponentSlot>? slots,
    Map<String, List<CanvasNode>>? slotContent,
    Map<String, String>? tokenBindings,
    List<CanvasNode>? templateChildren,
    Color? themeColor,
    Color? backgroundColor,
    double? cornerRadius,
    double? borderWidth,
    Color? borderColor,
    bool? showBadge,
  }) => ComponentPayload(
    masterComponentId: masterComponentId ?? this.masterComponentId,
    componentName: componentName ?? this.componentName,
    description: description ?? this.description,
    isMaster: isMaster ?? this.isMaster,
    overrides: overrides ?? this.overrides,
    properties: properties ?? this.properties,
    propertyValues: propertyValues ?? this.propertyValues,
    variants: variants ?? this.variants,
    variantId: variantId == _sentinel ? this.variantId : variantId as String?,
    slots: slots ?? this.slots,
    slotContent: slotContent ?? this.slotContent,
    tokenBindings: tokenBindings ?? this.tokenBindings,
    templateChildren: templateChildren ?? this.templateChildren,
    themeColor: themeColor ?? this.themeColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    borderWidth: borderWidth ?? this.borderWidth,
    borderColor: borderColor ?? this.borderColor,
    showBadge: showBadge ?? this.showBadge,
  );

  ComponentProperty? property(String propertyIdOrName) {
    final normalized = propertyIdOrName.trim().toLowerCase();
    return properties
        .where(
          (candidate) =>
              candidate.id.toLowerCase() == normalized ||
              candidate.name.toLowerCase() == normalized,
        )
        .firstOrNull;
  }

  Object? resolvedPropertyValue(
    String propertyIdOrName, {
    DesignTokenSet? designTokens,
    String? mode,
  }) {
    final definition = property(propertyIdOrName);
    if (definition == null) return null;

    final override = _readValue(overrides, definition);
    if (override.present) return _coerceValue(definition, override.value);

    final activeVariant = resolveVariant();
    if (activeVariant != null) {
      final variantValue = _readValue(activeVariant.propertyValues, definition);
      if (variantValue.present) {
        return _coerceValue(definition, variantValue.value);
      }
    }

    final tokenId =
        tokenBindings[definition.id] ??
        tokenBindings[definition.name] ??
        definition.tokenId;
    if (designTokens != null && tokenId != null) {
      final tokenValue = designTokens.resolve(tokenId, mode);
      if (tokenValue != null) return _coerceValue(definition, tokenValue);
    }

    final baseValue = _readValue(propertyValues, definition);
    return _coerceValue(
      definition,
      baseValue.present ? baseValue.value : definition.defaultValue,
    );
  }

  Map<String, dynamic> resolvedPropertyValues({
    DesignTokenSet? designTokens,
    String? mode,
  }) => {
    for (final definition in properties)
      definition.id: resolvedPropertyValue(
        definition.id,
        designTokens: designTokens,
        mode: mode,
      ),
  };

  Object? resolvedTargetValue(
    String target, {
    DesignTokenSet? designTokens,
    String? mode,
  }) {
    final definition = property(target);
    if (definition != null) {
      return resolvedPropertyValue(
        definition.id,
        designTokens: designTokens,
        mode: mode,
      );
    }
    if (overrides.containsKey(target)) return overrides[target];
    final activeVariant = resolveVariant();
    if (activeVariant?.propertyValues.containsKey(target) ?? false) {
      return activeVariant!.propertyValues[target];
    }
    final tokenId = tokenBindings[target];
    if (designTokens != null && tokenId != null) {
      return designTokens.resolve(tokenId, mode);
    }
    return propertyValues[target];
  }

  ComponentVariant? resolveVariant() {
    if (variants.isEmpty) return null;
    final selectedId = variantId ?? _storedVariantSelection();
    if (selectedId != null && selectedId.isNotEmpty) {
      final selected = variants
          .where(
            (variant) => variant.id == selectedId || variant.name == selectedId,
          )
          .firstOrNull;
      if (selected != null) return selected;
    }
    return variants.where((variant) => variant.isDefault).firstOrNull ??
        variants.first;
  }

  List<CanvasNode> resolvedSlotChildren(String slotId) {
    final content = slotContent[slotId];
    if (content != null) return content;
    return slots
            .where((slot) => slot.id == slotId)
            .firstOrNull
            ?.fallbackChildren ??
        const [];
  }

  String? tokenFor(String target) => tokenBindings[target];

  static ({bool present, Object? value}) _readValue(
    Map<String, dynamic> values,
    ComponentProperty definition,
  ) {
    if (values.containsKey(definition.id)) {
      return (present: true, value: values[definition.id]);
    }
    if (values.containsKey(definition.name)) {
      return (present: true, value: values[definition.name]);
    }
    return (present: false, value: null);
  }

  String? _storedVariantSelection() {
    final definition = properties
        .where(
          (property) =>
              property.type == ComponentPropType.variant &&
              (property.id.toLowerCase() == 'variant' ||
                  property.name.toLowerCase() == 'variant'),
        )
        .firstOrNull;
    if (definition == null) return null;
    final override = _readValue(overrides, definition);
    if (override.present) return override.value?.toString();
    final value = _readValue(propertyValues, definition);
    if (value.present) return value.value?.toString();
    return definition.defaultValue?.toString();
  }

  static Object? _coerceValue(ComponentProperty definition, Object? value) {
    if (value == null) return null;
    switch (definition.type) {
      case ComponentPropType.boolean:
        if (value is bool) return value;
        if (value is String) {
          if (value.toLowerCase() == 'true') return true;
          if (value.toLowerCase() == 'false') return false;
        }
        return definition.defaultValue is bool
            ? definition.defaultValue
            : value;
      case ComponentPropType.variant:
        final stringValue = value.toString();
        return definition.options.isEmpty ||
                definition.options.contains(stringValue)
            ? stringValue
            : definition.defaultValue;
      case ComponentPropType.text:
        return value.toString();
    }
  }

  static CanvasNode _cloneNodeTree(CanvasNode node) {
    final payload = node.payload;
    final clonedPayload = payload is ComponentPayload
        ? payload.clone()
        : payload.clone();
    return node.copyWith(payload: clonedPayload);
  }

  static const Object _sentinel = Object();
}

class ComponentInstanceFactory {
  const ComponentInstanceFactory._();

  static CanvasNode createInstance(
    CanvasNode master, {
    required Offset origin,
    String? instanceId,
    String Function()? idFactory,
  }) {
    final payload = master.payload;
    if (master.type != NodeType.component || payload is! ComponentPayload) {
      throw ArgumentError.value(master, 'master', 'Node is not a component');
    }
    final makeId = idFactory ?? () => const Uuid().v4();
    final childIds = <String, String>{};
    for (final child in payload.templateChildren) {
      _reserveChildIds(child, childIds, makeId);
    }
    for (final slot in payload.slots) {
      for (final child in slot.fallbackChildren) {
        _reserveChildIds(child, childIds, makeId);
      }
    }
    final nextPayload = payload.copyWith(
      isMaster: false,
      overrides: const {},
      propertyValues: {
        for (final property in payload.properties)
          property.id: payload.resolvedPropertyValue(property.id),
      },
      slotContent: const {},
      templateChildren: payload.templateChildren
          .map((child) => _remapChild(child, childIds))
          .toList(growable: false),
      slots: payload.slots
          .map(
            (slot) => slot.copyWith(
              fallbackChildren: slot.fallbackChildren
                  .map((child) => _remapChild(child, childIds))
                  .toList(growable: false),
            ),
          )
          .toList(growable: false),
    );
    return master.copyWith(
      id: instanceId ?? makeId(),
      x: origin.dx,
      y: origin.dy,
      payload: nextPayload,
    );
  }

  static Object? resolvedValue(
    ComponentPayload payload,
    String propertyId, {
    DesignTokenSet? designTokens,
    String? mode,
  }) => payload.resolvedPropertyValue(
    propertyId,
    designTokens: designTokens,
    mode: mode,
  );

  static ComponentPayload setPropertyValue(
    ComponentPayload payload,
    String propertyIdOrName,
    Object? value,
  ) {
    final property = payload.property(propertyIdOrName);
    if (property == null) {
      throw ArgumentError.value(propertyIdOrName, 'propertyIdOrName');
    }
    final values = Map<String, dynamic>.from(payload.propertyValues)
      ..remove(property.name)
      ..[property.id] = value;
    return payload.copyWith(propertyValues: values);
  }

  static ComponentPayload setOverride(
    ComponentPayload payload,
    String propertyIdOrName,
    Object? value,
  ) {
    final property = payload.property(propertyIdOrName);
    if (property == null) {
      throw ArgumentError.value(propertyIdOrName, 'propertyIdOrName');
    }
    final overrides = Map<String, dynamic>.from(payload.overrides)
      ..remove(property.name)
      ..[property.id] = value;
    return payload.copyWith(overrides: overrides);
  }

  static ComponentPayload resetOverride(
    ComponentPayload payload,
    String propertyIdOrName,
  ) {
    final property = payload.property(propertyIdOrName);
    if (property == null) {
      throw ArgumentError.value(propertyIdOrName, 'propertyIdOrName');
    }
    final overrides = Map<String, dynamic>.from(payload.overrides)
      ..remove(property.id)
      ..remove(property.name);
    return payload.copyWith(overrides: overrides);
  }

  static ComponentPayload setVariant(
    ComponentPayload payload,
    String? variantId,
  ) => payload.copyWith(variantId: variantId);

  static ComponentPayload setTokenBinding(
    ComponentPayload payload,
    String target,
    String? tokenId,
  ) {
    final property = payload.property(target);
    final canonicalTarget = property?.id ?? target;
    final bindings = Map<String, String>.from(payload.tokenBindings);
    if (tokenId == null || tokenId.trim().isEmpty) {
      bindings.remove(canonicalTarget);
    } else {
      bindings[canonicalTarget] = tokenId.trim();
    }
    return payload.copyWith(tokenBindings: bindings);
  }

  static ComponentPayload setSlotContent(
    ComponentPayload payload,
    String slotId,
    Iterable<CanvasNode> content,
  ) {
    final slot = payload.slots
        .where((candidate) => candidate.id == slotId)
        .firstOrNull;
    if (slot == null) throw ArgumentError.value(slotId, 'slotId');
    final nodes = content.toList(growable: false);
    if (slot.allowedNodeTypes.isNotEmpty &&
        nodes.any((node) => !slot.allowedNodeTypes.contains(node.type))) {
      throw ArgumentError.value(
        content,
        'content',
        'Slot contains a disallowed node type',
      );
    }
    return payload.copyWith(
      slotContent: {
        ...payload.slotContent,
        slotId: nodes
            .map(ComponentPayload._cloneNodeTree)
            .toList(growable: false),
      },
    );
  }

  static ComponentPayload clearSlotContent(
    ComponentPayload payload,
    String slotId,
  ) {
    if (!payload.slots.any((slot) => slot.id == slotId)) {
      throw ArgumentError.value(slotId, 'slotId');
    }
    final content = Map<String, List<CanvasNode>>.from(payload.slotContent)
      ..remove(slotId);
    return payload.copyWith(slotContent: content);
  }

  static void _reserveChildIds(
    CanvasNode child,
    Map<String, String> childIds,
    String Function() makeId,
  ) {
    childIds.putIfAbsent(child.id, makeId);
    final payload = child.payload;
    if (payload is ComponentPayload) {
      for (final nested in payload.templateChildren) {
        _reserveChildIds(nested, childIds, makeId);
      }
      for (final slot in payload.slots) {
        for (final nested in slot.fallbackChildren) {
          _reserveChildIds(nested, childIds, makeId);
        }
      }
    }
  }

  static CanvasNode _remapChild(
    CanvasNode child,
    Map<String, String> childIds,
  ) {
    final childPayload = child.payload;
    final remappedPayload = childPayload is ComponentPayload
        ? childPayload.copyWith(
            templateChildren: childPayload.templateChildren
                .map((nested) => _remapChild(nested, childIds))
                .toList(growable: false),
            slots: childPayload.slots
                .map(
                  (slot) => slot.copyWith(
                    fallbackChildren: slot.fallbackChildren
                        .map((nested) => _remapChild(nested, childIds))
                        .toList(growable: false),
                  ),
                )
                .toList(growable: false),
          )
        : childPayload.clone();
    return child.copyWith(
      id: childIds[child.id] ?? child.id,
      parentId: child.parentId == null
          ? null
          : childIds[child.parentId!] ?? child.parentId,
      payload: remappedPayload,
    );
  }
}
