import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/workspace_governance.dart';

void main() {
  test('workspace policy round trips quotas and retention controls', () {
    const policy = WorkspacePolicy(
      quota: WorkspaceQuota(aiCredits: 10, projectCount: 2),
      retention: RetentionPolicy(trashRetention: Duration(days: 7)),
      allowPublicSharing: false,
      billingPlan: 'team',
    );
    final restored = WorkspacePolicy.fromJson(policy.toJson());

    expect(restored.allowPublicSharing, isFalse);
    expect(restored.quota.aiCredits, 10);
    expect(restored.retention.trashRetention, const Duration(days: 7));
    expect(restored.billingPlan, 'team');
  });

  test('workspace policy gates AI spend and export', () {
    const policy = WorkspacePolicy(
      quota: WorkspaceQuota(aiCredits: 5),
      allowDataExport: false,
    );
    const usage = WorkspaceUsage(aiCredits: 2);

    expect(policy.canSpendAi(usage, 3), isTrue);
    expect(policy.canSpendAi(usage, 4), isFalse);
    expect(policy.canExportData(), isFalse);
  });

  test('audit events parse structured fields from Supabase rows', () {
    final event = WorkspaceAuditEvent.fromJson({
      'id': 'event-1',
      'actor_id': 'user-1',
      'action': 'workspace.policy.updated',
      'operation': 'workspace.policy.updated',
      'target_type': 'workspace',
      'target_id': 'project-1',
      'result': 'success',
      'correlation_id': 'corr-1',
      'project_id': 'project-1',
      'created_at': '2026-09-13T00:00:00Z',
      'metadata': {'safe': true},
    });

    expect(event.actorId, 'user-1');
    expect(event.operation, 'workspace.policy.updated');
    expect(event.targetType, 'workspace');
    expect(event.targetId, 'project-1');
    expect(event.result, 'success');
    expect(event.correlationId, 'corr-1');
    expect(event.metadata['safe'], isTrue);
  });
}
