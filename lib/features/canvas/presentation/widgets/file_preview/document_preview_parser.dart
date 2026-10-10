import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../document_conversion/document_source_resolver.dart';

class DocumentPreview {
  const DocumentPreview({required this.sections});

  final List<String> sections;
}

const maxDocumentArchiveEntries = 2048;
const maxDocumentArchiveEntryBytes = 16 * 1024 * 1024;
const maxDocumentArchiveExpandedBytes = 64 * 1024 * 1024;

DocumentPreview parseDocumentPreview(Uint8List bytes, String extension) {
  if (bytes.isEmpty || bytes.length > maxDocumentPreviewBytes) {
    throw const FormatException('Document archive exceeds the preview limit.');
  }
  _validateArchiveSignature(bytes);

  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Invalid document archive.');
  }
  _validateArchiveEntries(archive);

  final ext = extension.toLowerCase().replaceFirst('.', '');
  final sections = switch (ext) {
    'docx' => _parseDocx(archive),
    'xlsx' => _parseXlsx(archive),
    'pptx' => _parsePptx(archive),
    'odt' || 'ods' || 'odp' => _parseOdf(archive),
    _ => throw UnsupportedError('Unsupported document format: $ext'),
  };
  if (sections.isEmpty) {
    throw const FormatException('No readable document content found.');
  }
  return DocumentPreview(sections: sections);
}

List<String> _parseDocx(Archive archive) {
  final document = _xmlFile(archive, 'word/document.xml');
  final sections = <String>[];
  for (final element in document.descendants.whereType<XmlElement>()) {
    if (_localName(element) == 'p' &&
        element.ancestors.whereType<XmlElement>().every(
          (parent) => _localName(parent) != 'tc',
        )) {
      _addText(sections, _textNodes(element, 't'));
    }
    if (_localName(element) == 'tr') {
      final cells = element.childElements
          .where((child) => _localName(child) == 'tc')
          .map((cell) => _textNodes(cell, 't'))
          .where((text) => text.isNotEmpty)
          .toList();
      if (cells.isNotEmpty) sections.add(cells.join(' | '));
    }
  }
  return sections;
}

List<String> _parseXlsx(Archive archive) {
  final shared = <String>[];
  final sharedFile = _findFile(archive, 'xl/sharedStrings.xml');
  if (sharedFile != null) {
    final xml = XmlDocument.parse(utf8.decode(sharedFile.content as List<int>));
    for (final item in xml.descendants.whereType<XmlElement>().where(
      (element) => _localName(element) == 'si',
    )) {
      shared.add(_textNodes(item, 't'));
    }
  }

  final sheets =
      archive.files
          .where(
            (file) =>
                file.isFile &&
                RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  final sections = <String>[];
  for (var index = 0; index < sheets.length; index++) {
    sections.add('Sheet ${index + 1}');
    final xml = XmlDocument.parse(
      utf8.decode(sheets[index].content as List<int>),
    );
    for (final row in xml.descendants.whereType<XmlElement>().where(
      (element) => _localName(element) == 'row',
    )) {
      final cells = row.childElements
          .where((element) => _localName(element) == 'c')
          .map((cell) {
            final value = cell.descendants
                .whereType<XmlElement>()
                .where((element) => _localName(element) == 'v')
                .map((element) => element.innerText)
                .firstOrNull;
            if (value == null) return '';
            if (cell.getAttribute('t') == 's') {
              final sharedIndex = int.tryParse(value);
              if (sharedIndex != null && sharedIndex < shared.length) {
                return shared[sharedIndex];
              }
            }
            return value;
          })
          .toList();
      if (cells.any((cell) => cell.isNotEmpty)) sections.add(cells.join(' | '));
    }
  }
  return sections;
}

List<String> _parsePptx(Archive archive) {
  final slides =
      archive.files
          .where(
            (file) =>
                file.isFile &&
                RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  final sections = <String>[];
  for (var index = 0; index < slides.length; index++) {
    final xml = XmlDocument.parse(
      utf8.decode(slides[index].content as List<int>),
    );
    sections.add('Slide ${index + 1}');
    for (final paragraph in xml.descendants.whereType<XmlElement>().where(
      (element) => _localName(element) == 'p',
    )) {
      _addText(sections, _textNodes(paragraph, 't'));
    }
  }
  return sections;
}

List<String> _parseOdf(Archive archive) {
  final document = _xmlFile(archive, 'content.xml');
  final sections = <String>[];
  for (final element in document.descendants.whereType<XmlElement>()) {
    if ({'h', 'p'}.contains(_localName(element))) {
      _addText(sections, element.innerText.trim());
    }
    if (_localName(element) == 'table-row') {
      final cells = element.childElements
          .where((child) => _localName(child) == 'table-cell')
          .map((cell) => cell.innerText.trim())
          .toList();
      if (cells.any((cell) => cell.isNotEmpty)) sections.add(cells.join(' | '));
    }
  }
  return sections;
}

XmlDocument _xmlFile(Archive archive, String name) {
  final file = _findFile(archive, name);
  if (file == null) throw FormatException('Missing $name.');
  try {
    return XmlDocument.parse(utf8.decode(file.content as List<int>));
  } catch (_) {
    throw FormatException('Invalid $name.');
  }
}

void _validateArchiveSignature(Uint8List bytes) {
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      (bytes[2] != 0x03 && bytes[2] != 0x05 && bytes[2] != 0x07) ||
      (bytes[3] != 0x04 && bytes[3] != 0x06 && bytes[3] != 0x08)) {
    throw const FormatException('Document preview requires a ZIP archive.');
  }
}

void _validateArchiveEntries(Archive archive) {
  if (archive.files.length > maxDocumentArchiveEntries) {
    throw const FormatException('Document archive contains too many entries.');
  }
  var expandedBytes = 0;
  for (final file in archive.files) {
    final name = file.name.replaceAll('\\', '/');
    if (name.startsWith('/') ||
        name
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw const FormatException('Document archive contains an unsafe path.');
    }
    if (!file.isFile) continue;
    final length = (file.content as List<int>).length;
    if (length > maxDocumentArchiveEntryBytes ||
        expandedBytes > maxDocumentArchiveExpandedBytes - length) {
      throw const FormatException(
        'Document archive expands beyond the preview limit.',
      );
    }
    expandedBytes += length;
  }
}

ArchiveFile? _findFile(Archive archive, String name) {
  for (final file in archive.files) {
    if (file.isFile && file.name == name) return file;
  }
  return null;
}

String _localName(XmlElement element) => element.name.local;

String _textNodes(XmlElement element, String name) => element.descendants
    .whereType<XmlElement>()
    .where((child) => _localName(child) == name)
    .map((child) => child.innerText)
    .join()
    .trim();

void _addText(List<String> sections, String text) {
  if (text.isNotEmpty) sections.add(text);
}
