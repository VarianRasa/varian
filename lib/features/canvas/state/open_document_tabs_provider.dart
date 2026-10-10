import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';

@immutable
class OpenDocumentTab {
  final String projectId;
  final String name;

  const OpenDocumentTab({required this.projectId, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenDocumentTab &&
          other.projectId == projectId &&
          other.name == name;

  @override
  int get hashCode => Object.hash(projectId, name);
}

final openDocumentTabsProvider =
    StateNotifierProvider<OpenDocumentTabsNotifier, List<OpenDocumentTab>>(
      (ref) => OpenDocumentTabsNotifier(ref.read(localStorageServiceProvider)),
    );

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
    await ready;
    if (!mounted) return;
    final normalizedName = name.trim().isEmpty
        ? 'Untitled Project'
        : name.trim();
    final index = state.indexWhere((tab) => tab.projectId == projectId);
    if (index < 0) {
      state = [
        ...state,
        OpenDocumentTab(projectId: projectId, name: normalizedName),
      ];
      await _persist();
      return;
    }
    if (state[index].name == normalizedName) return;
    final next = [...state];
    next[index] = OpenDocumentTab(projectId: projectId, name: normalizedName);
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
          .map((tab) => {'projectId': tab.projectId, 'name': tab.name})
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
