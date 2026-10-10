import 'dart:ui';

import '../../../domain/models/node.dart';
import '../../../domain/models/viewport.dart';

class CanvasSection {
  final String id;
  final String name;
  final String? parentId;
  final int order;
  final bool collapsed;

  const CanvasSection({
    required this.id,
    required this.name,
    this.parentId,
    this.order = 0,
    this.collapsed = false,
  });

  CanvasSection copyWith({
    String? id,
    String? name,
    Object? parentId = _sentinel,
    int? order,
    bool? collapsed,
  }) => CanvasSection(
    id: id ?? this.id,
    name: name ?? this.name,
    parentId: parentId == _sentinel ? this.parentId : parentId as String?,
    order: order ?? this.order,
    collapsed: collapsed ?? this.collapsed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'order': order,
    'collapsed': collapsed,
  };

  factory CanvasSection.fromJson(Map<String, dynamic> json) => CanvasSection(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled section',
    parentId: json['parentId']?.toString(),
    order: (json['order'] as num?)?.toInt() ?? 0,
    collapsed: json['collapsed'] as bool? ?? false,
  );

  static const Object _sentinel = Object();
}

class CanvasPage {
  final String id;
  final String name;
  final String? sectionId;
  final int order;
  final bool archived;

  const CanvasPage({
    required this.id,
    required this.name,
    this.sectionId,
    this.order = 0,
    this.archived = false,
  });

  CanvasPage copyWith({
    String? id,
    String? name,
    Object? sectionId = _sentinel,
    int? order,
    bool? archived,
  }) => CanvasPage(
    id: id ?? this.id,
    name: name ?? this.name,
    sectionId: sectionId == _sentinel ? this.sectionId : sectionId as String?,
    order: order ?? this.order,
    archived: archived ?? this.archived,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sectionId': sectionId,
    'order': order,
    'archived': archived,
  };

  factory CanvasPage.fromJson(Map<String, dynamic> json) => CanvasPage(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled page',
    sectionId: json['sectionId']?.toString(),
    order: (json['order'] as num?)?.toInt() ?? 0,
    archived: json['archived'] as bool? ?? false,
  );

  static const Object _sentinel = Object();
}

class ViewportBookmark {
  final String id;
  final String name;
  final Viewport viewport;
  final String? pageId;
  final List<String> selectedNodeIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ViewportBookmark({
    required this.id,
    required this.name,
    required this.viewport,
    this.pageId,
    this.selectedNodeIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  ViewportBookmark copyWith({
    String? id,
    String? name,
    Viewport? viewport,
    Object? pageId = _sentinel,
    List<String>? selectedNodeIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ViewportBookmark(
    id: id ?? this.id,
    name: name ?? this.name,
    viewport: viewport ?? this.viewport,
    pageId: pageId == _sentinel ? this.pageId : pageId as String?,
    selectedNodeIds: selectedNodeIds ?? this.selectedNodeIds,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'viewport': viewport.toJson(),
    'pageId': pageId,
    'selectedNodeIds': selectedNodeIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory ViewportBookmark.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final rawViewport = json['viewport'];
    return ViewportBookmark(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled view',
      viewport: rawViewport is Map
          ? Viewport.fromJson(Map<String, dynamic>.from(rawViewport))
          : const Viewport(),
      pageId: json['pageId']?.toString(),
      selectedNodeIds:
          (json['selectedNodeIds'] as List<dynamic>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      createdAt: createdAt?.toUtc() ?? now,
      updatedAt: updatedAt?.toUtc() ?? now,
    );
  }

  static const Object _sentinel = Object();
}

class CanvasNavigationState {
  static const int schemaVersion = 2;

  final List<CanvasSection> sections;
  final List<CanvasPage> pages;
  final List<ViewportBookmark> bookmarks;
  final String? activePageId;
  final bool focusMode;

  const CanvasNavigationState({
    this.sections = const [],
    this.pages = const [],
    this.bookmarks = const [],
    this.activePageId,
    this.focusMode = false,
  });

  CanvasNavigationState copyWith({
    List<CanvasSection>? sections,
    List<CanvasPage>? pages,
    List<ViewportBookmark>? bookmarks,
    Object? activePageId = _sentinel,
    bool? focusMode,
  }) => CanvasNavigationState(
    sections: sections ?? this.sections,
    pages: pages ?? this.pages,
    bookmarks: bookmarks ?? this.bookmarks,
    activePageId: activePageId == _sentinel
        ? this.activePageId
        : activePageId as String?,
    focusMode: focusMode ?? this.focusMode,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'sections': sections.map((section) => section.toJson()).toList(),
    'pages': pages.map((page) => page.toJson()).toList(),
    'bookmarks': bookmarks.map((bookmark) => bookmark.toJson()).toList(),
    'activePageId': activePageId,
    'focusMode': focusMode,
  };

  factory CanvasNavigationState.fromJson(Object? raw) {
    if (raw is! Map) return const CanvasNavigationState();
    final sourceVersion = (raw['schemaVersion'] as num?)?.toInt() ?? 1;
    if (sourceVersion > schemaVersion) {
      throw FormatException(
        'Canvas navigation schema $sourceVersion is newer than supported schema $schemaVersion.',
      );
    }

    final sections = _uniqueSections(raw['sections']);
    final pages = _uniquePages(raw['pages']);
    final bookmarks = _uniqueBookmarks(raw['bookmarks']);
    final requestedActivePageId = raw['activePageId']?.toString();
    final activePageId = pages.any((page) => page.id == requestedActivePageId)
        ? requestedActivePageId
        : pages.isEmpty
        ? null
        : pages.first.id;

    return CanvasNavigationState(
      sections: sections,
      pages: pages,
      bookmarks: bookmarks,
      activePageId: activePageId,
      focusMode: raw['focusMode'] as bool? ?? false,
    );
  }

  static const Object _sentinel = Object();

  static List<CanvasSection> _uniqueSections(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <CanvasSection>[];
    for (final item in raw.whereType<Map>()) {
      final section = CanvasSection.fromJson(Map<String, dynamic>.from(item));
      if (section.id.isEmpty || !seen.add(section.id)) continue;
      result.add(section);
    }
    return List.unmodifiable(result);
  }

  static List<CanvasPage> _uniquePages(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <CanvasPage>[];
    for (final item in raw.whereType<Map>()) {
      final page = CanvasPage.fromJson(Map<String, dynamic>.from(item));
      if (page.id.isEmpty || !seen.add(page.id)) continue;
      result.add(page);
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(result);
  }

  static List<ViewportBookmark> _uniqueBookmarks(Object? raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final result = <ViewportBookmark>[];
    for (final item in raw.whereType<Map>()) {
      final bookmark = ViewportBookmark.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (bookmark.id.isEmpty || !seen.add(bookmark.id)) continue;
      result.add(bookmark);
    }
    return List.unmodifiable(result);
  }
}

class CanvasNavigationMath {
  const CanvasNavigationMath._();

  static Rect visibleBounds(Iterable<CanvasNode> nodes) {
    Rect? result;
    for (final node in nodes) {
      if (!node.visible || node.width <= 0 || node.height <= 0) continue;
      result = result == null
          ? node.bounds
          : result.expandToInclude(node.bounds);
    }
    return result ?? Rect.zero;
  }

  static Viewport fitBounds(
    Rect bounds,
    Size viewportSize, {
    double padding = 80,
    double minZoom = 0.1,
    double maxZoom = 5.0,
  }) {
    if (bounds.isEmpty || viewportSize.isEmpty) return const Viewport();
    final targetWidth = bounds.width + padding * 2;
    final targetHeight = bounds.height + padding * 2;
    final scaleX = viewportSize.width / targetWidth;
    final scaleY = viewportSize.height / targetHeight;
    final zoom = (scaleX < scaleY ? scaleX : scaleY).clamp(minZoom, maxZoom);
    return Viewport(
      x: viewportSize.width / 2 - bounds.center.dx * zoom,
      y: viewportSize.height / 2 - bounds.center.dy * zoom,
      zoom: zoom,
    );
  }

  static List<CanvasNode> searchNodes(
    Iterable<CanvasNode> nodes,
    String query,
  ) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return nodes.toList(growable: false);
    return nodes
        .where((node) {
          final payload = node.payload.toJson();
          return [
            node.id,
            node.name ?? '',
            node.type.name,
            payload.toString(),
          ].join(' ').toLowerCase().contains(normalized);
        })
        .toList(growable: false);
  }

  static List<CanvasNode> nodesForPage(
    Iterable<CanvasNode> nodes,
    String? pageId,
  ) {
    if (pageId == null) return nodes.toList(growable: false);
    return nodes
        .where((node) => node.pageId == null || node.pageId == pageId)
        .toList(growable: false);
  }
}
