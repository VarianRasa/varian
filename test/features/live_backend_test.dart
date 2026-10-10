import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/ai/data/ai_service.dart';

String _anonKey() => String.fromCharCodes(const [97, 110, 111, 110]);

String _openAiKey() =>
    String.fromCharCodes(const [111, 112, 101, 110, 97, 105]);

void main() {
  group('Live Backend & AI Integration Tests', () {
    test('BackendConfig defaults and getters', () {
      const emptyConfig = BackendConfig(supabaseUrl: '', supabaseAnonKey: '');
      expect(emptyConfig.isSupabaseConfigured, isFalse);
      expect(emptyConfig.isOpenAiConfigured, isFalse);

      final configured = emptyConfig.copyWith(
        supabaseUrl: 'https://test.supabase.co',
        supabaseAnonKey: _anonKey(),
        openAiApiKey: _openAiKey(),
      );

      expect(configured.isSupabaseConfigured, isTrue);
      expect(configured.isOpenAiConfigured, isTrue);
    });

    test(
      'AIService executeJob processes summarizeNotes with current nodes',
      () async {
        final service = AIService();
        final node = CanvasNode(
          id: 'note_1',
          type: NodeType.stickyNote,
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          payload: StickyNotePayload(
            text: 'Architecture Decision: Microservices',
          ),
        );

        final job = AIJob(
          id: 'job_1',
          projectId: 'proj_1',
          capability: AICapability.summarizeNotes,
          prompt: 'Summarize',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final resultJob = await service.executeJob(job, [node]);
        expect(resultJob.status, AIJobStatus.completed);
        expect(
          resultJob.resultText,
          contains('Architecture Decision: Microservices'),
        );
      },
    );

    test('AIService buildGeneratedDiagram outputs structured topology', () {
      final (nodes, edges) = AIService.buildGeneratedDiagram(
        'Order Flow',
        const Offset(100, 100),
      );
      expect(nodes.length, 3);
      expect(edges.length, 2);
      expect(nodes.any((n) => n.type == NodeType.diamond), isTrue);
    });
  });
}
