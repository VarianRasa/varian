import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/governance/domain/team_administration.dart';
import 'package:varian/features/governance/domain/usage_billing.dart';
import 'package:varian/features/governance/domain/workspace_policy_engine.dart';

void main() {
  final now = DateTime.utc(2026, 9, 14);
  final owner = WorkspaceMembership(
    userId: 'owner',
    workspaceId: 'workspace',
    role: WorkspaceRole.owner,
    joinedAt: now,
  );
  final editor = WorkspaceMembership(
    userId: 'editor',
    workspaceId: 'workspace',
    role: WorkspaceRole.editor,
    joinedAt: now,
  );

  test('legal hold blocks delete and purge but allows export', () {
    final hold = LegalHold(
      id: 'hold',
      workspaceId: 'workspace',
      matter: 'matter',
      createdBy: 'owner',
      projectIds: ['project'],
      createdAt: now,
    );
    final engine = WorkspacePolicyEngine(legalHolds: [hold]);

    expect(
      engine
          .decide(
            action: WorkspaceAction.deleteData,
            membership: owner,
            projectId: 'project',
            now: now,
          )
          .allowed,
      isFalse,
    );
    expect(
      engine
          .decide(
            action: WorkspaceAction.exportData,
            membership: owner,
            projectId: 'project',
            now: now,
          )
          .allowed,
      isTrue,
    );
  });

  test('role gates editing and guest invitations', () {
    const engine = WorkspacePolicyEngine();
    expect(
      engine
          .decide(action: WorkspaceAction.edit, membership: editor, now: now)
          .allowed,
      isTrue,
    );
    expect(
      engine
          .decide(
            action: WorkspaceAction.inviteGuest,
            membership: editor,
            now: now,
          )
          .allowed,
      isFalse,
    );
  });

  test('consumption uses the same entitlement gate as billing', () {
    final entitlement = EntitlementSnapshot(
      planId: 'starter',
      revision: 1,
      limits: {UsageMetric.aiCredits: 10},
      overagePolicy: OveragePolicy.block,
      fetchedAt: now,
      status: EntitlementStatus.active,
    );
    final engine = WorkspacePolicyEngine(entitlement: entitlement);
    final decision = engine.decide(
      action: WorkspaceAction.consumeUsage,
      membership: editor,
      usageMetric: UsageMetric.aiCredits,
      currentUsage: 9,
      requestedDelta: 2,
      now: now,
    );
    expect(decision.allowed, isFalse);
  });
}
