import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/commands/command_replay.dart';
import 'package:varian/features/canvas/commands/editor_commands.dart';

void main() {
  test('records command metadata and round trips the debug export', () {
    final node = CanvasNode(
      id: 'node-1',
      type: NodeType.rectangle,
      x: 0,
      y: 0,
      width: 100,
      height: 80,
      payload: ShapePayload(),
    );
    final command = CreateNodeCommand(node);
    final recorder = CommandReplayRecorder(
      projectId: 'project-1',
      createdAt: DateTime.utc(2026, 9, 11),
    );

    recorder.record(
      phase: 'execute',
      command: command,
      nodeCountBefore: 0,
      nodeCountAfter: 1,
      edgeCountBefore: 0,
      edgeCountAfter: 0,
      timestamp: DateTime.utc(2026, 9, 11, 1),
    );

    final restored = CommandReplayLog.decode(recorder.build().encode());
    expect(restored.projectId, 'project-1');
    expect(restored.entries.single.commandName, 'Create Node');
    expect(restored.entries.single.commandType, 'CreateNodeCommand');
    expect(restored.entries.single.nodeCountAfter, 1);
  });
}
