import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/mermaid/domain/mermaid_models.dart';
import 'package:varian/features/mermaid/domain/mermaid_svg_sanitizer.dart';

void main() {
  group('MermaidSourceLimits', () {
    test('accepts a bounded Mermaid source', () {
      final result = MermaidSourceLimits.validate('flowchart TD\nA --> B');

      expect(result, isNull);
    });

    test('rejects empty source with a user-safe diagnostic', () {
      final diagnostic = MermaidSourceLimits.validate('  \n');

      expect(diagnostic?.code, 'EMPTY_SOURCE');
      expect(diagnostic?.severity, MermaidDiagnosticSeverity.error);
    });

    test('rejects source over the byte limit before rendering', () {
      final diagnostic = MermaidSourceLimits.validate(
        'A' * (MermaidSourceLimits.maxSourceBytes + 1),
      );

      expect(diagnostic?.code, 'SOURCE_TOO_LARGE');
    });
  });

  group('MermaidRenderConfig', () {
    test('always sends strict security and the safe SVG pipeline', () {
      final json = const MermaidRenderConfig(
        theme: MermaidTheme.dark,
        direction: MermaidDirection.leftToRight,
      ).toOptionsJson();

      expect(json, contains('"securityLevel":"strict"'));
      expect(json, contains('"pipeline":"resvg-safe"'));
      expect(json, contains('"theme":"dark"'));
      expect(json, contains('"direction":"LR"'));
    });

    test('serializes every native theme under Merman site_config', () {
      const config = MermaidRenderConfig(
        direction: MermaidDirection.leftToRight,
        overrides: {
          'flowchart': {'nodeSpacing': 64},
          'themeVariables': {'primaryColor': '#112233'},
        },
      );

      for (final theme in MermaidTheme.values) {
        final options =
            jsonDecode(config.copyWith(theme: theme).toNativeOptionsJson())
                as Map<String, dynamic>;
        final siteConfig = options['site_config'] as Map<String, dynamic>;

        expect(options.containsKey('theme'), isFalse, reason: theme.value);
        expect(options['svg'], {'pipeline': 'resvg-safe'}, reason: theme.value);
        expect(siteConfig['theme'], theme.value, reason: theme.value);
        expect(siteConfig['direction'], 'LR', reason: theme.value);
        expect(siteConfig['flowchart'], {
          'nodeSpacing': 64,
        }, reason: theme.value);
        expect(siteConfig['themeVariables'], {
          'primaryColor': '#112233',
        }, reason: theme.value);
      }
    });
  });

  group('MermaidSvgSanitizer', () {
    test('keeps safe SVG structure and local references', () {
      const svg =
          '<svg width="100" height="50" viewBox="0 0 100 50">'
          '<defs><marker id="arrow"><path d="M0 0"/></marker></defs>'
          '<style>.node{fill:#fff}</style>'
          '<path class="node" marker-end="url(#arrow)" d="M0 0"/>'
          '<text x="2" y="10">Hello</text></svg>';

      expect(MermaidSvgSanitizer.sanitize(svg), svg);
    });

    test('inlines safe CSS rules for Flutter SVG rendering', () {
      const svg =
          '<svg id="diagram" xmlns="http://www.w3.org/2000/svg">'
          '<style>#diagram .node rect{fill:#ECECFF;stroke:#9370DB;stroke-width:1px;}'
          '#diagram .node .label text{fill:#333;}</style>'
          '<g class="node" id="node-a"><rect/>'
          '<g class="label"><text>Start</text></g></g></svg>';

      final normalized = MermaidSvgSanitizer.normalizeForFlutter(svg);

      expect(normalized, isNot(contains('<style>')));
      expect(normalized, contains('fill:#ECECFF'));
      expect(normalized, contains('stroke:#9370DB'));
      expect(normalized, contains('stroke-width:1px'));
      expect(normalized, contains('fill:#333'));
    });

    test('rejects active SVG content', () {
      expect(
        () => MermaidSvgSanitizer.sanitize(
          '<svg><script>alert(1)</script></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
      expect(
        () => MermaidSvgSanitizer.sanitize(
          '<svg><rect onclick="alert(1)"/></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
    });

    test('rejects external and executable references', () {
      expect(
        () => MermaidSvgSanitizer.sanitize(
          '<svg><image href="https://example.com/a.png"/></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
      expect(
        () => MermaidSvgSanitizer.sanitize(
          '<svg><path style="fill:url(https://example.com/a)"/></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
    });

    test('rejects comment-obfuscated external stylesheet directives', () {
      expect(
        () => MermaidSvgSanitizer.sanitize(
          '<svg><style>@im/**/port url(https://example.com/a.css);</style></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
    });

    test('rejects SVGs with excessive element counts', () {
      final shapes = List.filled(
        MermaidSourceLimits.maxSvgElements + 1,
        '<rect/>',
      ).join();

      expect(
        () => MermaidSvgSanitizer.normalizeForFlutter('<svg>$shapes</svg>'),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
    });

    test('rejects stylesheets with excessive rule counts', () {
      final rules = List.generate(
        MermaidSourceLimits.maxSvgCssRules + 1,
        (index) => '.node-$index{fill:#fff}',
      ).join();

      expect(
        () => MermaidSvgSanitizer.normalizeForFlutter(
          '<svg><style>$rules</style></svg>',
        ),
        throwsA(isA<MermaidSvgSecurityException>()),
      );
    });
  });
}
