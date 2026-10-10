import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/features/media/data/media_processing_checkpoint_store.dart';
import 'package:varian/features/media/data/media_processing_queue.dart';

MediaProcessingOutput outputFor(MediaArtifactKind kind) =>
    MediaProcessingOutput(
      artifacts: MediaArtifactManifest(
        items: [
          MediaArtifact(
            kind: kind,
            url: 'https://cdn.example/${kind.name}',
            checksum: 'sha256:${kind.name}',
          ),
        ],
      ),
      checksum: 'sha256:output',
    );

void main() {
  test('deduplicates equivalent requests and validates checksums', () async {
    var calls = 0;
    final queue = MediaProcessingQueue(
      handler: (request, _) async {
        calls++;
        return outputFor(request.artifactKinds.single);
      },
    );
    const request = MediaProcessingRequest(
      id: 'job-a',
      sourceKey: 'asset-a',
      inputChecksum: 'sha256:input',
      artifactKinds: [MediaArtifactKind.waveform],
    );

    final first = queue.enqueue(request);
    final duplicate = queue.enqueue(
      const MediaProcessingRequest(
        id: 'job-b',
        sourceKey: 'asset-a',
        inputChecksum: 'sha256:input',
        artifactKinds: [MediaArtifactKind.waveform],
      ),
    );
    await queue.waitForIdle();

    expect(duplicate.request.id, first.request.id);
    expect(queue[first.request.id]!.status, MediaProcessingStatus.succeeded);
    expect(calls, 1);
    await queue.dispose();
  });

  test('retries failed work up to maxAttempts', () async {
    var calls = 0;
    final queue = MediaProcessingQueue(
      handler: (request, _) async {
        calls++;
        if (calls == 1) throw StateError('temporary');
        return outputFor(request.artifactKinds.single);
      },
    );
    final job = queue.enqueue(
      const MediaProcessingRequest(
        id: 'retry',
        sourceKey: 'asset',
        inputChecksum: 'input',
        artifactKinds: [MediaArtifactKind.preview],
        maxAttempts: 2,
      ),
    );
    await queue.waitForIdle();

    expect(queue[job.request.id]!.status, MediaProcessingStatus.succeeded);
    expect(queue[job.request.id]!.attempt, 2);
    expect(calls, 2);
    await queue.dispose();
  });

  test('cancels queued work without invoking its handler', () async {
    final blocker = Completer<void>();
    var calls = 0;
    final queue = MediaProcessingQueue(
      handler: (request, _) async {
        calls++;
        if (request.id == 'first') await blocker.future;
        return outputFor(request.artifactKinds.single);
      },
    );
    queue.enqueue(
      const MediaProcessingRequest(
        id: 'first',
        sourceKey: 'first',
        inputChecksum: 'one',
        artifactKinds: [MediaArtifactKind.preview],
      ),
    );
    final second = queue.enqueue(
      const MediaProcessingRequest(
        id: 'second',
        sourceKey: 'second',
        inputChecksum: 'two',
        artifactKinds: [MediaArtifactKind.preview],
      ),
    );
    expect(queue.cancel(second.request.id), isTrue);
    blocker.complete();
    await queue.waitForIdle();

    expect(queue[second.request.id]!.status, MediaProcessingStatus.cancelled);
    expect(calls, 1);
    await queue.dispose();
  });

  test('restores a checkpointed request after queue recreation', () async {
    final store = MemoryMediaProcessingCheckpointStore();
    const request = MediaProcessingRequest(
      id: 'resume',
      sourceKey: 'asset',
      inputChecksum: 'input',
      artifactKinds: [MediaArtifactKind.preview],
      metadata: {
        'sourceBytesBase64': 'must-not-persist',
        'sourceMimeType': 'video/mp4',
      },
    );
    await store.upsert(request);

    var calls = 0;
    final queue = MediaProcessingQueue(
      checkpointStore: store,
      handler: (request, _) async {
        calls++;
        return outputFor(request.artifactKinds.single);
      },
    );
    await queue.waitForIdle();

    expect(calls, 1);
    expect(queue['resume']?.status, MediaProcessingStatus.succeeded);
    expect(await store.load(), isEmpty);
    await queue.dispose();
  });

  test('checkpoint serialization excludes transient source bytes', () async {
    final store = MemoryMediaProcessingCheckpointStore();
    const request = MediaProcessingRequest(
      id: 'safe-checkpoint',
      sourceKey: 'file:///media.wav',
      inputChecksum: 'input',
      artifactKinds: [MediaArtifactKind.waveform],
      metadata: {
        'sourceBytesBase64': 'private-bytes',
        'sourceMimeType': 'audio/wav',
      },
    );
    await store.upsert(request);

    final restored = await store.load();
    expect(restored, hasLength(1));
    expect(restored.single.metadata, {'sourceMimeType': 'audio/wav'});
  });

  test('does not persist ephemeral source keys', () async {
    final store = MemoryMediaProcessingCheckpointStore();
    final sourceKeys = [
      'data:audio/wav;base64,AAAA',
      'blob:https://example.test/temporary-media',
      'memory://audio.wav',
    ];

    for (var index = 0; index < sourceKeys.length; index++) {
      await store.upsert(
        MediaProcessingRequest(
          id: 'ephemeral-$index',
          sourceKey: sourceKeys[index],
          inputChecksum: 'input-$index',
          artifactKinds: const [MediaArtifactKind.waveform],
        ),
      );
    }

    expect(await store.load(), isEmpty);
  });

  test(
    'shared preferences store persists, updates, and removes checkpoints',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesMediaProcessingCheckpointStore(
        preferences: Future.value(preferences),
      );
      const first = MediaProcessingRequest(
        id: 'prefs-first',
        sourceKey: 'file:///media-first.wav',
        inputChecksum: 'input-first',
        artifactKinds: [MediaArtifactKind.waveform],
      );
      const second = MediaProcessingRequest(
        id: 'prefs-second',
        sourceKey: 'file:///media-second.wav',
        inputChecksum: 'input-second',
        artifactKinds: [MediaArtifactKind.thumbnail],
      );

      await Future.wait([store.upsert(first), store.upsert(second)]);
      final restored = await store.load();
      expect(
        restored.map((request) => request.id),
        containsAll(<String>['prefs-first', 'prefs-second']),
      );

      await store.remove(first.id);
      expect((await store.load()).map((request) => request.id), [
        'prefs-second',
      ]);
    },
  );

  test('shared preferences store ignores ephemeral checkpoints', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesMediaProcessingCheckpointStore(
      preferences: Future.value(preferences),
    );

    await store.upsert(
      const MediaProcessingRequest(
        id: 'prefs-ephemeral',
        sourceKey: 'blob:https://example.test/temporary-media',
        inputChecksum: 'input',
        artifactKinds: [MediaArtifactKind.preview],
      ),
    );

    expect(await store.load(), isEmpty);
  });

  test(
    'shared preferences store evicts oldest checkpoints at the count limit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final events = <MediaProcessingCheckpointEvent>[];
      final store = SharedPreferencesMediaProcessingCheckpointStore(
        preferences: Future.value(preferences),
        maxEntries: 2,
        observer: events.add,
      );

      for (var index = 1; index <= 3; index++) {
        await store.upsert(
          MediaProcessingRequest(
            id: 'bounded-$index',
            sourceKey: 'file:///media-$index.wav',
            inputChecksum: 'input-$index',
            artifactKinds: const [MediaArtifactKind.waveform],
          ),
        );
      }

      expect((await store.load()).map((request) => request.id), [
        'bounded-2',
        'bounded-3',
      ]);
      expect(
        events.where(
          (event) => event.type == MediaProcessingCheckpointEventType.evicted,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'shared preferences store skips checkpoints over the byte limit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final events = <MediaProcessingCheckpointEvent>[];
      final store = SharedPreferencesMediaProcessingCheckpointStore(
        preferences: Future.value(preferences),
        maxEncodedBytes: 256,
        observer: events.add,
      );

      await store.upsert(
        MediaProcessingRequest(
          id: 'oversized',
          sourceKey: 'file:///oversized.wav',
          inputChecksum: 'input',
          artifactKinds: const [MediaArtifactKind.waveform],
          metadata: {'timelineJson': 'x' * 1_024},
        ),
      );

      expect(await store.load(), isEmpty);
      expect(
        events.where(
          (event) =>
              event.type == MediaProcessingCheckpointEventType.skippedSize,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'shared preferences store removes legacy ephemeral checkpoints on write',
    () async {
      const legacyEphemeral = MediaProcessingRequest(
        id: 'legacy-ephemeral',
        sourceKey: 'memory://old.wav',
        inputChecksum: 'old-input',
        artifactKinds: [MediaArtifactKind.waveform],
      );
      SharedPreferences.setMockInitialValues({
        SharedPreferencesMediaProcessingCheckpointStore.storageKey: jsonEncode([
          legacyEphemeral.toCheckpointJson(),
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesMediaProcessingCheckpointStore(
        preferences: Future.value(preferences),
      );

      await store.upsert(
        const MediaProcessingRequest(
          id: 'new-stable',
          sourceKey: 'file:///new.wav',
          inputChecksum: 'new-input',
          artifactKinds: [MediaArtifactKind.preview],
        ),
      );

      expect((await store.load()).map((request) => request.id), ['new-stable']);
      expect(
        preferences.getString(
          SharedPreferencesMediaProcessingCheckpointStore.storageKey,
        ),
        isNot(contains('legacy-ephemeral')),
      );
    },
  );
}
