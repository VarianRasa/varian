import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable diagram themes exposed by the local Mermaid renderers.
enum MermaidTheme {
  defaultTheme('default'),
  base('base'),
  dark('dark'),
  forest('forest'),
  neutral('neutral'),
  neo('neo'),
  neoDark('neo-dark'),
  redux('redux'),
  reduxDark('redux-dark'),
  reduxColor('redux-color'),
  reduxDarkColor('redux-dark-color');

  const MermaidTheme(this.value);

  final String value;

  static MermaidTheme fromValue(Object? value) =>
      MermaidTheme.values.firstWhere(
        (theme) => theme.value == value,
        orElse: () => MermaidTheme.defaultTheme,
      );
}

enum MermaidDirection {
  topDown('TD'),
  bottomTop('BT'),
  leftToRight('LR'),
  rightToLeft('RL');

  const MermaidDirection(this.value);

  final String value;

  static MermaidDirection? fromValue(Object? value) {
    for (final direction in values) {
      if (direction.value == value) return direction;
    }
    return null;
  }
}

enum MermaidRenderMode { sourcePreview, native }

enum MermaidConversionStatus { notConverted, converted, nativeEdited }

enum MermaidDiagnosticSeverity { info, warning, error }

class MermaidDiagnostic {
  final String code;
  final String message;
  final int? line;
  final int? column;
  final MermaidDiagnosticSeverity severity;

  const MermaidDiagnostic({
    required this.code,
    required this.message,
    this.line,
    this.column,
    this.severity = MermaidDiagnosticSeverity.error,
  });

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'line': line,
    'column': column,
    'severity': severity.name,
  };

  factory MermaidDiagnostic.fromJson(Map<String, dynamic> json) {
    final rawMessage = json['message'] as String? ?? 'Mermaid error.';
    return MermaidDiagnostic(
      code: json['code'] as String? ?? 'MERMAID_ERROR',
      message: rawMessage.length > 1000
          ? rawMessage.substring(0, 1000)
          : rawMessage,
      line: (json['line'] as num?)?.toInt(),
      column: (json['column'] as num?)?.toInt(),
      severity: MermaidDiagnosticSeverity.values.firstWhere(
        (value) => value.name == json['severity'],
        orElse: () => MermaidDiagnosticSeverity.error,
      ),
    );
  }
}

/// Safe configuration passed to a Mermaid renderer.
///
/// The renderer owns the security level and SVG pipeline. [overrides] is
/// intentionally limited to JSON-like values and is never treated as code.
class MermaidRenderConfig {
  final MermaidTheme theme;
  final MermaidDirection? direction;
  final Map<String, dynamic> overrides;

  const MermaidRenderConfig({
    this.theme = MermaidTheme.defaultTheme,
    this.direction,
    this.overrides = const {},
  });

  Map<String, dynamic> get safeOverrides => _safeOverrides(overrides);

  /// Stable identity for render-affecting configuration.
  ///
  /// The key is persisted with cached SVG so a preview cannot display an
  /// artifact rendered with a different theme, direction, or override set.
  String get cacheKey => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'theme': theme.value,
            'direction': direction?.value,
            'overrides': safeOverrides,
          }),
        ),
      )
      .toString();

  String toOptionsJson({String svgPipeline = 'resvg-safe'}) {
    final config = <String, dynamic>{
      'securityLevel': 'strict',
      'theme': theme.value,
      'svg': {'pipeline': svgPipeline},
      ..._safeOverrides(overrides),
    };
    if (direction != null) config['direction'] = direction!.value;
    return jsonEncode(config);
  }

  /// Serializes options for the native Merman binding.
  ///
  /// Merman keeps Mermaid configuration under [site_config], unlike the Web
  /// Mermaid API, while SVG pipeline options stay at the binding root.
  String toNativeOptionsJson({String svgPipeline = 'resvg-safe'}) {
    final siteConfig = <String, dynamic>{
      'theme': theme.value,
      ..._safeOverrides(overrides),
    };
    if (direction != null) siteConfig['direction'] = direction!.value;
    return jsonEncode({
      'site_config': siteConfig,
      'svg': {'pipeline': svgPipeline},
    });
  }

  Map<String, dynamic> toJson() => {
    'theme': theme.value,
    'direction': direction?.value,
    'overrides': _safeOverrides(overrides),
  };

  factory MermaidRenderConfig.fromJson(Map<String, dynamic> json) {
    final rawOverrides = json['overrides'];
    return MermaidRenderConfig(
      theme: MermaidTheme.fromValue(json['theme']),
      direction: MermaidDirection.fromValue(json['direction']),
      overrides: rawOverrides is Map
          ? _safeOverrides(rawOverrides)
          : const <String, dynamic>{},
    );
  }

  MermaidRenderConfig copyWith({
    MermaidTheme? theme,
    Object? direction = _sentinel,
    Map<String, dynamic>? overrides,
  }) {
    return MermaidRenderConfig(
      theme: theme ?? this.theme,
      direction: direction == _sentinel
          ? this.direction
          : direction as MermaidDirection?,
      overrides: overrides ?? this.overrides,
    );
  }

  static const Object _sentinel = Object();

  static Map<String, dynamic> _safeOverrides(Map raw) {
    final result = <String, dynamic>{};
    for (final entry in raw.entries.take(32)) {
      final key = entry.key;
      if (key is! String || !_allowedOverrideKeys.contains(key)) continue;
      final value = _safeJsonValue(entry.value, depth: 0);
      if (value != null) result[key] = value;
    }
    return result;
  }

  static dynamic _safeJsonValue(Object? value, {required int depth}) {
    if (value == null || value is String || value is num || value is bool) {
      if (value is String && value.length > 200) return value.substring(0, 200);
      return value;
    }
    if (depth >= 2) return null;
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final entry in value.entries.take(32)) {
        if (entry.key is! String) continue;
        final nested = _safeJsonValue(entry.value, depth: depth + 1);
        if (nested != null) map[entry.key as String] = nested;
      }
      return map;
    }
    if (value is Iterable) {
      return value
          .take(32)
          .map((item) => _safeJsonValue(item, depth: depth + 1))
          .where((item) => item != null)
          .toList(growable: false);
    }
    return null;
  }

  static const _allowedOverrideKeys = <String>{
    'flowchart',
    'sequence',
    'class',
    'state',
    'er',
    'gantt',
    'gitGraph',
    'journey',
    'mindmap',
    'pie',
    'quadrantChart',
    'radar',
    'sankey',
    'timeline',
    'xyChart',
    'themeVariables',
  };
}

class MermaidSourceLimits {
  MermaidSourceLimits._();

  static const maxSourceBytes = 256 * 1024;
  static const maxSourceLines = 4000;
  static const maxLineLength = 16 * 1024;
  static const maxSvgBytes = 5 * 1024 * 1024;
  static const maxSvgElements = 20000;
  static const maxSvgUseDepth = 16;
  static const maxSvgUseExpansions = 512;
  static const maxSvgCssBytes = 256 * 1024;
  static const maxSvgCssRules = 2048;
  static const maxSvgCssSelectorLength = 512;
  static const maxSvgCssDeclarationLength = 4096;
  static const maxSvgCssMatchChecks = 500000;
  static const maxSvgEdgePointsBytes = 64 * 1024;
  static const maxSvgEdgePoints = 256;
  static const maxSvgCoordinate = 10000000.0;
  static const maxSvgEndpointDistance = 48.0;
  static const maxSvgEndpointAmbiguity = 1.0;
  static const maxGeneratedObjects = 2000;

  static MermaidDiagnostic? validate(String source) {
    if (source.trim().isEmpty) {
      return const MermaidDiagnostic(
        code: 'EMPTY_SOURCE',
        message: 'Enter Mermaid source before rendering.',
      );
    }
    if (source.contains('\u0000')) {
      return const MermaidDiagnostic(
        code: 'INVALID_SOURCE_CHARACTERS',
        message: 'Mermaid source contains an invalid control character.',
      );
    }
    if (utf8.encode(source).length > maxSourceBytes) {
      return const MermaidDiagnostic(
        code: 'SOURCE_TOO_LARGE',
        message: 'Mermaid source is too large to render.',
      );
    }
    final lines = source.split('\n');
    if (lines.length > maxSourceLines) {
      return const MermaidDiagnostic(
        code: 'SOURCE_TOO_MANY_LINES',
        message: 'Mermaid source contains too many lines.',
      );
    }
    if (lines.any((line) => line.length > maxLineLength)) {
      return const MermaidDiagnostic(
        code: 'SOURCE_LINE_TOO_LONG',
        message: 'A Mermaid source line is too long.',
      );
    }
    return null;
  }
}

class MermaidSvgSecurityException implements Exception {
  final String code;

  const MermaidSvgSecurityException(this.code);

  @override
  String toString() => 'MermaidSvgSecurityException($code)';
}

class MermaidPayloadData {
  MermaidPayloadData._();

  static const maxCachedSvgBytes = MermaidSourceLimits.maxSvgBytes;

  static String? boundedSvg(String? svg) {
    if (svg == null || utf8.encode(svg).length > maxCachedSvgBytes) return null;
    return svg;
  }

  static String? boundedCacheKey(Object? value) {
    if (value is! String ||
        value.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String? boundedRendererVersion(Object? value) {
    if (value is! String || value.isEmpty || value.length > 128) return null;
    return value;
  }
}
