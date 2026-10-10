import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'media_processing_queue.dart';

enum MediaProcessingCheckpointEventType {
  evicted,
  skippedEphemeral,
  skippedSize,
  readFailed,
  writeFailed,
}

class MediaProcessingCheckpointEvent {
  final MediaProcessingCheckpointEventType type;
  final String? requestId;
  final int? encodedBytes;
  final int? checkpointCount;
  final String? error;

  const MediaProcessingCheckpointEvent({
    required this.type,
    this.requestId,
    this.encodedBytes,
    this.checkpointCount,
    this.error,
  });
}

typedef MediaProcessingCheckpointObserver =
    void Function(MediaProcessingCheckpointEvent event);

class _MediaProcessingCheckpointMutation {
  final bool shouldWrite;
  final List<MediaProcessingCheckpointEvent> events;

  const _MediaProcessingCheckpointMutation({
    required this.shouldWrite,
    this.events = const [],
  });
}

class MemoryMediaProcessingCheckpointStore
    implements MediaProcessingCheckpointStore {
  final Map<String, Map<String, dynamic>> _items = {};

  @override
  Future<List<MediaProcessingRequest>> load() async => [
    for (final item in _items.values)
      if (MediaProcessingRequest.tryFromJson(item) case final request?
          when request.isCheckpointable)
        request,
  ];

  @override
  Future<void> upsert(MediaProcessingRequest request) async {
    if (!request.isCheckpointable) return;
    _items[request.id] = request.toCheckpointJson();
  }

  @override
  Future<void> remove(String requestId) async {
    _items.remove(requestId);
  }
}

class SharedPreferencesMediaProcessingCheckpointStore
    implements MediaProcessingCheckpointStore {
  static const storageKey = 'varian.media.processing.checkpoints.v1';
  static const defaultMaxEntries = 32;
  static const defaultMaxEncodedBytes = 512 * 1024;

  final Future<SharedPreferences> _preferences;
  final int maxEntries;
  final int maxEncodedBytes;
  final MediaProcessingCheckpointObserver? observer;
  Future<void> _writeTail = Future<void>.value();

  SharedPreferencesMediaProcessingCheckpointStore({
    Future<SharedPreferences>? preferences,
    this.maxEntries = defaultMaxEntries,
    this.maxEncodedBytes = defaultMaxEncodedBytes,
    this.observer,
  }) : assert(maxEntries > 0),
       assert(maxEncodedBytes > 0),
       _preferences = preferences ?? SharedPreferences.getInstance();

  @override
  Future<List<MediaProcessingRequest>> load() async {
    await _writeTail;
    try {
      final preferences = await _preferences;
      return _decode(preferences.getString(storageKey));
    } catch (error) {
      _notify(
        MediaProcessingCheckpointEventType.readFailed,
        error: error.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<void> upsert(MediaProcessingRequest request) => _mutate((items) {
    if (!request.isCheckpointable) {
      return _MediaProcessingCheckpointMutation(
        shouldWrite: false,
        events: [
          MediaProcessingCheckpointEvent(
            type: MediaProcessingCheckpointEventType.skippedEphemeral,
            requestId: request.id,
          ),
        ],
      );
    }
    final candidate = Map<String, Map<String, dynamic>>.from(items)
      ..[request.id] = request.toCheckpointJson();
    final evicted = _evictToBounds(candidate, protectedId: request.id);
    if (evicted == null) {
      return _MediaProcessingCheckpointMutation(
        shouldWrite: false,
        events: [
          MediaProcessingCheckpointEvent(
            type: MediaProcessingCheckpointEventType.skippedSize,
            requestId: request.id,
            encodedBytes: _encodedBytes(candidate),
            checkpointCount: candidate.length,
          ),
        ],
      );
    }
    items
      ..clear()
      ..addAll(candidate);
    return _MediaProcessingCheckpointMutation(
      shouldWrite: true,
      events: [
        for (final evictedId in evicted)
          MediaProcessingCheckpointEvent(
            type: MediaProcessingCheckpointEventType.evicted,
            requestId: evictedId,
            encodedBytes: _encodedBytes(items),
            checkpointCount: items.length,
          ),
      ],
    );
  });

  @override
  Future<void> remove(String requestId) => _mutate((items) {
    return _MediaProcessingCheckpointMutation(
      shouldWrite: items.remove(requestId) != null,
    );
  });

  Future<void> _mutate(
    _MediaProcessingCheckpointMutation Function(
      Map<String, Map<String, dynamic>> items,
    )
    mutation,
  ) {
    final operation = _writeTail.then((_) async {
      try {
        final preferences = await _preferences;
        final items = <String, Map<String, dynamic>>{
          for (final request in _checkpointableMaps(
            preferences.getString(storageKey),
          ))
            request['id'] as String: request,
        };
        final mutationResult = mutation(items);
        if (!mutationResult.shouldWrite) {
          _notifyAll(mutationResult.events);
          return;
        }
        final written = await preferences.setString(
          storageKey,
          jsonEncode(items.values.toList()),
        );
        if (!written) {
          throw StateError('Media processing checkpoint write failed.');
        }
        _notifyAll(mutationResult.events);
      } catch (error) {
        _notify(
          MediaProcessingCheckpointEventType.writeFailed,
          error: error.toString(),
        );
        rethrow;
      }
    });
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  List<MediaProcessingRequest> _decode(String? raw) => [
    for (final item in _checkpointableMaps(raw))
      if (MediaProcessingRequest.tryFromJson(item) case final request?
          when request.isCheckpointable)
        request,
  ];

  Iterable<Map<String, dynamic>> _checkpointableMaps(String? raw) sync* {
    for (final item in _decodeMaps(raw)) {
      final request = MediaProcessingRequest.tryFromJson(item);
      if (request?.isCheckpointable == true) yield item;
    }
  }

  List<String>? _evictToBounds(
    Map<String, Map<String, dynamic>> items, {
    required String protectedId,
  }) {
    final evicted = <String>[];
    while (items.length > maxEntries ||
        _encodedBytes(items) > maxEncodedBytes) {
      String? oldestId;
      for (final id in items.keys) {
        if (id != protectedId) {
          oldestId = id;
          break;
        }
      }
      if (oldestId == null) return null;
      items.remove(oldestId);
      evicted.add(oldestId);
    }
    return evicted;
  }

  int _encodedBytes(Map<String, Map<String, dynamic>> items) =>
      utf8.encode(jsonEncode(items.values.toList())).length;

  void _notify(
    MediaProcessingCheckpointEventType type, {
    String? requestId,
    int? encodedBytes,
    int? checkpointCount,
    String? error,
  }) {
    _notifyEvent(
      MediaProcessingCheckpointEvent(
        type: type,
        requestId: requestId,
        encodedBytes: encodedBytes,
        checkpointCount: checkpointCount,
        error: error,
      ),
    );
  }

  void _notifyAll(Iterable<MediaProcessingCheckpointEvent> events) {
    for (final event in events) {
      _notifyEvent(event);
    }
  }

  void _notifyEvent(MediaProcessingCheckpointEvent event) {
    try {
      observer?.call(event);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _decodeMaps(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const [];
    }
  }
}
