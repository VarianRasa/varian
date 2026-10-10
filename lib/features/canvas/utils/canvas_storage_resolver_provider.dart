import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/supabase_storage_path_resolver.dart';
import '../../../data/remote/supabase_sync_provider.dart';

final canvasStorageResolverProvider = Provider.autoDispose
    .family<SupabaseStoragePathResolver, String>((ref, projectId) {
      final sync = ref.watch(supabaseSyncServiceProvider);
      // SupabaseSyncService owns the resolver lifecycle and its HTTP client. The
      // project family remains scoped for invalidation, but does not duplicate or
      // dispose the shared resolver while another consumer may still use it.
      return sync.storageResolver;
    });
