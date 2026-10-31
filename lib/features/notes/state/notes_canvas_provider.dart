import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/data/notes_canvas_sync_repository.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';

final notesCanvasBoardsProvider =
    FutureProvider.family<List<NotesCanvasBoard>, (String, String?)>((
      ref,
      scope,
    ) {
      final (accountId, projectId) = scope;
      final user = ref.watch(authUserProvider).valueOrNull;
      if (user?.id != accountId || user?.isAnonymous != false) {
        return Future.error(
          StateError('The signed-in account changed during this action.'),
        );
      }
      return ref
          .watch(notesCanvasRepositoryProvider)
          .listBoards(projectId: projectId, expectedAccountId: accountId);
    });

final notesCanvasSyncRepositoryProvider = Provider<NotesCanvasSyncRepository?>((
  ref,
) {
  final offline = ref.watch(notesOfflineServiceProvider);
  final repository = ref.watch(notesCanvasRepositoryProvider);
  final client = ref.watch(supabaseClientProvider);
  if (offline == null || client == null) return null;
  final sync = NotesCanvasSyncRepository(
    store: offline.store,
    transport: repository,
    keyForAccount: offline.keyForAccount,
    currentAccountId: () async {
      final user = client.auth.currentUser;
      return user == null || user.isAnonymous ? null : user.id;
    },
  );
  ref.listen(authUserProvider, (_, _) => sync.accountChanged());
  return sync;
});
