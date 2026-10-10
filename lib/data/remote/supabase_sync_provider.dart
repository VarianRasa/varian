import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../artifacts/artifact_store_bundle.dart';
import 'supabase_service.dart';

/// Root-owned Supabase sync service shared by cloud reads, writes, and
/// transient private-Storage hydration.
final supabaseSyncServiceProvider = Provider<SupabaseSyncService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final service = SupabaseSyncService(
    client,
    artifactStoreBundle: ref.watch(artifactStoreBundleProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
