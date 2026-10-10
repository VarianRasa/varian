import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// The result of an export save attempt.
///
/// A web save can complete without a URI because the browser owns the
/// download. Native platforms use a null URI to signal cancellation.
enum ExportSaveOutcome { saved, canceled, failed }

/// Injectable boundary around [FilePicker.saveFile].
typedef ExportFileSaveCallback =
    Future<Uri?> Function({
      required String fileName,
      required Uint8List bytes,
      required String mimeType,
      String? dialogTitle,
    });

/// Saves already-generated export bytes through the platform file picker.
class ExportFileSaver {
  final ExportFileSaveCallback _saveFile;
  final bool _isWeb;

  ExportFileSaver({ExportFileSaveCallback? saveFile, bool? isWeb})
    : _saveFile = saveFile ?? _saveWithPicker,
      _isWeb = isWeb ?? kIsWeb;

  /// Opens the save dialog and returns its platform-independent outcome.
  ///
  /// Picker exceptions are intentionally not converted into an outcome so
  /// callers can preserve the original failure and decide how to present it.
  Future<ExportSaveOutcome> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
  }) async {
    final uri = await _saveFile(
      fileName: sanitizeExportFileName(fileName),
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: dialogTitle,
    );

    if (_isWeb || uri != null) return ExportSaveOutcome.saved;
    return ExportSaveOutcome.canceled;
  }

  /// Alias for callers that prefer the platform API's method name.
  Future<ExportSaveOutcome> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
  }) => save(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: dialogTitle,
  );

  static Future<Uri?> _saveWithPicker({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
  }) => FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: dialogTitle,
  );
}

/// Makes a suggested file name safe for Windows, macOS, Linux, Android, iOS,
/// and browser download implementations without changing its final extension.
String sanitizeExportFileName(String? fileName) {
  final base = (fileName ?? '').split(RegExp(r'[\\/]')).last;
  final cleaned = base
      .replaceAll(RegExp(r'[<>:"|?*\u0000-\u001F]'), '_')
      .trim()
      .replaceFirst(RegExp(r'[ .]+$'), '');
  final dot = cleaned.lastIndexOf('.');
  final hasExtension = dot > 0 && dot < cleaned.length - 1;
  final rawStem = hasExtension ? cleaned.substring(0, dot) : cleaned;
  final extension = hasExtension ? cleaned.substring(dot) : '';

  var stem = rawStem
      .trim()
      .replaceFirst(RegExp(r'^\.+'), '')
      .replaceFirst(RegExp(r'[ .]+$'), '');
  if (stem.isEmpty) stem = 'export';

  final reservedName = stem.split('.').first.toUpperCase();
  if (_windowsReservedNames.contains(reservedName)) {
    stem = '_$stem';
  }

  return '$stem$extension';
}

/// Compatibility name for integrations that use the generic file-name helper.
String sanitizeFileName(String? fileName) => sanitizeExportFileName(fileName);

const _windowsReservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};
