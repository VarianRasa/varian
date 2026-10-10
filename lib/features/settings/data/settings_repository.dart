import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/workspace_governance.dart';
import '../domain/settings_models.dart';

abstract interface class SettingsCodec<T> {
  Object? encode(T value);
  T decode(Object? raw);
}

class JsonSettingsCodec<T> implements SettingsCodec<T> {
  final Object? Function(T value) _encodeValue;
  final T Function(Object? raw) _decodeValue;

  const JsonSettingsCodec({
    required Object? Function(T value) encode,
    required T Function(Object? raw) decode,
  }) : _encodeValue = encode,
       _decodeValue = decode;

  @override
  Object? encode(T value) => _encodeValue(value);

  @override
  T decode(Object? raw) => _decodeValue(raw);
}

final class AccessibilitySettingsCodec
    extends JsonSettingsCodec<AccessibilitySettings> {
  const AccessibilitySettingsCodec() : super(encode: _encode, decode: _decode);

  static Object? _encode(AccessibilitySettings value) => value.toJson();

  static AccessibilitySettings _decode(Object? raw) =>
      AccessibilitySettings.fromJson(raw);
}

/// A small, typed, serialized settings boundary.
///
/// Secret material is intentionally not accepted here. Integrations keep
/// credentials in their secure/session stores and expose only non-secret
/// configuration through this repository.
final class SettingsRepository {
  SettingsRepository({this.preferences});

  static const schemaVersion = 1;
  final SharedPreferences? preferences;
  Future<SharedPreferences>? _preferencesFuture;
  Future<void>? _writeQueue;
  final Map<String, SettingsEnvelope<Object?>> _memory = {};

  Future<SharedPreferences> _prefs() async {
    final existing = preferences;
    if (existing != null) return existing;
    return _preferencesFuture ??= SharedPreferences.getInstance();
  }

  String key({
    required SettingsScope scope,
    required String subjectId,
    String setting = 'default',
  }) {
    final normalizedSubject = subjectId.trim();
    if (normalizedSubject.isEmpty) {
      throw ArgumentError.value(subjectId, 'subjectId', 'must not be empty');
    }
    final normalizedSetting = setting.trim();
    final base = 'settings:${scope.name}:$normalizedSubject';
    return normalizedSetting.isEmpty || normalizedSetting == 'default'
        ? base
        : '$base:$normalizedSetting';
  }

  Future<SettingsEnvelope<T>> read<T>({
    required SettingsScope scope,
    required String subjectId,
    required T fallback,
    required SettingsCodec<T> codec,
    String setting = 'default',
  }) async {
    final normalizedSubject = subjectId.trim();
    if (normalizedSubject.isEmpty) {
      throw ArgumentError.value(subjectId, 'subjectId', 'must not be empty');
    }
    final storageKey = key(
      scope: scope,
      subjectId: normalizedSubject,
      setting: setting,
    );
    final inMemory = _memory[storageKey];
    if (inMemory != null) {
      return _castEnvelope(inMemory, fallback, scope, normalizedSubject);
    }

    final prefs = await _prefs();
    final fallbackEnvelope = SettingsEnvelope<T>(
      schemaVersion: schemaVersion,
      scope: scope,
      subjectId: normalizedSubject,
      revision: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      value: fallback,
    );
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return _readLastKnownGood(
        prefs: prefs,
        storageKey: storageKey,
        codec: codec,
        fallback: fallbackEnvelope,
      );
    }

    try {
      final decoded = SettingsEnvelope.fromJson<T>(
        jsonDecode(raw),
        decodeValue: codec.decode,
        fallback: fallbackEnvelope,
      );
      _memory[storageKey] = _asObjectEnvelope(decoded);
      return decoded;
    } catch (error) {
      debugPrint('[Settings] Could not decode $storageKey: $error');
      return _readLastKnownGood(
        prefs: prefs,
        storageKey: storageKey,
        codec: codec,
        fallback: fallbackEnvelope,
      );
    }
  }

  Future<SettingsEnvelope<T>> _readLastKnownGood<T>({
    required SharedPreferences prefs,
    required String storageKey,
    required SettingsCodec<T> codec,
    required SettingsEnvelope<T> fallback,
  }) async {
    final backup = prefs.getString(_lastKnownGoodKey(storageKey));
    if (backup == null || backup.trim().isEmpty) return fallback;
    try {
      final decoded = SettingsEnvelope.fromJson<T>(
        jsonDecode(backup),
        decodeValue: codec.decode,
        fallback: fallback,
      );
      _memory[storageKey] = _asObjectEnvelope(decoded);
      return decoded;
    } catch (error) {
      debugPrint(
        '[Settings] Could not decode last-known-good $storageKey: $error',
      );
      return fallback;
    }
  }

  static String _lastKnownGoodKey(String storageKey) =>
      '$storageKey:last-known-good';

  /// Reads a legacy bare JSON value once and promotes it into the typed
  /// envelope. The legacy value is retained until normal storage cleanup can
  /// remove it after a separately verified migration.
  Future<SettingsEnvelope<T>> readWithLegacyJson<T>({
    required SettingsScope scope,
    required String subjectId,
    required T fallback,
    required SettingsCodec<T> codec,
    required String legacyKey,
    String setting = 'default',
  }) async {
    final current = await read<T>(
      scope: scope,
      subjectId: subjectId,
      fallback: fallback,
      codec: codec,
      setting: setting,
    );
    if (current.revision > 0) return current;

    if (legacyKey.trim().isEmpty) return current;
    final prefs = await _prefs();
    final raw = prefs.getString(legacyKey);
    if (raw == null || raw.trim().isEmpty) return current;
    try {
      final legacyValue = codec.decode(jsonDecode(raw));
      return await write<T>(
        envelope: current.copyWith(value: legacyValue),
        codec: codec,
        expectedRevision: current.revision,
        setting: setting,
      );
    } catch (error) {
      debugPrint('[Settings] Could not migrate legacy $legacyKey: $error');
      return current;
    }
  }

  Future<SettingsEnvelope<T>> write<T>({
    required SettingsEnvelope<T> envelope,
    required SettingsCodec<T> codec,
    int? expectedRevision,
    String setting = 'default',
  }) async {
    final normalizedSubject = envelope.subjectId.trim();
    final storageKey = key(
      scope: envelope.scope,
      subjectId: normalizedSubject,
      setting: setting,
    );
    late SettingsEnvelope<T> next;
    await _enqueue(() async {
      final current = await read<T>(
        scope: envelope.scope,
        subjectId: normalizedSubject,
        fallback: envelope.value,
        codec: codec,
        setting: setting,
      );
      if (expectedRevision != null && current.revision != expectedRevision) {
        throw SettingsConflictException(
          expectedRevision: expectedRevision,
          actualRevision: current.revision,
        );
      }
      next = envelope.copyWith(
        schemaVersion: schemaVersion,
        subjectId: normalizedSubject,
        revision: current.revision + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      await _persist(
        storageKey: storageKey,
        envelope: next,
        lastKnownGood: current,
        codec: codec,
      );
    });
    return next;
  }

  Future<SettingsEnvelope<T>> update<T>({
    required SettingsScope scope,
    required String subjectId,
    required T fallback,
    required SettingsCodec<T> codec,
    required T Function(T current) change,
    String setting = 'default',
  }) async {
    final normalizedSubject = subjectId.trim();
    final storageKey = key(
      scope: scope,
      subjectId: normalizedSubject,
      setting: setting,
    );
    late SettingsEnvelope<T> next;
    await _enqueue(() async {
      final current = await read<T>(
        scope: scope,
        subjectId: normalizedSubject,
        fallback: fallback,
        codec: codec,
        setting: setting,
      );
      next = current.copyWith(
        schemaVersion: schemaVersion,
        subjectId: normalizedSubject,
        revision: current.revision + 1,
        updatedAt: DateTime.now().toUtc(),
        value: change(current.value),
      );
      await _persist(
        storageKey: storageKey,
        envelope: next,
        lastKnownGood: current,
        codec: codec,
      );
    });
    return next;
  }

  Future<void> _persist<T>({
    required String storageKey,
    required SettingsEnvelope<T> envelope,
    required SettingsEnvelope<T> lastKnownGood,
    required SettingsCodec<T> codec,
  }) async {
    final prefs = await _prefs();
    final previousRaw = prefs.getString(storageKey);
    try {
      final serialized = _serialize(envelope, codec);
      final lastKnownGoodRaw = _serialize(lastKnownGood, codec);
      await prefs.setString(storageKey, serialized);
      if (lastKnownGood.revision > 0) {
        await prefs.setString(_lastKnownGoodKey(storageKey), lastKnownGoodRaw);
      }
      _memory[storageKey] = _asObjectEnvelope(envelope);
    } catch (error) {
      try {
        if (previousRaw == null) {
          await prefs.remove(storageKey);
        } else {
          await prefs.setString(storageKey, previousRaw);
        }
      } catch (_) {
        // Keep the original write error as the observable failure.
      }
      rethrow;
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) async {
    final previous = _writeQueue ?? Future<void>.value();
    final next = previous.then((_) => operation());
    _writeQueue = next.catchError((_) {});
    try {
      await next;
    } finally {
      if (identical(_writeQueue, next)) _writeQueue = null;
    }
  }

  static SettingsEnvelope<Object?> _asObjectEnvelope<T>(
    SettingsEnvelope<T> envelope,
  ) => SettingsEnvelope<Object?>(
    schemaVersion: envelope.schemaVersion,
    scope: envelope.scope,
    subjectId: envelope.subjectId,
    revision: envelope.revision,
    updatedAt: envelope.updatedAt,
    value: envelope.value,
    extensions: envelope.extensions,
  );

  static SettingsEnvelope<T> _castEnvelope<T>(
    SettingsEnvelope<Object?> envelope,
    T fallback,
    SettingsScope scope,
    String subjectId,
  ) => SettingsEnvelope<T>(
    schemaVersion: envelope.schemaVersion,
    scope: envelope.scope,
    subjectId: envelope.subjectId,
    revision: envelope.revision,
    updatedAt: envelope.updatedAt,
    value: envelope.value is T ? envelope.value as T : fallback,
    extensions: envelope.extensions,
  );

  static String _serialize<T>(
    SettingsEnvelope<T> envelope,
    SettingsCodec<T> codec,
  ) => envelope.encode((value) => codec.encode(value));
}
