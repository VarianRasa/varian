import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';

const guestDraftIdPreferenceKey = 'ccs_guest_canvas_draft_id';
const guestPendingRenamePreferenceKey = 'ccs_guest_pending_document_title';

/// Commits a guest draft and its staged title before consuming the guest intent.
Future<void> promoteGuestCanvasDraft({
  required String projectId,
  required CanvasDocument draft,
  required LocalStorageService storage,
  required ProjectSession session,
  required SharedPreferences preferences,
}) async {
  final prepared = await storage.prepareDocument(draft);
  await session.saveDocument(prepared);
  await storage.saveDocument(prepared);

  final existing = (await storage.getProjects())
      .where((project) => project.id == projectId)
      .firstOrNull;
  final pendingTitle = preferences
      .getString(guestPendingRenamePreferenceKey)
      ?.trim();
  final now = DateTime.now();
  await storage.saveProjectMetadata(
    LocalProjectMetadata(
      id: projectId,
      name: pendingTitle?.isNotEmpty == true
          ? pendingTitle!
          : existing?.name ?? 'Untitled Project',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    ),
  );

  await preferences.remove(guestDraftIdPreferenceKey);
  await preferences.remove(guestPendingRenamePreferenceKey);
}
