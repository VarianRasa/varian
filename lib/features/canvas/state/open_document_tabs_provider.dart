import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';

enum OpenDocumentTabType { canvas, note }

@immutable
class OpenDocumentTab {
  final OpenDocumentTabType type;
  final String documentId;
  final String name;
  final String? ownerAccountId;

  const OpenDocumentTab({
    String? projectId,
    String? documentId,
    required this.name,
    this.type = OpenDocumentTabType.canvas,
    this.ownerAccountId,
    this.noteProjectId,
  }) : documentId = documentId ?? projectId ?? '';

  final String? noteProjectId;

  String get projectId => documentId;
  String get identity => '${type.name}:${ownerAccountId ?? ''}:$documentId';
  bool get isCanvas => type == OpenDocumentTabType.canvas;
  bool get isNote => type == OpenDocumentTabType.note;

  factory OpenDocumentTab.note(WorkspaceNote note) => OpenDocumentTab(
    documentId: note.id,
    name: note.title,
    type: OpenDocumentTabType.note,
    ownerAccountId: note.ownerUserId,
    noteProjectId: note.projectId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenDocumentTab &&
          other.type == type &&
          other.documentId == documentId &&
          other.ownerAccountId == ownerAccountId &&
          other.noteProjectId == noteProjectId &&
          other.name == name;

  @override
  int get hashCode =>
      Object.hash(type, documentId, ownerAccountId, noteProjectId, name);
}

final activeDocumentTabProvider = StateProvider<OpenDocumentTab?>(
  (ref) => null,
);

final activeDocumentTabControllerProvider =
    Provider<ActiveDocumentTabController>(
      (ref) => ActiveDocumentTabController(ref),
    );

class ActiveDocumentTabController {
  ActiveDocumentTabController(this._ref);

  final Ref _ref;

  OpenDocumentTab? get current => _ref.read(activeDocumentTabProvider);

  User? get _authenticatedUser {
    final user = _ref.read(authUserProvider).asData?.value;
    if (user != null) return user;
    final client = _ref.read(supabaseClientProvider);
    return client?.auth.currentSession?.user ?? client?.auth.currentUser;
  }

  Future<void> select(OpenDocumentTab tab) async {
    if (tab.isCanvas) {
      await _ref.read(openDocumentTabsProvider.notifier).openTab(tab);
      _ref.read(activeDocumentTabProvider.notifier).state = tab;
      return;
    }

    final user = _authenticatedUser;
    final accountId = user?.id;
    if (user == null || user.isAnonymous || accountId == null) {
      throw StateError('Sign in to access private notes.');
    }
    if (tab.ownerAccountId != accountId && tab.noteProjectId == null) {
      throw StateError('The note is unavailable to this account.');
    }

    final accountScopedTab = OpenDocumentTab(
      documentId: tab.documentId,
      name: tab.name,
      type: OpenDocumentTabType.note,
      ownerAccountId: accountId,
      noteProjectId: tab.noteProjectId,
    );
    await _ref.read(openNoteTabsProvider.notifier).openTab(accountScopedTab);
    final currentUser = _authenticatedUser;
    if (currentUser?.id != accountId || currentUser?.isAnonymous != false) {
      throw StateError('The signed-in account changed during this action.');
    }
    _ref.read(activeDocumentTabProvider.notifier).state = accountScopedTab;
  }

  void clearIfActive(OpenDocumentTab tab) {
    if (current?.identity == tab.identity) {
      _ref.read(activeDocumentTabProvider.notifier).state = null;
    }
  }
}

final openDocumentTabsProvider =
    StateNotifierProvider<OpenDocumentTabsNotifier, List<OpenDocumentTab>>(
      (ref) => OpenDocumentTabsNotifier(ref.read(localStorageServiceProvider)),
    );

List<OpenDocumentTab> openDocumentTabsFor(WidgetRef ref) {
  final canvasTabs = ref.watch(openDocumentTabsProvider);
  final noteTabs = ref.watch(openNoteTabsProvider);
  final seen = <String>{};
  return [
    for (final tab in [...canvasTabs, ...noteTabs])
      if (seen.add(tab.identity)) tab,
  ];
}

final openNoteTabsProvider =
    StateNotifierProvider<OpenNoteTabsNotifier, List<OpenDocumentTab>>((ref) {
      final client = ref.watch(supabaseClientProvider);
      final notifier = OpenNoteTabsNotifier(client);
      final subscription = client?.auth.onAuthStateChange.listen(
        (change) {
          final user = change.session?.user;
          final nextAccountId = user == null || user.isAnonymous
              ? null
              : user.id;
          final active = ref.read(activeDocumentTabProvider);
          if (active?.isNote == true &&
              active!.ownerAccountId != nextAccountId) {
            ref.read(activeDocumentTabProvider.notifier).state = null;
          }
          unawaited(notifier.setAccount(nextAccountId));
        },
        // Retryable auth transport failures do not mean the signed-in account
        // changed. Keep note tabs scoped to the current session until auth emits
        // an actual state transition.
        onError: (Object _, StackTrace _) {},
      );
      ref.onDispose(() => subscription?.cancel());
      return notifier;
    });

class OpenNoteTabsNotifier extends StateNotifier<List<OpenDocumentTab>> {
  OpenNoteTabsNotifier(this._client) : super(const []) {
    final user = _client?.auth.currentUser;
    if (user != null && !user.isAnonymous) {
      unawaited(setAccount(user.id));
    }
  }

  final SupabaseClient? _client;
  Future<void> _writeQueue = Future<void>.value();
  String? _accountId;
  int _generation = 0;
  static const _keyPrefix = 'ccs_open_note_tabs_';

  Future<void> setAccount(String? accountId) async {
    final normalized = accountId?.trim();
    final authenticatedUser = _client?.auth.currentUser;
    final nextAccountId =
        normalized == null ||
            normalized.isEmpty ||
            authenticatedUser?.id != normalized ||
            authenticatedUser?.isAnonymous != false
        ? null
        : normalized;
    if (_accountId == nextAccountId) return;
    final generation = ++_generation;
    _accountId = nextAccountId;
    state = const [];
    if (nextAccountId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted ||
          generation != _generation ||
          _accountId != nextAccountId) {
        return;
      }
      final raw = prefs.getString('$_keyPrefix$nextAccountId');
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return;
      final seen = <String>{};
      state = [
        for (final item in decoded)
          if (item is Map<String, dynamic> &&
              item['id'] is String &&
              (item['id'] as String).isNotEmpty &&
              seen.add(item['id'] as String) &&
              item['name'] is String)
            OpenDocumentTab(
              documentId: item['id'] as String,
              name: item['name'] as String,
              type: OpenDocumentTabType.note,
              ownerAccountId: nextAccountId,
            ),
      ];
    } catch (error) {
      debugPrint('[OpenNoteTabs] Could not restore tabs: $error');
    }
  }

  Future<void> openTab(OpenDocumentTab tab) async {
    if (!tab.isNote) throw ArgumentError.value(tab, 'tab', 'Expected note tab');
    final accountId = _accountId;
    if (accountId == null ||
        tab.ownerAccountId != accountId ||
        _client?.auth.currentUser?.id != accountId ||
        _client?.auth.currentUser?.isAnonymous != false) {
      throw StateError('Sign in to access private notes.');
    }
    final index = state.indexWhere((item) => item.documentId == tab.documentId);
    if (index < 0) {
      state = [...state, tab];
    } else if (state[index].name != tab.name) {
      final next = [...state];
      next[index] = tab;
      state = next;
    }
    await _persist(accountId);
  }

  Future<void> rename(String noteId, String name) async {
    final index = state.indexWhere((tab) => tab.documentId == noteId);
    if (index < 0) return;
    final next = [...state];
    next[index] = OpenDocumentTab(
      documentId: noteId,
      name: name,
      type: OpenDocumentTabType.note,
      ownerAccountId: _accountId,
    );
    state = next;
    final accountId = _accountId;
    if (accountId != null) await _persist(accountId);
  }

  Future<void> close(String noteId) async {
    final next = state.where((tab) => tab.documentId != noteId).toList();
    if (next.length == state.length) return;
    state = next;
    final accountId = _accountId;
    if (accountId != null) await _persist(accountId);
  }

  Future<void> closeDeletedNote(String noteId, String ownerAccountId) async {
    if (_accountId != ownerAccountId ||
        _client?.auth.currentUser?.id != ownerAccountId) {
      return;
    }
    final next = state
        .where(
          (tab) =>
              !(tab.documentId == noteId &&
                  tab.ownerAccountId == ownerAccountId),
        )
        .toList();
    if (next.length == state.length) return;
    state = next;
    await _persist(ownerAccountId);
  }

  Future<void> _persist(String accountId) async {
    final serialized = jsonEncode(
      state.map((tab) => {'id': tab.documentId, 'name': tab.name}).toList(),
    );
    final previous = _writeQueue;
    final next = previous.then((_) async {
      if (!mounted ||
          _accountId != accountId ||
          _client?.auth.currentUser?.id != accountId) {
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted ||
            _accountId != accountId ||
            _client?.auth.currentUser?.id != accountId) {
          return;
        }
        await prefs.setString('$_keyPrefix$accountId', serialized);
      } catch (error) {
        debugPrint('[OpenNoteTabs] Could not save tabs: $error');
      }
    });
    _writeQueue = next.catchError((_) {});
    await next;
  }
}

class OpenDocumentTabsNotifier extends StateNotifier<List<OpenDocumentTab>> {
  static const _storageKey = 'ccs_open_document_tabs';

  final LocalStorageService _storage;
  Future<void> _writeQueue = Future<void>.value();
  late final Future<void> ready = _load();

  OpenDocumentTabsNotifier(this._storage) : super(const []);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final projects = await _storage.getProjects();
      final namesById = {
        for (final project in projects)
          if (project.status != ProjectStatus.trashed) project.id: project.name,
      };
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return;

      final restored = <OpenDocumentTab>[];
      final seenIds = <String>{};
      for (final value in decoded) {
        if (value is! Map<String, dynamic>) continue;
        final projectId = value['projectId'];
        if (projectId is! String ||
            projectId.isEmpty ||
            !namesById.containsKey(projectId) ||
            !seenIds.add(projectId)) {
          continue;
        }
        final storedName = value['name'];
        final name =
            namesById[projectId] ??
            (storedName is String && storedName.trim().isNotEmpty
                ? storedName.trim()
                : 'Untitled Project');
        restored.add(OpenDocumentTab(projectId: projectId, name: name));
      }
      if (mounted) {
        state = restored;
        if (restored.length != decoded.length) await _persist();
      }
    } catch (error) {
      debugPrint('[OpenDocumentTabs] Could not load tabs: $error');
    }
  }

  Future<void> open({required String projectId, required String name}) async {
    await openTab(OpenDocumentTab(projectId: projectId, name: name));
  }

  Future<void> openTab(OpenDocumentTab tab) async {
    if (!tab.isCanvas) {
      throw ArgumentError.value(tab, 'tab', 'Expected Canvas tab');
    }
    await ready;
    if (!mounted) return;
    final normalizedName = tab.name.trim().isEmpty
        ? 'Untitled Project'
        : tab.name.trim();
    final index = state.indexWhere((item) => item.documentId == tab.documentId);
    if (index < 0) {
      state = [
        ...state,
        OpenDocumentTab(documentId: tab.documentId, name: normalizedName),
      ];
      await _persist();
      return;
    }
    if (state[index].name == normalizedName) return;
    final next = [...state];
    next[index] = OpenDocumentTab(
      documentId: tab.documentId,
      name: normalizedName,
    );
    state = next;
    await _persist();
  }

  Future<void> rename(String projectId, String name) =>
      open(projectId: projectId, name: name);

  Future<void> close(String projectId) async {
    await ready;
    if (!mounted) return;
    final next = state
        .where((tab) => tab.projectId != projectId)
        .toList(growable: false);
    if (next.length == state.length) return;
    state = next;
    await _persist();
  }

  Future<void> _persist() async {
    final serialized = jsonEncode(
      state
          .map((tab) => {'projectId': tab.documentId, 'name': tab.name})
          .toList(),
    );
    final previous = _writeQueue;
    final next = previous.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, serialized);
      } catch (error) {
        debugPrint('[OpenDocumentTabs] Could not save tabs: $error');
      }
    });
    _writeQueue = next.catchError((_) {});
    await next;
  }
}
