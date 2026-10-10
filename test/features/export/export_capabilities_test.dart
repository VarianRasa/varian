import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/export/export_capabilities.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_service.dart';

void main() {
  test('video export reports an honest unavailable capability', () async {
    final result = await ExportPresetRegistry.video.export(
      CanvasDocument(
        projectId: 'video-project',
        updatedAt: DateTime.utc(2026, 9, 13),
      ),
    );

    expect(result?.isFailure, isTrue);
    expect(result?.capability?.isSupported, isFalse);
    expect(() => result!.data, throwsStateError);
  });

  test(
    'presentation export emits a portable contract with provenance',
    () async {
      final result = await ExportPresetRegistry.presentation.export(
        CanvasDocument(
          projectId: 'presentation-project',
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
      );
      final decoded = jsonDecode(result!.text!) as Map<String, dynamic>;

      expect(result.isFailure, isFalse);
      expect(decoded['format'], 'varian.presentation.contract');
      expect(decoded['provenance']['projectId'], 'presentation-project');
      expect(decoded['slides'], isNotEmpty);
    },
  );

  test('capability registry keeps native video boundary explicit', () {
    expect(
      ExportCapabilityRegistry.forFormat(ExportPresetFormat.video),
      same(ExportCapabilityRegistry.video),
    );
    expect(ExportCapabilityRegistry.presentation.isSupported, isTrue);
    expect(
      ExportService.exportPresentationContract(
        CanvasDocument(
          projectId: 'contract',
          updatedAt: DateTime.utc(2026, 9, 13),
        ),
      ),
      contains('varian.presentation.contract'),
    );
  });
}
