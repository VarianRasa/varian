import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectionProvider = StateNotifierProvider<SelectionNotifier, Set<String>>(
  (ref) {
    return SelectionNotifier();
  },
);

class SelectionNotifier extends StateNotifier<Set<String>> {
  SelectionNotifier() : super({});

  void select(String id) {
    state = {id};
  }

  void toggle(String id) {
    if (state.contains(id)) {
      state = state.difference({id});
    } else {
      state = {...state, id};
    }
  }

  void selectAll(List<String> ids) {
    state = ids.toSet();
  }

  void clear() {
    state = {};
  }
}
