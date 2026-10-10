import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/governance/domain/team_administration.dart';

void main() {
  final now = DateTime.utc(2026, 9, 13);

  test('organization hierarchy and identity readiness round trip', () {
    const identity = IdentityProvisioningReadiness(
      ssoConfigured: true,
      scimConfigured: true,
      domainVerified: true,
      provider: 'acme-idp',
    );
    const policy = TeamAdministrationPolicy(
      requireSso: true,
      identity: identity,
    );
    final membership = WorkspaceMembership(
      userId: 'user-1',
      workspaceId: 'workspace-1',
      role: WorkspaceRole.editor,
      joinedAt: now,
    );
    final organization = OrganizationNode(
      id: 'org-1',
      name: 'Acme',
      workspaceIds: const ['workspace-1'],
      createdAt: now,
    );

    expect(OrganizationNode.fromJson(organization.toJson()).workspaceIds, [
      'workspace-1',
    ]);
    expect(policy.canUseWorkspace(membership, now), isTrue);
    expect(identity.toJson()['provider'], 'acme-idp');
  });

  test('transfer planner enforces admin and policy boundaries', () {
    final denied = ProjectTransferPlanner.plan(
      projectId: 'project-1',
      sourceWorkspaceId: 'workspace-1',
      targetWorkspaceId: 'workspace-2',
      actorRole: WorkspaceRole.editor,
      policy: const TeamAdministrationPolicy(),
      targetWorkspaceExists: true,
    );
    final allowed = ProjectTransferPlanner.plan(
      projectId: 'project-1',
      sourceWorkspaceId: 'workspace-1',
      targetWorkspaceId: 'workspace-2',
      actorRole: WorkspaceRole.admin,
      policy: const TeamAdministrationPolicy(),
      targetWorkspaceExists: true,
    );

    expect(denied.allowed, isFalse);
    expect(allowed.allowed, isTrue);
  });

  test(
    'legal hold blocks workspace deletion but not export when policy allows it',
    () {
      const policy = WorkspacePolicy();
      final hold = LegalHold(
        id: 'hold-1',
        workspaceId: 'workspace-1',
        matter: 'Matter 42',
        createdBy: 'admin-1',
        createdAt: now,
      );
      final deletion = WorkspaceDataRequest(
        id: 'delete-1',
        workspaceId: 'workspace-1',
        requestedBy: 'user-1',
        type: WorkspaceDataRequestType.deletion,
        status: WorkspaceDataRequestStatus.approved,
        createdAt: now,
      );
      final exportRequest = WorkspaceDataRequest(
        id: 'export-1',
        workspaceId: 'workspace-1',
        requestedBy: 'user-1',
        type: WorkspaceDataRequestType.export,
        status: WorkspaceDataRequestStatus.approved,
        createdAt: now,
      );

      expect(deletion.canExecute(policy: policy, legalHolds: [hold]), isFalse);
      expect(
        exportRequest.canExecute(policy: policy, legalHolds: [hold]),
        isTrue,
      );
    },
  );

  test('admin dashboard reports pending work and structured audit export', () {
    final dashboard = AdminActivityDashboard(
      auditEvents: [
        WorkspaceAuditEvent(
          id: 'event-1',
          actorId: 'admin-1',
          action: 'project.transfer.requested',
          timestamp: now,
        ),
      ],
      transferRequests: [
        ProjectTransferRequest(
          id: 'transfer-1',
          projectId: 'project-1',
          sourceWorkspaceId: 'workspace-1',
          targetWorkspaceId: 'workspace-2',
          requestedBy: 'admin-1',
          createdAt: now,
        ),
      ],
    );

    expect(dashboard.pendingTransfers, 1);
    expect(dashboard.exportAuditJson(), contains('project.transfer.requested'));
    expect(dashboard.exportAuditJson(), startsWith('[{"id"'));
  });
}
