import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mix/mix.dart';

/// Semantic tokens shared by application chrome and canvas renderers.
///
/// Document payload colors remain document data; these tokens only describe
/// surfaces owned by the application itself.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color canvas;
  final Color canvasGrid;
  final Color panel;
  final Color panelElevated;
  final Color panelBorder;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentForeground;
  final Color accentSoft;
  final Color selection;
  final Color handle;
  final Color success;
  final Color warning;
  final Color info;
  final Color danger;
  final Color videoBuffered;
  final Color videoBackground;
  final Color raisedShadow;
  final Color pressedShadow;
  final double panelRadius;
  final double controlRadius;
  final double spacing;

  const AppTokens({
    required this.canvas,
    required this.canvasGrid,
    required this.panel,
    required this.panelElevated,
    required this.panelBorder,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentForeground,
    required this.accentSoft,
    required this.selection,
    required this.handle,
    required this.success,
    required this.warning,
    required this.info,
    required this.danger,
    required this.videoBuffered,
    required this.videoBackground,
    required this.raisedShadow,
    required this.pressedShadow,
    this.panelRadius = 10,
    this.controlRadius = 6,
    this.spacing = 8,
  });

  static const light = AppTokens(
    canvas: Color(0xFFF5F5F5),
    canvasGrid: Color(0xFFD4D4D4),
    panel: Color(0xFFFAFAFA),
    panelElevated: Color(0xFFFFFFFF),
    panelBorder: Color(0xFFE5E5E5),
    text: Color(0xFF171717),
    textMuted: Color(0xFF737373),
    accent: Color(0xFF262626),
    accentForeground: Color(0xFFFAFAFA),
    accentSoft: Color(0xFFF5F5F5),
    selection: Color(0xFF525252),
    handle: Color(0xFFFFFFFF),
    success: Color(0xFF166534),
    warning: Color(0xFF92400E),
    info: Color(0xFF1D4ED8),
    danger: Color(0xFFB91C1C),
    videoBuffered: Color(0xFFA3A3A3),
    videoBackground: Color(0xFFE5E5E5),
    raisedShadow: Color(0xFFC9CDD2),
    pressedShadow: Color(0xFFFFFFFF),
  );

  static const dark = AppTokens(
    canvas: Color(0xFF0A0A0A),
    canvasGrid: Color(0xFF333333),
    panel: Color(0xFF171717),
    panelElevated: Color(0xFF262626),
    panelBorder: Color(0xFF404040),
    text: Color(0xFFFAFAFA),
    textMuted: Color(0xFFA1A1A1),
    accent: Color(0xFFD4D4D4),
    accentForeground: Color(0xFF171717),
    accentSoft: Color(0xFF262626),
    selection: Color(0xFFE5E5E5),
    handle: Color(0xFFFAFAFA),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    info: Color(0xFF60A5FA),
    danger: Color(0xFFF87171),
    videoBuffered: Color(0xFF737373),
    videoBackground: Color(0xFF404040),
    raisedShadow: Color(0xFF050505),
    pressedShadow: Color(0xFF2A2A2A),
  );

  @override
  AppTokens copyWith({
    Color? canvas,
    Color? canvasGrid,
    Color? panel,
    Color? panelElevated,
    Color? panelBorder,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? accentForeground,
    Color? accentSoft,
    Color? selection,
    Color? handle,
    Color? success,
    Color? warning,
    Color? info,
    Color? danger,
    Color? videoBuffered,
    Color? videoBackground,
    Color? raisedShadow,
    Color? pressedShadow,
    double? panelRadius,
    double? controlRadius,
    double? spacing,
  }) => AppTokens(
    canvas: canvas ?? this.canvas,
    canvasGrid: canvasGrid ?? this.canvasGrid,
    panel: panel ?? this.panel,
    panelElevated: panelElevated ?? this.panelElevated,
    panelBorder: panelBorder ?? this.panelBorder,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    accentSoft: accentSoft ?? this.accentSoft,
    selection: selection ?? this.selection,
    handle: handle ?? this.handle,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    danger: danger ?? this.danger,
    videoBuffered: videoBuffered ?? this.videoBuffered,
    videoBackground: videoBackground ?? this.videoBackground,
    raisedShadow: raisedShadow ?? this.raisedShadow,
    pressedShadow: pressedShadow ?? this.pressedShadow,
    panelRadius: panelRadius ?? this.panelRadius,
    controlRadius: controlRadius ?? this.controlRadius,
    spacing: spacing ?? this.spacing,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasGrid: Color.lerp(canvasGrid, other.canvasGrid, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      handle: Color.lerp(handle, other.handle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      videoBuffered: Color.lerp(videoBuffered, other.videoBuffered, t)!,
      videoBackground: Color.lerp(videoBackground, other.videoBackground, t)!,
      raisedShadow: Color.lerp(raisedShadow, other.raisedShadow, t)!,
      pressedShadow: Color.lerp(pressedShadow, other.pressedShadow, t)!,
      panelRadius: panelRadius + (other.panelRadius - panelRadius) * t,
      controlRadius: controlRadius + (other.controlRadius - controlRadius) * t,
      spacing: spacing + (other.spacing - spacing) * t,
    );
  }
}

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double page = 16;
  static const double pageWide = 20;
}

abstract final class AppTypography {
  static const double compactScale = 0.9;
}

abstract final class AppRadius {
  static const double control = 6;
  static const double panel = 10;
  static const double dialog = 12;
  static const double pill = 999;
}

abstract final class AppBorder {
  static const double thin = 1;
  static const double focus = 2;
}

abstract final class AppControlSize {
  static const double extraSmall = 28;
  static const double compact = 32;
  static const double regular = 36;
  static const double input = 40;
  static const double touch = 40;
  static const double minimumHitTarget = 44;
}

abstract final class AppElevation {
  static const double panelOffset = 2;
  static const double panelBlur = 6;
  static const double controlOffset = 1;
  static const double controlBlur = 3;
  static const double pressedOffset = 1;
  static const double pressedBlur = 2;
  static const double floatingOffset = 4;
  static const double floatingBlur = 16;
}

abstract final class AppOpacity {
  static const double disabled = 0.48;
  static const double hover = 0.08;
  static const double focus = 0.12;
  static const double overlay = 0.52;
}

abstract final class AppMotion {
  static const Duration short = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);

  static Duration durationFor(BuildContext context, Duration duration) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : duration;
}

extension AppBuildContextTokens on BuildContext {
  AppTokens get appTokens =>
      Theme.of(this).extension<AppTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppTokens.dark
          : AppTokens.light);
}

abstract final class AppMixTokens {
  static const canvas = ColorToken('app.canvas');
  static const panel = ColorToken('app.panel');
  static const panelElevated = ColorToken('app.panel.elevated');
  static const border = ColorToken('app.border');
  static const text = ColorToken('app.text');
  static const textMuted = ColorToken('app.text.muted');
  static const accent = ColorToken('app.accent');
  static const accentForeground = ColorToken('app.accent.foreground');
  static const accentSoft = ColorToken('app.accent.soft');
  static const success = ColorToken('app.status.success');
  static const warning = ColorToken('app.status.warning');
  static const info = ColorToken('app.status.info');
  static const danger = ColorToken('app.status.danger');
  static const successSoft = ColorToken('app.status.success.soft');
  static const warningSoft = ColorToken('app.status.warning.soft');
  static const infoSoft = ColorToken('app.status.info.soft');
  static const dangerSoft = ColorToken('app.status.danger.soft');
  static const raisedShadow = ColorToken('app.shadow.raised');
  static const pressedShadow = ColorToken('app.shadow.pressed');

  static Map<ColorToken, Color> colors(AppTokens tokens) => {
    canvas: tokens.canvas,
    panel: tokens.panel,
    panelElevated: tokens.panelElevated,
    border: tokens.panelBorder,
    text: tokens.text,
    textMuted: tokens.textMuted,
    accent: tokens.accent,
    accentForeground: tokens.accentForeground,
    accentSoft: tokens.accentSoft,
    success: tokens.success,
    warning: tokens.warning,
    info: tokens.info,
    danger: tokens.danger,
    successSoft: Color.alphaBlend(
      tokens.success.withValues(alpha: 0.12),
      tokens.panel,
    ),
    warningSoft: Color.alphaBlend(
      tokens.warning.withValues(alpha: 0.12),
      tokens.panel,
    ),
    infoSoft: Color.alphaBlend(
      tokens.info.withValues(alpha: 0.12),
      tokens.panel,
    ),
    dangerSoft: Color.alphaBlend(
      tokens.danger.withValues(alpha: 0.12),
      tokens.panel,
    ),
    raisedShadow: tokens.raisedShadow,
    pressedShadow: tokens.pressedShadow,
  };
}

abstract final class AppStyles {
  static final surface = BoxStyler()
      .color(AppMixTokens.panel())
      .borderRounded(AppRadius.panel)
      .boxShadows([
        BoxShadowMix(
          color: AppMixTokens.raisedShadow(),
          offset: const Offset(
            AppElevation.panelOffset,
            AppElevation.panelOffset,
          ),
          blurRadius: AppElevation.panelBlur,
        ),
        BoxShadowMix(
          color: AppMixTokens.pressedShadow(),
          offset: const Offset(
            -AppElevation.panelOffset,
            -AppElevation.panelOffset,
          ),
          blurRadius: AppElevation.panelBlur,
        ),
      ]);

  static final control = BoxStyler()
      .color(AppMixTokens.panel())
      .borderRounded(AppRadius.control)
      .boxShadows([
        BoxShadowMix(
          color: AppMixTokens.raisedShadow(),
          offset: const Offset(
            AppElevation.controlOffset,
            AppElevation.controlOffset,
          ),
          blurRadius: AppElevation.controlBlur,
        ),
        BoxShadowMix(
          color: AppMixTokens.pressedShadow(),
          offset: const Offset(
            -AppElevation.controlOffset,
            -AppElevation.controlOffset,
          ),
          blurRadius: AppElevation.controlBlur,
        ),
      ])
      .onPressed(
        BoxStyler().boxShadows([
          BoxShadowMix(
            color: AppMixTokens.pressedShadow(),
            offset: const Offset(
              AppElevation.pressedOffset,
              AppElevation.pressedOffset,
            ),
            blurRadius: AppElevation.pressedBlur,
          ),
          BoxShadowMix(
            color: AppMixTokens.raisedShadow(),
            offset: const Offset(
              -AppElevation.pressedOffset,
              -AppElevation.pressedOffset,
            ),
            blurRadius: AppElevation.pressedBlur,
          ),
        ]),
      );

  static final pressedControl = BoxStyler()
      .color(AppMixTokens.panel())
      .borderRounded(AppRadius.control)
      .boxShadows([
        BoxShadowMix(
          color: AppMixTokens.pressedShadow(),
          offset: const Offset(
            AppElevation.pressedOffset,
            AppElevation.pressedOffset,
          ),
          blurRadius: AppElevation.pressedBlur,
        ),
        BoxShadowMix(
          color: AppMixTokens.raisedShadow(),
          offset: const Offset(
            -AppElevation.pressedOffset,
            -AppElevation.pressedOffset,
          ),
          blurRadius: AppElevation.pressedBlur,
        ),
      ]);
}

class AppTheme {
  // Compatibility aliases for painters and legacy feature surfaces.
  // Keep these aliases grayscale; document and drawing payload colors remain data.
  static const Color canvasDarkBg = Color(0xFF0A0A0A);
  static const Color canvasLightBg = Color(0xFFF5F5F5);
  static const Color panelDarkBg = Color(0xFF171717);
  static const Color panelDarkSurface = Color(0xFF262626);
  static const Color panelBorder = Color(0xFF404040);
  static const Color panelHighlight = Color(0xFF525252);

  static const Color braunOrange = Color(0xFFE5E5E5);
  static const Color braunAmber = Color(0xFFA3A3A3);
  static const Color retroSage = Color(0xFFD4D4D4);
  static const Color retroCobalt = Color(0xFFBDBDBD);
  static const Color retroCrt = Color(0xFFD4D4D4);
  static const Color primaryAccent = Color(0xFFE5E5E5);
  static const Color selectionOutline = Color(0xFFE5E5E5);
  static const Color handleFill = Color(0xFFFAFAFA);

  static final ThemeData darkTheme = _materialTheme(
    AppTokens.dark,
    Brightness.dark,
  );
  static final ThemeData lightTheme = _materialTheme(
    AppTokens.light,
    Brightness.light,
  );

  static ThemeData materialThemeFor(AppTokens tokens) => _materialTheme(
    tokens,
    tokens == AppTokens.dark ? Brightness.dark : Brightness.light,
  );

  static Widget mixScope({
    required Widget child,
    AppTokens tokens = AppTokens.light,
  }) => MixScope.inherit(colors: AppMixTokens.colors(tokens), child: child);

  static ThemeData _materialTheme(AppTokens tokens, Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: tokens.accent,
          brightness: brightness,
        ).copyWith(
          primary: tokens.accent,
          onPrimary: tokens.accentForeground,
          secondary: tokens.accentSoft,
          onSecondary: tokens.text,
          surface: tokens.canvas,
          onSurface: tokens.text,
          error: tokens.danger,
          onError: tokens.accentForeground,
          outline: tokens.panelBorder,
        );
    final baseTextTheme = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = baseTextTheme.apply(
      bodyColor: tokens.text,
      displayColor: tokens.text,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    final compactButtonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, AppControlSize.regular),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
      shape: WidgetStatePropertyAll(controlShape),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.canvas,
      cardColor: tokens.panel,
      dividerColor: tokens.panelBorder,
      textTheme: textTheme,
      extensions: [tokens],
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minVerticalPadding: AppSpacing.xs,
        horizontalTitleGap: AppSpacing.sm,
        minLeadingWidth: AppControlSize.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        iconColor: tokens.textMuted,
        textColor: tokens.text,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: compactButtonStyle),
      filledButtonTheme: FilledButtonThemeData(style: compactButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: compactButtonStyle),
      textButtonTheme: TextButtonThemeData(style: compactButtonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(AppControlSize.compact, AppControlSize.compact),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.xs)),
          shape: WidgetStatePropertyAll(controlShape),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.panelElevated,
        elevation: 2,
        shadowColor: tokens.raisedShadow,
        surfaceTintColor: Colors.transparent,
        menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final foreground = states.contains(WidgetState.disabled)
              ? tokens.textMuted.withValues(alpha: AppOpacity.disabled)
              : tokens.text;
          return textTheme.bodyMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.panelElevated),
          shadowColor: WidgetStatePropertyAll(tokens.raisedShadow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(2),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.xs)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppControlSize.regular),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textMuted.withValues(alpha: AppOpacity.disabled);
            }
            return tokens.text;
          }),
          iconColor: WidgetStatePropertyAll(tokens.textMuted),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return tokens.pressedShadow.withValues(alpha: AppOpacity.focus);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return tokens.accent.withValues(alpha: AppOpacity.hover);
            }
            return Colors.transparent;
          }),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(tokens.panelElevated),
          shadowColor: WidgetStatePropertyAll(tokens.raisedShadow),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(2),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.xs)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.panelElevated,
        contentTextStyle: TextStyle(color: tokens.text),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accentForeground
              : tokens.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.panelBorder,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.text,
        elevation: 0,
        toolbarHeight: 44,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: tokens.text,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: tokens.text, size: 18),
        actionsIconTheme: IconThemeData(color: tokens.text, size: 18),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: const BoxConstraints(minHeight: AppControlSize.input),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppControlSize.input,
          minHeight: AppControlSize.input,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: AppControlSize.input,
          minHeight: AppControlSize.input,
        ),
        hintStyle: TextStyle(color: tokens.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(
            color: tokens.panelBorder,
            width: AppBorder.thin,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(
            color: tokens.panelBorder,
            width: AppBorder.thin,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(color: tokens.accent, width: AppBorder.focus),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(color: tokens.danger, width: AppBorder.thin),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          borderSide: BorderSide(color: tokens.danger, width: AppBorder.focus),
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

extension AppThemeMaterialTokens on ThemeData {
  AppTokens get appTokens =>
      extension<AppTokens>() ??
      (brightness == Brightness.dark ? AppTokens.dark : AppTokens.light);
}

class AppThemeScope extends StatelessWidget {
  final ThemeData data;
  final Widget child;

  const AppThemeScope({required this.data, required this.child, super.key});

  @override
  Widget build(BuildContext context) => Theme(
    data: data,
    child: MixScope.inherit(
      colors: AppMixTokens.colors(data.appTokens),
      child: child,
    ),
  );
}
