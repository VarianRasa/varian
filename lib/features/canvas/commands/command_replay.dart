import 'dart:convert';

import 'editor_commands.dart';

class CommandReplayEntry {
  final int sequence;
  final String phase;
  final String commandType;
  final String commandName;
  final DateTime timestamp;
  final int nodeCountBefore;
  final int nodeCountAfter;
  final int edgeCountBefore;
  final int edgeCountAfter;

  const CommandReplayEntry({
    required this.sequence,
    required this.phase,
    required this.commandType,
    required this.commandName,
    required this.timestamp,
    required this.nodeCountBefore,
    required this.nodeCountAfter,
    required this.edgeCountBefore,
    required this.edgeCountAfter,
  });

  factory CommandReplayEntry.fromCommand({
    required int sequence,
    required String phase,
    required EditorCommand command,
    required DateTime timestamp,
    required int nodeCountBefore,
    required int nodeCountAfter,
    required int edgeCountBefore,
    required int edgeCountAfter,
  }) {
    return CommandReplayEntry(
      sequence: sequence,
      phase: phase,
      commandType: command.runtimeType.toString(),
      commandName: command.name,
      timestamp: timestamp.toUtc(),
      nodeCountBefore: nodeCountBefore,
      nodeCountAfter: nodeCountAfter,
      edgeCountBefore: edgeCountBefore,
      edgeCountAfter: edgeCountAfter,
    );
  }

  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'phase': phase,
    'commandType': commandType,
    'commandName': commandName,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'nodeCountBefore': nodeCountBefore,
    'nodeCountAfter': nodeCountAfter,
    'edgeCountBefore': edgeCountBefore,
    'edgeCountAfter': edgeCountAfter,
  };

  factory CommandReplayEntry.fromJson(Map<String, dynamic> json) {
    return CommandReplayEntry(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      phase: json['phase'] as String? ?? 'execute',
      commandType: json['commandType'] as String? ?? 'UnknownCommand',
      commandName: json['commandName'] as String? ?? 'Unnamed command',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      nodeCountBefore: (json['nodeCountBefore'] as num?)?.toInt() ?? 0,
      nodeCountAfter: (json['nodeCountAfter'] as num?)?.toInt() ?? 0,
      edgeCountBefore: (json['edgeCountBefore'] as num?)?.toInt() ?? 0,
      edgeCountAfter: (json['edgeCountAfter'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommandReplayLog {
  static const String format = 'varian.canvas.command-replay';
  static const int version = 1;

  final String projectId;
  final DateTime createdAt;
  final List<CommandReplayEntry> entries;

  const CommandReplayLog({
    required this.projectId,
    required this.createdAt,
    this.entries = const [],
  });

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'projectId': projectId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };

  String encode({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  factory CommandReplayLog.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const FormatException('Unsupported command replay format.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List) {
      throw const FormatException('Command replay entries must be a list.');
    }
    return CommandReplayLog(
      projectId: json['projectId'] as String? ?? 'default_proj',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      entries: [
        for (final rawEntry in rawEntries)
          if (rawEntry is Map)
            CommandReplayEntry.fromJson(Map<String, dynamic>.from(rawEntry)),
      ],
    );
  }

  factory CommandReplayLog.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Command replay root must be an object.');
    }
    return CommandReplayLog.fromJson(Map<String, dynamic>.from(decoded));
  }
}

class CommandReplayRecorder {
  final String projectId;
  final DateTime createdAt;
  final List<CommandReplayEntry> _entries = [];

  CommandReplayRecorder({required this.projectId, DateTime? createdAt})
    : createdAt = (createdAt ?? DateTime.now()).toUtc();

  void record({
    required String phase,
    required EditorCommand command,
    required int nodeCountBefore,
    required int nodeCountAfter,
    required int edgeCountBefore,
    required int edgeCountAfter,
    DateTime? timestamp,
  }) {
    _entries.add(
      CommandReplayEntry.fromCommand(
        sequence: _entries.length,
        phase: phase,
        command: command,
        timestamp: timestamp ?? DateTime.now(),
        nodeCountBefore: nodeCountBefore,
        nodeCountAfter: nodeCountAfter,
        edgeCountBefore: edgeCountBefore,
        edgeCountAfter: edgeCountAfter,
      ),
    );
  }

  CommandReplayLog build() => CommandReplayLog(
    projectId: projectId,
    createdAt: createdAt,
    entries: List<CommandReplayEntry>.unmodifiable(_entries),
  );
}
