import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_queue.dart';

void main() {
  test('runs jobs serially and preserves completion results', () async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    final running = <String>[];
    final first = queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () async {
        running.add('first-start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        running.add('first-end');
        return const ExportPresetResult.text(ExportPresetRegistry.json, '{}');
      },
    );
    final second = queue.enqueue(
      preset: ExportPresetRegistry.markdown,
      task: () async {
        running.add('second');
        return const ExportPresetResult.text(
          ExportPresetRegistry.markdown,
          '# doc',
        );
      },
    );

    await queue.waitForIdle();

    expect(running, ['first-start', 'first-end', 'second']);
    expect(queue[first]?.status, ExportQueueJobStatus.completed);
    expect(queue[first]?.result?.text, '{}');
    expect(queue[second]?.status, ExportQueueJobStatus.completed);
  });

  test('cancels queued work and retries failed work', () async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    final gate = Completer<void>();
    var attempts = 0;
    queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () async {
        await gate.future;
        return const ExportPresetResult.text(ExportPresetRegistry.json, '{}');
      },
      id: 'blocking',
    );
    final canceled = queue.enqueue(
      preset: ExportPresetRegistry.markdown,
      task: () async =>
          const ExportPresetResult.text(ExportPresetRegistry.markdown, 'skip'),
      id: 'canceled',
    );
    final failed = queue.enqueue(
      preset: ExportPresetRegistry.plainText,
      task: () async {
        attempts++;
        if (attempts == 1) throw StateError('temporary');
        return const ExportPresetResult.text(
          ExportPresetRegistry.plainText,
          'ok',
        );
      },
      id: 'retryable',
    );

    expect(queue.cancel(canceled), isTrue);
    gate.complete();
    await queue.waitForIdle();
    expect(queue[canceled]?.status, ExportQueueJobStatus.canceled);
    expect(queue[failed]?.status, ExportQueueJobStatus.failed);
    expect(queue.retry(failed), isTrue);
    await queue.waitForIdle();
    expect(queue[failed]?.status, ExportQueueJobStatus.completed);
    expect(attempts, 2);
  });

  test('marks null results as failed and supports terminal cleanup', () async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    final id = queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () async => null,
    );

    await queue.waitForIdle();

    expect(queue[id]?.status, ExportQueueJobStatus.failed);
    expect(queue[id]?.error, isA<StateError>());
    queue.clearTerminal();
    expect(queue.jobs, isEmpty);
  });

  test('waits for one job without waiting for unrelated queue work', () async {
    final queue = ExportQueue();
    addTearDown(queue.dispose);
    final gate = Completer<void>();
    final first = queue.enqueue(
      preset: ExportPresetRegistry.json,
      task: () async {
        await gate.future;
        return const ExportPresetResult.text(ExportPresetRegistry.json, '{}');
      },
      id: 'first',
    );
    final second = queue.enqueue(
      preset: ExportPresetRegistry.markdown,
      task: () async =>
          const ExportPresetResult.text(ExportPresetRegistry.markdown, '# doc'),
      id: 'second',
    );

    final firstDone = queue.waitForJob(first);
    gate.complete();
    final firstJob = await firstDone;

    expect(firstJob.status, ExportQueueJobStatus.completed);
    expect(
      queue[second]?.status,
      anyOf(ExportQueueJobStatus.queued, ExportQueueJobStatus.running),
    );

    await queue.waitForJob(second);
    expect(queue[second]?.status, ExportQueueJobStatus.completed);
  });

  test('encodes rendered PNG bytes as JPEG and WebP presets', () {
    final source = image.Image(width: 2, height: 2);
    source.setPixelRgba(0, 0, 255, 32, 64, 255);
    final png = Uint8List.fromList(image.encodePng(source));

    final jpeg = encodeRasterExport(png, format: ExportPresetFormat.jpeg);
    final webp = encodeRasterExport(png, format: ExportPresetFormat.webp);

    expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
    expect(webp.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]);
    expect(webp.sublist(8, 12), [0x57, 0x45, 0x42, 0x50]);
  });
}
