import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/charts/data/chart_source_loader.dart';

class _FakeClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  _FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _response(
  http.BaseRequest request,
  String body, {
  int statusCode = 200,
  int? contentLength,
}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    contentLength: contentLength ?? bytes.length,
    request: request,
  );
}

void main() {
  test('loads the supported nested chart JSON contract', () async {
    late http.BaseRequest request;
    final client = _FakeClient((nextRequest) async {
      request = nextRequest;
      return _response(
        nextRequest,
        jsonEncode({
          'data': {
            'categories': ['Q1', 'Q2'],
            'series': [
              {
                'name': 'Revenue',
                'values': [10, 14],
              },
            ],
          },
        }),
      );
    });
    final loader = ChartSourceLoader(client: client);
    addTearDown(loader.dispose);

    final payload = await loader.load('https://example.com/chart.json');

    expect(request.method, 'GET');
    expect(request.url.toString(), 'https://example.com/chart.json');
    expect((request as http.Request).followRedirects, isFalse);
    expect((request as http.Request).maxRedirects, 0);
    expect(payload.categories, ['Q1', 'Q2']);
    expect(payload.series.single.values, [10, 14]);
  });

  test('rejects non HTTP(S) URLs and URLs with credentials', () async {
    var calls = 0;
    final loader = ChartSourceLoader(
      client: _FakeClient((_) async {
        calls++;
        throw StateError('must not send');
      }),
    );
    addTearDown(loader.dispose);

    await expectLater(
      loader.load('file:///private/chart.json'),
      throwsA(isA<ChartSourceException>()),
    );
    await expectLater(
      loader.load('https://user:password@example.com/chart.json'),
      throwsA(isA<ChartSourceException>()),
    );
    expect(calls, 0);
  });

  test('rejects invalid responses and oversized payloads', () async {
    final invalidClient = _FakeClient(
      (request) async =>
          _response(request, '{"categories": []}', statusCode: 500),
    );
    final invalidLoader = ChartSourceLoader(client: invalidClient);
    addTearDown(invalidLoader.dispose);
    await expectLater(
      invalidLoader.load('https://example.com/chart.json'),
      throwsA(isA<ChartSourceException>()),
    );

    final oversizedClient = _FakeClient(
      (request) async => _response(
        request,
        '{}',
        contentLength: ChartSourceLoader.maxResponseBytes + 1,
      ),
    );
    final oversizedLoader = ChartSourceLoader(client: oversizedClient);
    addTearDown(oversizedLoader.dispose);
    await expectLater(
      oversizedLoader.load('https://example.com/chart.json'),
      throwsA(isA<ChartSourceException>()),
    );
  });

  test(
    'rejects malformed chart data instead of returning an empty payload',
    () async {
      final client = _FakeClient(
        (request) async => _response(
          request,
          jsonEncode({
            'categories': ['A'],
            'series': [],
          }),
        ),
      );
      final loader = ChartSourceLoader(client: client);
      addTearDown(loader.dispose);

      await expectLater(
        loader.load('https://example.com/chart.json'),
        throwsA(isA<ChartSourceException>()),
      );
    },
  );
}
