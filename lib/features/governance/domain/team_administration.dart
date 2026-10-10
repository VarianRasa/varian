import 'dart:convert';

import '../../../domain/models/workspace_governance.dart';

enum OrganizationRole { owner, admin, member }

enum WorkspaceRole { owner, admin, editor, commenter, viewer, guest }

class OrganizationNode {
  final String id;
  final String name;
  final List<String> workspaceIds;
  final DateTime createdAt;

  const OrganizationNode({
    required this.id,
    required this.name,
    this.workspaceIds = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'workspaceIds': workspaceIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory OrganizationNode.fromJson(Map<String, dynamic> json) =>
      OrganizationNode(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        workspaceIds: (json['workspaceIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class WorkspaceNode {
  final String id;
  final String organizationId;
  final String name;
  final bool archived;
  final DateTime createdAt;

  const WorkspaceNode({
    required this.id,
    required this.organizationId,
    required this.name,
    this.archived = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'archived': archived,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class WorkspaceMembership {
  final String userId;
  final String workspaceId;
  final WorkspaceRole role;
  final bool guest;
  final DateTime joinedAt;
  final DateTime? expiresAt;

  const WorkspaceMembership({
    required this.userId,
    required this.workspaceId,
    required this.role,
    this.guest = false,
    required this.joinedAt,
    this.expiresAt,
  });

  bool isActiveAt(DateTime now) =>
      expiresAt == null || expiresAt!.isAfter(now.toUtc());

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'workspaceId': workspaceId,
    'role': role.name,
    'guest': guest,
    'joinedAt': joinedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };
}

class IdentityProvisioningReadiness {
  final bool ssoConfigured;
  final bool scimConfigured;
  final bool domainVerified;
  final String? provider;
  final List<String> missingClaims;

  const IdentityProvisioningReadiness({
    this.ssoConfigured = false,
    this.scimConfigured = false,
    this.domainVerified = false,
    this.provider,
    this.missingClaims = const [],
  });

  bool get isReady =>
      ssoConfigured &&
      scimConfigured &&
      domainVerified &&
      missingClaims.isEmpty;

  Map<String, dynamic> toJson() => {
    'ssoConfigured': ssoConfigured,
    'scimConfigured': scimConfigured,
    'domainVerified': domainVerified,
    'provider': provider,
    'missingClaims': missingClaims,
  };
}

class TeamAdministrationPolicy {
  final bool allowGuests;
  final bool requireSso;
  final bool allowProjectTransfer;
  final bool allowUserDeletionRequests;
  final IdentityProvisioningReadiness identity;

  const TeamAdministrationPolicy({
    this.allowGuests = true,
    this.requireSso = false,
    this.allowProjectTransfer = true,
    this.allowUserDeletionRequests = true,
    this.identity = const IdentityProvisioningReadiness(),
  });

  bool canUseWorkspace(WorkspaceMembership membership, DateTime now) {
    if (!membership.isActiveAt(now)) return false;
    return !requireSso || identity.isReady;
  }

  bool canInviteGuest(WorkspaceRole actorRole) =>
      allowGuests && _roleRank(actorRole) >= _roleRank(WorkspaceRole.admin);
}

class ProjectTransferPlan {
  final bool allowed;
  final String reason;
  final String projectId;
  final String sourceWorkspaceId;
  final String targetWorkspaceId;

  const ProjectTransferPlan({
    required this.allowed,
    required this.reason,
    required this.projectId,
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
  });
}

class ProjectTransferPlanner {
  ProjectTransferPlanner._();

  static ProjectTransferPlan plan({
    required String projectId,
    required String sourceWorkspaceId,
    required String targetWorkspaceId,
    required WorkspaceRole actorRole,
    required TeamAdministrationPolicy policy,
    required bool targetWorkspaceExists,
  }) {
    String? reason;
    if (projectId.trim().isEmpty) reason = 'Project ID is required.';
    if (sourceWorkspaceId == targetWorkspaceId) {
      reason = 'Source and target workspaces must differ.';
    }
    if (!policy.allowProjectTransfer) {
      reason = 'Project transfer is disabled by policy.';
    }
    if (!targetWorkspaceExists) reason = 'Target workspace does not exist.';
    if (_roleRank(actorRole) < _roleRank(WorkspaceRole.admin)) {
      reason = 'Only workspace admins can transfer projects.';
    }
    return ProjectTransferPlan(
      allowed: reason == null,
      reason: reason ?? 'Project transfer is allowed.',
      projectId: projectId,
      sourceWorkspaceId: sourceWorkspaceId,
      targetWorkspaceId: targetWorkspaceId,
    );
  }
}

enum ProjectTransferStatus { pending, approved, rejected, completed }

class ProjectTransferRequest {
  final String id;
  final String projectId;
  final String sourceWorkspaceId;
  final String targetWorkspaceId;
  final String requestedBy;
  final ProjectTransferStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const ProjectTransferRequest({
    required this.id,
    required this.projectId,
    required this.sourceWorkspaceId,
    required this.targetWorkspaceId,
    required this.requestedBy,
    this.status = ProjectTransferStatus.pending,
    required this.createdAt,
    this.resolvedAt,
  });

  ProjectTransferRequest resolve(ProjectTransferStatus next, DateTime at) =>
      ProjectTransferRequest(
        id: id,
        projectId: projectId,
        sourceWorkspaceId: sourceWorkspaceId,
        targetWorkspaceId: targetWorkspaceId,
        requestedBy: requestedBy,
        status: next,
        createdAt: createdAt,
        resolvedAt: at.toUtc(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'sourceWorkspaceId': sourceWorkspaceId,
    'targetWorkspaceId': targetWorkspaceId,
    'requestedBy': requestedBy,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
  };
}

class LegalHold {
  final String id;
  final String workspaceId;
  final String matter;
  final String createdBy;
  final List<String> projectIds;
  final bool active;
  final DateTime createdAt;

  const LegalHold({
    required this.id,
    required this.workspaceId,
    required this.matter,
    required this.createdBy,
    this.projectIds = const [],
    this.active = true,
    required this.createdAt,
  });

  bool protects(String projectId) => active && projectIds.contains(projectId);

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'matter': matter,
    'createdBy': createdBy,
    'projectIds': projectIds,
    'active': active,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

enum WorkspaceDataRequestType { export, deletion }

enum WorkspaceDataRequestStatus { pending, approved, rejected, completed }

class WorkspaceDataRequest {
  final String id;
  final String workspaceId;
  final String requestedBy;
  final WorkspaceDataRequestType type;
  final WorkspaceDataRequestStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;

  const WorkspaceDataRequest({
    required this.id,
    required this.workspaceId,
    required this.requestedBy,
    required this.type,
    this.status = WorkspaceDataRequestStatus.pending,
    required this.createdAt,
    this.completedAt,
  });

  bool canExecute({
    required WorkspacePolicy policy,
    required Iterable<LegalHold> legalHolds,
  }) {
    if (status != WorkspaceDataRequestStatus.approved) return false;
    if (type == WorkspaceDataRequestType.export) return policy.canExportData();
    return !legalHolds.any(
      (hold) => hold.workspaceId == workspaceId && hold.active,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'workspaceId': workspaceId,
    'requestedBy': requestedBy,
    'type': type.name,
    'status': status.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };
}

class AdminActivityDashboard {
  final List<WorkspaceAuditEvent> auditEvents;
  final List<ProjectTransferRequest> transferRequests;
  final List<WorkspaceDataRequest> dataRequests;

  const AdminActivityDashboard({
    this.auditEvents = const [],
    this.transferRequests = const [],
    this.dataRequests = const [],
  });

  int get pendingTransfers => transferRequests
      .where((request) => request.status == ProjectTransferStatus.pending)
      .length;

  int get pendingDataRequests => dataRequests
      .where((request) => request.status == WorkspaceDataRequestStatus.pending)
      .length;

  String exportAuditJson() => jsonEncode(
    auditEvents.map((event) => event.toJson()).toList(growable: false),
  );
}

int _roleRank(WorkspaceRole role) => switch (role) {
  WorkspaceRole.guest => 0,
  WorkspaceRole.viewer => 1,
  WorkspaceRole.commenter => 2,
  WorkspaceRole.editor => 3,
  WorkspaceRole.admin => 4,
  WorkspaceRole.owner => 5,
};
