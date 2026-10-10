import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/data/canvas_file_source.dart';

void main() {
  test('reads an XFile stream when it stays within the byte cap', () async {
    final file = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3]),
      name: 'small.bin',
    );

    expect(
      await readCanvasXFileBytes(file, maxBytes: 3),
      orderedEquals(<int>[1, 2, 3]),
    );
  });

  test('rejects an XFile stream that exceeds the byte cap', () async {
    final file = XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      name: 'large.bin',
    );

    expect(await readCanvasXFileBytes(file, maxBytes: 3), isNull);
  });

  test(
    'rejects a stream that grows beyond the byte cap after its first chunk',
    () async {
      final chunks = Stream<List<int>>.fromIterable([
        <int>[1, 2],
        <int>[3, 4],
      ]);

      expect(await readCanvasByteStreamBytes(chunks, maxBytes: 3), isNull);
    },
  );
}
