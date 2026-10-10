import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/supabase_service.dart';
import '../../../data/local/durable/project_session.dart';
import '../../canvas/state/autosave_controller.dart';
import '../data/asset_library_repository.dart';
import '../data/asset_library_service.dart';

final assetLibraryServiceProvider =
    Provider.family<AssetLibraryService, String>((ref, scopeId) {
      return AssetLibraryService(
        scopeId: scopeId,
        localStorage: ref.read(localStorageServiceProvider),
        durableStore: ref.read(projectSessionProvider(scopeId)).store,
        client: ref.read(supabaseClientProvider),
      );
    });

final assetLibraryRepositoryProvider =
    Provider.family<AssetLibraryRepository, String>(
      (ref, scopeId) => ref.watch(assetLibraryServiceProvider(scopeId)),
    );
