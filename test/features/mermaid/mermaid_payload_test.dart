import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  test(
    'MermaidPayload round-trips source, config, cache, and conversion state',
    () {
      const renderConfig = MermaidRenderConfig(
        theme: MermaidTheme.dark,
        direction: MermaidDirection.leftToRight,
        overrides: {
          'flowchart': {'nodeSpacing': 64},
        },
      );
      final payload = MermaidPayload(
        source: 'flowchart LR\nA --> B',
        diagramType: 'flowchart',
        theme: renderConfig.theme,
        direction: renderConfig.direction,
        config: renderConfig.safeOverrides,

        renderMode: MermaidRenderMode.native,
        sourceRevision: 3,
        conversionStatus: MermaidConversionStatus.nativeEdited,
        nativeNodeIds: const ['native-a'],
        nativeEdgeIds: const ['native-edge'],
        cachedSvg: '<svg/>',
        cachedSvgRevision: 3,
        cachedSvgConfigKey: renderConfig.cacheKey,
        rendererVersion: '0.7.0',
        lastError: const MermaidDiagnostic(
          code: 'WARNING',
          message: 'Unsupported style.',
          severity: MermaidDiagnosticSeverity.warning,
        ),
      );

      final restored = MermaidPayload.fromJson(payload.toJson());

      expect(restored.source, payload.source);
      expect(restored.diagramType, 'flowchart');
      expect(restored.theme, MermaidTheme.dark);
      expect(restored.direction, MermaidDirection.leftToRight);
      expect(restored.config['flowchart'], {'nodeSpacing': 64});
      expect(restored.renderMode, MermaidRenderMode.native);
      expect(restored.sourceRevision, 3);
      expect(restored.conversionStatus, MermaidConversionStatus.nativeEdited);
      expect(restored.nativeNodeIds, ['native-a']);
      expect(restored.nativeEdgeIds, ['native-edge']);
      expect(restored.cachedSvg, '<svg/>');
      expect(restored.cachedSvgRevision, 3);
      expect(restored.cachedSvgConfigKey, renderConfig.cacheKey);
      expect(restored.rendererVersion, '0.7.0');
      expect(restored.lastError?.severity, MermaidDiagnosticSeverity.warning);
    },
  );

  test(
    'MermaidPayload drops executable and oversized configuration values',
    () {
      final restored = MermaidPayload.fromJson({
        'source': 'flowchart TD\nA --> B',
        'config': {
          'flowchart': {'nodeSpacing': 50},
          'onRender': 'javascript:alert(1)',
          'unknown': {'nested': true},
        },
        'cachedSvg': '<svg/>',
      });

      expect(restored.config.containsKey('flowchart'), isTrue);
      expect(restored.config.containsKey('onRender'), isFalse);
      expect(restored.config.containsKey('unknown'), isFalse);
    },
  );

  test('MermaidPayload bounds renderer identity metadata', () {
    final restored = MermaidPayload.fromJson({
      'source': 'flowchart TD\\nA --> B',
      'rendererVersion': 'x' * 129,
    });

    expect(restored.rendererVersion, isNull);
  });

  test('legacy node JSON still defaults Mermaid fields safely', () {
    final restored = MermaidPayload.fromJson({
      'source': 'flowchart TD\nA --> B',
    });

    expect(restored.theme, MermaidTheme.defaultTheme);
    expect(restored.renderMode, MermaidRenderMode.sourcePreview);
    expect(restored.conversionStatus, MermaidConversionStatus.notConverted);
    expect(restored.sourceRevision, 0);
  });
}
