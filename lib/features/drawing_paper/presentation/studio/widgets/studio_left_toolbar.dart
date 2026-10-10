import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class StudioLeftToolbar extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;

  const StudioLeftToolbar({super.key, required this.initialPayload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;

    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          right: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _ToolButton(
            icon: Icons.pan_tool_outlined,
            label: 'Hand / Pan Paper (H / Space)',
            isActive: state.activeTool == StudioTool.hand,
            onTap: () => notifier.setTool(StudioTool.hand),
          ),
          _ToolButton(
            icon: Icons.draw_outlined,
            label: 'Pen & Brushes (B)',
            isActive: state.activeTool == StudioTool.brush,
            onTap: () => notifier.setTool(StudioTool.brush),
          ),
          _ToolButton(
            icon: Icons.auto_fix_normal_outlined,
            label: 'Eraser (E)',
            isActive: state.activeTool == StudioTool.eraser,
            onTap: () => notifier.setTool(StudioTool.eraser),
          ),
          _ToolButton(
            icon: Icons.format_color_fill_outlined,
            label: 'Bucket Fill',
            isActive: state.activeTool == StudioTool.bucketFill,
            onTap: () => notifier.setTool(StudioTool.bucketFill),
          ),
          _ToolButton(
            icon: Icons.blur_on_outlined,
            label: 'Smudge & Blend',
            isActive: state.activeTool == StudioTool.smudge,
            onTap: () => notifier.setTool(StudioTool.smudge),
          ),
          Divider(
            color: tokens.panelBorder,
            height: AppSpacing.lg,
            thickness: AppBorder.thin,
          ),
          _ToolButton(
            icon: Icons.crop_free,
            label: 'Lasso / Pixel Selection',
            isActive: state.activeTool == StudioTool.selection,
            onTap: () => notifier.setTool(StudioTool.selection),
          ),
          _ToolButton(
            icon: Icons.near_me_outlined,
            label: 'Select Items (V): move, resize, rotate, copy, delete',
            isActive: state.activeTool == StudioTool.itemSelection,
            onTap: () => notifier.setTool(StudioTool.itemSelection),
          ),
          _ToolButton(
            icon: Icons.transform_outlined,
            label: 'Transform & Warp',
            isActive: state.activeTool == StudioTool.transform,
            onTap: () => notifier.setTool(StudioTool.transform),
          ),
          _ToolButton(
            icon: Icons.straighten_outlined,
            label: 'Rulers & Guides',
            isActive: state.activeTool == StudioTool.ruler,
            onTap: () => notifier.setTool(StudioTool.ruler),
          ),
          Divider(
            color: tokens.panelBorder,
            height: AppSpacing.lg,
            thickness: AppBorder.thin,
          ),
          _ToolButton(
            icon: Icons.dashboard_outlined,
            label: 'Manga Comic Panels',
            isActive: state.activeTool == StudioTool.mangaPanel,
            onTap: () => notifier.setTool(StudioTool.mangaPanel),
          ),
          _ToolButton(
            icon: Icons.chat_bubble_outline,
            label: 'Speech Balloons',
            isActive: state.activeTool == StudioTool.speechBalloon,
            onTap: () => notifier.setTool(StudioTool.speechBalloon),
          ),
          _ToolButton(
            icon: Icons.title,
            label: 'Text Object (T)',
            isActive: state.activeTool == StudioTool.text,
            onTap: () => notifier.setTool(StudioTool.text),
          ),
          _ToolButton(
            icon: Icons.category_outlined,
            label: 'Shapes (Line/Rect/Ellipse/Polygon)',
            isActive: state.activeTool == StudioTool.shapes,
            onTap: () => notifier.setTool(StudioTool.shapes),
          ),
          _ToolButton(
            icon: Icons.colorize_outlined,
            label: 'Eyedropper',
            isActive: state.activeTool == StudioTool.eyedropper,
            onTap: () => notifier.setTool(StudioTool.eyedropper),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: UiIconButton(
          icon: icon,
          tooltip: label,
          size: UiButtonSize.md,
          selected: isActive,
          onPressed: onTap,
        ),
      ),
    );
  }
}
