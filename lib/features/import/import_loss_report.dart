enum ImportSourceFormat {
  json,
  mermaid,
  drawio,
  plantuml,
  markdown,
  csv,
  svg,
  imageBundle,
  pdf,
  pptx,
  file,
}

class ImportLossReport {
  final ImportSourceFormat format;
  final List<String> preserved;
  final List<String> lossy;
  final List<String> unsupported;

  const ImportLossReport({
    required this.format,
    this.preserved = const [],
    this.lossy = const [],
    this.unsupported = const [],
  });

  bool get isLossless => lossy.isEmpty && unsupported.isEmpty;

  List<String> get messages => [
    ...preserved.map((item) => 'Preserved: $item'),
    ...lossy.map((item) => 'Lossy: $item'),
    ...unsupported.map((item) => 'Unsupported: $item'),
  ];
}
