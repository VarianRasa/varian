import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme.dart';
import '../../../../app/responsive.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../../../domain/models/component_payload.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';

class ComponentEditorModal extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onUpdate;

  const ComponentEditorModal({
    super.key,
    required this.node,
    required this.onUpdate,
  });

  static Future<void> show(
    BuildContext context, {
    required CanvasNode node,
    required ValueChanged<CanvasNode> onUpdate,
  }) {
    return showUiDialog<void>(
      context: context,
      builder: (context) =>
          ComponentEditorModal(node: node, onUpdate: onUpdate),
    );
  }

  @override
  State<ComponentEditorModal> createState() => _ComponentEditorModalState();
}

class _ComponentEditorModalState extends State<ComponentEditorModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late ComponentPayload _payload;
  late List<ComponentProperty> _properties;
  late Map<String, dynamic> _propertyValues;
  late List<CanvasNode> _templateChildren;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _payload = widget.node.payload is ComponentPayload
        ? (widget.node.payload as ComponentPayload).clone()
        : ComponentPayload(
            masterComponentId: widget.node.id,
            componentName: widget.node.name ?? 'New Component',
            isMaster: true,
          );
    _nameController = TextEditingController(text: _payload.componentName);
    _descController = TextEditingController(text: _payload.description);
    _properties = List<ComponentProperty>.from(_payload.properties);
    _propertyValues = {
      for (final property in _properties)
        property.id:
            _payload.propertyValues[property.id] ??
            _payload.propertyValues[property.name] ??
            property.defaultValue,
    };
    _templateChildren = List<CanvasNode>.from(_payload.templateChildren);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _syncChanges() {
    final updatedPayload = _payload.copyWith(
      componentName: _nameController.text.trim().isEmpty
          ? 'Component'
          : _nameController.text.trim(),
      description: _descController.text.trim(),
      properties: _properties,
      propertyValues: _propertyValues,
      templateChildren: _templateChildren,
    );
    _payload = updatedPayload;
    final updatedNode = widget.node.copyWith(
      name: updatedPayload.componentName,
      payload: updatedPayload,
    );
    widget.onUpdate(updatedNode);
  }

  dynamic _currentPropertyValue(ComponentProperty property) {
    if (!_payload.isMaster && _payload.overrides.containsKey(property.id)) {
      return _payload.overrides[property.id];
    }
    return _payload.resolvedPropertyValue(property.id) ??
        _propertyValues[property.id] ??
        property.defaultValue;
  }

  void _setPropertyValue(ComponentProperty property, Object? value) {
    setState(() {
      _propertyValues[property.id] = value;
      _payload = _payload.isMaster
          ? ComponentInstanceFactory.setPropertyValue(
              _payload,
              property.id,
              value,
            )
          : ComponentInstanceFactory.setOverride(_payload, property.id, value);
    });
    _syncChanges();
  }

  void _addPropertyDialog() {
    final nameCtrl = TextEditingController();
    ComponentPropType selectedType = ComponentPropType.text;
    final optionsCtrl = TextEditingController(
      text: 'Primary, Secondary, Danger, Ghost',
    );

    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => UiDialog(
          semanticsLabel: 'Add component property',
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 420,
            maxHeight: 520,
          ),
          builder: (context, style) => SizedBox(
            width: AppResponsive.dialogWidth(context, preferred: 420),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: AppResponsive.dialogHeight(context, preferred: 520),
              ),
              child: Padding(
                padding: AppResponsive.dialogPadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add Component Property (Figma Prop)',
                      style: style.titleTextStyle,
                    ),
                    const SizedBox(height: AppSpacing.lg - AppSpacing.xxs),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            UiTextField(
                              controller: nameCtrl,
                              autofocus: true,
                              label: 'Property Name',
                              hint: 'label, hasIcon, variant',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            UiSelect<ComponentPropType>(
                              items: const {
                                'Text Prop': ComponentPropType.text,
                                'Boolean Switch': ComponentPropType.boolean,
                                'Variant Options': ComponentPropType.variant,
                              },
                              value: selectedType,
                              label: 'Type',
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => selectedType = value);
                                }
                              },
                            ),
                            if (selectedType == ComponentPropType.variant) ...[
                              const SizedBox(
                                height: AppSpacing.md - AppSpacing.xxs,
                              ),
                              UiTextField(
                                controller: optionsCtrl,
                                label: 'Options',
                                hint: 'Primary, Secondary, Danger, Ghost',
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        UiButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          variant: UiButtonVariant.ghost,
                          child: const Text('Cancel'),
                        ),
                        UiButton(
                          onPressed: () {
                            final propName = nameCtrl.text.trim();
                            if (propName.isEmpty) return;
                            final newPropId = const Uuid().v4().substring(0, 6);
                            dynamic defaultVal;
                            List<String> options = [];

                            if (selectedType == ComponentPropType.boolean) {
                              defaultVal = true;
                            } else if (selectedType ==
                                ComponentPropType.variant) {
                              options = optionsCtrl.text
                                  .split(',')
                                  .map((value) => value.trim())
                                  .where((value) => value.isNotEmpty)
                                  .toList();
                              defaultVal = options.isNotEmpty
                                  ? options.first
                                  : 'Default';
                            } else {
                              defaultVal = 'Button Label';
                            }

                            final newProp = ComponentProperty(
                              id: newPropId,
                              name: propName,
                              type: selectedType,
                              defaultValue: defaultVal,
                              options: options,
                            );

                            setState(() {
                              _properties.add(newProp);
                              _propertyValues[newProp.id] = defaultVal;
                              _payload = _payload.copyWith(
                                properties: _properties,
                                propertyValues: _propertyValues,
                              );
                            });
                            _syncChanges();
                            Navigator.pop(dialogContext);
                          },
                          variant: UiButtonVariant.primary,
                          child: const Text('Add Property'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addTemplateChild(NodeType type) {
    final count = _templateChildren.length;
    final childId = const Uuid().v4().substring(0, 6);
    CanvasNode childNode;

    switch (type) {
      case NodeType.text:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Text Label',
          x: 16,
          y: 12 + (count * 18).toDouble(),
          width: (widget.node.width - 32).clamp(40.0, 400.0),
          height: 28,
          payload: TextPayload(
            text: 'Component Title',
            color: Colors.white,
            fontSize: 13,
          ),
        );
        break;
      case NodeType.rectangle:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Box Background',
          x: 0,
          y: 0,
          width: widget.node.width,
          height: widget.node.height,
          payload: ShapePayload(
            fill: const Color(0xFF4F46E5),
            stroke: const Color(0xFF818CF8),
            strokeWidth: 1.5,
            cornerRadius: 6.0,
          ),
        );
        break;
      case NodeType.ellipse:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Circle Badge / Icon',
          x: 12,
          y: 12,
          width: 32,
          height: 32,
          payload: ShapePayload(
            fill: const Color(0xFFA855F7),
            stroke: Colors.white,
            strokeWidth: 1.5,
          ),
        );
        break;
      case NodeType.diamond:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Decision Indicator',
          x: 14,
          y: 14,
          width: 36,
          height: 36,
          payload: ShapePayload(
            fill: const Color(0xFFEAB308),
            stroke: Colors.white,
            strokeWidth: 1.5,
          ),
        );
        break;
      case NodeType.cylinder:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Database Container',
          x: 10,
          y: 10,
          width: 50,
          height: 50,
          payload: ShapePayload(
            fill: const Color(0xFF0EA5E9),
            stroke: const Color(0xFF7DD3FC),
            strokeWidth: 1.5,
          ),
        );
        break;
      case NodeType.parallelogram:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Data IO Shape',
          x: 10,
          y: 10,
          width: 60,
          height: 35,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF6EE7B7),
            strokeWidth: 1.5,
          ),
        );
        break;
      case NodeType.frame:
        childNode = CanvasNode(
          id: childId,
          type: type,
          name: 'Inner Auto-Layout Frame',
          x: 4,
          y: 4,
          width: widget.node.width - 8,
          height: widget.node.height - 8,
          payload: FramePayload(
            name: 'Frame Container',
            background: const Color(0xFF1E293B),
            borderColor: const Color(0xFF6366F1),
            borderWidth: 1.0,
            cornerRadius: 4.0,
          ),
        );
        break;
      default:
        childNode = CanvasNode(
          id: childId,
          type: NodeType.rectangle,
          name: 'Layer #${count + 1}',
          x: 10,
          y: 10,
          width: 80,
          height: 40,
          payload: ShapePayload(fill: const Color(0xFF334155)),
        );
    }

    setState(() {
      _templateChildren.add(childNode);
    });
    _syncChanges();
  }

  void _showAddLayerMenu(BuildContext context, Offset globalPos) {
    showUiDialog<NodeType>(
      context: context,
      builder: (dialogContext) => UiDialog(
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 420,
          maxHeight: 500,
        ),
        builder: (context, style) => SizedBox(
          width: AppResponsive.dialogWidth(context, preferred: 420),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppResponsive.dialogHeight(context, preferred: 500),
            ),
            child: Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Shape Layer', style: style.titleTextStyle),
                  const SizedBox(height: AppSpacing.sm),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry
                              in const <(NodeType, IconData, String)>[
                                (
                                  NodeType.rectangle,
                                  Icons.crop_square,
                                  'Rectangle (R)',
                                ),
                                (
                                  NodeType.ellipse,
                                  Icons.circle_outlined,
                                  'Ellipse (O)',
                                ),
                                (
                                  NodeType.diamond,
                                  Icons.change_history,
                                  'Diamond (Decision)',
                                ),
                                (
                                  NodeType.cylinder,
                                  Icons.storage_outlined,
                                  'Cylinder (Database)',
                                ),
                                (
                                  NodeType.parallelogram,
                                  Icons.view_sidebar_outlined,
                                  'Data / IO',
                                ),
                                (NodeType.text, Icons.title, 'Text Layer (T)'),
                                (
                                  NodeType.frame,
                                  Icons.crop_free,
                                  'Frame Container (F)',
                                ),
                              ])
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: UiButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  _addTemplateChild(entry.$1);
                                },
                                variant: UiButtonVariant.outline,
                                prefix: Icon(entry.$2, size: 16),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(entry.$3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _editLayerDialog(int index) {
    final layer = _templateChildren[index];
    final nameCtrl = TextEditingController(text: layer.name);
    final xCtrl = TextEditingController(text: layer.x.toStringAsFixed(0));
    final yCtrl = TextEditingController(text: layer.y.toStringAsFixed(0));
    final wCtrl = TextEditingController(text: layer.width.toStringAsFixed(0));
    final hCtrl = TextEditingController(text: layer.height.toStringAsFixed(0));
    final textCtrl = TextEditingController(
      text: layer.payload is TextPayload
          ? (layer.payload as TextPayload).text
          : '',
    );

    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 520,
          maxHeight: 560,
        ),
        builder: (context, style) => SizedBox(
          width: AppResponsive.dialogWidth(context, preferred: 520),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppResponsive.dialogHeight(context, preferred: 560),
            ),
            child: Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit Layer: ${layer.name}',
                    style: style.titleTextStyle,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Flexible(
                    child: SingleChildScrollView(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 440;
                          final coordinates = compact
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    UiTextField(
                                      controller: xCtrl,
                                      label: 'X Pos',
                                      keyboardType: TextInputType.number,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    UiTextField(
                                      controller: yCtrl,
                                      label: 'Y Pos',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: UiTextField(
                                        controller: xCtrl,
                                        label: 'X Pos',
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: UiTextField(
                                        controller: yCtrl,
                                        label: 'Y Pos',
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                );
                          final dimensions = compact
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    UiTextField(
                                      controller: wCtrl,
                                      label: 'Width',
                                      keyboardType: TextInputType.number,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    UiTextField(
                                      controller: hCtrl,
                                      label: 'Height',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: UiTextField(
                                        controller: wCtrl,
                                        label: 'Width',
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: UiTextField(
                                        controller: hCtrl,
                                        label: 'Height',
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ],
                                );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              UiTextField(
                                controller: nameCtrl,
                                label: 'Layer Name',
                              ),
                              if (layer.payload is TextPayload) ...[
                                const SizedBox(height: AppSpacing.sm),
                                UiTextField(
                                  controller: textCtrl,
                                  label: 'Text Content',
                                ),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              coordinates,
                              const SizedBox(height: AppSpacing.sm),
                              dimensions,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () {
                          final newX = double.tryParse(xCtrl.text) ?? layer.x;
                          final newY = double.tryParse(yCtrl.text) ?? layer.y;
                          final newW =
                              double.tryParse(wCtrl.text) ?? layer.width;
                          final newH =
                              double.tryParse(hCtrl.text) ?? layer.height;
                          NodePayload? updatedPayload = layer.payload;
                          if (layer.payload is TextPayload) {
                            updatedPayload = (layer.payload as TextPayload)
                                .copyWith(text: textCtrl.text);
                          }
                          setState(() {
                            _templateChildren[index] = layer.copyWith(
                              name: nameCtrl.text.trim().isEmpty
                                  ? layer.name
                                  : nameCtrl.text.trim(),
                              x: newX,
                              y: newY,
                              width: newW,
                              height: newH,
                              payload: updatedPayload,
                            );
                          });
                          _syncChanges();
                          Navigator.pop(dialogContext);
                        },
                        variant: UiButtonVariant.primary,
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      xCtrl.dispose();
      yCtrl.dispose();
      wCtrl.dispose();
      hCtrl.dispose();
      textCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final dialogWidth = AppResponsive.dialogWidth(context, preferred: 720);
    final dialogHeight = AppResponsive.dialogHeight(context, preferred: 620);
    final compact = AppResponsive.isNarrow(context);
    return UiDialog(
      semanticsLabel: 'Component editor',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 720,
        maxHeight: 620,
      ),
      builder: (context, style) => SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: UiSurface(
          padding: AppResponsive.dialogPadding(context),
          color: tokens.panel,
          child: Column(
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(tokens.controlRadius),
                      border: Border.all(color: tokens.accent),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        AppSpacing.xs + AppSpacing.xxs,
                      ),
                      child: Text(
                        _payload.isMaster ? '❖' : '◇',
                        style: TextStyle(
                          fontSize: 16,
                          color: tokens.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _payload.isMaster
                              ? 'Main Component Settings (Figma-Engine)'
                              : 'Component Instance Overrides',
                          style: style.titleTextStyle,
                        ),
                        Text(
                          _payload.isMaster
                              ? 'Define master properties, variants & nested shape templates'
                              : 'Linked to Master ID: ${_payload.masterComponentId}',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.lg),
              Expanded(
                child: UiTabs(
                  scrollable: compact,
                  index: _tabController.index,
                  onChanged: (index) {
                    if (_tabController.index != index) {
                      _tabController.animateTo(index);
                    }
                  },
                  expands: true,
                  tabs: [
                    UiTabEntry(
                      label: const Text('Properties & Props'),
                      child: _buildPropertiesTab(),
                    ),
                    UiTabEntry(
                      label: const Text('Layers / Shapes'),
                      child: _buildLayersTab(),
                    ),
                    UiTabEntry(
                      label: const Text('Styling'),
                      child: _buildStylingTab(),
                    ),
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (!_payload.isMaster)
                    compact
                        ? UiIconButton(
                            icon: Icons.restore,
                            tooltip: 'Reset overrides',
                            onPressed: () {
                              setState(() {
                                _payload = _payload.copyWith(overrides: {});
                              });
                              _syncChanges();
                              showUiToast(
                                context,
                                'All overrides reset to master!',
                                variant: UiToastVariant.success,
                              );
                            },
                          )
                        : UiButton(
                            onPressed: () {
                              setState(() {
                                _payload = _payload.copyWith(overrides: {});
                              });
                              _syncChanges();
                              showUiToast(
                                context,
                                'All overrides reset to master!',
                                variant: UiToastVariant.success,
                              );
                            },
                            variant: UiButtonVariant.outline,
                            prefix: const Icon(Icons.restore, size: 14),
                            child: const Text('Reset Overrides'),
                          ),
                  if (compact)
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close component editor',
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    UiButton(
                      onPressed: () => Navigator.pop(context),
                      variant: UiButtonVariant.ghost,
                      child: const Text('Close'),
                    ),
                  UiButton(
                    onPressed: () {
                      _syncChanges();
                      Navigator.pop(context);
                    },
                    variant: UiButtonVariant.primary,
                    prefix: const Icon(Icons.check, size: 14),
                    child: Text(compact ? 'Save' : 'Save Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesTab() {
    final tokens = context.appTokens;
    return ListView(
      children: [
        UiTextField(
          controller: _nameController,
          label: 'Component Name',
          onChanged: (_) => _syncChanges(),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        UiTextField(
          controller: _descController,
          label: 'Description / Usage Instructions',
          minLines: 2,
          maxLines: 2,
          onChanged: (_) => _syncChanges(),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            const Expanded(
              child: UiSectionHeader(title: 'COMPONENT PROPS (Figma-Style)'),
            ),
            UiButton(
              onPressed: _addPropertyDialog,
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.add, size: 13),
              child: const Text('New Prop'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        if (_properties.isEmpty)
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.page),
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            child: const Center(
              child: Text(
                'No custom props configured.\nAdd Text, Boolean switch, or Variant props to expose editable controls for instances.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ..._properties.map(_buildPropertyItemCard),
        const SizedBox(height: AppSpacing.lg),
        _buildVariantsSection(),
        const SizedBox(height: AppSpacing.lg),
        _buildSlotsSection(),
        const SizedBox(height: AppSpacing.lg),
        _buildTokenBindingsSection(),
      ],
    );
  }

  Widget _buildVariantsSection() {
    final tokens = context.appTokens;
    if (!_payload.isMaster) {
      final options = {
        for (final variant in _payload.variants) variant.id: variant.name,
      };
      return UiSurface(
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
        color: tokens.panelElevated,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        child: UiSelect<String>(
          label: 'Component Variant',
          items: options,
          value: options.containsKey(_payload.variantId)
              ? _payload.variantId
              : _payload.resolveVariant()?.id,
          enabled: options.isNotEmpty,
          onChanged: (value) {
            setState(() {
              _payload = ComponentInstanceFactory.setVariant(_payload, value);
            });
            _syncChanges();
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: UiSectionHeader(title: 'COMPONENT VARIANTS')),
            UiButton(
              onPressed: _addVariantDialog,
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.add, size: 13),
              child: const Text('New Variant'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_payload.variants.isEmpty)
          Text(
            'Create named visual states and select them per instance.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          )
        else
          ..._payload.variants.map(
            (variant) => UiSurface(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppSpacing.xxs,
                vertical: AppSpacing.sm,
              ),
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              child: Row(
                children: [
                  Icon(Icons.alt_route, size: 15, color: tokens.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${variant.name}${variant.isDefault ? ' · default' : ''}',
                      style: TextStyle(color: tokens.text, fontSize: 12),
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete Variant',
                    variant: UiButtonVariant.destructive,
                    onPressed: () {
                      final variants = _payload.variants
                          .where((candidate) => candidate.id != variant.id)
                          .toList(growable: false);
                      setState(() {
                        _payload = _payload.copyWith(
                          variants: variants,
                          variantId: _payload.variantId == variant.id
                              ? null
                              : _payload.variantId,
                        );
                      });
                      _syncChanges();
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _addVariantDialog() {
    showUiDialog<void>(
      context: context,
      builder: (_) => _AddComponentVariantDialog(
        onAdd: (name) {
          final variant = ComponentVariant(
            id: const Uuid().v4().substring(0, 8),
            name: name,
            isDefault: _payload.variants.isEmpty,
            propertyValues: {
              for (final property in _properties)
                property.id: property.defaultValue,
            },
          );
          setState(() {
            _payload = _payload.copyWith(
              variants: [..._payload.variants, variant],
            );
          });
          _syncChanges();
        },
      ),
    );
  }

  Widget _buildSlotsSection() {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: UiSectionHeader(title: 'CONTENT SLOTS')),
            if (_payload.isMaster)
              UiButton(
                onPressed: _addSlotDialog,
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.add, size: 13),
                child: const Text('New Slot'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_payload.slots.isEmpty)
          Text(
            'Slots let instances replace a defined content region.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          )
        else
          ..._payload.slots.map(
            (slot) => UiSurface(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppSpacing.xxs,
                vertical: AppSpacing.sm,
              ),
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              child: Row(
                children: [
                  Icon(
                    Icons.view_agenda_outlined,
                    size: 15,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${slot.name} · ${slot.width.toInt()}×${slot.height.toInt()}',
                      style: TextStyle(color: tokens.text, fontSize: 12),
                    ),
                  ),
                  if (!_payload.isMaster &&
                      _payload.slotContent.containsKey(slot.id))
                    UiIconButton(
                      icon: Icons.restore,
                      tooltip: 'Use Slot Fallback',
                      onPressed: () {
                        setState(() {
                          _payload = ComponentInstanceFactory.clearSlotContent(
                            _payload,
                            slot.id,
                          );
                        });
                        _syncChanges();
                      },
                    ),
                  if (_payload.isMaster)
                    UiIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete Slot',
                      variant: UiButtonVariant.destructive,
                      onPressed: () {
                        setState(() {
                          _payload = _payload.copyWith(
                            slots: _payload.slots
                                .where((candidate) => candidate.id != slot.id)
                                .toList(growable: false),
                            slotContent: Map<String, List<CanvasNode>>.from(
                              _payload.slotContent,
                            )..remove(slot.id),
                          );
                        });
                        _syncChanges();
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _addSlotDialog() {
    showUiDialog<void>(
      context: context,
      builder: (_) => _AddComponentSlotDialog(
        onAdd: (name) {
          setState(() {
            _payload = _payload.copyWith(
              slots: [
                ..._payload.slots,
                ComponentSlot(
                  id: const Uuid().v4().substring(0, 8),
                  name: name,
                  width: widget.node.width,
                  height: 40,
                ),
              ],
            );
          });
          _syncChanges();
        },
      ),
    );
  }

  Widget _buildTokenBindingsSection() {
    final tokens = context.appTokens;
    final targets = <String>['backgroundColor', 'borderColor'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UiSectionHeader(title: 'DESIGN TOKEN BINDINGS'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Use token IDs from the document token manager. Overrides still win on instances.',
          style: Theme.of(
            context,
          ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...[
          ..._properties.map((property) => (property.id, property.name)),
          ...targets.map((target) => (target, target)),
        ].map(
          (target) => Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.xs + AppSpacing.xxs,
            ),
            child: UiTextField(
              key: ValueKey('component-token-${target.$1}'),
              controller: TextEditingController(
                text: _payload.tokenBindings[target.$1] ?? '',
              ),
              label: '${target.$2} token ID',
              onChanged: (value) {
                setState(() {
                  _payload = ComponentInstanceFactory.setTokenBinding(
                    _payload,
                    target.$1,
                    value,
                  );
                });
                _syncChanges();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyItemCard(ComponentProperty prop) {
    final currentVal = _currentPropertyValue(prop);
    final tokens = context.appTokens;

    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
      color: tokens.panelElevated,
      borderRadius: BorderRadius.circular(tokens.controlRadius),
      child: Row(
        children: [
          Icon(
            prop.type == ComponentPropType.boolean
                ? Icons.toggle_on_outlined
                : (prop.type == ComponentPropType.variant
                      ? Icons.list_alt
                      : Icons.text_fields),
            size: 16,
            color: tokens.accent,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prop.name,
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Type: ${prop.type.name}',
                  style: TextStyle(color: tokens.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Expanded(flex: 3, child: _buildPropValueWidget(prop, currentVal)),
          UiIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove Prop',
            variant: UiButtonVariant.destructive,
            onPressed: () {
              setState(() {
                _properties.removeWhere((p) => p.id == prop.id);
                _propertyValues.remove(prop.id);
                _payload = _payload.copyWith(
                  properties: _properties,
                  propertyValues: _propertyValues,
                  overrides: Map<String, dynamic>.from(_payload.overrides)
                    ..remove(prop.id),
                );
              });
              _syncChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPropValueWidget(ComponentProperty prop, dynamic currentVal) {
    switch (prop.type) {
      case ComponentPropType.boolean:
        final boolVal = currentVal is bool ? currentVal : true;
        return UiSwitch(
          value: boolVal,
          onChange: (val) => _setPropertyValue(prop, val),
        );
      case ComponentPropType.variant:
        final options = prop.options;
        return UiSelect<String>(
          items: {for (final option in options) option: option},
          value: options.contains(currentVal)
              ? currentVal.toString()
              : (options.isNotEmpty ? options.first : null),
          label: prop.name,
          enabled: options.isNotEmpty,
          onChanged: (val) {
            if (val != null) {
              _setPropertyValue(prop, val);
            }
          },
        );
      case ComponentPropType.text:
        return UiTextField(
          controller: TextEditingController(text: currentVal?.toString() ?? ''),
          onChanged: (val) => _setPropertyValue(prop, val),
        );
    }
  }

  Widget _buildLayersTab() {
    final tokens = context.appTokens;
    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: UiSectionHeader(title: 'INNER TEMPLATE SHAPES & LAYERS'),
            ),
            UiButton(
              onPressed: () => _showAddLayerMenu(context, Offset.zero),
              variant: UiButtonVariant.primary,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.add, size: 14),
              child: const Text('Add Shape Layer'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        if (_templateChildren.isEmpty)
          UiSurface(
            padding: const EdgeInsets.all(AppSpacing.pageWide),
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            child: const Center(
              child: Text(
                'No internal template layers added yet.\nClick "Add Shape Layer ▾" to insert Rectangle, Ellipse, Diamond, Cylinder, Parallelogram, Text, or Frame layers into this component!',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ..._templateChildren.asMap().entries.map((entry) {
            final idx = entry.key;
            final child = entry.value;
            return Container(
              key: ValueKey(child.id),
              margin: const EdgeInsets.only(
                bottom: AppSpacing.xs + AppSpacing.xxs,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppSpacing.xxs,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: tokens.panelElevated,
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                border: Border.all(
                  color: tokens.panelBorder,
                  width: AppBorder.thin,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getShapeIcon(child.type),
                    size: 15,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          child.name ?? 'Layer #${idx + 1}',
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${child.type.name} • pos: (${child.x.toInt()}, ${child.y.toInt()}) • size: ${child.width.toInt()}x${child.height.toInt()}',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit Shape Properties',
                    onPressed: () => _editLayerDialog(idx),
                  ),
                  UiIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete Shape Layer',
                    variant: UiButtonVariant.destructive,
                    onPressed: () {
                      setState(() => _templateChildren.removeAt(idx));
                      _syncChanges();
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  IconData _getShapeIcon(NodeType type) {
    switch (type) {
      case NodeType.rectangle:
        return Icons.crop_square;
      case NodeType.ellipse:
        return Icons.circle_outlined;
      case NodeType.diamond:
        return Icons.change_history;
      case NodeType.cylinder:
        return Icons.storage_outlined;
      case NodeType.parallelogram:
        return Icons.view_sidebar_outlined;
      case NodeType.text:
        return Icons.title;
      case NodeType.frame:
        return Icons.crop_free;
      default:
        return Icons.layers_outlined;
    }
  }

  Widget _buildStylingTab() {
    final tokens = context.appTokens;
    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Show Component Badge Indicator',
              style: Theme.of(
                context,
              ).textTheme.labelMedium!.copyWith(color: tokens.text),
            ),
            UiSwitch(
              value: _payload.showBadge,
              onChange: (val) {
                setState(() => _payload = _payload.copyWith(showBadge: val));
                _syncChanges();
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Is Master Component',
          style: Theme.of(
            context,
          ).textTheme.labelMedium!.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Row(
          children: [
            Expanded(
              child: UiButton(
                onPressed: () {
                  setState(() => _payload = _payload.copyWith(isMaster: true));
                  _syncChanges();
                },
                variant: _payload.isMaster
                    ? UiButtonVariant.primary
                    : UiButtonVariant.outline,
                child: const Text('❖ Master'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: UiButton(
                onPressed: () {
                  setState(() => _payload = _payload.copyWith(isMaster: false));
                  _syncChanges();
                },
                variant: !_payload.isMaster
                    ? UiButtonVariant.primary
                    : UiButtonVariant.outline,
                child: const Text('◇ Instance'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Corner Radius',
          style: Theme.of(
            context,
          ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
        ),
        UiSlider(
          value: _payload.cornerRadius.clamp(0.0, 32.0) / 32,
          onChanged: (value) {
            setState(
              () => _payload = _payload.copyWith(cornerRadius: value * 32),
            );
            _syncChanges();
          },
        ),
      ],
    );
  }
}

class _AddComponentVariantDialog extends StatefulWidget {
  const _AddComponentVariantDialog({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<_AddComponentVariantDialog> createState() =>
      _AddComponentVariantDialogState();
}

class _AddComponentVariantDialogState
    extends State<_AddComponentVariantDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildComponentNameDialog(
    context: context,
    title: 'Add Component Variant',
    label: 'Variant Name',
    hint: 'Primary, Secondary, Disabled',
    actionLabel: 'Add Variant',
    controller: _controller,
    onAdd: widget.onAdd,
  );
}

class _AddComponentSlotDialog extends StatefulWidget {
  const _AddComponentSlotDialog({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  State<_AddComponentSlotDialog> createState() =>
      _AddComponentSlotDialogState();
}

class _AddComponentSlotDialogState extends State<_AddComponentSlotDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildComponentNameDialog(
    context: context,
    title: 'Add Content Slot',
    label: 'Slot Name',
    hint: 'Body, icon, footer',
    actionLabel: 'Add Slot',
    controller: _controller,
    onAdd: widget.onAdd,
  );
}

Widget _buildComponentNameDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String hint,
  required String actionLabel,
  required TextEditingController controller,
  required ValueChanged<String> onAdd,
}) {
  return UiDialog(
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 420,
      maxHeight: 420,
    ),
    builder: (context, style) => SizedBox(
      width: AppResponsive.dialogWidth(context, preferred: 420),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: AppResponsive.dialogHeight(context, preferred: 420),
        ),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md),
                UiTextField(
                  controller: controller,
                  autofocus: true,
                  label: label,
                  hint: hint,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    UiButton(
                      onPressed: () => Navigator.of(context).pop(),
                      variant: UiButtonVariant.ghost,
                      child: const Text('Cancel'),
                    ),
                    UiButton(
                      onPressed: () {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;
                        onAdd(name);
                        Navigator.of(context).pop();
                      },
                      variant: UiButtonVariant.primary,
                      child: Text(actionLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
