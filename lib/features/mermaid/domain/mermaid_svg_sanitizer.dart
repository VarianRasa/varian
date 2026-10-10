import 'dart:convert';

import 'package:xml/xml.dart';

import '../../../domain/models/mermaid_payload.dart';

/// Validates that a renderer-produced SVG is a passive, local drawing.
///
/// The sanitizer rejects rather than rewrites unsafe output. Keeping the
/// original output out of the widget on failure prevents a future SVG parser
/// change from turning a previously tolerated attribute into active content.
class MermaidSvgSanitizer {
  MermaidSvgSanitizer._();

  static const _allowedElements = <String>{
    'svg',
    'g',
    'defs',
    'style',
    'path',
    'image',
    'rect',
    'circle',
    'ellipse',
    'line',
    'polyline',
    'polygon',
    'text',
    'tspan',
    'marker',
    'symbol',
    'use',
    'clipPath',
    'mask',
    'filter',
    'feDropShadow',
    'linearGradient',
    'radialGradient',
    'stop',
    'switch',
    'title',
  };

  static const _allowedNamespaceValues = <String>{
    'http://www.w3.org/2000/svg',
    'http://www.w3.org/1999/xlink',
  };

  static const _allowedAttributes = <String>{
    'xmlns',
    'xmlns:xlink',
    'xlink:href',
    'href',
    'width',
    'height',
    'viewBox',
    'preserveAspectRatio',
    'fill',
    'fill-opacity',
    'fill-rule',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-miterlimit',
    'stroke-dasharray',
    'color',
    'stroke-dashoffset',
    'stroke-opacity',
    'stop-color',
    'stop-opacity',
    'gradientUnits',
    'spreadMethod',
    'opacity',
    'transform',
    'transform-origin',
    'd',
    'points',
    'x',
    'y',
    'x1',
    'y1',
    'x2',
    'y2',
    'cx',
    'cy',
    'r',
    'rx',
    'ry',
    'dx',
    'dy',
    'offset',
    'stdDeviation',
    'flood-color',
    'flood-opacity',
    'class',
    'id',
    'name',
    'role',
    'aria-roledescription',
    'aria-label',
    'alignment-baseline',
    'dominant-baseline',
    'font-family',
    'font-size',
    'font-weight',
    'font-style',
    'lengthAdjust',
    'letter-spacing',
    'text-anchor',
    'textLength',
    'marker-start',
    'marker-mid',
    'marker-end',
    'markerHeight',
    'markerWidth',
    'markerUnits',
    'orient',
    'refX',
    'refY',
    'clip-rule',
    'clip-path',
    'mask',
    'filter',
    'overflow',
    'shape-rendering',
    'style',
    'xml:space',
  };

  /// Converts the safe stylesheet subset emitted by Mermaid into inline SVG
  /// styles understood by Flutter's SVG parser.
  ///
  /// Mermaid emits presentation rules in a `<style>` block. Flutter's
  /// cross-platform SVG parser does not apply those CSS selectors, which
  /// otherwise leaves shapes black and text invisible. Unsupported CSS is
  /// ignored; unsafe SVG is still rejected by [sanitize].
  static String normalizeForFlutter(String svg) {
    final safeSvg = sanitize(_flattenSafeForeignObjects(svg));
    if (!safeSvg.contains('<style')) return safeSvg;

    return _inlineStyles(safeSvg);
  }

  static String _inlineStyles(String safeSvg) {
    final document = XmlDocument.parse(safeSvg);
    final styleElements = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'style')
        .toList();
    if (styleElements.isEmpty) return safeSvg;

    final rules = <_MermaidCssRule>[];
    var ruleOrder = 0;
    for (final styleElement in styleElements) {
      final css = styleElement.innerText.replaceAll(
        RegExp(r'/\*[\s\S]*?\*/'),
        '',
      );
      if (utf8.encode(css).length > MermaidSourceLimits.maxSvgCssBytes) {
        throw const MermaidSvgSecurityException('SVG_CSS_TOO_LARGE');
      }
      for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
        if (rules.length >= MermaidSourceLimits.maxSvgCssRules) {
          throw const MermaidSvgSecurityException('SVG_CSS_TOO_COMPLEX');
        }
        final selectorText = match.group(1)?.trim() ?? '';
        if (selectorText.isEmpty || selectorText.startsWith('@')) continue;
        if (selectorText.length > MermaidSourceLimits.maxSvgCssSelectorLength) {
          throw const MermaidSvgSecurityException('SVG_CSS_SELECTOR_TOO_LARGE');
        }
        final declarationText = match.group(2) ?? '';
        if (declarationText.length >
            MermaidSourceLimits.maxSvgCssDeclarationLength) {
          throw const MermaidSvgSecurityException(
            'SVG_CSS_DECLARATION_TOO_LARGE',
          );
        }
        final declarations = _parseCssDeclarations(declarationText);
        if (declarations.isEmpty) continue;
        for (final selector in selectorText.split(',')) {
          if (rules.length >= MermaidSourceLimits.maxSvgCssRules) {
            throw const MermaidSvgSecurityException('SVG_CSS_TOO_COMPLEX');
          }
          final normalizedSelector = selector.trim();
          final selectorWithoutRoot = normalizedSelector.replaceAll(
            ':root',
            '',
          );
          if (normalizedSelector.isEmpty ||
              normalizedSelector.length >
                  MermaidSourceLimits.maxSvgCssSelectorLength ||
              selectorWithoutRoot.contains(':') ||
              normalizedSelector.contains('+') ||
              normalizedSelector.contains('~')) {
            continue;
          }
          rules.add(
            _MermaidCssRule(
              selector: normalizedSelector,
              declarations: declarations,
              specificity: _cssSpecificity(normalizedSelector),
              order: ruleOrder++,
            ),
          );
        }
      }
    }

    var matchChecks = 0;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'style') continue;
      final declarations = <String, _MermaidCssDeclaration>{};
      for (final declaration in _parseCssDeclarations(
        element.getAttribute('style') ?? '',
      ).entries) {
        declarations[declaration.key] = _MermaidCssDeclaration(
          value: declaration.value,
          specificity: 10000,
          order: -1,
        );
      }
      for (final rule in rules) {
        if (++matchChecks > MermaidSourceLimits.maxSvgCssMatchChecks) {
          throw const MermaidSvgSecurityException('SVG_CSS_TOO_COMPLEX');
        }
        if (!_matchesCssSelector(element, rule.selector)) continue;
        for (final declaration in rule.declarations.entries) {
          final existing = declarations[declaration.key];
          if (existing == null ||
              rule.specificity > existing.specificity ||
              (rule.specificity == existing.specificity &&
                  rule.order >= existing.order)) {
            declarations[declaration.key] = _MermaidCssDeclaration(
              value: declaration.value,
              specificity: rule.specificity,
              order: rule.order,
            );
          }
        }
      }
      if (declarations.isNotEmpty) {
        element.setAttribute(
          'style',
          declarations.entries
              .map((entry) => '${entry.key}:${entry.value.value}')
              .join(';'),
        );
      }
    }

    for (final styleElement in styleElements) {
      styleElement.parent?.children.remove(styleElement);
    }
    return sanitize(document.toXmlString());
  }

  /// Replaces Mermaid's passive HTML labels with equivalent SVG text nodes.
  ///
  /// Mermaid uses `foreignObject` for labels in several diagram families. The
  /// canvas converter and Flutter SVG widget intentionally do not accept HTML,
  /// so only the bounded text-only subset is flattened before normal SVG
  /// validation. Any other embedded element or attribute fails closed.
  static String _flattenSafeForeignObjects(String svg) {
    if (!RegExp(r'<foreignObject\b', caseSensitive: false).hasMatch(svg)) {
      return svg;
    }

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(svg);
    } catch (_) {
      throw const MermaidSvgSecurityException('SVG_INVALID_XML');
    }

    final foreignObjects = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local.toLowerCase() == 'foreignobject')
        .toList();
    for (final foreignObject in foreignObjects) {
      _validateForeignObject(foreignObject);
      final text = _foreignObjectText(foreignObject).trim();
      if (text.isEmpty) {
        foreignObject.remove();
        continue;
      }

      final x = _svgNumber(foreignObject.getAttribute('x')) ?? 0;
      final y = _svgNumber(foreignObject.getAttribute('y')) ?? 0;
      final width = _svgNumber(foreignObject.getAttribute('width')) ?? 0;
      final height = _svgNumber(foreignObject.getAttribute('height')) ?? 0;
      if (!x.isFinite ||
          !y.isFinite ||
          width <= 0 ||
          height <= 0 ||
          !width.isFinite ||
          !height.isFinite) {
        throw const MermaidSvgSecurityException('SVG_GEOMETRY_INVALID');
      }
      final classes = <String>{};
      final styleDeclarations = <String, String>{};
      for (final element in [
        foreignObject,
        ...foreignObject.descendants.whereType<XmlElement>(),
      ]) {
        final classValue = element.getAttribute('class');
        if (classValue != null) {
          classes.addAll(
            classValue.split(RegExp(r'\s+')).where((value) => value.isNotEmpty),
          );
        }
        styleDeclarations.addAll(
          _parseCssDeclarations(element.getAttribute('style') ?? ''),
        );
      }

      final attributes = <XmlAttribute>[
        XmlAttribute(XmlName('x'), (x + width / 2).toString()),
        XmlAttribute(XmlName('y'), (y + height / 2).toString()),
        XmlAttribute(XmlName('text-anchor'), 'middle'),
        XmlAttribute(XmlName('dominant-baseline'), 'central'),
        if (foreignObject.getAttribute('transform') != null)
          XmlAttribute(
            XmlName('transform'),
            foreignObject.getAttribute('transform')!,
          ),
        if (classes.isNotEmpty)
          XmlAttribute(XmlName('class'), classes.join(' ')),
        if (styleDeclarations.isNotEmpty)
          XmlAttribute(
            XmlName('style'),
            styleDeclarations.entries
                .map((entry) => '${entry.key}:${entry.value}')
                .join(';'),
          ),
      ];
      foreignObject.replace(
        XmlElement(XmlName('text'), attributes, [XmlText(text)], false),
      );
    }

    final switches = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local.toLowerCase() == 'switch')
        .toList();
    for (final switchElement in switches) {
      final candidates = switchElement.children.whereType<XmlElement>().toList(
        growable: false,
      );
      if (candidates.any((element) => element.name.local != 'text')) {
        throw const MermaidSvgSecurityException('SVG_SWITCH_NOT_ALLOWED');
      }
      if (candidates.isEmpty) {
        switchElement.remove();
      } else {
        switchElement.replace(candidates.first.copy());
      }
    }
    return document.toXmlString();
  }

  static void _validateForeignObject(XmlElement foreignObject) {
    const allowedElements = {
      'foreignobject',
      'div',
      'span',
      'p',
      'br',
      'tspan',
    };
    const allowedAttributes = {
      'xmlns',
      'class',
      'style',
      'x',
      'y',
      'width',
      'height',
      'dx',
      'dy',
      'transform',
    };
    for (final element in [
      foreignObject,
      ...foreignObject.descendants.whereType<XmlElement>(),
    ]) {
      if (!allowedElements.contains(element.name.local.toLowerCase())) {
        throw const MermaidSvgSecurityException('SVG_HTML_NOT_ALLOWED');
      }
      for (final attribute in element.attributes) {
        final name = attribute.name.qualified.toLowerCase();
        if (!allowedAttributes.contains(name) &&
            !allowedAttributes.contains(attribute.name.local.toLowerCase())) {
          throw const MermaidSvgSecurityException('SVG_ATTRIBUTE_NOT_ALLOWED');
        }
        if (name == 'xmlns') {
          if (!_allowedNamespaceValues.contains(attribute.value.trim()) &&
              attribute.value.trim() != 'http://www.w3.org/1999/xhtml') {
            throw const MermaidSvgSecurityException(
              'SVG_NAMESPACE_NOT_ALLOWED',
            );
          }
          continue;
        }
        if (name == 'style' && !_isSafeStyle(attribute.value)) {
          throw const MermaidSvgSecurityException('SVG_STYLE_NOT_ALLOWED');
        }
        final lowerValue = attribute.value.toLowerCase();
        if (lowerValue.contains('javascript:') ||
            lowerValue.contains('http://') ||
            lowerValue.contains('https://') ||
            lowerValue.contains('data:')) {
          throw const MermaidSvgSecurityException('SVG_ACTIVE_REFERENCE');
        }
      }
    }
  }

  static String _foreignObjectText(XmlNode node) {
    if (node is XmlText) return node.value;
    if (node is! XmlElement) return '';
    final name = node.name.local.toLowerCase();
    if (name == 'br') return '\n';
    final content = node.children.map(_foreignObjectText).join();
    return name == 'p' ? '$content\n' : content;
  }

  static double? _svgNumber(String? raw) {
    if (raw == null) return null;
    final value = double.tryParse(raw.trim().replaceFirst(RegExp(r'px$'), ''));
    return value != null && value.isFinite ? value : null;
  }

  static bool _isSafeDataImage(String value) {
    final match = RegExp(
      r'^data:image/png;base64,([A-Za-z0-9+/=\s]+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return false;

    final encoded = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty || encoded.length > MermaidSourceLimits.maxSvgBytes) {
      return false;
    }
    try {
      final bytes = base64Decode(encoded);
      return bytes.length >= 8 &&
          bytes.length <= MermaidSourceLimits.maxSvgBytes &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A;
    } on FormatException {
      return false;
    }
  }

  static String sanitize(String svg) {
    if (utf8.encode(svg).length > MermaidSourceLimits.maxSvgBytes) {
      throw const MermaidSvgSecurityException('SVG_TOO_LARGE');
    }
    if (svg.trim().isEmpty) {
      throw const MermaidSvgSecurityException('SVG_EMPTY');
    }

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(svg);
    } catch (_) {
      throw const MermaidSvgSecurityException('SVG_INVALID_XML');
    }

    final root = document.rootElement;
    if (root.name.local != 'svg') {
      throw const MermaidSvgSecurityException('SVG_ROOT_NOT_ALLOWED');
    }

    var elementCount = 0;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (++elementCount > MermaidSourceLimits.maxSvgElements) {
        throw const MermaidSvgSecurityException('SVG_TOO_COMPLEX');
      }
      final elementName = element.name.local;
      if (!_allowedElements.contains(elementName)) {
        throw MermaidSvgSecurityException(
          'SVG_ELEMENT_NOT_ALLOWED:$elementName',
        );
      }
      if (elementName == 'style') {
        if (utf8.encode(element.innerText).length >
            MermaidSourceLimits.maxSvgCssBytes) {
          throw const MermaidSvgSecurityException('SVG_CSS_TOO_LARGE');
        }
        if (!_isSafeStyle(element.innerText)) {
          throw const MermaidSvgSecurityException('SVG_STYLE_NOT_ALLOWED');
        }
      }
      for (final attribute in element.attributes) {
        final name = attribute.name.local;
        final qualifiedName = attribute.name.qualified;
        if (!_allowedAttributes.contains(qualifiedName) &&
            !_allowedAttributes.contains(name) &&
            !name.startsWith('data-')) {
          throw MermaidSvgSecurityException(
            'SVG_ATTRIBUTE_NOT_ALLOWED:$elementName:$qualifiedName',
          );
        }
        final value = attribute.value.trim();
        if (qualifiedName == 'xlink:href' || name == 'href' || name == 'src') {
          if (elementName == 'image' &&
              qualifiedName == 'xlink:href' &&
              _isSafeDataImage(value)) {
            continue;
          }
          if (elementName == 'use' && _isLocalReference(value)) continue;
          throw const MermaidSvgSecurityException('SVG_EXTERNAL_REFERENCE');
        }
        if (qualifiedName == 'xmlns' || qualifiedName == 'xmlns:xlink') {
          if (!_allowedNamespaceValues.contains(value)) {
            throw const MermaidSvgSecurityException(
              'SVG_NAMESPACE_NOT_ALLOWED',
            );
          }
          continue;
        }
        final lowerValue = value.toLowerCase();
        if (lowerValue.contains('javascript:') ||
            lowerValue.contains('expression(') ||
            lowerValue.contains('@import') ||
            lowerValue.contains('http://') ||
            lowerValue.contains('https://') ||
            lowerValue.contains('data:')) {
          throw const MermaidSvgSecurityException('SVG_ACTIVE_REFERENCE');
        }
        if (qualifiedName == 'style' && !_isSafeStyle(value)) {
          throw const MermaidSvgSecurityException('SVG_STYLE_NOT_ALLOWED');
        }
        if (qualifiedName == 'clip-path' ||
            qualifiedName == 'mask' ||
            qualifiedName == 'filter' ||
            qualifiedName.startsWith('marker-')) {
          if (!_isLocalReference(value)) {
            throw const MermaidSvgSecurityException('SVG_REFERENCE_NOT_LOCAL');
          }
        }
      }
    }

    return svg;
  }

  static Map<String, String> _parseCssDeclarations(String declarations) {
    if (declarations.length > MermaidSourceLimits.maxSvgCssDeclarationLength) {
      throw const MermaidSvgSecurityException('SVG_CSS_DECLARATION_TOO_LARGE');
    }
    final result = <String, String>{};
    for (final declaration in _splitCssDeclarations(declarations)) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;
      final property = declaration.substring(0, separator).trim().toLowerCase();
      final value = declaration.substring(separator + 1).trim();
      if (!_allowedCssProperties.contains(property) || value.isEmpty) continue;
      result[property] = value.replaceAll(RegExp(r'\s+'), ' ');
    }
    return result;
  }

  static Iterable<String> _splitCssDeclarations(String declarations) sync* {
    var start = 0;
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var index = 0; index < declarations.length; index++) {
      final code = declarations.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (quote != 0) {
        if (code == 0x5C) {
          escaped = true;
        } else if (code == quote) {
          quote = 0;
        }
        continue;
      }
      if (code == 0x27 || code == 0x22) {
        quote = code;
      } else if (code == 0x28) {
        depth++;
      } else if (code == 0x29) {
        depth--;
        if (depth < 0) {
          throw const MermaidSvgSecurityException('SVG_CSS_NOT_ALLOWED');
        }
      } else if (code == 0x3B && depth == 0) {
        yield declarations.substring(start, index);
        start = index + 1;
      }
    }
    if (quote != 0 || depth != 0) {
      throw const MermaidSvgSecurityException('SVG_CSS_NOT_ALLOWED');
    }
    yield declarations.substring(start);
  }

  static int _cssSpecificity(String selector) {
    final ids = '#'.allMatches(selector).length;
    final classes = RegExp(r'[.\[]').allMatches(selector).length;
    final withoutClasses = selector.replaceAll(RegExp(r'[#.][\w-]+'), '');
    final elements = RegExp(
      r'\b[a-zA-Z][\w-]*\b',
    ).allMatches(withoutClasses).length;
    return ids * 100 + classes * 10 + elements;
  }

  static bool _matchesCssSelector(XmlElement element, String selector) {
    final normalized = selector
        .trim()
        .replaceAll(RegExp(r'\s*>\s*'), '>')
        .replaceAll(RegExp(r'\s+'), ' ');
    final tokens = RegExp(r'[^\s>]+|>')
        .allMatches(normalized)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    if (tokens.isEmpty || tokens.last == '>') return false;

    XmlElement? current = element;
    var index = tokens.length - 1;
    if (!_matchesSimpleSelector(current, tokens[index])) return false;
    index--;

    while (index >= 0) {
      if (tokens[index] == '>') {
        index--;
        if (index < 0) return false;
        current = current?.parent is XmlElement
            ? current!.parent as XmlElement
            : null;
        if (current == null ||
            !_matchesSimpleSelector(current, tokens[index])) {
          return false;
        }
        index--;
        continue;
      }

      final ancestorSelector = tokens[index];
      final parent = current?.parent;
      current = parent is XmlElement ? parent : null;
      while (current != null &&
          !_matchesSimpleSelector(current, ancestorSelector)) {
        final nextParent = current.parent;
        current = nextParent is XmlElement ? nextParent : null;
      }
      if (current == null) return false;
      index--;
    }
    return true;
  }

  static bool _matchesSimpleSelector(XmlElement element, String selector) {
    final isRoot = selector.contains(':root');
    final withoutRoot = selector.replaceAll(':root', '');
    if (isRoot && element.parent is! XmlDocument) return false;

    final tag = RegExp(r'^[a-zA-Z][\w-]*').firstMatch(withoutRoot)?.group(0);
    if (tag != null && element.name.local != tag) return false;
    for (final id in RegExp(r'#([\w-]+)').allMatches(withoutRoot)) {
      if (element.getAttribute('id') != id.group(1)) return false;
    }
    for (final classMatch in RegExp(r'\.([\w-]+)').allMatches(withoutRoot)) {
      final classes = (element.getAttribute('class') ?? '')
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (!classes.contains(classMatch.group(1))) return false;
    }
    for (final attribute in RegExp(
      r'\[([\w:-]+)(?:(\$=|=)"([^"]*)")?\]',
    ).allMatches(withoutRoot)) {
      final name = attribute.group(1)!;
      final operator = attribute.group(2);
      final expected = attribute.group(3);
      final actual = element.getAttribute(name);
      if (actual == null) return false;
      if (operator == '=' && actual != expected) return false;
      if (operator == r'$=' && !actual.endsWith(expected ?? '')) return false;
    }
    return isRoot ||
        tag != null ||
        withoutRoot.contains('#') ||
        withoutRoot.contains('.') ||
        withoutRoot.contains('[');
  }

  static const _allowedCssProperties = <String>{
    'alignment-baseline',
    'color',
    'dominant-baseline',
    'fill',
    'fill-opacity',
    'fill-rule',
    'font-family',
    'font-size',
    'font-style',
    'font-weight',
    'letter-spacing',
    'marker-end',
    'marker-mid',
    'marker-start',
    'opacity',
    'stroke',
    'stroke-dasharray',
    'stroke-dashoffset',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-miterlimit',
    'stroke-opacity',
    'stroke-width',
    'text-anchor',
  };

  static bool _isLocalReference(String value) {
    final normalized = value.replaceAll(' ', '');
    return normalized.isEmpty ||
        normalized.startsWith('url(#') ||
        normalized.startsWith('#');
  }

  static bool _isSafeStyle(String value) {
    final withoutComments = value.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final lower = withoutComments.toLowerCase();
    final compact = lower.replaceAll(RegExp(r'\s+'), '');
    if (lower.contains('url(')) {
      final references = RegExp(
        r'url\(([^)]*)\)',
        caseSensitive: false,
      ).allMatches(withoutComments);
      if (references.any((match) => !_isLocalReference(match.group(1) ?? ''))) {
        return false;
      }
    }
    return !compact.contains('behavior:') &&
        !compact.contains('javascript:') &&
        !compact.contains('@import') &&
        !compact.contains('http://') &&
        !compact.contains('https://') &&
        !compact.contains('data:');
  }
}

class _MermaidCssRule {
  final String selector;
  final Map<String, String> declarations;
  final int specificity;
  final int order;

  const _MermaidCssRule({
    required this.selector,
    required this.declarations,
    required this.specificity,
    required this.order,
  });
}

class _MermaidCssDeclaration {
  final String value;
  final int specificity;
  final int order;

  const _MermaidCssDeclaration({
    required this.value,
    required this.specificity,
    required this.order,
  });
}
