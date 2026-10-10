import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/components/domain/component_library.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'published snapshot stays immutable and enforces access policy',
    () async {
      final document = CanvasDocument(
        projectId: 'publish-project',
        updatedAt: DateTime.utc(2026, 9, 11),
      );
      final snapshot = PublishedSnapshot.publish(
        document,
        id: 'snapshot-1',
        version: 4,
        publishedBy: 'owner',
        access: PublishedAccess.password,
        password: 'correct horse',
        downloadPolicy: PublishedDownloadPolicy.exportOnly,
        publishedAt: DateTime.utc(2026, 9, 11),
      );
      expect(snapshot.canRead(password: 'wrong'), isFalse);
      expect(snapshot.canRead(password: 'correct horse'), isTrue);
      expect(snapshot.canDownload(password: 'correct horse'), isTrue);
      expect(snapshot.contentHash, isNotEmpty);

      final storage = LocalStorageService();
      await storage.savePublishedSnapshot(snapshot);
      final restored = await storage.loadPublishedSnapshot('publish-project');
      expect(restored?.id, 'snapshot-1');
      expect(restored?.contentHash, snapshot.contentHash);
      expect(restored?.document.toJson(), document.toJson());
    },
  );

  test('plugin, accessibility, quota, and retention contracts validate', () {
    const manifest = PluginManifest(
      id: 'csv-importer',
      name: 'CSV Importer',
      version: '1.2.0',
      permissions: [
        PluginPermission.readSelection,
        PluginPermission.writeNodes,
      ],
    );
    expect(manifest.validate(), isEmpty);
    expect(manifest.requests(PluginPermission.writeNodes), isTrue);

    const accessibility = AccessibilitySettings(reducedMotion: true);
    expect(
      accessibility.motionDuration(const Duration(milliseconds: 250)),
      Duration.zero,
    );

    const quota = WorkspaceQuota(storageBytes: 100, aiCredits: 10);
    expect(
      const WorkspaceUsage(storageBytes: 80, aiCredits: 4).within(quota),
      isTrue,
    );
    expect(const WorkspaceUsage(storageBytes: 101).within(quota), isFalse);

    const policy = RetentionPolicy(trashRetention: Duration(days: 30));
    expect(
      policy.shouldPurge(
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 9, 11),
        policy.trashRetention,
      ),
      isTrue,
    );
  });

  test('persists component library and accessibility settings', () async {
    final storage = LocalStorageService();
    final updatedAt = DateTime.utc(2026, 9, 11);
    final library = ComponentLibrary(
      entries: {
        'button': ComponentLibraryEntry(
          id: 'button',
          sourceNodeId: 'master-node',
          name: 'Primary button',
          published: true,
          updatedAt: updatedAt,
        ),
      },
    );
    await storage.saveComponentLibrary('library-project', library);
    await storage.saveAccessibilitySettings(
      const AccessibilitySettings(reducedMotion: true, keyboardOnly: true),
    );

    final restoredLibrary = await storage.loadComponentLibrary(
      'library-project',
    );
    final restoredSettings = await storage.loadAccessibilitySettings();
    expect(restoredLibrary.entries['button']?.published, isTrue);
    expect(restoredSettings.reducedMotion, isTrue);
    expect(restoredSettings.keyboardOnly, isTrue);
  });
}
