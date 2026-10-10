import 'package:flutter/material.dart';

import '../../../app/widgets/ui_primitives.dart';
import '../export_presets.dart';

/// Presents the canonical document export presets without performing export
/// side effects. The host owns file naming and calls the selected preset.
class ExportPresetChooser extends StatelessWidget {
  final ExportPreset selected;
  final ValueChanged<ExportPreset> onChanged;
  final List<ExportPreset> presets;
  final String? label;
  final String? hint;
  final bool enabled;

  ExportPresetChooser({
    required this.selected,
    required this.onChanged,
    List<ExportPreset>? presets,
    this.label = 'Export format',
    this.hint,
    this.enabled = true,
    super.key,
  }) : presets = List<ExportPreset>.unmodifiable(
         presets ?? ExportPresetRegistry.all,
       );

  @override
  Widget build(BuildContext context) {
    final available = presets.isEmpty ? ExportPresetRegistry.all : presets;
    final selectedPreset = available.any((preset) => preset.id == selected.id)
        ? selected
        : available.first;

    return UiSelect<String>(
      items: {for (final preset in available) preset.label: preset.id},
      value: selectedPreset.id,
      label: label,
      hint: hint,
      enabled: enabled,
      onChanged: (id) {
        if (id == null) return;
        for (final preset in available) {
          if (preset.id == id) {
            onChanged(preset);
            return;
          }
        }
      },
    );
  }
}

/// Short alias for integrations that already call selectors "selects".
typedef ExportPresetSelect = ExportPresetChooser;
