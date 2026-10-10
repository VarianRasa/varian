import 'package:flutter/material.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? nodeId;
  final String? projectId;

  const SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.nodeId,
    this.projectId,
  });
}

class SearchService {
  static List<SearchResult> searchNodes(List<CanvasNode> nodes, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final results = <SearchResult>[];

    for (final node in nodes) {
      if (!node.visible) continue;
      final haystack = _nodeSearchText(node).toLowerCase();
      if (!haystack.contains(q)) continue;

      results.add(
        SearchResult(
          id: 'node_${node.id}',
          title: _nodeTitle(node),
          subtitle: node.type.name.toUpperCase(),
          icon: _nodeIcon(node.type),
          color: _nodeColor(node.type),
          nodeId: node.id,
        ),
      );
    }

    return results;
  }

  static String _nodeSearchText(CanvasNode node) {
    final payload = node.payload;
    final buffer = StringBuffer();

    if (node.name != null) buffer.writeln(node.name);

    switch (payload) {
      case TextPayload p:
        buffer.writeln(p.text);
        if (p.blocks != null) {
          for (final b in p.blocks!) {
            buffer.writeln(b.plainText);
          }
        }
        break;
      case StickyNotePayload p:
        buffer.writeln(p.text);
        break;
      case DocumentPayload p:
        buffer.writeln(p.title);
        for (final b in p.blocks) {
          buffer.writeln(b.plainText);
        }
        break;
      case LinkPayload p:
        buffer.writeln(p.title);
        buffer.writeln(p.url);
        buffer.writeln(p.description);
        break;
      case FilePayload p:
        buffer.writeln(p.fileName);
        break;
      case Model3DPayload p:
        buffer.writeln(p.displayName);
        buffer.writeln(p.fileSizeText);
        break;
      case TodoListPayload p:
        buffer.writeln(p.title);
        for (final i in p.items) {
          buffer.writeln(i.text);
        }
        break;
      case TablePayload p:
        for (final c in p.columns) {
          buffer.writeln(c);
        }
        for (final r in p.rows) {
          for (final c in r) {
            buffer.writeln(c);
          }
        }
        break;
      case ColumnPayload p:
        buffer.writeln(p.headerTitle);
        for (final t in p.itemTitles) {
          buffer.writeln(t);
        }
        break;
      case ColorSwatchPayload p:
        buffer.writeln(p.label);
        buffer.writeln(p.colorHex);
        break;
      case VideoPayload p:
        buffer.writeln(p.title);
        break;
      case AudioPayload p:
        buffer.writeln(p.trackName);
        buffer.writeln(p.artist);
        break;
      case MapPayload p:
        buffer.writeln(p.locationTitle);
        buffer.writeln(p.address);
        break;
      case EmbedPayload p:
        buffer.writeln(p.provider);
        buffer.writeln(p.title);
        buffer.writeln(p.url);
        break;
      case SketchCardPayload p:
        buffer.writeln(p.title);
        break;
      case FramePayload p:
        buffer.writeln(p.name);
        break;
      case GroupPayload p:
        buffer.writeln(p.name);
        break;
      case ComponentPayload p:
        buffer.writeln(p.componentName);
        break;
      default:
        break;
    }

    return buffer.toString();
  }

  static String _nodeTitle(CanvasNode node) {
    final payload = node.payload;
    if (node.name != null && node.name!.isNotEmpty) return node.name!;
    switch (payload) {
      case TextPayload p:
        return p.text.isNotEmpty ? p.text : 'Text';
      case StickyNotePayload p:
        return p.text.isNotEmpty ? p.text : 'Sticky Note';
      case DocumentPayload p:
        return p.title;
      case LinkPayload p:
        return p.title;
      case FilePayload p:
        return p.fileName;
      case Model3DPayload p:
        return p.displayName;
      case TodoListPayload p:
        return p.title;
      case TablePayload _:
        return 'Table';
      case ColumnPayload p:
        return p.headerTitle;
      case ColorSwatchPayload p:
        return p.label;
      case VideoPayload p:
        return p.title;
      case AudioPayload p:
        return p.trackName;
      case MapPayload p:
        return '${p.locationTitle} ${p.address}';
      case EmbedPayload p:
        return p.title ?? p.provider;
      case SketchCardPayload p:
        return p.title;
      case FramePayload p:
        return p.name;
      case GroupPayload p:
        return p.name;
      case ComponentPayload p:
        return p.componentName;
      default:
        return node.type.name.toUpperCase();
    }
  }

  static IconData _nodeIcon(NodeType type) {
    switch (type) {
      case NodeType.text:
        return Icons.title;
      case NodeType.stickyNote:
        return Icons.sticky_note_2_outlined;
      case NodeType.document:
        return Icons.description_outlined;
      case NodeType.linkCard:
        return Icons.link_outlined;
      case NodeType.fileCard:
        return Icons.insert_drive_file_outlined;
      case NodeType.model3d:
        return Icons.view_in_ar_outlined;
      case NodeType.todoList:
        return Icons.checklist_outlined;
      case NodeType.tableGrid:
        return Icons.table_chart_outlined;
      case NodeType.columnContainer:
        return Icons.view_column_outlined;
      case NodeType.colorSwatch:
        return Icons.palette_outlined;
      case NodeType.videoCard:
        return Icons.videocam_outlined;
      case NodeType.audioCard:
        return Icons.audiotrack_outlined;
      case NodeType.mapCard:
        return Icons.map_outlined;
      case NodeType.embed:
        return Icons.smart_display_outlined;
      case NodeType.sketchCard:
        return Icons.gesture_outlined;
      case NodeType.frame:
        return Icons.crop_free;
      case NodeType.group:
        return Icons.folder_outlined;
      case NodeType.component:
        return Icons.widgets_outlined;
      case NodeType.image:
        return Icons.image_outlined;
      default:
        return Icons.crop_square;
    }
  }

  static Color _nodeColor(NodeType type) {
    switch (type) {
      case NodeType.text:
        return const Color(0xFFF3F4F6);
      case NodeType.stickyNote:
        return const Color(0xFFFEF08A);
      case NodeType.document:
        return const Color(0xFFF3F4F6);
      case NodeType.linkCard:
        return const Color(0xFF38BDF8);
      case NodeType.fileCard:
        return const Color(0xFFEF4444);
      case NodeType.model3d:
        return const Color(0xFF60A5FA);
      case NodeType.todoList:
        return const Color(0xFF34D399);
      case NodeType.tableGrid:
        return const Color(0xFF60A5FA);
      case NodeType.columnContainer:
        return const Color(0xFFF97316);
      case NodeType.colorSwatch:
        return const Color(0xFFFBBF24);
      case NodeType.videoCard:
        return const Color(0xFFF97316);
      case NodeType.audioCard:
        return const Color(0xFF10B981);
      case NodeType.mapCard:
        return const Color(0xFFEF4444);
      case NodeType.embed:
        return const Color(0xFFF59E0B);
      case NodeType.sketchCard:
        return const Color(0xFFF59E0B);
      case NodeType.frame:
        return const Color(0xFF818CF8);
      case NodeType.group:
        return const Color(0xFFD97706);
      case NodeType.component:
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}
