import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';

void main() {
  group('Infinite Board Feature Suite Tests', () {
    test('Content Expansion payloads serialize and deserialize accurately', () {
      // 1. FilePayload
      final fileNode = CanvasNode(
        id: 'file_1',
        type: NodeType.fileCard,
        x: 10,
        y: 10,
        width: 200,
        height: 80,
        payload: FilePayload(
          fileName: 'Architecture.pdf',
          fileExtension: 'PDF',
          fileSizeText: '4.5 MB',
        ),
      );
      final fileJson = fileNode.toJson();
      final restoredFile = CanvasNode.fromJson(fileJson);
      expect(restoredFile.type, equals(NodeType.fileCard));
      expect(
        (restoredFile.payload as FilePayload).fileName,
        equals('Architecture.pdf'),
      );

      // 2. LinkPayload
      final linkNode = CanvasNode(
        id: 'link_1',
        type: NodeType.linkCard,
        x: 20,
        y: 20,
        width: 240,
        height: 90,
        payload: LinkPayload(
          title: 'Supabase Docs',
          url: 'https://supabase.com/docs',
        ),
      );
      final restoredLink = CanvasNode.fromJson(linkNode.toJson());
      expect(restoredLink.type, equals(NodeType.linkCard));
      expect(
        (restoredLink.payload as LinkPayload).title,
        equals('Supabase Docs'),
      );

      // 3. Media & Swatch
      final swatchNode = CanvasNode(
        id: 'swatch_1',
        type: NodeType.colorSwatch,
        x: 0,
        y: 0,
        width: 100,
        height: 120,
        payload: ColorSwatchPayload(
          label: 'Amber Glow',
          color: const Color(0xFFD97706),
          colorHex: '#D97706',
        ),
      );
      final restoredSwatch = CanvasNode.fromJson(swatchNode.toJson());
      expect(
        (restoredSwatch.payload as ColorSwatchPayload).colorHex,
        equals('#D97706'),
      );
    });

    test('Audio payload preserves playback metadata and source settings', () {
      final payload = AudioPayload(
        trackName: 'Field Recording',
        artist: 'Braun Sound',
        durationText: '02:14',
        durationSeconds: 134,
        audioPath: 'C:/audio/recording.mp3',
        isLooping: true,
        playbackSpeed: 1.25,
      );
      final restored = AudioPayload.fromJson(payload.toJson());

      expect(restored.artist, 'Braun Sound');
      expect(AudioPayload().artist, isEmpty);
      expect(restored.durationSeconds, 134);
      // Playback state is runtime-only and is restored to safe defaults.
      expect(restored.isLooping, isFalse);
      expect(restored.playbackSpeed, 1.0);
    });

    test('Audio payload identifies supported source schemes', () {
      expect(AudioPayload.isRemoteSource('https://example.com/a.mp3'), isTrue);
      expect(
        AudioPayload.isRemoteSource('blob:https://example.com/id'),
        isTrue,
      );
      expect(AudioPayload.isRemoteSource('data:audio/mpeg;base64,abc'), isTrue);
      expect(AudioPayload.isRemoteSource('C:/audio/a.mp3'), isFalse);
    });

    test(
      'Creative & Organization payloads serialize and deserialize properly',
      () {
        // 1. TodoListPayload
        final todoNode = CanvasNode(
          id: 'todo_1',
          type: NodeType.todoList,
          x: 50,
          y: 50,
          width: 200,
          height: 150,
          payload: TodoListPayload(
            title: 'Sprint Backlog',
            items: [
              TodoItem(id: 't1', text: 'Write Unit Tests', isDone: true),
              TodoItem(id: 't2', text: 'Deploy to Web', isDone: false),
            ],
          ),
        );
        final restoredTodo = CanvasNode.fromJson(todoNode.toJson());
        final todoPayload = restoredTodo.payload as TodoListPayload;
        expect(todoPayload.title, equals('Sprint Backlog'));
        expect(todoPayload.items.length, equals(2));
        expect(todoPayload.items[0].isDone, isTrue);

        // 2. TablePayload
        final tableNode = CanvasNode(
          id: 'tbl_1',
          type: NodeType.tableGrid,
          x: 0,
          y: 0,
          width: 300,
          height: 120,
          payload: TablePayload(
            columns: ['Col A', 'Col B'],
            rows: [
              ['Val 1', 'Val 2'],
            ],
          ),
        );
        final restoredTable = CanvasNode.fromJson(tableNode.toJson());
        expect(
          (restoredTable.payload as TablePayload).columns.length,
          equals(2),
        );

        // 3. ColumnPayload & NestedBoardPayload
        final colNode = CanvasNode(
          id: 'col_1',
          type: NodeType.columnContainer,
          x: 0,
          y: 0,
          width: 200,
          height: 300,
          payload: ColumnPayload(
            headerTitle: 'QA Ready',
            itemTitles: ['Ticket A', 'Ticket B'],
          ),
        );
        final restoredCol = CanvasNode.fromJson(colNode.toJson());
        expect(
          (restoredCol.payload as ColumnPayload).headerTitle,
          equals('QA Ready'),
        );
      },
    );

    test(
      'NodePainter renders new Infinite Board node types without throwing',
      () {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);

        final nodesToPaint = [
          CanvasNode(
            id: '1',
            type: NodeType.fileCard,
            x: 0,
            y: 0,
            width: 200,
            height: 70,
            payload: FilePayload(),
          ),
          CanvasNode(
            id: '2',
            type: NodeType.linkCard,
            x: 0,
            y: 0,
            width: 220,
            height: 80,
            payload: LinkPayload(),
          ),
          CanvasNode(
            id: '3',
            type: NodeType.videoCard,
            x: 0,
            y: 0,
            width: 200,
            height: 140,
            payload: VideoPayload(),
          ),
          CanvasNode(
            id: '4',
            type: NodeType.audioCard,
            x: 0,
            y: 0,
            width: 200,
            height: 70,
            payload: AudioPayload(),
          ),
          CanvasNode(
            id: '5',
            type: NodeType.mapCard,
            x: 0,
            y: 0,
            width: 180,
            height: 140,
            payload: MapPayload(),
          ),
          CanvasNode(
            id: '6',
            type: NodeType.colorSwatch,
            x: 0,
            y: 0,
            width: 100,
            height: 120,
            payload: ColorSwatchPayload(),
          ),
          CanvasNode(
            id: '7',
            type: NodeType.sketchCard,
            x: 0,
            y: 0,
            width: 180,
            height: 120,
            payload: SketchCardPayload(),
          ),
          CanvasNode(
            id: '8',
            type: NodeType.annotatedImage,
            x: 0,
            y: 0,
            width: 200,
            height: 150,
            payload: AnnotatedImagePayload(),
          ),
          CanvasNode(
            id: '9',
            type: NodeType.columnContainer,
            x: 0,
            y: 0,
            width: 200,
            height: 200,
            payload: ColumnPayload(),
          ),
          CanvasNode(
            id: '10',
            type: NodeType.nestedBoard,
            x: 0,
            y: 0,
            width: 220,
            height: 140,
            payload: NestedBoardPayload(),
          ),
          CanvasNode(
            id: '11',
            type: NodeType.tableGrid,
            x: 0,
            y: 0,
            width: 250,
            height: 120,
            payload: TablePayload(),
          ),
          CanvasNode(
            id: '12',
            type: NodeType.todoList,
            x: 0,
            y: 0,
            width: 200,
            height: 150,
            payload: TodoListPayload(),
          ),
        ];

        for (final node in nodesToPaint) {
          expect(() => NodePainter.paint(canvas, node), returnsNormally);
        }
      },
    );

    test(
      'Collaboration threaded comments, replies, mentions, and reactions serialization',
      () {
        final comment = CanvasComment(
          id: 'c_root',
          authorId: 'u1',
          authorName: 'Sarah Architect',
          text: 'Please review the schema @Alex and @David',
          x: 150,
          y: 220,
          createdAt: DateTime.now(),
          mentions: ['Alex', 'David'],
          reactions: {'👍': 4, '🚀': 2},
          replies: [
            CommentReply(
              id: 'r1',
              authorId: 'u2',
              authorName: 'Alex',
              text: 'Looks solid, proceeding with implementation.',
              createdAt: DateTime.now(),
            ),
          ],
        );

        final json = comment.toJson();
        final restored = CanvasComment.fromJson(json);

        expect(restored.id, equals('c_root'));
        expect(restored.mentions.length, equals(2));
        expect(restored.mentions.contains('Alex'), isTrue);
        expect(restored.reactions['👍'], equals(4));
        expect(restored.replies.length, equals(1));
        expect(restored.replies.first.authorName, equals('Alex'));
      },
    );
  });
}
