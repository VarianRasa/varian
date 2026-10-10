import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme.dart';
import '../../templates/data/diagram_templates.dart';

/// A small, interactive preview of real built-in canvas templates.
///
/// The showcase gives new users a quick sense of what they can make without
/// implying that an account is required to explore the local workspace.
class AuthTemplateShowcase extends StatefulWidget {
  final bool compact;

  const AuthTemplateShowcase({required this.compact, super.key});

  @override
  State<AuthTemplateShowcase> createState() => _AuthTemplateShowcaseState();
}

class _AuthTemplateShowcaseState extends State<AuthTemplateShowcase> {
  static const _showcaseIds = [
    'moodboard',
    'storyboard',
    'pitch-deck',
    'flowchart',
  ];

  String _selectedId = 'moodboard';

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    final templates = DiagramTemplates.listTemplates()
        .where((template) => _showcaseIds.contains(template.id))
        .toList(growable: false);
    final compact = widget.compact;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = compact ? 94 + (textScale - 1).clamp(0.0, 2.0) * 28 : 124.0;
    final previewHeight = compact ? 58.0 : 78.0;
    final gap = AppSpacing.sm;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final showCount = constraints.maxWidth >= 360;
              return Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: compact ? 13 : 15,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      copy.isIndonesian
                          ? 'MULAI DARI TEMPLATE'
                          : 'START WITH A TEMPLATE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        fontSize: compact ? 9 : 10,
                      ),
                    ),
                  ),
                  if (showCount)
                    Text(
                      '${templates.length} ${copy.isIndonesian ? 'TEMPLATE' : 'TEMPLATES'}',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.textMuted,
                        fontSize: compact ? 8 : 9,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: previewHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = compact
                    ? 112.0
                    : ((constraints.maxWidth - gap * 3) / 4)
                          .clamp(132.0, 196.0)
                          .toDouble();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: templates.length,
                  separatorBuilder: (_, _) => SizedBox(width: gap),
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    final selected = template.id == _selectedId;
                    return _AuthTemplateCard(
                      key: ValueKey('auth-template-${template.id}'),
                      semanticsKey: ValueKey(
                        'auth-template-${template.id}-semantics',
                      ),
                      template: template,
                      width: cardWidth,
                      height: previewHeight,
                      compact: compact,
                      selected: selected,
                      tokens: tokens,
                      onTap: () => setState(() => _selectedId = template.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthTemplateCard extends StatelessWidget {
  final Key semanticsKey;
  final DiagramTemplateMetadata template;
  final double width;
  final double height;
  final bool compact;
  final bool selected;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _AuthTemplateCard({
    required this.semanticsKey,
    required this.template,
    required this.width,
    required this.height,
    required this.compact,
    required this.selected,
    required this.tokens,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final label = _templateSubtitle(template.id, context);
    final radius = BorderRadius.circular(AppRadius.control);
    final border = selected ? tokens.selection : tokens.panelBorder;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      key: semanticsKey,
      button: true,
      selected: selected,
      label: '${template.name} template${selected ? ', selected' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: tokens.selection.withValues(alpha: 0.12),
          highlightColor: tokens.selection.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      tokens.selection.withValues(alpha: 0.07),
                      tokens.panelElevated,
                    )
                  : tokens.panelElevated,
              borderRadius: radius,
              border: Border.all(
                color: border.withValues(alpha: selected ? 0.9 : 0.72),
                width: selected ? 1.5 : AppBorder.thin,
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _TemplateThumbnailPainter(template.id, tokens),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
                      vertical: compact ? AppSpacing.xxs : AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                template.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: tokens.text,
                                      fontSize: compact ? 9 : 11,
                                      height: 1.15,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              if (!compact) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: tokens.textMuted,
                                        fontSize: 9,
                                        height: 1.1,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child: selected
                              ? Padding(
                                  key: const ValueKey('selected'),
                                  padding: const EdgeInsets.only(
                                    left: AppSpacing.xxs,
                                  ),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: compact ? 12 : 14,
                                    color: tokens.selection,
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('unselected'),
                                ),
                        ),
                      ],
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

  String _templateSubtitle(String id, BuildContext context) {
    final indonesian = CreativeStudioLocalizations.of(context).isIndonesian;
    return switch (id) {
      'moodboard' => indonesian ? 'Arah visual' : 'Visual direction',
      'storyboard' => indonesian ? 'Cerita per adegan' : 'Scene by scene',
      'pitch-deck' => indonesian ? 'Presentasikan ide' : 'Present an idea',
      _ => indonesian ? 'Peta proses' : 'Map a process',
    };
  }
}

class _TemplateThumbnailPainter extends CustomPainter {
  final String templateId;
  final AppTokens tokens;

  const _TemplateThumbnailPainter(this.templateId, this.tokens);

  static const _blue = Color(0xFF6392D5);
  static const _orange = Color(0xFFEA9B60);
  static const _mint = Color(0xFF80A996);
  static const _rose = Color(0xFFD37C70);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final background = Color.alphaBlend(
      tokens.canvasGrid.withValues(alpha: 0.15),
      tokens.panel,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    switch (templateId) {
      case 'moodboard':
        _paintMoodboard(canvas, size);
        break;
      case 'storyboard':
        _paintStoryboard(canvas, size);
        break;
      case 'pitch-deck':
        _paintPitchDeck(canvas, size);
        break;
      default:
        _paintFlowchart(canvas, size);
        break;
    }
    canvas.restore();
  }

  void _paintMoodboard(Canvas canvas, Size size) {
    final pad = size.width * 0.09;
    final gap = size.width * 0.045;
    final leftWidth = size.width * 0.54;
    final top = size.height * 0.13;
    final imageHeight = size.height * 0.62;
    _roundRect(
      canvas,
      Rect.fromLTWH(pad, top, leftWidth, imageHeight),
      _blue.withValues(alpha: 0.78),
      5,
    );
    _roundRect(
      canvas,
      Rect.fromLTWH(
        pad + leftWidth * 0.54,
        top + imageHeight * 0.18,
        leftWidth * 0.36,
        imageHeight * 0.58,
      ),
      _orange.withValues(alpha: 0.9),
      4,
    );
    final rightX = pad + leftWidth + gap;
    final rightWidth = size.width - rightX - pad;
    _roundRect(
      canvas,
      Rect.fromLTWH(rightX, top, rightWidth, imageHeight * 0.42),
      _rose.withValues(alpha: 0.82),
      4,
    );
    _roundRect(
      canvas,
      Rect.fromLTWH(
        rightX,
        top + imageHeight * 0.52,
        rightWidth,
        imageHeight * 0.48,
      ),
      _mint.withValues(alpha: 0.82),
      4,
    );
    _line(
      canvas,
      Offset(pad, size.height * 0.84),
      leftWidth * 0.66,
      tokens.text,
    );
    _line(
      canvas,
      Offset(pad, size.height * 0.92),
      leftWidth * 0.42,
      tokens.textMuted,
    );
  }

  void _paintStoryboard(Canvas canvas, Size size) {
    final pad = size.width * 0.08;
    final gap = size.width * 0.04;
    final frameWidth = (size.width - pad * 2 - gap * 2) / 3;
    final top = size.height * 0.16;
    final frameHeight = size.height * 0.62;
    final colors = [_blue, _orange, _mint];
    for (var index = 0; index < 3; index++) {
      final rect = Rect.fromLTWH(
        pad + index * (frameWidth + gap),
        top,
        frameWidth,
        frameHeight,
      );
      _roundRect(canvas, rect, colors[index].withValues(alpha: 0.68), 4);
      final sunCenter = Offset(
        rect.left + rect.width * (index == 1 ? 0.68 : 0.32),
        rect.top + rect.height * 0.36,
      );
      canvas.drawCircle(
        sunCenter,
        math.min(frameWidth, frameHeight) * 0.13,
        Paint()..color = const Color(0xFFFFE1A3).withValues(alpha: 0.88),
      );
      final ground = Paint()..color = tokens.canvas.withValues(alpha: 0.54);
      final path = Path()
        ..moveTo(rect.left, rect.top + rect.height * 0.74)
        ..quadraticBezierTo(
          rect.left + rect.width * 0.48,
          rect.top + rect.height * 0.45,
          rect.right,
          rect.top + rect.height * 0.72,
        )
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(path, ground);
    }
    for (var index = 0; index < 3; index++) {
      _roundRect(
        canvas,
        Rect.fromLTWH(
          pad + index * (frameWidth + gap),
          size.height * 0.88,
          frameWidth * (0.72 - index * 0.1),
          math.max(2, size.height * 0.035),
        ),
        tokens.textMuted.withValues(alpha: 0.55),
        2,
      );
    }
  }

  void _paintPitchDeck(Canvas canvas, Size size) {
    final pad = size.width * 0.08;
    final sheet = Rect.fromLTWH(
      pad,
      size.height * 0.12,
      size.width * 0.84,
      size.height * 0.74,
    );
    _roundRect(canvas, sheet, tokens.panelElevated, 4);
    _roundRect(
      canvas,
      Rect.fromLTWH(sheet.left, sheet.top, sheet.width * 0.42, sheet.height),
      _blue.withValues(alpha: 0.85),
      4,
    );
    _roundRect(
      canvas,
      Rect.fromLTWH(
        sheet.left + sheet.width * 0.54,
        sheet.top + sheet.height * 0.18,
        sheet.width * 0.32,
        sheet.height * 0.14,
      ),
      _orange.withValues(alpha: 0.88),
      3,
    );
    _line(
      canvas,
      Offset(sheet.left + sheet.width * 0.54, sheet.top + sheet.height * 0.52),
      sheet.width * 0.3,
      tokens.text,
      stroke: 2,
    );
    _line(
      canvas,
      Offset(sheet.left + sheet.width * 0.54, sheet.top + sheet.height * 0.64),
      sheet.width * 0.22,
      tokens.textMuted,
      stroke: 1.5,
    );
    final chartBase = sheet.bottom - sheet.height * 0.16;
    for (var index = 0; index < 4; index++) {
      final barHeight = sheet.height * (0.12 + index * 0.08);
      _roundRect(
        canvas,
        Rect.fromLTWH(
          sheet.left + sheet.width * (0.56 + index * 0.075),
          chartBase - barHeight,
          sheet.width * 0.045,
          barHeight,
        ),
        index.isEven ? _mint : _orange,
        2,
      );
    }
  }

  void _paintFlowchart(Canvas canvas, Size size) {
    final left = size.width * 0.14;
    final right = size.width * 0.86;
    final top = size.height * 0.18;
    final mid = size.height * 0.5;
    final bottom = size.height * 0.82;
    final wirePaint = Paint()
      ..color = tokens.textMuted.withValues(alpha: 0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(left + size.width * 0.16, top + size.height * 0.09)
      ..lineTo(size.width * 0.53, top + size.height * 0.09)
      ..lineTo(size.width * 0.66, mid)
      ..lineTo(right - size.width * 0.08, mid)
      ..lineTo(right - size.width * 0.08, bottom)
      ..lineTo(left + size.width * 0.2, bottom);
    canvas.drawPath(path, wirePaint);
    final nodes = [
      (Offset(left + size.width * 0.14, top), _blue),
      (Offset(size.width * 0.52, mid - size.height * 0.11), _orange),
      (Offset(right - size.width * 0.22, bottom - size.height * 0.1), _mint),
    ];
    for (final (origin, color) in nodes) {
      _roundRect(
        canvas,
        Rect.fromLTWH(
          origin.dx,
          origin.dy,
          size.width * 0.24,
          size.height * 0.2,
        ),
        color.withValues(alpha: 0.82),
        4,
      );
      canvas.drawCircle(
        Offset(origin.dx + size.width * 0.045, origin.dy + size.height * 0.065),
        2.4,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
      _line(
        canvas,
        Offset(origin.dx + size.width * 0.085, origin.dy + size.height * 0.065),
        size.width * 0.1,
        Colors.white,
      );
      _line(
        canvas,
        Offset(origin.dx + size.width * 0.045, origin.dy + size.height * 0.13),
        size.width * 0.14,
        Colors.white.withValues(alpha: 0.7),
      );
    }
    for (final point in [
      Offset(size.width * 0.53, top + size.height * 0.09),
      Offset(right - size.width * 0.08, mid),
    ]) {
      canvas.drawCircle(point, 3, Paint()..color = tokens.accent);
    }
  }

  void _roundRect(Canvas canvas, Rect rect, Color color, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void _line(
    Canvas canvas,
    Offset start,
    double width,
    Color color, {
    double stroke = 1.2,
  }) {
    canvas.drawLine(
      start,
      start.translate(width, 0),
      Paint()
        ..color = color.withValues(alpha: 0.72)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) =>
      oldDelegate.templateId != templateId || oldDelegate.tokens != tokens;
}
