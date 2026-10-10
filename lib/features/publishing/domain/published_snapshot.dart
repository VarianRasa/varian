import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/document.dart';

enum PublishedAccess { link, password, private }

enum PublishedDownloadPolicy { allowed, disabled, exportOnly }

class PublishedSnapshot {
  final String id;
  final String projectId;
  final int version;
  final CanvasDocument document;
  final String publishedBy;
  final DateTime publishedAt;
  final DateTime? expiresAt;
  final PublishedAccess access;
  final PublishedDownloadPolicy downloadPolicy;
  final bool embedEnabled;
  final bool watermarkEnabled;
  final String? passwordDigest;
  final String contentHash;

  const PublishedSnapshot({
    required this.id,
    required this.projectId,
    required this.version,
    required this.document,
    required this.publishedBy,
    required this.publishedAt,
    this.expiresAt,
    this.access = PublishedAccess.link,
    this.downloadPolicy = PublishedDownloadPolicy.allowed,
    this.embedEnabled = false,
    this.watermarkEnabled = false,
    this.passwordDigest,
    required this.contentHash,
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  bool canRead({String? password, DateTime? now}) {
    final current = now ?? DateTime.now();
    if (expiresAt != null && !expiresAt!.isAfter(current)) return false;
    switch (access) {
      case PublishedAccess.link:
        return true;
      case PublishedAccess.private:
        return false;
      case PublishedAccess.password:
        return passwordDigest == _digest(id, password ?? '');
    }
  }

  bool canDownload({String? password, DateTime? now}) =>
      canRead(password: password, now: now) &&
      downloadPolicy != PublishedDownloadPolicy.disabled;

  static String passwordDigestFor(String id, String password) =>
      _digest(id, password);

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'version': version,
    'document': document.toPersistenceJson(),
    'publishedBy': publishedBy,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'access': access.name,
    'downloadPolicy': downloadPolicy.name,
    'embedEnabled': embedEnabled,
    'watermarkEnabled': watermarkEnabled,
    'passwordDigest': passwordDigest,
    'contentHash': contentHash,
  };

  factory PublishedSnapshot.fromJson(Map<String, dynamic> json) =>
      PublishedSnapshot(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        version: (json['version'] as num?)?.toInt() ?? 1,
        document: CanvasDocument.fromJson(
          Map<String, dynamic>.from(json['document'] as Map),
        ),
        publishedBy: json['publishedBy'] as String? ?? '',
        publishedAt: DateTime.parse(json['publishedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.tryParse(json['expiresAt'] as String),
        access: PublishedAccess.values.firstWhere(
          (value) => value.name == json['access'],
          orElse: () => PublishedAccess.link,
        ),
        downloadPolicy: PublishedDownloadPolicy.values.firstWhere(
          (value) => value.name == json['downloadPolicy'],
          orElse: () => PublishedDownloadPolicy.allowed,
        ),
        embedEnabled: json['embedEnabled'] as bool? ?? false,
        watermarkEnabled: json['watermarkEnabled'] as bool? ?? false,
        passwordDigest: json['passwordDigest'] as String?,
        contentHash: json['contentHash'] as String? ?? '',
      );

  static PublishedSnapshot publish(
    CanvasDocument document, {
    required String publishedBy,
    int version = 1,
    String? id,
    DateTime? expiresAt,
    PublishedAccess access = PublishedAccess.link,
    PublishedDownloadPolicy downloadPolicy = PublishedDownloadPolicy.allowed,
    bool embedEnabled = false,
    bool watermarkEnabled = false,
    String? password,
    DateTime? publishedAt,
  }) {
    final snapshotId = id ?? const Uuid().v4();
    final passwordDigest =
        access == PublishedAccess.password && password != null
        ? _digest(snapshotId, password)
        : null;
    final contentHash = sha256
        .convert(utf8.encode(jsonEncode(document.toPersistenceJson())))
        .toString();
    return PublishedSnapshot(
      id: snapshotId,
      projectId: document.projectId,
      version: version,
      document: document,
      publishedBy: publishedBy,
      publishedAt: (publishedAt ?? DateTime.now()).toUtc(),
      expiresAt: expiresAt?.toUtc(),
      access: access,
      downloadPolicy: downloadPolicy,
      embedEnabled: embedEnabled,
      watermarkEnabled: watermarkEnabled,
      passwordDigest: passwordDigest,
      contentHash: contentHash,
    );
  }

  static String _digest(String id, String password) =>
      sha256.convert(utf8.encode('$id:$password')).toString();
}
