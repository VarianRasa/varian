import 'package:varian/domain/models/node_payload.dart';

enum FilePreviewType {
  pdf,
  image,
  text,
  audio,
  video,
  html,
  document,
  external,
}

const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
const _textExtensions = {
  'txt',
  'md',
  'markdown',
  'json',
  'xml',
  'csv',
  'log',
  'dart',
  'js',
  'ts',
  'jsx',
  'tsx',
  'css',
  'scss',
  'sass',
  'less',
  'yaml',
  'yml',
  'toml',
  'ini',
  'conf',
  'py',
  'java',
  'kt',
  'kts',
  'swift',
  'c',
  'h',
  'cpp',
  'cc',
  'cxx',
  'hpp',
  'cs',
  'go',
  'rs',
  'rb',
  'php',
  'sh',
  'bash',
  'zsh',
  'ps1',
  'sql',
};
const _audioExtensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg'};
const _videoExtensions = {'mp4', 'webm', 'mov'};
const _htmlExtensions = {'html', 'htm'};
const _documentExtensions = {
  'doc',
  'docx',
  'rtf',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'odt',
  'ods',
  'odp',
};

String normalizedFileExtension(FilePayload payload) {
  final explicit = payload.fileExtension.trim().toLowerCase();
  if (explicit.isNotEmpty) {
    return explicit.startsWith('.') ? explicit.substring(1) : explicit;
  }

  final fileName = payload.fileName.trim();
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) return '';
  return fileName.substring(dotIndex + 1).toLowerCase();
}

FilePreviewType classifyFilePreview(FilePayload payload) {
  final extension = normalizedFileExtension(payload);
  if (extension == 'pdf') return FilePreviewType.pdf;
  if (_imageExtensions.contains(extension)) return FilePreviewType.image;
  if (_textExtensions.contains(extension)) return FilePreviewType.text;
  if (_audioExtensions.contains(extension)) return FilePreviewType.audio;
  if (_videoExtensions.contains(extension)) return FilePreviewType.video;
  if (_htmlExtensions.contains(extension)) return FilePreviewType.html;
  if (_documentExtensions.contains(extension)) return FilePreviewType.document;
  return FilePreviewType.external;
}
