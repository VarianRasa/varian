import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../artifacts/artifact_store_bundle.dart';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../artifacts/transient_artifact_hydrator.dart';
import '../local/local_storage_service.dart';
import '../../domain/models/collaboration.dart';
import '../../domain/models/document.dart';
import '../../domain/models/document_asset.dart';
import '../../domain/models/document_asset_dependencies.dart';
import '../../domain/models/cloud_project_deletion.dart';
import '../../domain/models/media_timeline.dart';
import '../../domain/models/workspace_governance.dart';
import '../../domain/models/durable_asset_reference.dart';
import '../../features/ai/data/image_artifact_store_types.dart';
import '../../features/ai/data/video_artifact_store_types.dart';
import '../../features/assets/data/file_artifact_store.dart';
import '../../features/assets/data/file_artifact_store_types.dart';
import '../../features/media/data/media_artifact_store.dart';
import '../../features/model3d/data/model3d_artifact_store.dart';
import '../../features/model3d/data/model3d_artifact_store_types.dart';
import '../../features/governance/domain/operability.dart';
import '../../features/governance/domain/remote_operability.dart';
import '../../features/collaboration/domain/crdt_engine.dart';
import '../../features/governance/domain/plugin_registry.dart';
import '../../features/governance/domain/usage_billing.dart';
import '../../features/templates/domain/project_template.dart';
import '../../features/presentation/domain/remote_presenter_control.dart';
import '../../features/publishing/domain/published_snapshot.dart';
import 'supabase_storage_path_resolver.dart';

bool isSupabaseInitialized() {
  try {
    return Supabase.instance.isInitialized;
  } catch (_) {
    return false;
  }
}

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

Future<(bool, String?)> testSupabaseConnection({
  required String url,
  required String publishableKey,
  http.Client? httpClient,
}) async {
  final normalizedUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
  final key = publishableKey.trim();
  if (normalizedUrl.isEmpty || key.isEmpty) {
    return (false, 'Supabase URL and Anon Key are required.');
  }
  final client = httpClient ?? http.Client();
  try {
    final response = await client
        .get(
          Uri.parse('$normalizedUrl/auth/v1/settings'),
          headers: {'apikey': key, 'Authorization': 'Bearer $key'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (true, null);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return (
        false,
        'Supabase Anon Key ditolak (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode == 404) {
      return (false, 'Supabase Project URL tidak ditemukan (HTTP 404).');
    }
    return (false, 'Supabase returned HTTP ${response.statusCode}.');
  } catch (_) {
    return (false, 'Supabase connection failed. Verify the URL and key.');
  } finally {
    if (httpClient == null) client.close();
  }
}

Future<void> initializeSupabaseFromConfig({
  required String url,
  required String publishableKey,
}) async {
  final normalizedUrl = url.trim().replaceFirst(RegExp(r'/+$'), '');
  final key = publishableKey.trim();
  if (normalizedUrl.isEmpty || key.isEmpty) return;
  if (isSupabaseInitialized()) {
    final existing = Supabase.instance.client;
    final existingUrl = existing.rest.url.endsWith('/rest/v1')
        ? existing.rest.url.substring(
            0,
            existing.rest.url.length - '/rest/v1'.length,
          )
        : existing.rest.url;
    final existingKey = existing.rest.headers['apikey'];
    if (existingUrl == normalizedUrl && existingKey == key) return;
    if (existing.realtime.channels.isNotEmpty) {
      throw StateError(
        'Close the active collaboration room before changing Supabase settings.',
      );
    }
    await Supabase.instance.dispose();
  }
  await Supabase.initialize(
    url: normalizedUrl,
    publishableKey: key,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: false,
    ),
  );
}

class SyncException implements Exception {
  final String message;
  final dynamic cause;
  const SyncException(this.message, [this.cause]);

  @override
  String toString() =>
      'SyncException: $message${cause != null ? ' ($cause)' : ''}';
}

String createShareLinkErrorMessage(Object error) {
  if (error is SyncException &&
      error.message ==
          'Sign in is required before writing cloud canvas data.') {
    return 'Sign in is required to create a share link.';
  }
  return 'Could not create a share link. Check the Supabase collaboration setup.';
}

class CanvasShareLink {
  final String id;
  final String projectId;
  final String token;
  final DateTime? expiresAt;

  const CanvasShareLink({
    required this.id,
    required this.projectId,
    required this.token,
    this.expiresAt,
  });

  static String newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String hashToken(String token) =>
      sha256.convert(utf8.encode(token.trim())).toString();

  static Map<String, dynamic>? recordFromRpcResponse(Object? response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.length == 1 && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return null;
  }
}

class SharedCanvasData {
  final CanvasDocument document;
  final List<CanvasComment> comments;
  final String? publishedSnapshotId;
  final int? publishedVersion;
  final PublishedAccess? access;
  final PublishedDownloadPolicy downloadPolicy;
  final bool embedEnabled;
  final bool watermarkEnabled;

  const SharedCanvasData({
    required this.document,
    this.comments = const [],
    this.publishedSnapshotId,
    this.publishedVersion,
    this.access,
    this.downloadPolicy = PublishedDownloadPolicy.allowed,
    this.embedEnabled = false,
    this.watermarkEnabled = false,
  });

  bool get isPublished => publishedSnapshotId?.isNotEmpty == true;

  bool get canExport => downloadPolicy != PublishedDownloadPolicy.disabled;
}

class SharedCanvasPasswordRequired implements Exception {
  final String snapshotId;
  final bool rejected;

  const SharedCanvasPasswordRequired({
    required this.snapshotId,
    this.rejected = false,
  });

  @override
  String toString() => rejected
      ? 'The published canvas password is incorrect.'
      : 'The published canvas requires a password.';
}

class CanvasMember {
  final String projectId;
  final String userId;
  final String role;
  final String displayName;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastSeenAt;
  final bool online;
  final bool cursorActive;

  const CanvasMember({
    required this.projectId,
    required this.userId,
    required this.role,
    this.displayName = '',
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
    this.lastSeenAt,
    this.online = false,
    this.cursorActive = false,
  });

  CollaborationRole get collaborationRole => CollaborationRole.fromWire(role);

  CanvasMember copyWith({
    String? projectId,
    String? userId,
    String? role,
    String? displayName,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSeenAt,
    bool? online,
    bool? cursorActive,
  }) => CanvasMember(
    projectId: projectId ?? this.projectId,
    userId: userId ?? this.userId,
    role: role ?? this.role,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    online: online ?? this.online,
    cursorActive: cursorActive ?? this.cursorActive,
  );

  factory CanvasMember.fromJson(Map<String, dynamic> json) => CanvasMember(
    projectId: json['project_id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    role: json['role']?.toString() ?? 'viewer',
    displayName: CollaborationDisplayNameGenerator.resolve(
      stableId: json['user_id']?.toString() ?? '',
      preferredName:
          json['display_name']?.toString() ?? json['user_name']?.toString(),
    ),
    avatarUrl: json['avatar_url']?.toString(),
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? ''),
    online: json['online'] as bool? ?? false,
    cursorActive: json['cursor_active'] as bool? ?? false,
  );
}

class CanvasRoom {
  final String id;
  final String projectId;
  final String projectName;
  final String roomCode;
  final String role;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const CanvasRoom({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.roomCode,
    this.role = 'owner',
    this.createdAt,
    this.expiresAt,
  });

  factory CanvasRoom.fromRpcResponse(Object? response) {
    final record = CanvasShareLink.recordFromRpcResponse(response);
    if (record == null) {
      throw const FormatException('Collaboration room RPC returned no room.');
    }
    return CanvasRoom(
      id: record['id']?.toString() ?? '',
      projectId: record['project_id']?.toString() ?? '',
      projectName: record['project_name']?.toString() ?? 'Untitled Project',
      roomCode: record['room_code']?.toString() ?? '',
      role: record['role']?.toString() ?? 'owner',
      createdAt: DateTime.tryParse(record['created_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(record['expires_at']?.toString() ?? ''),
    );
  }

  static bool isValidRoomCode(String value) =>
      RegExp(r'^\d{6}$').hasMatch(value.trim());
}

class CollaborationRoomCache {
  static const _keyPrefix = 'ccs_collaboration_room_';
  static Future<void>? _writeQueue;

  static String _key(String projectId) => '$_keyPrefix$projectId';

  static Future<T> _enqueue<T>(Future<T> Function() operation) async {
    final previous = _writeQueue ?? Future<void>.value();
    final next = previous.then((_) => operation());
    final queued = next.then<void>((_) {}).catchError((_) {});
    _writeQueue = queued;
    try {
      return await next;
    } finally {
      if (identical(_writeQueue, queued)) _writeQueue = null;
    }
  }

  static Future<void> _waitForWrites() async {
    final pending = _writeQueue;
    if (pending != null) await pending;
  }

  static String? _currentAccountId() {
    try {
      final client = Supabase.instance.client;
      return client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;
    } catch (_) {
      return null;
    }
  }

  static Future<CanvasRoom?> read(String projectId) async {
    await _waitForWrites();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(projectId));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final record = Map<String, dynamic>.from(data);
      final storedAccountId = record['accountId']?.toString();
      if (storedAccountId == null || storedAccountId != _currentAccountId()) {
        await clear(projectId);
        return null;
      }
      final roomCode = record['roomCode']?.toString() ?? '';
      final expiresAt = DateTime.tryParse(
        record['expiresAt']?.toString() ?? '',
      );
      if (!CanvasRoom.isValidRoomCode(roomCode) ||
          (expiresAt != null && !expiresAt.isAfter(DateTime.now()))) {
        await clear(projectId);
        return null;
      }
      return CanvasRoom(
        id: record['id']?.toString() ?? '',
        projectId: record['projectId']?.toString() ?? projectId,
        projectName: record['projectName']?.toString() ?? 'Untitled Project',
        roomCode: roomCode,
        role: record['role']?.toString() ?? 'owner',
        createdAt: DateTime.tryParse(record['createdAt']?.toString() ?? ''),
        expiresAt: expiresAt,
      );
    } catch (_) {
      await clear(projectId);
      return null;
    }
  }

  static Future<void> write(CanvasRoom room, {String? accountId}) {
    return _enqueue(() async {
      if (accountId != null && _currentAccountId() != accountId) return;
      final prefs = await SharedPreferences.getInstance();
      if (accountId != null && _currentAccountId() != accountId) return;
      final encoded = jsonEncode({
        'id': room.id,
        'projectId': room.projectId,
        'projectName': room.projectName,
        'roomCode': room.roomCode,
        'role': room.role,
        'accountId': accountId,
        'createdAt': room.createdAt?.toIso8601String(),
        'expiresAt': room.expiresAt?.toIso8601String(),
      });
      await prefs.setString(_key(room.projectId), encoded);
      if (accountId != null && _currentAccountId() != accountId) {
        if (prefs.getString(_key(room.projectId)) == encoded) {
          await prefs.remove(_key(room.projectId));
        }
      }
    });
  }

  static Future<void> clear(String projectId, {String? expectedAccountId}) {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (expectedAccountId != null) {
        final raw = prefs.getString(_key(projectId));
        if (raw == null) return;
        try {
          final data = jsonDecode(raw);
          if (data is! Map ||
              data['accountId']?.toString() != expectedAccountId) {
            return;
          }
        } catch (_) {
          return;
        }
      }
      await prefs.remove(_key(projectId));
    });
  }

  /// Removes room metadata before another account can use this device.
  static Future<void> clearAll({String? expectedAccountId}) {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(_keyPrefix))
          .toList(growable: false);
      for (final key in keys) {
        if (expectedAccountId != null) {
          final raw = prefs.getString(key);
          if (raw == null) continue;
          try {
            final data = jsonDecode(raw);
            if (data is! Map ||
                data['accountId']?.toString() != expectedAccountId) {
              continue;
            }
          } catch (_) {
            continue;
          }
        }
        await prefs.remove(key);
      }
    });
  }
}

Future<void> ensureAnonymousSupabaseSession(SupabaseClient client) async {
  if (client.auth.currentSession != null) return;
  await client.auth.signInAnonymously();
}

Future<Map<String, dynamic>> invokeAIVideoFunction(
  SupabaseClient client,
  Map<String, dynamic> body,
) async {
  await ensureAnonymousSupabaseSession(client);
  try {
    final response = await client.functions.invoke('ai-video', body: body);
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const SyncException(
      'AI video function returned an invalid response.',
    );
  } on FunctionsHttpException catch (error) {
    throw SyncException(
      'AI video function request failed (HTTP ${error.status}).',
    );
  }
}

class SupabaseCollaborationService {
  final SupabaseClient? _client;
  RealtimeChannel? _activeChannel;
  final void Function(RemoteCursor)? onRemoteCursor;
  final void Function(CanvasComment)? onRemoteComment;

  SupabaseCollaborationService(
    this._client, {
    this.onRemoteCursor,
    this.onRemoteComment,
  });

  bool get isConnected => _client != null && _activeChannel != null;

  void joinProjectRoom({
    required String projectId,
    required String userId,
    required String userName,
    required Color userColor,
  }) {
    if (_client == null) return;

    _activeChannel?.unsubscribe();
    final channel = _client.channel('canvas_room:$projectId');

    channel.onBroadcast(
      event: 'cursor_move',
      callback: (payload) {
        if (payload['userId'] == userId) return;
        final cursor = RemoteCursor(
          userId: payload['userId'] as String? ?? 'anon',
          userName: payload['userName'] as String? ?? 'Collaborator',
          userColor: Color(
            (payload['userColor'] as num?)?.toInt() ?? 0xFFF97316,
          ),
          x: (payload['x'] as num?)?.toDouble() ?? 0.0,
          y: (payload['y'] as num?)?.toDouble() ?? 0.0,
          lastActive: DateTime.now(),
        );
        onRemoteCursor?.call(cursor);
      },
    );

    channel.onBroadcast(
      event: 'new_comment',
      callback: (payload) {
        final comment = CanvasComment.fromJson(payload);
        onRemoteComment?.call(comment);
      },
    );

    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint(
          '[SupabaseCollaboration] Joined room canvas_room:$projectId',
        );
      } else if (error != null) {
        debugPrint('[SupabaseCollaboration] Realtime channel error: $error');
      }
    });
    _activeChannel = channel;
  }

  Future<void> broadcastCursorPosition({
    required String userId,
    required String userName,
    required Color userColor,
    required double x,
    required double y,
  }) async {
    if (_activeChannel == null) return;
    try {
      await _activeChannel!.sendBroadcastMessage(
        event: 'cursor_move',
        payload: {
          'userId': userId,
          'userName': userName,
          'userColor': userColor.toARGB32(),
          'x': x,
          'y': y,
        },
      );
    } catch (e) {
      debugPrint('[SupabaseCollaboration] Broadcast cursor failed: $e');
    }
  }

  Future<void> broadcastComment(CanvasComment comment) async {
    if (_activeChannel == null) return;
    try {
      await _activeChannel!.sendBroadcastMessage(
        event: 'new_comment',
        payload: comment.toJson(),
      );
    } catch (e) {
      debugPrint('[SupabaseCollaboration] Broadcast comment failed: $e');
    }
  }

  void leaveRoom() {
    _activeChannel?.unsubscribe();
    _activeChannel = null;
  }
}

enum _ProjectUploadAuthorization { owner, editor }

class _CloudOperationCancelled implements Exception {
  const _CloudOperationCancelled();
}

class SupabaseSyncService {
  void _ensureOperationCurrent(bool Function()? isOperationCurrent) {
    if (isOperationCurrent != null && !isOperationCurrent()) {
      throw const _CloudOperationCancelled();
    }
  }

  final SupabaseClient? _client;
  final TransientArtifactHydrator _artifactHydrator;
  late final SupabaseStoragePathResolver _storageResolver;

  SupabaseSyncService(
    this._client, {
    TransientArtifactHydrator? artifactHydrator,
    ArtifactStoreBundle? artifactStoreBundle,
  }) : _artifactHydrator =
           artifactHydrator ??
           TransientArtifactHydrator(
             imageArtifactStore: artifactStoreBundle?.imageArtifactStore,
             fileArtifactStore: artifactStoreBundle?.fileArtifactStore,
             mediaArtifactStore: artifactStoreBundle?.mediaArtifactStore,
             videoArtifactStore: artifactStoreBundle?.videoArtifactStore,
             model3DArtifactStore: artifactStoreBundle?.model3DArtifactStore,
           ) {
    _storageResolver = SupabaseStoragePathResolver(
      syncService: this,
      currentUserId: () => currentUserId,
    );
    _artifactHydrator.setStorageByteReader(_readPrivateStorageBytes);
  }

  Future<Uint8List?> _readPrivateStorageBytes({
    required String projectId,
    required String path,
    String? accountId,
    required int maxBytes,
  }) => _storageResolver.readBytes(
    projectId: projectId,
    storagePath: path,
    expectedUserId: accountId,
    maxBytes: maxBytes,
  );

  /// Reads a private project artifact through the shared resolver without
  /// exposing the signed delivery URL to a render or persistence consumer.
  Future<Uint8List?> readPrivateStorageBytes({
    required String projectId,
    required String path,
    String? accountId,
    required int maxBytes,
  }) => _readPrivateStorageBytes(
    projectId: projectId,
    path: path,
    accountId: accountId,
    maxBytes: maxBytes,
  );

  /// Resolver shared by render and download consumers.
  ///
  /// The owning sync service remains responsible for disposing it. Callers
  /// must not create a second resolver for the same client.
  SupabaseStoragePathResolver get storageResolver => _storageResolver;

  /// Releases the resolver's transient HTTP client and signed URL cache.
  void dispose() {
    _storageResolver.dispose();
    _artifactHydrator.setStorageByteReader(null);
  }

  bool get isConfigured => _client != null;

  bool get isAuthenticated =>
      _client?.auth.currentUser != null ||
      _client?.auth.currentSession?.user != null;

  String? get currentUserId =>
      _client?.auth.currentUser?.id ?? _client?.auth.currentSession?.user.id;

  DateTime? _parseCloudTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  Future<List<LocalProjectMetadata>> fetchOwnedProjectMetadata({
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) return const [];
    final userId = _authenticatedUserId(expectedUserId: expectedUserId);
    try {
      final projectResponse = await client
          .from('projects')
          .select(
            'id,owner_id,name,created_at,updated_at,archived_at,trashed_at',
          )
          .eq('owner_id', userId);
      _authenticatedUserId(expectedUserId: userId);
      final projectRows = projectResponse
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      if (projectRows.isEmpty) return const [];

      final projectIds = projectRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final snapshotResponse = await client
          .from('canvas_snapshots')
          .select('project_id,updated_at')
          .inFilter('project_id', projectIds);
      _authenticatedUserId(expectedUserId: userId);
      final snapshotUpdatedAt = <String, DateTime>{};
      for (final row in snapshotResponse.whereType<Map>()) {
        final projectId = row['project_id']?.toString();
        final updatedAt = _parseCloudTimestamp(row['updated_at']);
        if (projectId != null && updatedAt != null) {
          snapshotUpdatedAt[projectId] = updatedAt;
        }
      }

      final preferenceResponse = await client
          .from('user_project_preferences')
          .select('project_id,is_pinned')
          .eq('user_id', userId);
      _authenticatedUserId(expectedUserId: userId);
      final pinnedProjectIds = preferenceResponse
          .whereType<Map>()
          .where((row) => row['is_pinned'] == true)
          .map((row) => row['project_id']?.toString())
          .whereType<String>()
          .toSet();

      return projectRows
          .map((row) {
            final projectId = row['id'].toString();
            final updatedAt =
                _parseCloudTimestamp(row['updated_at']) ??
                _parseCloudTimestamp(row['created_at']) ??
                DateTime.now().toUtc();
            final snapshotAt = snapshotUpdatedAt[projectId];
            final cloudUpdatedAt = snapshotAt ?? updatedAt;
            final createdAt =
                _parseCloudTimestamp(row['created_at']) ?? updatedAt;
            final status = row['trashed_at'] != null
                ? ProjectStatus.trashed
                : row['archived_at'] != null
                ? ProjectStatus.archived
                : ProjectStatus.active;
            return LocalProjectMetadata(
              id: projectId,
              name: row['name']?.toString() ?? 'Untitled Project',
              createdAt: createdAt,
              updatedAt: updatedAt,
              isPinned: pinnedProjectIds.contains(projectId),
              status: status,
              trashedAt: _parseCloudTimestamp(row['trashed_at']),
              cloudOwnerId: row['owner_id']?.toString() ?? userId,
              cloudUpdatedAt: cloudUpdatedAt,
            );
          })
          .toList(growable: false);
    } on SyncException {
      rethrow;
    } catch (error) {
      debugPrint('[SupabaseSync] fetchOwnedProjectMetadata failed: $error');
      throw SyncException('Failed to load cloud project catalog', error);
    }
  }

  Future<void> syncProjectMetadata(
    LocalProjectMetadata metadata, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final userId = _authenticatedUserId(expectedUserId: expectedUserId);
    try {
      final updatedRows = await client
          .from('projects')
          .update({
            'name': metadata.name,
            'created_at': metadata.createdAt.toUtc().toIso8601String(),
            'updated_at': metadata.updatedAt.toUtc().toIso8601String(),
            'updated_by': userId,
            'archived_at': metadata.status == ProjectStatus.archived
                ? metadata.updatedAt.toUtc().toIso8601String()
                : null,
            'trashed_at': metadata.status == ProjectStatus.trashed
                ? (metadata.trashedAt ?? metadata.updatedAt)
                      .toUtc()
                      .toIso8601String()
                : null,
          })
          .eq('id', metadata.id)
          .eq('owner_id', userId)
          .select('id');
      _authenticatedUserId(expectedUserId: userId);
      if (updatedRows.isEmpty) {
        throw const SyncException(
          'The signed-in account does not own this project.',
        );
      }

      _authenticatedUserId(expectedUserId: userId);
      await client.from('user_project_preferences').upsert({
        'user_id': userId,
        'project_id': metadata.id,
        'is_pinned': metadata.isPinned,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,project_id');
      _authenticatedUserId(expectedUserId: userId);
    } on SyncException {
      rethrow;
    } catch (error) {
      debugPrint('[SupabaseSync] syncProjectMetadata failed: $error');
      throw SyncException('Failed to sync project metadata', error);
    }
  }

  Future<CloudProjectDeletionResult> deleteOwnedProject(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final userId = _authenticatedUserId(expectedUserId: expectedUserId);
    try {
      final response = await client.rpc(
        'request_workspace_note_project_delete',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: userId);
      return CloudProjectDeletionResult.fromJson(
        _singleCloudProjectDeletionRow(response),
      );
    } on SyncException {
      rethrow;
    } catch (error) {
      debugPrint('[SupabaseSync] deleteOwnedProject failed: $error');
      throw SyncException('Failed to request cloud project deletion', error);
    }
  }

  Future<CloudProjectDeletionResult?> getOwnedProjectDeletionStatus(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final userId = _authenticatedUserId(expectedUserId: expectedUserId);
    try {
      final row = await client
          .from('workspace_note_attachment_rehome_jobs')
          .select('id, requested_by, status, attempt_count, last_error_code')
          .eq('job_kind', 'project_delete')
          .eq('source_project_id', projectId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      _authenticatedUserId(expectedUserId: userId);
      if (row == null) return null;
      if (row['requested_by'] != userId) {
        throw const SyncException('Cloud project deletion is unavailable.');
      }
      return CloudProjectDeletionResult.fromJson(
        Map<String, dynamic>.from(row),
      );
    } on SyncException {
      rethrow;
    } catch (error) {
      debugPrint('[SupabaseSync] getOwnedProjectDeletionStatus failed.');
      throw SyncException(
        'Failed to read cloud project deletion status',
        error,
      );
    }
  }

  Future<void> retryOwnedProjectDeletion({
    required String jobId,
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final userId = _authenticatedUserId(expectedUserId: expectedUserId);
    try {
      await client.rpc(
        'retry_workspace_note_attachment_rehome',
        params: {'p_job_id': jobId},
      );
      _authenticatedUserId(expectedUserId: userId);
    } on SyncException {
      rethrow;
    } catch (error) {
      debugPrint('[SupabaseSync] retryOwnedProjectDeletion failed.');
      throw SyncException('Failed to retry cloud project deletion', error);
    }
  }

  Map<String, dynamic> _singleCloudProjectDeletionRow(Object? value) {
    final row = value is List && value.length == 1 ? value.single : value;
    if (row is Map) return Map<String, dynamic>.from(row);
    throw const FormatException('Cloud project deletion response is invalid.');
  }

  Future<void> claimProjectOwnership(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      await client.rpc(
        'claim_canvas_project_ownership',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: userId);
    } catch (error) {
      debugPrint('[SupabaseSync] claimProjectOwnership failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to claim canvas ownership', error);
    }
  }

  Future<List<CanvasMember>> listProjectMembers(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) return const [];
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client
          .from('workspace_members')
          .select(
            'project_id,user_id,role,display_name,avatar_url,created_at,updated_at,last_seen_at',
          )
          .eq('project_id', projectId)
          .order('created_at');
      return response
          .whereType<Map>()
          .map((row) => CanvasMember.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('[SupabaseSync] listProjectMembers failed: $error');
      throw SyncException('Failed to list canvas members', error);
    }
  }

  Future<CanvasMember> upsertWorkspaceMemberProfile({
    required String projectId,
    required String displayName,
    String? avatarUrl,
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'upsert_workspace_member_profile',
        params: {
          'p_project_id': projectId,
          'p_display_name': displayName,
          'p_avatar_url': avatarUrl,
        },
      );
      if (response is! Map) {
        throw const FormatException('Member profile RPC returned no member.');
      }
      return CanvasMember.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] upsertWorkspaceMemberProfile failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to update collaboration profile', error);
    }
  }

  Future<CanvasMember> touchWorkspaceMember(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'touch_workspace_member',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException('Member activity RPC returned no member.');
      }
      return CanvasMember.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] touchWorkspaceMember failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to update member activity', error);
    }
  }

  Future<CanvasMember> setProjectMemberRole({
    required String projectId,
    required String userId,
    required String role,
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    if (!const {'editor', 'commenter', 'viewer'}.contains(role)) {
      throw const SyncException('Invalid canvas member role.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'set_canvas_member_role',
        params: {
          'p_project_id': projectId,
          'p_user_id': userId,
          'p_role': role,
        },
      );
      _authenticatedUserId(expectedUserId: expectedUserId);
      if (response is! Map) {
        throw const FormatException('Member-role RPC returned no member.');
      }
      return CanvasMember.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] setProjectMemberRole failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to update canvas member role', error);
    }
  }

  Future<void> removeProjectMember({
    required String projectId,
    required String userId,
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      await client.rpc(
        'remove_canvas_member',
        params: {'p_project_id': projectId, 'p_user_id': userId},
      );
      _authenticatedUserId(expectedUserId: expectedUserId);
    } catch (error) {
      debugPrint('[SupabaseSync] removeProjectMember failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to remove canvas member', error);
    }
  }

  Future<CanvasRoom> createCollaborationRoom({
    required String projectId,
    required String projectName,
    DateTime? expiresAt,
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      await verifyProjectOwnership(projectId, expectedUserId: userId);
      _authenticatedUserId(expectedUserId: userId);
      final response = await client.rpc(
        'create_collaboration_room',
        params: {
          'p_project_id': projectId,
          'p_project_name': projectName,
          'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        },
      );
      _authenticatedUserId(expectedUserId: expectedUserId);
      final room = CanvasRoom.fromRpcResponse(response);
      if (room.id.isEmpty ||
          room.projectId.isEmpty ||
          !CanvasRoom.isValidRoomCode(room.roomCode)) {
        throw const FormatException(
          'Collaboration room RPC returned invalid data.',
        );
      }
      return room;
    } catch (error) {
      debugPrint('[SupabaseSync] createCollaborationRoom failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to create collaboration room', error);
    }
  }

  Future<CanvasRoom> joinCollaborationRoom({
    required String roomCode,
    String displayName = 'Collaborator',
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final normalizedCode = roomCode.trim();
    if (!CanvasRoom.isValidRoomCode(normalizedCode)) {
      throw const SyncException('Room ID must contain six digits.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'join_collaboration_room',
        params: {
          'p_room_code': normalizedCode,
          'p_display_name': displayName.trim().isEmpty
              ? 'Collaborator'
              : displayName.trim(),
        },
      );
      _authenticatedUserId(expectedUserId: expectedUserId);
      final room = CanvasRoom.fromRpcResponse(response);
      if (room.projectId.isEmpty || room.projectName.isEmpty) {
        throw const FormatException(
          'Collaboration room RPC returned invalid data.',
        );
      }
      return CanvasRoom(
        id: room.id,
        projectId: room.projectId,
        projectName: room.projectName,
        roomCode: normalizedCode,
        role: room.role,
        createdAt: room.createdAt,
        expiresAt: room.expiresAt,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] joinCollaborationRoom failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to join collaboration room', error);
    }
  }

  Future<void> revokeCollaborationRoom(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      await client.rpc(
        'revoke_collaboration_room',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: expectedUserId);
      await CollaborationRoomCache.clear(
        projectId,
        expectedAccountId: expectedUserId,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] revokeCollaborationRoom failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to revoke collaboration room', error);
    }
  }

  Future<PresenterRemoteSession> createPresenterRemoteSession({
    required String projectId,
    required String presenterId,
    required PresenterRemoteRole role,
    DateTime? expiresAt,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final params = <String, dynamic>{
        'p_project_id': projectId,
        'p_presenter_id': presenterId,
        'p_role': role.name,
      };
      if (expiresAt != null) {
        params['p_expires_at'] = expiresAt.toUtc().toIso8601String();
      }
      final response = await client.rpc(
        'create_presenter_remote_session',
        params: params,
      );
      if (response is! Map) {
        throw const FormatException(
          'Presenter remote session RPC returned invalid data.',
        );
      }
      return PresenterRemoteSession.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] createPresenterRemoteSession failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to create presenter remote session', error);
    }
  }

  Future<PresenterRemoteSession> getPresenterRemoteSession(
    String sessionId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_presenter_remote_session',
        params: {'p_session_id': sessionId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Presenter remote session RPC returned invalid data.',
        );
      }
      return PresenterRemoteSession.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] getPresenterRemoteSession failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read presenter remote session', error);
    }
  }

  Future<PresenterRemoteSession> grantPresenterRemoteConsent(
    String sessionId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'grant_presenter_remote_consent',
        params: {'p_session_id': sessionId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Presenter remote consent RPC returned invalid data.',
        );
      }
      return PresenterRemoteSession.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] grantPresenterRemoteConsent failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to grant presenter remote consent', error);
    }
  }

  Future<void> revokePresenterRemoteSession(String sessionId) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      await client.rpc(
        'revoke_presenter_remote_session',
        params: {'p_session_id': sessionId},
      );
    } catch (error) {
      debugPrint('[SupabaseSync] revokePresenterRemoteSession failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to revoke presenter remote session', error);
    }
  }

  Future<PresenterRemoteCommand> appendPresenterRemoteCommand(
    PresenterRemoteCommand command,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'append_presenter_remote_command',
        params: {
          'p_session_id': command.sessionId,
          'p_command_id': command.commandId,
          'p_action': command.action.name,
          'p_frame_index': command.frameIndex,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Presenter remote command RPC returned invalid data.',
        );
      }
      return PresenterRemoteCommand.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] appendPresenterRemoteCommand failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to append presenter remote command', error);
    }
  }

  Future<WorkspaceOwnerEligibility> getWorkspaceOwnerEligibility(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client
          .from('projects')
          .select('id,owner_id')
          .eq('id', projectId)
          .maybeSingle();
      _authenticatedUserId(expectedUserId: userId);
      if (response == null) {
        throw const FormatException(
          'Project ownership lookup returned invalid data.',
        );
      }
      final row = Map<String, dynamic>.from(response);
      final returnedProjectId = row['id'];
      final ownerId = row['owner_id'];
      if (returnedProjectId != projectId ||
          ownerId is! String ||
          ownerId.trim().isEmpty) {
        throw const FormatException(
          'Project ownership lookup returned incomplete data.',
        );
      }
      return WorkspaceOwnerEligibility(
        projectId: projectId,
        ownerId: ownerId,
        currentUserId: userId,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceOwnerEligibility failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to verify workspace ownership', error);
    }
  }

  Future<WorkspaceGovernanceSnapshot> getWorkspaceGovernance(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'get_workspace_governance',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: userId);
      if (response is! Map) {
        throw const FormatException(
          'Workspace governance RPC returned invalid data.',
        );
      }
      final snapshot = WorkspaceGovernanceSnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (snapshot.projectId != projectId) {
        throw const FormatException(
          'Workspace governance RPC returned another project.',
        );
      }
      return snapshot;
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceGovernance failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace governance', error);
    }
  }

  Future<EntitlementSnapshot> getWorkspaceEntitlement(String projectId) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_workspace_entitlement',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace entitlement RPC returned invalid data.',
        );
      }
      return EntitlementSnapshot.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceEntitlement failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace entitlement', error);
    }
  }

  Future<List<PluginRegistration>> listWorkspacePluginRegistrations(
    String projectId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'list_workspace_plugin_registrations',
        params: {'p_project_id': projectId},
      );
      if (response is! List) {
        throw const FormatException(
          'Workspace plugin registry RPC returned invalid data.',
        );
      }
      return response
          .whereType<Map>()
          .map(
            (value) =>
                PluginRegistration.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false);
    } catch (error) {
      debugPrint(
        '[SupabaseSync] listWorkspacePluginRegistrations failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace plugin registry', error);
    }
  }

  Future<PluginRegistration> upsertWorkspacePluginRegistration({
    required String projectId,
    required PluginRegistration registration,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_workspace_plugin_registration',
        params: {
          'p_project_id': projectId,
          'p_manifest': registration.manifest.toJson(),
          'p_state': registration.state.name,
          'p_approved_permissions': registration.approvedPermissions
              .map((permission) => permission.name)
              .toList(growable: false),
          'p_errors': registration.errors,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace plugin registration RPC returned invalid data.',
        );
      }
      return PluginRegistration.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint(
        '[SupabaseSync] upsertWorkspacePluginRegistration failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException(
        'Failed to save workspace plugin registration',
        error,
      );
    }
  }

  Future<PluginRegistration> setWorkspacePluginState({
    required String projectId,
    required String pluginId,
    required PluginRegistrationState state,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'set_workspace_plugin_state',
        params: {
          'p_project_id': projectId,
          'p_plugin_id': pluginId,
          'p_state': state.name,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace plugin state RPC returned invalid data.',
        );
      }
      return PluginRegistration.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] setWorkspacePluginState failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to update workspace plugin state', error);
    }
  }

  Future<bool> deleteWorkspacePluginRegistration({
    required String projectId,
    required String pluginId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'delete_workspace_plugin_registration',
        params: {'p_project_id': projectId, 'p_plugin_id': pluginId},
      );
      if (response is! bool) {
        throw const FormatException(
          'Workspace plugin deletion RPC returned invalid data.',
        );
      }
      return response;
    } catch (error) {
      debugPrint(
        '[SupabaseSync] deleteWorkspacePluginRegistration failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException(
        'Failed to delete workspace plugin registration',
        error,
      );
    }
  }

  Future<Map<String, dynamic>> authorizeWorkspacePluginCommand({
    required String projectId,
    required String pluginId,
    required String commandType,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'authorize_workspace_plugin_command',
        params: {
          'p_project_id': projectId,
          'p_plugin_id': pluginId,
          'p_command_type': commandType,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace plugin command RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint(
        '[SupabaseSync] authorizeWorkspacePluginCommand failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException(
        'Failed to authorize workspace plugin command',
        error,
      );
    }
  }

  Future<WorkspacePolicy> upsertWorkspacePolicy({
    required String projectId,
    required WorkspacePolicy policy,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_workspace_policy',
        params: {'p_project_id': projectId, 'p_policy': policy.toJson()},
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace policy RPC returned invalid data.',
        );
      }
      return WorkspacePolicy.fromJson(response);
    } catch (error) {
      debugPrint('[SupabaseSync] upsertWorkspacePolicy failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to save workspace policy', error);
    }
  }

  Future<Map<String, dynamic>> recordWorkspaceUsage({
    required String projectId,
    required String category,
    required int delta,
    required String operationId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'record_workspace_usage',
        params: {
          'p_project_id': projectId,
          'p_category': category,
          'p_delta': delta,
          'p_operation_id': operationId,
          'p_metadata': metadata,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace usage RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] recordWorkspaceUsage failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to record workspace usage', error);
    }
  }

  Future<WorkspaceObservabilityReceipt> recordWorkspaceObservabilityEvent(
    WorkspaceObservabilityEvent event,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final validation = event.validate();
    if (validation.isNotEmpty) {
      throw ArgumentError(
        'Invalid observability event: ${validation.join(' ')}',
      );
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'record_workspace_observability_event',
        params: {
          'p_project_id': event.projectId,
          'p_event_type': event.eventType,
          'p_severity': event.severity.name,
          'p_correlation_id': event.correlationId,
          'p_payload': event.toJson()['payload'],
          'p_recorded_at': event.recordedAt.toUtc().toIso8601String(),
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Observability event RPC returned invalid data.',
        );
      }
      return WorkspaceObservabilityReceipt.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint(
        '[SupabaseSync] recordWorkspaceObservabilityEvent failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException(
        'Failed to record workspace observability event',
        error,
      );
    }
  }

  Future<WorkspaceSupportBundleReceipt> submitWorkspaceSupportBundle({
    required String projectId,
    required String operationId,
    required SupportBundle bundle,
    required String checksum,
    DateTime? expiresAt,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    if (projectId.trim().isEmpty || operationId.trim().length < 8) {
      throw ArgumentError('Project ID and operation ID are required.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(checksum.trim())) {
      throw ArgumentError('Support bundle checksum must be SHA-256.');
    }
    if (utf8.encode(bundle.encode()).length > 2 * 1024 * 1024) {
      throw ArgumentError('Support bundle must be at most 2 MiB.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'submit_workspace_support_bundle',
        params: {
          'p_project_id': projectId,
          'p_operation_id': operationId,
          'p_checksum': checksum.trim().toLowerCase(),
          'p_bundle': bundle.toJson(),
          'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Support bundle RPC returned invalid data.',
        );
      }
      return WorkspaceSupportBundleReceipt.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] submitWorkspaceSupportBundle failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to submit workspace support bundle', error);
    }
  }

  Future<Map<String, dynamic>> getWorkspaceSupportBundle({
    required String projectId,
    required String operationId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_workspace_support_bundle',
        params: {'p_project_id': projectId, 'p_operation_id': operationId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Support bundle read RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceSupportBundle failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace support bundle', error);
    }
  }

  Future<WorkspaceReleasePolicySnapshot> getWorkspaceReleasePolicy(
    String projectId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_workspace_release_policy',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Release policy RPC returned invalid data.',
        );
      }
      return WorkspaceReleasePolicySnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceReleasePolicy failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace release policy', error);
    }
  }

  Future<WorkspaceReleasePolicySnapshot> upsertWorkspaceReleasePolicy(
    WorkspaceReleasePolicySnapshot releasePolicy,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    if (releasePolicy.projectId.trim().isEmpty ||
        !RegExp(
          r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$',
        ).hasMatch(releasePolicy.policy.version)) {
      throw ArgumentError('Project ID and semantic version are required.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_workspace_release_policy',
        params: {
          'p_project_id': releasePolicy.projectId,
          'p_channel': releasePolicy.policy.channel.name,
          'p_version': releasePolicy.policy.version,
          'p_rollback_version': releasePolicy.policy.rollbackVersion,
          'p_released_at': releasePolicy.releasedAt.toUtc().toIso8601String(),
          'p_rollback_until': releasePolicy.releasedAt
              .toUtc()
              .add(releasePolicy.policy.rollbackWindow)
              .toIso8601String(),
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Release policy update RPC returned invalid data.',
        );
      }
      return WorkspaceReleasePolicySnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] upsertWorkspaceReleasePolicy failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to update workspace release policy', error);
    }
  }

  Future<WorkspaceHealthSnapshot> getWorkspaceHealth(String projectId) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_workspace_health',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace health RPC returned invalid data.',
        );
      }
      return WorkspaceHealthSnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceHealth failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace health', error);
    }
  }

  Future<Map<String, dynamic>> authorizeAIJob({
    required String projectId,
    required String jobId,
    required String provider,
    String? model,
    int estimatedCredits = 1,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      dynamic response;
      if (model?.trim().isNotEmpty == true) {
        try {
          response = await client.rpc(
            'authorize_ai_job_v2',
            params: {
              'p_project_id': projectId,
              'p_job_id': jobId,
              'p_provider': provider,
              'p_model': model!.trim(),
              'p_estimated_credits': estimatedCredits,
            },
          );
        } catch (error) {
          if (!_isMissingAIAuthorizationV2(error)) rethrow;
        }
      }
      response ??= await client.rpc(
        'authorize_ai_job',
        params: {
          'p_project_id': projectId,
          'p_job_id': jobId,
          'p_provider': provider,
          'p_estimated_credits': estimatedCredits,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'AI authorization RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] authorizeAIJob failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to authorize AI job', error);
    }
  }

  bool _isMissingAIAuthorizationV2(Object error) {
    if (error is PostgrestException && error.code == '42883') return true;
    final text = error.toString().toLowerCase();
    return text.contains('authorize_ai_job_v2') &&
        (text.contains('not found') ||
            text.contains('could not find') ||
            text.contains('schema cache') ||
            text.contains('does not exist') ||
            text.contains('undefined function'));
  }

  Future<Map<String, dynamic>> getWorkspaceAIGovernance(
    String projectId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'get_workspace_ai_governance',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException('AI governance RPC returned invalid data.');
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] getWorkspaceAIGovernance failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read AI governance', error);
    }
  }

  Future<Map<String, dynamic>> upsertWorkspaceAIProviderPolicy({
    required String projectId,
    required Map<String, dynamic> policy,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_workspace_ai_provider_policy',
        params: {'p_project_id': projectId, 'p_policy': policy},
      );
      if (response is! Map) {
        throw const FormatException(
          'AI provider policy RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint(
        '[SupabaseSync] upsertWorkspaceAIProviderPolicy failed: $error',
      );
      if (error is SyncException) rethrow;
      throw SyncException('Failed to save AI provider policy', error);
    }
  }

  Future<Map<String, dynamic>> upsertWorkspaceAIGovernance({
    required String projectId,
    required Map<String, dynamic> policy,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_workspace_ai_governance',
        params: {'p_project_id': projectId, 'p_ai_policy': policy},
      );
      if (response is! Map) {
        throw const FormatException(
          'AI governance policy RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] upsertWorkspaceAIGovernance failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to save AI governance policy', error);
    }
  }

  Future<Map<String, dynamic>> requestWorkspaceDataExport({
    required String projectId,
    required String operationId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'request_workspace_data_export',
        params: {'p_project_id': projectId, 'p_operation_id': operationId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace export RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] requestWorkspaceDataExport failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to request workspace export', error);
    }
  }

  Future<ProjectDeletionRequestReceipt> requestProjectDeletion(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      final response = await client.rpc(
        'request_project_deletion',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: userId);
      if (response is! Map) {
        throw const FormatException(
          'Project deletion RPC returned invalid data.',
        );
      }
      final receipt = ProjectDeletionRequestReceipt.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (receipt.projectId != projectId) {
        throw const FormatException(
          'Project deletion RPC returned another project.',
        );
      }
      return receipt;
    } catch (error) {
      debugPrint('[SupabaseSync] requestProjectDeletion failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to request project deletion', error);
    }
  }

  Future<void> cancelProjectDeletion(
    String projectId, {
    String? expectedUserId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      await client.rpc(
        'cancel_project_deletion',
        params: {'p_project_id': projectId},
      );
      _authenticatedUserId(expectedUserId: userId);
    } catch (error) {
      debugPrint('[SupabaseSync] cancelProjectDeletion failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to cancel project deletion', error);
    }
  }

  Future<Map<String, dynamic>> purgeWorkspaceRetention(String projectId) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'purge_workspace_retention',
        params: {'p_project_id': projectId},
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace retention RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] purgeWorkspaceRetention failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to purge workspace retention data', error);
    }
  }

  Future<Map<String, dynamic>> enqueueWorkspaceBillingEvent({
    required String projectId,
    required String eventType,
    required String idempotencyKey,
    Map<String, dynamic> payload = const {},
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'enqueue_workspace_billing_event',
        params: {
          'p_project_id': projectId,
          'p_event_type': eventType,
          'p_idempotency_key': idempotencyKey,
          'p_payload': payload,
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Workspace billing RPC returned invalid data.',
        );
      }
      return Map<String, dynamic>.from(response);
    } catch (error) {
      debugPrint('[SupabaseSync] enqueueWorkspaceBillingEvent failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to enqueue billing event', error);
    }
  }

  Future<List<WorkspaceAuditEvent>> listWorkspaceAuditEvents(
    String projectId, {
    int limit = 100,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'list_workspace_audit_events',
        params: {'p_project_id': projectId, 'p_limit': limit},
      );
      if (response is! List) {
        throw const FormatException(
          'Workspace audit RPC returned invalid data.',
        );
      }
      return response
          .whereType<Map>()
          .map(
            (item) =>
                WorkspaceAuditEvent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (error) {
      debugPrint('[SupabaseSync] listWorkspaceAuditEvents failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to read workspace audit events', error);
    }
  }

  Future<ProjectTemplateCatalog> loadProjectTemplates(
    String workspaceId,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'list_project_templates',
        params: {'p_workspace_id': workspaceId},
      );
      if (response is! List) {
        throw const FormatException(
          'Project template RPC returned invalid data.',
        );
      }
      final custom = response
          .whereType<Map>()
          .map(
            (item) => ProjectTemplate.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
      return ProjectTemplateCatalog.withBuiltIns(custom: custom);
    } catch (error) {
      debugPrint('[SupabaseSync] loadProjectTemplates failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to load project templates', error);
    }
  }

  Future<ProjectTemplateSyncResult> syncProjectTemplates({
    required String workspaceId,
    required ProjectTemplateCatalog local,
  }) async {
    final remote = await loadProjectTemplates(workspaceId);
    final merge = local.mergeRemote(remote);
    var catalog = merge.catalog;
    final uploaded = <ProjectTemplate>[];
    final failedUploads = <ProjectTemplate>[];

    for (final localTemplate in merge.localWins) {
      try {
        final syncedTemplate = await upsertProjectTemplate(
          workspaceId: workspaceId,
          template: localTemplate,
        );
        catalog = catalog.upsert(syncedTemplate);
        uploaded.add(syncedTemplate);
      } catch (error) {
        debugPrint(
          '[SupabaseSync] Project template upload unavailable: $error',
        );
        failedUploads.add(localTemplate);
      }
    }

    return ProjectTemplateSyncResult(
      catalog: catalog,
      uploaded: List.unmodifiable(uploaded),
      failedUploads: List.unmodifiable(failedUploads),
    );
  }

  Future<ProjectTemplate> upsertProjectTemplate({
    required String workspaceId,
    required ProjectTemplate template,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    if (template.isBuiltIn) {
      throw const SyncException('Built-in templates cannot be synced.');
    }
    try {
      _authenticatedUserId();
      final response = await client.rpc(
        'upsert_project_template',
        params: {
          'p_workspace_id': workspaceId,
          'p_template_id': template.id,
          'p_scope': template.scope.name,
          'p_template_json': template.toJson(),
        },
      );
      if (response is! Map) {
        throw const FormatException(
          'Project template RPC returned invalid data.',
        );
      }
      return ProjectTemplate.fromJson(Map<String, dynamic>.from(response));
    } catch (error) {
      debugPrint('[SupabaseSync] upsertProjectTemplate failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to sync project template', error);
    }
  }

  Future<void> deleteProjectTemplate({
    required String workspaceId,
    required String templateId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      await client.rpc(
        'delete_project_template',
        params: {'p_workspace_id': workspaceId, 'p_template_id': templateId},
      );
    } catch (error) {
      debugPrint('[SupabaseSync] deleteProjectTemplate failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to delete project template', error);
    }
  }

  Future<CanvasShareLink?> publishCanvasSnapshot(
    PublishedSnapshot snapshot,
  ) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }

    try {
      final userId = _authenticatedUserId();
      final document = await prepareCollaborativeDocument(
        snapshot.document,
        expectedUserId: userId,
      );
      _authenticatedUserId(expectedUserId: userId);
      if (document == null || document.projectId != snapshot.projectId) {
        throw const SyncException(
          'Published canvas contains an asset that cannot cross the private artifact boundary.',
        );
      }
      final documentData = document.toPersistenceJson();
      final contentHash = sha256
          .convert(utf8.encode(jsonEncode(documentData)))
          .toString();
      final token = snapshot.access == PublishedAccess.private
          ? null
          : CanvasShareLink.newToken();
      final response = await client.rpc(
        'publish_canvas_snapshot',
        params: {
          'p_project_id': snapshot.projectId,
          'p_snapshot_id': snapshot.id,
          'p_version': snapshot.version,
          'p_document_data': documentData,
          'p_published_by': snapshot.publishedBy,
          'p_published_at': snapshot.publishedAt.toUtc().toIso8601String(),
          'p_expires_at': snapshot.expiresAt?.toUtc().toIso8601String(),
          'p_access': snapshot.access.name,
          'p_download_policy': snapshot.downloadPolicy.name,
          'p_embed_enabled': snapshot.embedEnabled,
          'p_watermark_enabled': snapshot.watermarkEnabled,
          'p_password_digest': snapshot.passwordDigest,
          'p_content_hash': contentHash,
          'p_token_hash': token == null
              ? null
              : CanvasShareLink.hashToken(token),
        },
      );
      _authenticatedUserId(expectedUserId: userId);
      final record = CanvasShareLink.recordFromRpcResponse(response);
      if (record == null) {
        throw const FormatException(
          'Published snapshot RPC returned invalid data.',
        );
      }
      if (token == null) return null;
      final linkId = record['share_link_id']?.toString();
      if (linkId == null || linkId.isEmpty) {
        throw const FormatException(
          'Published snapshot RPC returned no share link ID.',
        );
      }
      return CanvasShareLink(
        id: linkId,
        projectId: snapshot.projectId,
        token: token,
        expiresAt: snapshot.expiresAt,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] publishCanvasSnapshot failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to publish canvas snapshot', error);
    }
  }

  Future<CanvasShareLink> createCanvasShareLink({
    required String projectId,
    DateTime? expiresAt,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      final token = CanvasShareLink.newToken();
      final response = await client.rpc(
        'create_canvas_share_link',
        params: {
          'p_project_id': projectId,
          'p_token_hash': CanvasShareLink.hashToken(token),
          'p_expires_at': expiresAt?.toIso8601String(),
        },
      );
      final record = CanvasShareLink.recordFromRpcResponse(response);
      if (record == null || record['id'] == null) {
        throw const FormatException('Share-link RPC returned no link ID.');
      }
      return CanvasShareLink(
        id: record['id'].toString(),
        projectId: projectId,
        token: token,
        expiresAt: expiresAt,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] createCanvasShareLink failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to create secure canvas share link', error);
    }
  }

  Future<void> revokeCanvasShareLink(String linkId) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _authenticatedUserId();
      await client.rpc(
        'revoke_canvas_share_link',
        params: {'p_link_id': linkId},
      );
    } catch (error) {
      debugPrint('[SupabaseSync] revokeCanvasShareLink failed: $error');
      if (error is SyncException) rethrow;
      throw SyncException('Failed to revoke secure canvas share link', error);
    }
  }

  Future<SharedCanvasData> readSharedCanvas({
    required String projectId,
    required String token,
    String? passwordDigest,
  }) async {
    final client = _client;
    final normalizedToken = token.trim();
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    if (normalizedToken.length < 32) {
      throw const SyncException('The canvas share link is invalid.');
    }
    try {
      final response = await client.rpc(
        'read_canvas_share',
        params: {
          'p_project_id': projectId,
          'p_token_hash': CanvasShareLink.hashToken(normalizedToken),
          'p_password_digest': passwordDigest?.trim(),
        },
      );
      if (response is! Map) {
        throw const SyncException(
          'The canvas share link is invalid or expired.',
        );
      }
      final responseMap = Map<String, dynamic>.from(response);
      if (responseMap['requiresPassword'] == true) {
        final snapshotId = responseMap['snapshotId']?.toString() ?? '';
        if (snapshotId.isEmpty) {
          throw const SyncException(
            'The canvas share link is invalid or expired.',
          );
        }
        throw SharedCanvasPasswordRequired(
          snapshotId: snapshotId,
          rejected: passwordDigest != null,
        );
      }
      if (responseMap['document'] is! Map) {
        throw const SyncException(
          'The canvas share link is invalid or expired.',
        );
      }
      final rawComments = responseMap['comments'];
      final comments = rawComments is List
          ? rawComments
                .whereType<Map>()
                .map(
                  (comment) => CanvasComment.fromJson(
                    Map<String, dynamic>.from(comment),
                  ),
                )
                .toList()
          : const <CanvasComment>[];
      final document = await _artifactHydrator.hydrate(
        CanvasDocument.fromJson(
          Map<String, dynamic>.from(responseMap['document'] as Map),
        ),
        projectId: projectId,
        accountId: currentUserId,
      );
      return SharedCanvasData(
        document: document,
        comments: comments,
        publishedSnapshotId: responseMap['snapshotId']?.toString(),
        publishedVersion: (responseMap['version'] as num?)?.toInt(),
        access: _publishedAccess(responseMap['access']?.toString()),
        downloadPolicy: _publishedDownloadPolicy(
          responseMap['downloadPolicy']?.toString(),
        ),
        embedEnabled: responseMap['embedEnabled'] as bool? ?? false,
        watermarkEnabled: responseMap['watermarkEnabled'] as bool? ?? false,
      );
    } catch (error) {
      debugPrint('[SupabaseSync] readSharedCanvas failed: $error');
      if (error is SyncException || error is SharedCanvasPasswordRequired) {
        rethrow;
      }
      throw SyncException('Failed to open the canvas share link', error);
    }
  }

  PublishedAccess? _publishedAccess(String? value) {
    if (value == null || value.isEmpty) return null;
    return PublishedAccess.values.firstWhere(
      (candidate) => candidate.name == value,
      orElse: () => PublishedAccess.link,
    );
  }

  PublishedDownloadPolicy _publishedDownloadPolicy(String? value) =>
      PublishedDownloadPolicy.values.firstWhere(
        (candidate) => candidate.name == value,
        orElse: () => PublishedDownloadPolicy.allowed,
      );

  String _authenticatedUserId({String? expectedUserId}) {
    final userId =
        _client?.auth.currentUser?.id ?? _client?.auth.currentSession?.user.id;
    if (userId == null || userId.isEmpty) {
      throw const SyncException(
        'Sign in is required before writing cloud canvas data.',
      );
    }
    if (expectedUserId != null && userId != expectedUserId) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    return userId;
  }

  /// Test connection by querying canvas_snapshots table with limit 1
  Future<(bool, String?)> testConnection() async {
    if (_client == null) {
      return (
        false,
        'Supabase client is not initialized. Please verify URL & Anon Key.',
      );
    }
    try {
      await _client.from('canvas_snapshots').select('project_id').limit(1);
      return (true, null);
    } catch (err) {
      debugPrint('[SupabaseSync] testConnection error: $err');
      return (false, err.toString());
    }
  }

  /// Test storage bucket accessibility
  Future<(bool, String?)> testStorageAccess([String bucket = 'assets']) async {
    if (_client == null) {
      return (false, 'Supabase client is not initialized.');
    }
    try {
      await _client.storage
          .from(bucket)
          .list(path: '', searchOptions: const SearchOptions(limit: 1));
      return (true, null);
    } catch (err) {
      debugPrint('[SupabaseSync] testStorageAccess error: $err');
      return (false, err.toString());
    }
  }

  Future<void> syncDocumentSnapshot(
    CanvasDocument doc, {
    String? expectedUserId,
    bool Function()? isOperationCurrent,
  }) => _syncDocumentSnapshot(
    doc,
    expectedUserId: expectedUserId,
    isOperationCurrent: isOperationCurrent,
  );

  /// Claims an unowned project only after adoption is confirmed. Existing
  /// snapshots are accepted only when their persisted content already matches;
  /// client and server clocks are never compared to infer freshness.
  Future<void> adoptDocumentSnapshot(
    CanvasDocument doc, {
    required String expectedUserId,
  }) => _syncDocumentSnapshot(
    doc,
    expectedUserId: expectedUserId,
    explicitAdoption: true,
  );

  Future<void> _syncDocumentSnapshot(
    CanvasDocument doc, {
    String? expectedUserId,
    bool Function()? isOperationCurrent,
    bool explicitAdoption = false,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    try {
      _ensureOperationCurrent(isOperationCurrent);
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      final project = await client
          .from('projects')
          .select('owner_id')
          .eq('id', doc.projectId)
          .maybeSingle();
      _authenticatedUserId(expectedUserId: userId);
      _ensureOperationCurrent(isOperationCurrent);

      final ownerId = project?['owner_id']?.toString().trim();
      if (ownerId != userId) {
        if (ownerId != null && ownerId.isNotEmpty) {
          throw const SyncException(
            'The signed-in account does not own this project.',
          );
        }
        if (!explicitAdoption) {
          throw const SyncException(
            'This local project must be adopted before cloud sync.',
          );
        }
      }

      final existingSnapshot = await client
          .from('canvas_snapshots')
          .select(
            explicitAdoption
                ? 'project_id,updated_at,revision,document_data'
                : 'project_id,updated_at,revision',
          )
          .eq('project_id', doc.projectId)
          .maybeSingle();
      _authenticatedUserId(expectedUserId: userId);
      _ensureOperationCurrent(isOperationCurrent);

      final existingData = existingSnapshot?['document_data'];
      var cloudSnapshotMatchesAdoption = false;
      if (explicitAdoption && existingSnapshot != null && existingData is Map) {
        final preparedForComparison = await _prepareSnapshotDocument(
          doc,
          expectedUserId: userId,
          isOperationCurrent: isOperationCurrent,
          stageAssets: false,
        );
        _authenticatedUserId(expectedUserId: userId);
        _ensureOperationCurrent(isOperationCurrent);
        cloudSnapshotMatchesAdoption =
            preparedForComparison != null &&
            _isCloudSnapshotContentMatchingPreparedLocal(
              existingData,
              preparedForComparison,
            );
      }

      if (explicitAdoption && existingSnapshot != null) {
        if (!cloudSnapshotMatchesAdoption) {
          throw const SyncException(
            'A cloud snapshot already exists with different content; review it before adoption.',
          );
        }
        if (ownerId != userId) {
          await _claimAndVerifyProjectOwnership(doc.projectId, userId: userId);
        } else {
          await _requireOwnedProject(doc.projectId, userId: userId);
        }
        _authenticatedUserId(expectedUserId: userId);
        _ensureOperationCurrent(isOperationCurrent);
        return;
      }

      if (explicitAdoption) {
        if (ownerId != userId) {
          await _claimAndVerifyProjectOwnership(doc.projectId, userId: userId);
        } else {
          await _requireOwnedProject(doc.projectId, userId: userId);
        }
      } else {
        await _requireOwnedProject(doc.projectId, userId: userId);
      }
      _authenticatedUserId(expectedUserId: userId);
      _ensureOperationCurrent(isOperationCurrent);

      final prepared = await _prepareSnapshotDocument(
        doc,
        expectedUserId: userId,
        isOperationCurrent: isOperationCurrent,
      );
      _authenticatedUserId(expectedUserId: userId);
      _ensureOperationCurrent(isOperationCurrent);
      if (prepared == null || prepared.projectId != doc.projectId) {
        throw const SyncException(
          'Canvas contains an asset that cannot cross the private artifact boundary.',
        );
      }
      final snapshotData = {
        'project_id': doc.projectId,
        'user_id': userId,
        'updated_by': userId,
        'document_data': prepared.toPersistenceJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      _authenticatedUserId(expectedUserId: userId);
      if (existingSnapshot == null) {
        _ensureOperationCurrent(isOperationCurrent);
        await client.from('canvas_snapshots').insert({
          ...snapshotData,
          'revision': 0,
        });
      } else {
        final expectedRevision = _cloudSnapshotRevision(existingSnapshot);
        final expectedUpdatedAt = existingSnapshot['updated_at']?.toString();
        if (expectedUpdatedAt == null || expectedUpdatedAt.isEmpty) {
          throw const SyncException(
            'Cloud snapshot version is unavailable; sync was stopped.',
          );
        }
        _ensureOperationCurrent(isOperationCurrent);
        final updatedRows = await client
            .from('canvas_snapshots')
            .update({...snapshotData, 'revision': expectedRevision + 1})
            .eq('project_id', doc.projectId)
            .eq('revision', expectedRevision)
            .eq('updated_at', expectedUpdatedAt)
            .select('project_id,revision');
        if (updatedRows.isEmpty) {
          throw SyncException(
            explicitAdoption
                ? 'The cloud snapshot changed during adoption; retry after reviewing it.'
                : 'The cloud snapshot changed during sync; retry after reviewing it.',
          );
        }
      }
      _authenticatedUserId(expectedUserId: userId);
    } on _CloudOperationCancelled {
      return;
    } on SyncException {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const SyncException(
          'A cloud snapshot was created during sync; review it before retrying.',
        );
      }
      debugPrint('[SupabaseSync] syncDocumentSnapshot failed: $error');
      throw SyncException('Failed to sync canvas snapshot to cloud', error);
    } catch (e) {
      if (e.toString().toLowerCase().contains('client is already closed')) {
        return;
      }
      debugPrint('[SupabaseSync] syncDocumentSnapshot failed: $e');
      throw SyncException('Failed to sync canvas snapshot to cloud', e);
    }
  }

  int _cloudSnapshotRevision(Map<String, dynamic> snapshot) {
    final rawRevision = snapshot['revision'];
    final revision = rawRevision is int
        ? rawRevision
        : int.tryParse(rawRevision?.toString() ?? '');
    if (revision == null || revision < 0) {
      throw const SyncException(
        'Cloud snapshot revision is unavailable; sync was stopped.',
      );
    }
    return revision;
  }

  bool _isCloudSnapshotContentMatchingPreparedLocal(
    Object cloudData,
    CanvasDocument preparedDocument,
  ) {
    if (cloudData is! Map) return false;
    final cloudDocument = _decodeDocumentForProject(
      cloudData,
      preparedDocument.projectId,
    );
    return jsonEncode(
          _canonicalizeJsonValue(
            _persistenceJsonWithoutAssetUpdatedAt(cloudDocument),
          ),
        ) ==
        jsonEncode(
          _canonicalizeJsonValue(
            _persistenceJsonWithoutAssetUpdatedAt(preparedDocument),
          ),
        );
  }

  Object? _canonicalizeJsonValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonicalizeJsonValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalizeJsonValue).toList(growable: false);
    }
    return value;
  }

  Map<String, dynamic> _persistenceJsonWithoutAssetUpdatedAt(
    CanvasDocument document,
  ) {
    final json = Map<String, dynamic>.from(document.toPersistenceJson());
    final rawAssets = json['assets'];
    if (rawAssets is Map) {
      final normalizedAssets = Map<String, dynamic>.from(rawAssets);
      final rawItems = normalizedAssets['items'];
      if (rawItems is List) {
        normalizedAssets['items'] = rawItems
            .map((rawAsset) {
              if (rawAsset is! Map) return rawAsset;
              return Map<String, dynamic>.from(rawAsset)..remove('updatedAt');
            })
            .toList(growable: false);
      }
      json['assets'] = normalizedAssets;
    }
    return json;
  }

  Future<void> verifyProjectOwnership(
    String projectId, {
    required String expectedUserId,
  }) => _requireOwnedProject(projectId, userId: expectedUserId);

  Future<void> _requireOwnedProject(
    String projectId, {
    required String userId,
  }) async {
    final client = _client;
    if (client == null) {
      throw const SyncException('Cloud backend is not configured.');
    }
    final row = await client
        .from('projects')
        .select('owner_id')
        .eq('id', projectId)
        .maybeSingle();
    _authenticatedUserId(expectedUserId: userId);
    final ownerId = row?['owner_id']?.toString().trim();
    if (ownerId != userId) {
      throw const SyncException(
        'The signed-in account does not own this project.',
      );
    }
  }

  Future<void> _claimAndVerifyProjectOwnership(
    String projectId, {
    required String userId,
  }) async {
    await claimProjectOwnership(projectId, expectedUserId: userId);
    await _requireOwnedProject(projectId, userId: userId);
  }

  @visibleForTesting
  Future<void> requireOwnedProjectForTesting(
    String projectId, {
    required String userId,
  }) => _requireOwnedProject(projectId, userId: userId);

  CanvasDocument _decodeDocumentForProject(Object? raw, String projectId) {
    if (raw is! Map) {
      throw const FormatException('Cloud canvas document is not an object.');
    }
    final document = CanvasDocument.fromJson(Map<String, dynamic>.from(raw));
    if (document.projectId != projectId) {
      throw const FormatException('Cloud canvas document project mismatch.');
    }
    return document;
  }

  Future<CanvasDocument?> fetchDocumentSnapshot(String projectId) async {
    if (_client == null) return null;
    try {
      _authenticatedUserId();
      final res = await _client
          .from('canvas_snapshots')
          .select('document_data')
          .eq('project_id', projectId)
          .maybeSingle();

      if (res != null && res['document_data'] != null) {
        final document = _decodeDocumentForProject(
          res['document_data'],
          projectId,
        );
        return await _artifactHydrator.hydrate(
          document,
          projectId: projectId,
          accountId: currentUserId,
        );
      }
    } catch (e) {
      debugPrint('[SupabaseSync] fetchDocumentSnapshot failed: $e');
      throw SyncException(
        'Failed to fetch canvas snapshot for project: $projectId',
        e,
      );
    }
    return null;
  }

  /// Reads and materializes the latest collaboration CRDT snapshot and
  /// operations when the legacy canvas snapshot is absent.
  Future<CanvasDocument?> fetchCollaborationSnapshot(String projectId) async {
    if (_client == null) return null;
    try {
      _authenticatedUserId();
      final response = await _client.rpc(
        'get_canvas_crdt_delta',
        params: {'p_project_id': projectId, 'p_version_vector': const {}},
      );
      if (response is! List) return null;

      CanvasDocument? document;
      var version = CrdtVersionVector();
      var crdtState = <String, dynamic>{};
      final comments = <CanvasComment>[];
      final operations = <CrdtOperation>[];
      for (final rawRow in response) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final snapshot = row['snapshot'];
        if (snapshot is Map) {
          final versionValue = snapshot['version'];
          version = CrdtVersionVector.fromJson(versionValue);
          final rawState = snapshot['state'];
          if (rawState is Map) {
            final envelope = Map<String, dynamic>.from(rawState);
            final rawDocument = envelope['document'];
            if (rawDocument is Map) {
              document = _decodeDocumentForProject(rawDocument, projectId);
            }
            final rawCrdt = envelope['crdt'];
            if (rawCrdt is Map) {
              crdtState = Map<String, dynamic>.from(rawCrdt);
            }
            final rawComments = envelope['comments'];
            if (rawComments is List) {
              comments.addAll(
                rawComments.whereType<Map>().map(
                  (comment) => CanvasComment.fromJson(
                    Map<String, dynamic>.from(comment),
                  ),
                ),
              );
            }
          }
        }
        final rawOperation = row['operation'];
        if (rawOperation is Map) {
          try {
            final operation = CrdtOperation.fromJson(
              Map<String, dynamic>.from(rawOperation),
            );
            if (operation.projectId != projectId) {
              throw const FormatException(
                'Collaboration snapshot operation project mismatch.',
              );
            }
            operations.add(operation);
          } on FormatException catch (error) {
            if (error.message.contains('project mismatch')) rethrow;
            // Ignore malformed historical operations and keep the snapshot.
          }
        }
      }
      if (document == null) return null;
      final session = CrdtDocumentSession.fromSnapshot(
        document: document,
        actorId: 'route-hydrator',
        version: version,
        state: crdtState,
        comments: comments,
      );
      for (final operation in operations) {
        session.applyRemote(operation);
      }
      return await _artifactHydrator.hydrate(
        session.document,
        projectId: projectId,
        accountId: currentUserId,
      );
    } catch (e) {
      debugPrint('[SupabaseSync] fetchCollaborationSnapshot failed: $e');
      throw SyncException(
        'Failed to fetch collaboration snapshot for project: $projectId',
        e,
      );
    }
  }

  Future<void> syncComment(CanvasComment comment, String projectId) async {
    if (_client == null) return;
    try {
      final userId = _authenticatedUserId();
      await _client.from('comments').upsert({
        'id': comment.id,
        'project_id': projectId,
        'feedback_thread_id': comment.feedbackThreadId,
        'author_id': comment.authorId,
        'author_name': comment.authorName,
        'text': comment.text,
        'node_id': comment.nodeId,
        'x': comment.x,
        'y': comment.y,
        'resolved': comment.resolved,
        'edited_at': comment.editedAt?.toIso8601String(),
        'replies': comment.replies.map((r) => r.toJson()).toList(),
        'mentions': comment.mentions,
        'reactions': comment.reactions,
        'attachments': comment.attachments
            .map((attachment) => attachment.toJson())
            .toList(),
        'labels': comment.normalizedLabels,
        'assignee_id': comment.assigneeId,
        'assignee_name': comment.assigneeName,
        'due_date': comment.dueDate?.toIso8601String(),
        'watchers': comment.watchers,
        'updated_by': userId,
        'created_at': comment.createdAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SupabaseSync] syncComment failed: $e');
      throw SyncException('Failed to sync comment to Supabase', e);
    }
  }

  Future<void> deleteComment(String commentId, String projectId) async {
    if (_client == null) return;
    try {
      _authenticatedUserId();
      await _client
          .from('comments')
          .delete()
          .eq('id', commentId)
          .eq('project_id', projectId);
    } catch (e) {
      debugPrint('[SupabaseSync] deleteComment failed: $e');
      throw SyncException('Failed to delete comment from Supabase', e);
    }
  }

  Future<List<CanvasComment>> fetchComments(String projectId) async {
    if (_client == null) return [];
    try {
      final res = await _client
          .from('comments')
          .select()
          .eq('project_id', projectId)
          .order('created_at');
      return res.map((row) {
        final m = row;
        return CanvasComment(
          id: m['id'] as String,
          feedbackThreadId: m['feedback_thread_id'] as String?,
          authorId: m['author_id'] as String? ?? 'anon',
          authorName: m['author_name'] as String? ?? 'Collaborator',
          text: m['text'] as String? ?? '',
          nodeId: m['node_id'] as String?,
          x: (m['x'] as num?)?.toDouble() ?? 0.0,
          y: (m['y'] as num?)?.toDouble() ?? 0.0,
          resolved: m['resolved'] as bool? ?? false,
          createdAt:
              DateTime.tryParse(m['created_at'] as String? ?? '') ??
              DateTime.now(),
          editedAt: DateTime.tryParse(m['edited_at']?.toString() ?? ''),
          replies:
              (m['replies'] as List<dynamic>?)
                  ?.map((r) => CommentReply.fromJson(r as Map<String, dynamic>))
                  .toList() ??
              const [],
          mentions:
              (m['mentions'] as List<dynamic>?)
                  ?.map((mention) => mention.toString())
                  .toList() ??
              const [],
          reactions:
              (m['reactions'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, (v as num).toInt()),
              ) ??
              const {},
          attachments:
              (m['attachments'] as List<dynamic>?)
                  ?.whereType<Map>()
                  .map(
                    (attachment) => CommentAttachment.fromJson(
                      Map<String, dynamic>.from(attachment),
                    ),
                  )
                  .toList() ??
              const [],
          labels:
              (m['labels'] as List<dynamic>?)
                  ?.map((label) => label.toString())
                  .toList() ??
              const [],
          assigneeId: m['assignee_id']?.toString(),
          assigneeName: m['assignee_name']?.toString(),
          dueDate: DateTime.tryParse(m['due_date']?.toString() ?? ''),
          watchers:
              (m['watchers'] as List<dynamic>?)
                  ?.map((watcher) => watcher.toString())
                  .toList() ??
              const [],
        );
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseSync] fetchComments failed: $e');
      return [];
    }
  }

  Future<void> syncProjectSharing(String projectId, bool shared) async {
    if (_client == null) return;
    try {
      final userId = _authenticatedUserId();
      await _client
          .from('projects')
          .update({
            'is_shared': shared,
            'updated_by': userId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', projectId);
    } catch (e) {
      debugPrint('[SupabaseSync] syncProjectSharing failed: $e');
      throw SyncException('Failed to update project share status', e);
    }
  }

  /// Uploads an object and returns its stable bucket-relative path.
  ///
  /// Asset paths are durable metadata. A signed URL is intentionally never
  /// returned here or persisted in a document; callers resolve a transient URL
  /// with [signedAssetUrl] only while rendering.
  Future<String?> uploadAsset({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    bool upsert = true,
    String? expectedUserId,
    bool Function()? isOperationCurrent,
  }) => _uploadAsset(
    bucket: bucket,
    path: path,
    bytes: bytes,
    contentType: contentType,
    upsert: upsert,
    expectedUserId: expectedUserId,
    isOperationCurrent: isOperationCurrent,
    authorization: _ProjectUploadAuthorization.owner,
  );

  /// Uploads after the server confirms editor rights for the active account.
  Future<String?> uploadAssetForProjectEditor({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    bool upsert = true,
    required String expectedUserId,
    bool Function()? isOperationCurrent,
  }) => _uploadAsset(
    bucket: bucket,
    path: path,
    bytes: bytes,
    contentType: contentType,
    upsert: upsert,
    expectedUserId: expectedUserId,
    isOperationCurrent: isOperationCurrent,
    authorization: _ProjectUploadAuthorization.editor,
  );

  Future<String?> _uploadAsset({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    required bool upsert,
    required String? expectedUserId,
    bool Function()? isOperationCurrent,
    required _ProjectUploadAuthorization authorization,
  }) async {
    if (_client == null) return null;
    try {
      _ensureOperationCurrent(isOperationCurrent);
      final userId = _authenticatedUserId(expectedUserId: expectedUserId);
      final segments = path.split('/');
      final projectId = segments.first == 'drawing-paper' && segments.length > 1
          ? segments[1]
          : segments.first;
      StorageAssetReference.parse(
        bucket: bucket,
        path: path,
        projectId: projectId,
      );
      switch (authorization) {
        case _ProjectUploadAuthorization.owner:
          await _requireOwnedProject(projectId, userId: userId);
          break;
        case _ProjectUploadAuthorization.editor:
          final canEdit = await _client.rpc(
            'can_edit_project',
            params: {'p_project_id': projectId},
          );
          if (canEdit != true) {
            throw const SyncException(
              'The signed-in account cannot edit this project.',
            );
          }
          break;
      }
      _authenticatedUserId(expectedUserId: userId);
      _ensureOperationCurrent(isOperationCurrent);
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: upsert,
              contentType: contentType,
              metadata: {
                'size': '${bytes.lengthInBytes}',
                if (contentType != null && contentType.trim().isNotEmpty)
                  'mimetype': contentType.trim().toLowerCase(),
              },
            ),
          );
      _authenticatedUserId(expectedUserId: userId);
      return path;
    } on _CloudOperationCancelled {
      return null;
    } catch (error) {
      if (error is SyncException) rethrow;
      debugPrint('[SupabaseSync] uploadAsset failed: $error');
      return null;
    }
  }

  Future<String?> signedAssetUrl({
    required String bucket,
    required String path,
    int expiresIn = 900,
    String? expectedUserId,
  }) async {
    if (_client == null) return null;
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty || normalizedPath != path) return null;
    if (expiresIn < 60 || expiresIn > 3600) {
      throw ArgumentError.value(
        expiresIn,
        'expiresIn',
        'Signed asset URLs must expire between 60 and 3600 seconds.',
      );
    }
    try {
      _authenticatedUserId(expectedUserId: expectedUserId);
      final signed = await _client.storage
          .from(bucket)
          .createSignedUrl(normalizedPath, expiresIn);
      _authenticatedUserId(expectedUserId: expectedUserId);
      final uri = Uri.tryParse(signed);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        return null;
      }
      return signed;
    } catch (error) {
      if (error is SyncException) rethrow;
      debugPrint('[SupabaseSync] Signed asset URL failed.');
      return null;
    }
  }

  Future<String?> uploadCollaborativeImageAsset({
    required String projectId,
    required String assetId,
    required String source,
    String? expectedUserId,
  }) async {
    if (_client == null) return null;
    _authenticatedUserId(expectedUserId: expectedUserId);
    final normalizedSource = source.trim();
    if (normalizedSource.isEmpty) return null;
    if (_isPublicAssetUrl(normalizedSource)) return normalizedSource;

    final asset = await _readImageAsset(normalizedSource);
    _authenticatedUserId(expectedUserId: expectedUserId);
    if (asset == null || asset.bytes.isEmpty) return null;

    final safeProjectId = _safeStorageSegment(projectId);
    final safeAssetId = _safeStorageSegment(assetId);
    final extension = _imageExtension(asset.contentType);
    return uploadAsset(
      bucket: 'assets',
      path: '$safeProjectId/ai/$safeAssetId$extension',
      bytes: asset.bytes,
      contentType: asset.contentType,
      expectedUserId: expectedUserId,
    );
  }

  Future<DocumentAsset?> prepareCollaborativeAsset({
    required String projectId,
    required DocumentAsset asset,
    String? expectedUserId,
  }) async {
    final source = (asset.durableReference ?? asset.remoteUrl ?? '').trim();
    if (!_needsCollaborativeAssetUpload(asset)) {
      if (_isPrivateProjectStoragePath(source, projectId)) {
        return asset.copyWith(
          storage: DocumentAssetStorage.remote,
          durableReference: source,
          remoteUrl: null,
          localPath: null,
        );
      }
      if (source.isEmpty) {
        // A local path is a runtime delivery handle, not a portable asset
        // source. Refuse every asset without a portable source rather than
        // allowing an empty durable record to cross the collaboration boundary.
        return null;
      }
      if (_isPublicAssetUrl(source)) {
        if (_client == null) return null;
        final decoded = await _readCollaborativeAsset(
          asset,
          source: source,
          projectId: projectId,
        );
        final accountId = _authenticatedUserId(expectedUserId: expectedUserId);
        if (decoded == null || decoded.bytes.isEmpty) return null;
        final actualChecksum = sha256.convert(decoded.bytes).toString();
        final safeProjectId = _safeStorageSegment(projectId);
        final safeAssetId = _safeStorageSegment(asset.id);
        if (safeProjectId != projectId || safeAssetId.isEmpty) return null;
        final storagePath = await uploadAssetForProjectEditor(
          bucket: 'assets',
          path:
              '$safeProjectId/collaboration/$safeAssetId-v${asset.version}${_assetExtension(decoded.contentType, fallbackName: asset.name)}',
          bytes: decoded.bytes,
          contentType: decoded.contentType,
          expectedUserId: accountId,
        );
        _authenticatedUserId(expectedUserId: accountId);
        if (storagePath == null) return null;
        return asset.copyWith(
          storage: DocumentAssetStorage.remote,
          remoteUrl: null,
          durableReference: storagePath,
          localPath: null,
          sizeBytes: decoded.bytes.length,
          checksum: actualChecksum,
          mimeType: decoded.contentType,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      if (_looksLikeOwnedArtifactReference(source)) return null;
      if (_looksLikeStoragePath(source)) return null;
      return asset;
    }
    if (_client == null) return null;

    final accountId = _authenticatedUserId(expectedUserId: expectedUserId);
    final decoded = await _readCollaborativeAsset(
      asset,
      source: source,
      projectId: projectId,
    );
    _authenticatedUserId(expectedUserId: accountId);
    if (decoded == null || decoded.bytes.isEmpty) return null;
    if (asset.sizeBytes != null && asset.sizeBytes != decoded.bytes.length) {
      return null;
    }
    final expectedChecksum = _normalizedAssetChecksum(asset.checksum);
    if (asset.checksum?.trim().isNotEmpty == true && expectedChecksum == null) {
      return null;
    }
    final actualChecksum = sha256.convert(decoded.bytes).toString();
    if (expectedChecksum != null && expectedChecksum != actualChecksum) {
      return null;
    }

    final safeProjectId = _safeStorageSegment(projectId);
    final safeAssetId = _safeStorageSegment(asset.id);
    if (safeProjectId != projectId || safeAssetId.isEmpty) return null;
    final extension = _assetExtension(
      decoded.contentType,
      fallbackName: asset.name,
    );
    final storagePath = await uploadAssetForProjectEditor(
      bucket: 'assets',
      path:
          '$safeProjectId/collaboration/$safeAssetId-v${asset.version}$extension',
      bytes: decoded.bytes,
      contentType: decoded.contentType,
      expectedUserId: accountId,
    );
    _authenticatedUserId(expectedUserId: accountId);
    if (storagePath == null ||
        StorageAssetReference.tryParse(
              bucket: 'assets',
              path: storagePath,
              projectId: projectId,
            ) ==
            null) {
      return null;
    }
    return asset.copyWith(
      storage: DocumentAssetStorage.remote,
      remoteUrl: null,
      durableReference: storagePath,
      localPath: null,
      sizeBytes: decoded.bytes.length,
      checksum: actualChecksum,
      mimeType: decoded.contentType,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Prepares snapshot assets on immutable content-addressed paths. Unlike
  /// collaboration assets, staged snapshot objects are never overwritten.
  Future<CanvasDocument?> _prepareSnapshotDocument(
    CanvasDocument document, {
    String? expectedUserId,
    bool Function()? isOperationCurrent,
    bool stageAssets = true,
  }) async {
    _ensureOperationCurrent(isOperationCurrent);
    if (document.projectId.trim().isEmpty) return null;

    final closure = collectDocumentAssetDependencies(document.nodes);
    final manifest = document.assets;
    final byReference = <String, List<DocumentAsset>>{};
    for (final asset in manifest.items) {
      final reference = asset.durableReference?.trim();
      if (reference != null && reference.isNotEmpty) {
        byReference.putIfAbsent(reference, () => []).add(asset);
      }
    }
    for (final dependency in closure.dependencies) {
      final asset = dependency.assetId == null
          ? null
          : manifest[dependency.assetId!];
      if (asset == null) {
        final reference = dependency.durableReference;
        final candidates = reference == null
            ? const <DocumentAsset>[]
            : byReference[reference] ?? const <DocumentAsset>[];
        if (candidates.length != 1 ||
            candidates.single.kind != dependency.kind) {
          return null;
        }
      } else {
        if (asset.kind != dependency.kind) return null;
        final dependencyReference = dependency.durableReference;
        final assetReference = asset.durableReference?.trim();
        if (dependencyReference != null &&
            assetReference != null &&
            dependencyReference != assetReference) {
          return null;
        }
      }
    }

    var preparedManifest = manifest;
    for (final asset in manifest.items) {
      _ensureOperationCurrent(isOperationCurrent);
      final prepared = stageAssets
          ? await _prepareSnapshotAsset(
              projectId: document.projectId,
              asset: asset,
              expectedUserId: expectedUserId,
              isOperationCurrent: isOperationCurrent,
            )
          : await _normalizeSnapshotAssetForComparison(
              projectId: document.projectId,
              asset: asset,
              expectedUserId: expectedUserId,
            );
      _ensureOperationCurrent(isOperationCurrent);
      if (prepared == null) return null;
      preparedManifest = preparedManifest.upsert(prepared);
    }
    return document.copyWith(assets: preparedManifest);
  }

  Future<DocumentAsset?> _normalizeSnapshotAssetForComparison({
    required String projectId,
    required DocumentAsset asset,
    String? expectedUserId,
  }) async {
    final source = (asset.durableReference ?? asset.remoteUrl ?? '').trim();
    if (!_needsCollaborativeAssetUpload(asset)) {
      if (_isPrivateProjectStoragePath(source, projectId)) {
        return asset.copyWith(
          storage: DocumentAssetStorage.remote,
          durableReference: source,
          remoteUrl: null,
          localPath: null,
        );
      }
      if (source.isNotEmpty &&
          !_isPublicAssetUrl(source) &&
          !_looksLikeStoragePath(source) &&
          !_looksLikeOwnedArtifactReference(source)) {
        return asset;
      }
      return null;
    }
    if (!_looksLikeOwnedArtifactReference(source) &&
        !source.startsWith('data:')) {
      return null;
    }
    final accountId = _authenticatedUserId(expectedUserId: expectedUserId);
    final decoded = await _readCollaborativeAsset(
      asset,
      source: source,
      projectId: projectId,
    );
    _authenticatedUserId(expectedUserId: accountId);
    if (decoded == null || decoded.bytes.isEmpty) return null;
    if (asset.sizeBytes != null && asset.sizeBytes != decoded.bytes.length) {
      return null;
    }
    final expectedChecksum = _normalizedAssetChecksum(asset.checksum);
    if (asset.checksum?.trim().isNotEmpty == true && expectedChecksum == null) {
      return null;
    }
    final actualChecksum = sha256.convert(decoded.bytes).toString();
    if (expectedChecksum != null && expectedChecksum != actualChecksum) {
      return null;
    }
    final safeProjectId = _safeStorageSegment(projectId);
    if (safeProjectId != projectId) return null;
    final path =
        '$safeProjectId/snapshots/$actualChecksum${_assetExtension(decoded.contentType, fallbackName: asset.name)}';
    if (StorageAssetReference.tryParse(
          bucket: 'assets',
          path: path,
          projectId: projectId,
        ) ==
        null) {
      return null;
    }
    return asset.copyWith(
      storage: DocumentAssetStorage.remote,
      remoteUrl: null,
      durableReference: path,
      localPath: null,
      sizeBytes: decoded.bytes.length,
      checksum: actualChecksum,
      mimeType: decoded.contentType,
    );
  }

  Future<DocumentAsset?> _prepareSnapshotAsset({
    required String projectId,
    required DocumentAsset asset,
    String? expectedUserId,
    bool Function()? isOperationCurrent,
  }) async {
    _ensureOperationCurrent(isOperationCurrent);
    final source = (asset.durableReference ?? asset.remoteUrl ?? '').trim();
    if (!_needsCollaborativeAssetUpload(asset)) {
      if (_isPrivateProjectStoragePath(source, projectId)) {
        return asset.copyWith(
          storage: DocumentAssetStorage.remote,
          durableReference: source,
          remoteUrl: null,
          localPath: null,
        );
      }
      if (source.isNotEmpty &&
          !_isPublicAssetUrl(source) &&
          !_looksLikeStoragePath(source) &&
          !_looksLikeOwnedArtifactReference(source)) {
        return asset;
      }
      return null;
    }
    if (_client == null) return null;
    final accountId = _authenticatedUserId(expectedUserId: expectedUserId);
    final decoded = await _readCollaborativeAsset(
      asset,
      source: source,
      projectId: projectId,
    );
    _authenticatedUserId(expectedUserId: accountId);
    if (decoded == null || decoded.bytes.isEmpty) return null;
    if (asset.sizeBytes != null && asset.sizeBytes != decoded.bytes.length) {
      return null;
    }
    final expectedChecksum = _normalizedAssetChecksum(asset.checksum);
    if (asset.checksum?.trim().isNotEmpty == true && expectedChecksum == null) {
      return null;
    }
    final actualChecksum = sha256.convert(decoded.bytes).toString();
    if (expectedChecksum != null && expectedChecksum != actualChecksum) {
      return null;
    }
    final safeProjectId = _safeStorageSegment(projectId);
    if (safeProjectId != projectId) return null;
    final path =
        '$safeProjectId/snapshots/$actualChecksum${_assetExtension(decoded.contentType, fallbackName: asset.name)}';
    if (StorageAssetReference.tryParse(
          bucket: 'assets',
          path: path,
          projectId: projectId,
        ) ==
        null) {
      return null;
    }
    _ensureOperationCurrent(isOperationCurrent);
    final uploaded = await uploadAsset(
      bucket: 'assets',
      path: path,
      bytes: decoded.bytes,
      contentType: decoded.contentType,
      upsert: false,
      expectedUserId: accountId,
      isOperationCurrent: isOperationCurrent,
    );
    _authenticatedUserId(expectedUserId: accountId);
    _ensureOperationCurrent(isOperationCurrent);
    if (uploaded == null) {
      final existingMatches = await _snapshotAssetMatchesExisting(
        path,
        actualChecksum,
        isOperationCurrent: isOperationCurrent,
      );
      _ensureOperationCurrent(isOperationCurrent);
      if (!existingMatches) return null;
    }
    _authenticatedUserId(expectedUserId: accountId);
    return asset.copyWith(
      storage: DocumentAssetStorage.remote,
      remoteUrl: null,
      durableReference: path,
      localPath: null,
      sizeBytes: decoded.bytes.length,
      checksum: actualChecksum,
      mimeType: decoded.contentType,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<bool> _snapshotAssetMatchesExisting(
    String path,
    String expectedChecksum, {
    bool Function()? isOperationCurrent,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      _ensureOperationCurrent(isOperationCurrent);
      final response = await client.storage
          .from('assets')
          .list(
            path: path.substring(0, path.lastIndexOf('/')),
            searchOptions: SearchOptions(
              search: path.substring(path.lastIndexOf('/') + 1),
              limit: 1,
            ),
          );
      _ensureOperationCurrent(isOperationCurrent);
      final fileName = path.split('/').last;
      if (!response.any((file) => file.name == fileName)) return false;
      _ensureOperationCurrent(isOperationCurrent);
      final bytes = await client.storage.from('assets').download(path);
      _ensureOperationCurrent(isOperationCurrent);
      return sha256.convert(bytes).toString() == expectedChecksum;
    } on _CloudOperationCancelled {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Stages every asset in a document before the document crosses a durable
  /// collaboration or publication boundary. Runtime paths and delivery URLs
  /// are never copied into the returned document.
  Future<CanvasDocument?> prepareCollaborativeDocument(
    CanvasDocument document, {
    String? expectedUserId,
  }) async {
    if (document.projectId.trim().isEmpty) return null;

    final closure = collectDocumentAssetDependencies(document.nodes);
    final manifest = document.assets;
    final reachableIds = closure.assetIds;
    final byReference = <String, List<DocumentAsset>>{};
    for (final asset in manifest.items) {
      final reference = asset.durableReference?.trim();
      if (reference != null && reference.isNotEmpty) {
        byReference.putIfAbsent(reference, () => []).add(asset);
      }
    }

    // A payload reference is a durable dependency, not optional decoration.
    // Reject stale/unknown IDs before any upload so a partial snapshot cannot
    // cross the collaboration boundary.
    for (final dependency in closure.dependencies) {
      final asset = dependency.assetId == null
          ? null
          : manifest[dependency.assetId!];
      if (asset == null) {
        final reference = dependency.durableReference;
        final candidates = reference == null
            ? const <DocumentAsset>[]
            : byReference[reference] ?? const <DocumentAsset>[];
        if (candidates.length != 1 ||
            candidates.single.kind != dependency.kind) {
          return null;
        }
      } else {
        if (asset.kind != dependency.kind) return null;
        final dependencyReference = dependency.durableReference;
        final assetReference = asset.durableReference?.trim();
        if (dependencyReference != null &&
            assetReference != null &&
            dependencyReference != assetReference) {
          return null;
        }
      }
    }

    var preparedManifest = manifest;
    for (final asset in manifest.items) {
      // Keep unreferenced manifest records durable, but only stage records that
      // can cross this boundary. This preserves existing document semantics.
      if (reachableIds.isNotEmpty && !reachableIds.contains(asset.id)) {
        final prepared = await prepareCollaborativeAsset(
          projectId: document.projectId,
          asset: asset,
          expectedUserId: expectedUserId,
        );
        if (prepared == null) return null;
        preparedManifest = preparedManifest.upsert(prepared);
        continue;
      }
      final prepared = await prepareCollaborativeAsset(
        projectId: document.projectId,
        asset: asset,
        expectedUserId: expectedUserId,
      );
      if (prepared == null) return null;
      preparedManifest = preparedManifest.upsert(prepared);
    }
    return document.copyWith(assets: preparedManifest);
  }

  /// Exposes the delivery decision to focused boundary tests without exposing
  /// runtime bytes, local paths, or provider delivery URLs.
  @visibleForTesting
  bool requiresCollaborativeAssetDeliveryForTesting(DocumentAsset asset) =>
      _needsCollaborativeAssetUpload(asset);

  bool _needsCollaborativeAssetUpload(DocumentAsset asset) {
    final remoteUrl = asset.remoteUrl?.trim() ?? '';
    final durableSource = asset.durableReference?.trim() ?? '';
    final source = durableSource.isNotEmpty ? durableSource : remoteUrl;
    if (source.isEmpty) return asset.localPath?.trim().isNotEmpty == true;
    if (_isPublicAssetUrl(remoteUrl) && durableSource.isEmpty) return true;
    if (_looksLikeOwnedArtifactReference(source)) return true;
    return source.startsWith('data:') ||
        source.startsWith('http://') ||
        source.startsWith('https://');
  }

  bool _looksLikeOwnedArtifactReference(String source) {
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase();
    return scheme == 'varian-image' ||
        scheme == 'varian-file' ||
        scheme == 'varian-media' ||
        scheme == 'varian-video' ||
        scheme == 'varian-model3d';
  }

  bool _looksLikeStoragePath(String source) {
    final normalized = source.toLowerCase();
    if (normalized.startsWith('data:') ||
        normalized.startsWith('http:') ||
        normalized.startsWith('https:') ||
        normalized.startsWith('varian-')) {
      return false;
    }
    return source.contains('/');
  }

  bool _isPrivateProjectStoragePath(String source, String projectId) {
    if (source.isEmpty || _looksLikeOwnedArtifactReference(source)) {
      return false;
    }
    return StorageAssetReference.tryParse(
          bucket: 'assets',
          path: source,
          projectId: projectId,
        ) !=
        null;
  }

  Future<({Uint8List bytes, String contentType})?> _readCollaborativeAsset(
    DocumentAsset asset, {
    required String source,
    required String projectId,
  }) async {
    if (_looksLikeOwnedArtifactReference(source)) {
      return _readOwnedArtifactReference(asset, source);
    }
    return _readBinaryAsset(source, fallbackContentType: asset.mimeType);
  }

  Future<({Uint8List bytes, String contentType})?> _readOwnedArtifactReference(
    DocumentAsset asset,
    String source,
  ) async {
    Object? artifact;
    try {
      switch (asset.kind) {
        case DocumentAssetKind.image:
          final reference = validImageArtifactReference(source);
          if (reference == null) return null;
          artifact = await _artifactHydrator.imageArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact is! ImageArtifact) return null;
          final bytes = await _artifactHydrator.imageArtifactStore.read(
            artifact,
          );
          if (bytes == null || bytes.isEmpty) return null;
          if (!_binaryMatchesContentType(bytes, asset.mimeType)) return null;
          return (bytes: bytes, contentType: _imageContentType(bytes, asset));
        case DocumentAssetKind.document:
          final reference = validFileArtifactReference(source);
          if (reference == null) return null;
          artifact = await _artifactHydrator.fileArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact is! FileArtifact) return null;
          final bytes = await _artifactHydrator.fileArtifactStore.read(
            artifact,
          );
          if (bytes == null || bytes.isEmpty) return null;
          if (!_assetBytesMatchContentType(
            bytes,
            asset.mimeType,
            allowGenericFile: true,
          )) {
            return null;
          }
          return (
            bytes: Uint8List.fromList(bytes),
            contentType: _contentTypeForAsset(asset),
          );
        case DocumentAssetKind.audio:
          final reference = validMediaArtifactReference(source);
          if (reference == null) return null;
          final kind = mediaArtifactKindFromReference(reference);
          if (kind == null) return null;
          artifact = await _artifactHydrator.mediaArtifactStore.hydrate(
            reference,
            kind: kind,
            mimeType: asset.mimeType,
            checksum: mediaArtifactChecksumFromReference(reference),
            fileName: asset.name,
          );
          if (artifact is! MediaArtifact) return null;
          final bytes = await _artifactHydrator.mediaArtifactStore.read(
            artifact,
          );
          if (bytes == null || bytes.isEmpty) return null;
          if (!_binaryMatchesContentType(bytes, asset.mimeType)) return null;
          return (bytes: bytes, contentType: _contentTypeForAsset(asset));
        case DocumentAssetKind.video:
          final reference = validVideoArtifactReference(source);
          if (reference == null) return null;
          artifact = await _artifactHydrator.videoArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact is! VideoArtifact) return null;
          final bytes = await _artifactHydrator.videoArtifactStore.read(
            artifact,
          );
          if (bytes == null || bytes.isEmpty) return null;
          if (!_binaryMatchesContentType(bytes, asset.mimeType)) return null;
          return (bytes: bytes, contentType: _contentTypeForAsset(asset));
        case DocumentAssetKind.model3d:
          final reference = validModel3DArtifactReference(source);
          if (reference == null) return null;
          artifact = await _artifactHydrator.model3DArtifactStore.hydrate(
            reference,
            fileName: asset.name,
          );
          if (artifact is! Model3DArtifact) return null;
          final bytes = await _artifactHydrator.model3DArtifactStore.read(
            artifact,
          );
          if (bytes == null || bytes.isEmpty) return null;
          if (!_binaryMatchesContentType(bytes, asset.mimeType)) return null;
          return (bytes: bytes, contentType: 'model/gltf-binary');
        case DocumentAssetKind.drawing:
        case DocumentAssetKind.font:
        case DocumentAssetKind.other:
          return null;
      }
    } finally {
      if (artifact is ImageArtifact) {
        await _artifactHydrator.imageArtifactStore.dispose(artifact);
      } else if (artifact is FileArtifact) {
        await _artifactHydrator.fileArtifactStore.dispose(artifact);
      } else if (artifact is MediaArtifact) {
        await _artifactHydrator.mediaArtifactStore.dispose(artifact);
      } else if (artifact is VideoArtifact) {
        await _artifactHydrator.videoArtifactStore.dispose(artifact);
      } else if (artifact is Model3DArtifact) {
        await _artifactHydrator.model3DArtifactStore.dispose(artifact);
      }
    }
  }

  String _contentTypeForAsset(DocumentAsset asset) {
    final normalized = asset.mimeType.trim().toLowerCase();
    return normalized.isEmpty ? 'application/octet-stream' : normalized;
  }

  String _imageContentType(Uint8List bytes, DocumentAsset asset) {
    final normalized = asset.mimeType.trim().toLowerCase();
    if (normalized == 'image/png' ||
        normalized == 'image/jpeg' ||
        normalized == 'image/webp') {
      return normalized;
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  String? _normalizedAssetChecksum(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    final checksum = normalized.startsWith('sha256:')
        ? normalized.substring('sha256:'.length)
        : normalized;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ? checksum : null;
  }

  Future<({Uint8List bytes, String contentType})?> _readImageAsset(
    String source,
  ) async {
    final result = await _readBinaryAsset(
      source,
      fallbackContentType: 'image/png',
    );
    if (result == null || !result.contentType.startsWith('image/')) return null;
    return result;
  }

  Future<({Uint8List bytes, String contentType})?> _readBinaryAsset(
    String source, {
    String? fallbackContentType,
  }) async {
    const maxBytes = 50 * 1024 * 1024;
    if (source.startsWith('data:')) {
      final separator = source.indexOf(',');
      if (separator <= 5) return null;
      final metadata = source.substring(5, separator);
      if (!metadata.toLowerCase().contains(';base64')) return null;
      final contentType = metadata.split(';').first.trim().toLowerCase();
      try {
        final bytes = Uint8List.fromList(
          base64Decode(base64.normalize(source.substring(separator + 1))),
        );
        if (bytes.isEmpty || bytes.length > maxBytes) return null;
        final resolvedType = contentType.isEmpty
            ? (fallbackContentType ?? 'application/octet-stream')
            : contentType;
        if (!_binaryMatchesContentType(bytes, resolvedType)) return null;
        return (bytes: bytes, contentType: resolvedType);
      } catch (_) {
        return null;
      }
    }

    final uri = Uri.tryParse(source);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..maxRedirects = 0;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.isRedirect ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxBytes) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > maxBytes) return null;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;
      final contentType =
          response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() ??
          fallbackContentType ??
          _contentTypeFromPath(uri.path);
      if (!_binaryMatchesContentType(bytes, contentType)) return null;
      return (bytes: Uint8List.fromList(bytes), contentType: contentType);
    } catch (_) {
      debugPrint('[SupabaseSync] Asset download failed.');
      return null;
    } finally {
      client.close();
    }
  }

  bool _isPublicAssetUrl(String source) =>
      source.contains('/storage/v1/object/public/assets/');

  bool _assetBytesMatchContentType(
    Uint8List bytes,
    String contentType, {
    bool allowGenericFile = false,
  }) {
    final normalized = contentType.trim().toLowerCase();
    if (allowGenericFile && normalized == 'application/octet-stream') {
      return bytes.isNotEmpty;
    }
    return _binaryMatchesContentType(bytes, normalized);
  }

  bool _binaryMatchesContentType(Uint8List bytes, String contentType) {
    final normalized = contentType.trim().toLowerCase();
    if (normalized == 'application/octet-stream') return false;
    bool startsWith(List<int> prefix, {int offset = 0}) {
      if (bytes.length < offset + prefix.length) return false;
      for (var index = 0; index < prefix.length; index++) {
        if (bytes[offset + index] != prefix[index]) return false;
      }
      return true;
    }

    return switch (normalized) {
      'image/png' => startsWith([137, 80, 78, 71, 13, 10, 26, 10]),
      'image/jpeg' => startsWith([255, 216, 255]),
      'image/gif' => startsWith('GIF'.codeUnits),
      'image/webp' =>
        startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, offset: 8),
      'application/pdf' => startsWith('%PDF-'.codeUnits),
      'model/gltf-binary' => startsWith('glTF'.codeUnits),
      'video/mp4' ||
      'video/quicktime' ||
      'audio/mp4' => startsWith('ftyp'.codeUnits, offset: 4),
      'audio/mpeg' =>
        startsWith('ID3'.codeUnits) ||
            (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224),
      'audio/wav' =>
        startsWith('RIFF'.codeUnits) && startsWith('WAVE'.codeUnits, offset: 8),
      'audio/ogg' || 'application/ogg' => startsWith('OggS'.codeUnits),
      'audio/flac' => startsWith('fLaC'.codeUnits),
      'video/webm' || 'video/x-matroska' => startsWith([26, 69, 223, 163]),
      'application/zip' ||
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        startsWith([80, 75, 3, 4]) || startsWith([80, 75, 5, 6]),
      _ => false,
    };
  }

  String _contentTypeFromPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
  }

  String _imageExtension(String contentType) => switch (contentType) {
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    _ => '.png',
  };

  String _assetExtension(String contentType, {required String fallbackName}) {
    final normalized = contentType.toLowerCase();
    final known = switch (normalized) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'audio/mpeg' => '.mp3',
      'audio/ogg' || 'application/ogg' => '.ogg',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/mp4' || 'audio/x-m4a' => '.m4a',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'application/pdf' => '.pdf',
      _ => '',
    };
    if (known.isNotEmpty) return known;
    final extension = fallbackName.split('.').last.toLowerCase();
    return extension.isEmpty || extension.length > 8 ? '.bin' : '.$extension';
  }

  String _safeStorageSegment(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
