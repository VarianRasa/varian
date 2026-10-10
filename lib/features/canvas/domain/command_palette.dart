import 'dart:convert';

enum CanvasCommandCategory {
  navigation,
  create,
  edit,
  arrange,
  view,
  history,
  review,
  export,
}

class CanvasCommandDescriptor {
  final String id;
  final String title;
  final String description;
  final CanvasCommandCategory category;
  final String? shortcut;
  final List<String> keywords;
  final bool requiresEdit;
  final bool enabled;

  const CanvasCommandDescriptor({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.shortcut,
    this.keywords = const [],
    this.requiresEdit = false,
    this.enabled = true,
  });

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    final haystack = [
      id,
      title,
      description,
      category.name,
      ...keywords,
      ?shortcut,
    ].join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  int score(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return 0;
    final titleValue = title.toLowerCase();
    final idValue = id.toLowerCase();
    if (titleValue == normalized || idValue == normalized) return 100;
    if (titleValue.startsWith(normalized) || idValue.startsWith(normalized)) {
      return 80;
    }
    if (titleValue.contains(normalized) || idValue.contains(normalized)) {
      return 60;
    }
    return 20;
  }
}

class CanvasCommandCatalog {
  const CanvasCommandCatalog._();

  static List<CanvasCommandDescriptor> core({
    bool readOnly = false,
    bool canUndo = true,
    bool canRedo = true,
    bool hasSelection = false,
  }) {
    return [
      const CanvasCommandDescriptor(
        id: 'canvas.search',
        title: 'Search canvas',
        description: 'Find nodes, assets, comments, and project content.',
        category: CanvasCommandCategory.navigation,
        shortcut: 'Ctrl/Cmd+F',
        keywords: ['find', 'locate'],
      ),
      const CanvasCommandDescriptor(
        id: 'canvas.zoom_to_content',
        title: 'Zoom to content',
        description: 'Fit visible content inside the current viewport.',
        category: CanvasCommandCategory.view,
        keywords: ['fit', 'frame', 'overview'],
      ),
      const CanvasCommandDescriptor(
        id: 'canvas.viewport_bookmarks',
        title: 'Viewport bookmarks',
        description: 'Save or restore named canvas views.',
        category: CanvasCommandCategory.navigation,
        keywords: ['views', 'locations'],
      ),
      const CanvasCommandDescriptor(
        id: 'canvas.toggle_focus',
        title: 'Toggle focus mode',
        description: 'Hide surrounding chrome for distraction-free editing.',
        category: CanvasCommandCategory.view,
        shortcut: 'Ctrl/Cmd+Shift+\\',
        keywords: ['fullscreen', 'distraction free'],
      ),
      CanvasCommandDescriptor(
        id: 'history.undo',
        title: 'Undo',
        description: 'Undo the most recent canvas command.',
        category: CanvasCommandCategory.history,
        shortcut: 'Ctrl/Cmd+Z',
        enabled: !readOnly && canUndo,
        requiresEdit: true,
      ),
      CanvasCommandDescriptor(
        id: 'history.redo',
        title: 'Redo',
        description: 'Redo the most recently undone canvas command.',
        category: CanvasCommandCategory.history,
        shortcut: 'Ctrl/Cmd+Shift+Z',
        enabled: !readOnly && canRedo,
        requiresEdit: true,
      ),
      CanvasCommandDescriptor(
        id: 'selection.duplicate',
        title: 'Duplicate selection',
        description: 'Create an offset copy while preserving relationships.',
        category: CanvasCommandCategory.edit,
        shortcut: 'Ctrl/Cmd+D',
        enabled: !readOnly && hasSelection,
        requiresEdit: true,
        keywords: ['copy', 'clone'],
      ),
      CanvasCommandDescriptor(
        id: 'selection.delete',
        title: 'Delete selection',
        description: 'Remove selected nodes and attached connectors.',
        category: CanvasCommandCategory.edit,
        shortcut: 'Delete',
        enabled: !readOnly && hasSelection,
        requiresEdit: true,
        keywords: ['remove', 'trash'],
      ),
      CanvasCommandDescriptor(
        id: 'selection.group',
        title: 'Group selection',
        description: 'Put selected nodes into a new editable group.',
        category: CanvasCommandCategory.arrange,
        shortcut: 'Ctrl/Cmd+G',
        enabled: !readOnly && hasSelection,
        requiresEdit: true,
        keywords: ['container', 'nest'],
      ),
      CanvasCommandDescriptor(
        id: 'selection.align',
        title: 'Align and distribute',
        description: 'Open precision alignment actions for the selection.',
        category: CanvasCommandCategory.arrange,
        enabled: !readOnly && hasSelection,
        requiresEdit: true,
        keywords: ['layout', 'spacing', 'distribute'],
      ),
      CanvasCommandDescriptor(
        id: 'navigation.new_page',
        title: 'Create canvas page',
        description: 'Create an isolated page for the current project.',
        category: CanvasCommandCategory.navigation,
        enabled: !readOnly,
        requiresEdit: true,
        keywords: ['board', 'workspace'],
      ),
      CanvasCommandDescriptor(
        id: 'navigation.rename_page',
        title: 'Rename current page',
        description: 'Change the name shown in breadcrumbs and navigation.',
        category: CanvasCommandCategory.navigation,
        enabled: !readOnly,
        requiresEdit: true,
      ),
      const CanvasCommandDescriptor(
        id: 'view.precision_settings',
        title: 'Precision settings',
        description: 'Configure grid, guides, snapping, and measurement.',
        category: CanvasCommandCategory.view,
        keywords: ['ruler', 'snap', 'guide', 'grid'],
      ),
      const CanvasCommandDescriptor(
        id: 'view.shortcut_help',
        title: 'Keyboard shortcuts',
        description: 'Review keyboard, pointer, touch, and stylus behavior.',
        category: CanvasCommandCategory.view,
        shortcut: '?',
        keywords: ['help', 'input', 'discoverability'],
      ),
    ];
  }
}

class CanvasToolHistoryEntry {
  final String toolId;
  final int useCount;
  final DateTime lastUsedAt;

  const CanvasToolHistoryEntry({
    required this.toolId,
    required this.useCount,
    required this.lastUsedAt,
  });

  CanvasToolHistoryEntry copyWith({int? useCount, DateTime? lastUsedAt}) {
    return CanvasToolHistoryEntry(
      toolId: toolId,
      useCount: useCount ?? this.useCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'toolId': toolId,
    'useCount': useCount,
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
  };

  factory CanvasToolHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CanvasToolHistoryEntry(
      toolId: json['toolId']?.toString() ?? '',
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      lastUsedAt:
          DateTime.tryParse(json['lastUsedAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class CanvasToolHistory {
  static const int maxEntries = 24;

  final List<CanvasToolHistoryEntry> entries;

  const CanvasToolHistory({this.entries = const []});

  CanvasToolHistory record(String toolId, {DateTime? now}) {
    final normalized = toolId.trim();
    if (normalized.isEmpty) return this;
    final timestamp = (now ?? DateTime.now()).toUtc();
    final existing = entries.where((entry) => entry.toolId == normalized);
    final nextEntry = existing.isEmpty
        ? CanvasToolHistoryEntry(
            toolId: normalized,
            useCount: 1,
            lastUsedAt: timestamp,
          )
        : existing.first.copyWith(
            useCount: existing.first.useCount + 1,
            lastUsedAt: timestamp,
          );
    final next = [
      nextEntry,
      ...entries.where((entry) => entry.toolId != normalized),
    ]..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return CanvasToolHistory(
      entries: next.take(maxEntries).toList(growable: false),
    );
  }

  List<String> get recentToolIds =>
      entries.map((entry) => entry.toolId).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  factory CanvasToolHistory.fromJson(Object? raw) {
    if (raw is String) {
      try {
        return CanvasToolHistory.fromJson(jsonDecode(raw));
      } catch (_) {
        return const CanvasToolHistory();
      }
    }
    if (raw is! Map || raw['entries'] is! List) {
      return const CanvasToolHistory();
    }
    final entries = <CanvasToolHistoryEntry>[];
    final seen = <String>{};
    for (final item in (raw['entries'] as List).whereType<Map>()) {
      final entry = CanvasToolHistoryEntry.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (entry.toolId.isEmpty || !seen.add(entry.toolId)) continue;
      entries.add(entry);
    }
    entries.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return CanvasToolHistory(
      entries: entries.take(maxEntries).toList(growable: false),
    );
  }
}
