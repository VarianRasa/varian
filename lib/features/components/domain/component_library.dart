import '../../../domain/models/component_payload.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';

class ComponentLibraryEntry {
  final String id;
  final String sourceNodeId;
  final String name;
  final String description;
  final int version;
  final List<String> tags;
  final bool published;
  final bool pinned;
  final DateTime updatedAt;

  const ComponentLibraryEntry({
    required this.id,
    required this.sourceNodeId,
    required this.name,
    this.description = '',
    this.version = 1,
    this.tags = const [],
    this.published = false,
    this.pinned = false,
    required this.updatedAt,
  });

  ComponentLibraryEntry copyWith({
    String? id,
    String? sourceNodeId,
    String? name,
    String? description,
    int? version,
    List<String>? tags,
    bool? published,
    bool? pinned,
    DateTime? updatedAt,
  }) => ComponentLibraryEntry(
    id: id ?? this.id,
    sourceNodeId: sourceNodeId ?? this.sourceNodeId,
    name: name ?? this.name,
    description: description ?? this.description,
    version: version ?? this.version,
    tags: tags ?? this.tags,
    published: published ?? this.published,
    pinned: pinned ?? this.pinned,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceNodeId': sourceNodeId,
    'name': name,
    'description': description,
    'version': version,
    'tags': tags,
    'published': published,
    'pinned': pinned,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory ComponentLibraryEntry.fromJson(Map<String, dynamic> json) =>
      ComponentLibraryEntry(
        id: json['id'] as String,
        sourceNodeId: json['sourceNodeId'] as String,
        name: json['name'] as String? ?? 'Component',
        description: json['description'] as String? ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        tags:
            (json['tags'] as List<dynamic>?)?.whereType<String>().toList() ??
            const [],
        published: json['published'] as bool? ?? false,
        pinned: json['pinned'] as bool? ?? false,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class ComponentLibrary {
  final Map<String, ComponentLibraryEntry> entries;

  const ComponentLibrary({this.entries = const {}});

  List<ComponentLibraryEntry> search(String query) {
    final normalized = query.trim().toLowerCase();
    final result = entries.values.where((entry) {
      if (normalized.isEmpty) return true;
      return [
        entry.id,
        entry.name,
        entry.description,
        ...entry.tags,
      ].join(' ').toLowerCase().contains(normalized);
    }).toList();
    result.sort((left, right) {
      if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return result;
  }

  ComponentLibrary upsert(ComponentLibraryEntry entry) =>
      ComponentLibrary(entries: {...entries, entry.id: entry});

  ComponentLibrary merge(ComponentLibrary other) {
    if (other.entries.isEmpty) return this;
    final next = Map<String, ComponentLibraryEntry>.from(entries);
    for (final entry in other.entries.values) {
      final existing = next[entry.id];
      if (existing == null) {
        next[entry.id] = entry;
        continue;
      }
      next[entry.id] = existing.copyWith(
        sourceNodeId: entry.sourceNodeId,
        name: entry.name,
        description: entry.description,
        tags: entry.tags.isEmpty ? existing.tags : entry.tags,
        version: entry.version > existing.version
            ? entry.version
            : existing.version,
        updatedAt: entry.updatedAt.isAfter(existing.updatedAt)
            ? entry.updatedAt
            : existing.updatedAt,
      );
    }
    return ComponentLibrary(entries: next);
  }

  ComponentLibrary setPublished(String id, bool published) {
    final entry = entries[id];
    if (entry == null || entry.published == published) return this;
    return upsert(
      entry.copyWith(
        published: published,
        version: published ? entry.version : entry.version + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  ComponentLibrary setPinned(String id, bool pinned) {
    final entry = entries[id];
    if (entry == null || entry.pinned == pinned) return this;
    return upsert(
      entry.copyWith(pinned: pinned, updatedAt: DateTime.now().toUtc()),
    );
  }

  List<ComponentLibraryEntry> get pinnedEntries =>
      entries.values.where((entry) => entry.pinned).toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name));

  ComponentLibrary remove(String id) {
    if (!entries.containsKey(id)) return this;
    return ComponentLibrary(entries: {...entries}..remove(id));
  }

  Map<String, dynamic> toJson() => {
    'items': entries.values.map((entry) => entry.toJson()).toList(),
  };

  factory ComponentLibrary.fromJson(Object? raw) {
    if (raw is! Map) return const ComponentLibrary();
    final entries = <String, ComponentLibraryEntry>{};
    final items = raw['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final entry = ComponentLibraryEntry.fromJson(
          Map<String, dynamic>.from(item),
        );
        entries[entry.id] = entry;
      }
    }
    return ComponentLibrary(entries: entries);
  }

  static ComponentLibrary discover(Iterable<CanvasNode> nodes) {
    final entries = <String, ComponentLibraryEntry>{};
    for (final node in nodes) {
      final payload = node.payload;
      if (node.type != NodeType.component || payload is! ComponentPayload) {
        continue;
      }
      if (!payload.isMaster) continue;
      final id = payload.masterComponentId.isEmpty
          ? node.id
          : payload.masterComponentId;
      entries[id] = ComponentLibraryEntry(
        id: id,
        sourceNodeId: node.id,
        name: payload.componentName,
        description: payload.description,
        tags: const [],
        published: false,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    return ComponentLibrary(entries: entries);
  }

  static List<CanvasNode> usages(
    Iterable<CanvasNode> nodes,
    String componentId, {
    bool includeMaster = false,
  }) {
    final result = <CanvasNode>[];
    final visited = <String>{};

    void visit(CanvasNode node) {
      if (!visited.add(node.id)) return;
      final payload = node.payload;
      if (node.type == NodeType.component &&
          payload is ComponentPayload &&
          payload.masterComponentId == componentId &&
          (includeMaster || !payload.isMaster)) {
        result.add(node);
      }
      if (payload is ComponentPayload) {
        for (final child in payload.templateChildren) {
          visit(child);
        }
        for (final slot in payload.slots) {
          for (final child in slot.fallbackChildren) {
            visit(child);
          }
        }
        for (final children in payload.slotContent.values) {
          for (final child in children) {
            visit(child);
          }
        }
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return result;
  }

  static int usageCount(
    Iterable<CanvasNode> nodes,
    String componentId, {
    bool includeMaster = false,
  }) => usages(nodes, componentId, includeMaster: includeMaster).length;
}
