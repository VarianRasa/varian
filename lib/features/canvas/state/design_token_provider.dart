import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/design_tokens.dart';

final designTokenSetProvider =
    StateNotifierProvider<DesignTokenSetNotifier, DesignTokenSet>(
      (ref) => DesignTokenSetNotifier(),
    );

class DesignTokenSetNotifier extends StateNotifier<DesignTokenSet> {
  DesignTokenSetNotifier() : super(const DesignTokenSet());

  void setSet(DesignTokenSet next) => state = next;

  void upsert(DesignToken token) => state = state.upsert(token);

  void remove(String tokenId) => state = state.remove(tokenId);

  void clear() => state = const DesignTokenSet();
}
