import '../../../domain/models/workspace_governance.dart';
import 'team_administration.dart';
import 'usage_billing.dart';

enum WorkspaceAction {
  open,
  edit,
  comment,
  inviteGuest,
  transferProject,
  exportData,
  deleteData,
  purgeRetention,
  enablePlugin,
  consumeUsage,
}

class WorkspacePolicyDecision {
  final bool allowed;
  final String reason;
  final bool overage;

  const WorkspacePolicyDecision({
    required this.allowed,
    required this.reason,
    this.overage = false,
  });
}

class WorkspacePolicyEngine {
  final TeamAdministrationPolicy teamPolicy;
  final WorkspacePolicy workspacePolicy;
  final Iterable<LegalHold> legalHolds;
  final EntitlementSnapshot? entitlement;

  const WorkspacePolicyEngine({
    this.teamPolicy = const TeamAdministrationPolicy(),
    this.workspacePolicy = const WorkspacePolicy(),
    this.legalHolds = const [],
    this.entitlement,
  });

  WorkspacePolicyDecision decide({
    required WorkspaceAction action,
    required WorkspaceMembership membership,
    required DateTime now,
    UsageMetric? usageMetric,
    int currentUsage = 0,
    int requestedDelta = 0,
    String? projectId,
    bool targetWorkspaceExists = true,
  }) {
    if (!membership.isActiveAt(now)) {
      return const WorkspacePolicyDecision(
        allowed: false,
        reason: 'Workspace membership is expired.',
      );
    }
    if (!teamPolicy.canUseWorkspace(membership, now)) {
      return const WorkspacePolicyDecision(
        allowed: false,
        reason: 'Workspace requires a ready SSO and identity configuration.',
      );
    }

    final protectedProject =
        projectId != null && legalHolds.any((hold) => hold.protects(projectId));
    final protectedWorkspace = legalHolds.any(
      (hold) => hold.workspaceId == membership.workspaceId && hold.active,
    );
    if ((action == WorkspaceAction.deleteData ||
            action == WorkspaceAction.purgeRetention) &&
        (protectedProject || protectedWorkspace)) {
      return const WorkspacePolicyDecision(
        allowed: false,
        reason: 'Legal hold prevents destructive data operations.',
      );
    }

    switch (action) {
      case WorkspaceAction.open:
        return const WorkspacePolicyDecision(
          allowed: true,
          reason: 'Workspace access is allowed.',
        );
      case WorkspaceAction.edit:
        return _roleDecision(
          membership.role,
          WorkspaceRole.editor,
          'Editing requires editor or administrator access.',
        );
      case WorkspaceAction.comment:
        return _roleDecision(
          membership.role,
          WorkspaceRole.commenter,
          'Commenting requires commenter or higher access.',
        );
      case WorkspaceAction.inviteGuest:
        return WorkspacePolicyDecision(
          allowed: teamPolicy.canInviteGuest(membership.role),
          reason: teamPolicy.canInviteGuest(membership.role)
              ? 'Guest invitations are allowed.'
              : 'Guest invitations require administrator access.',
        );
      case WorkspaceAction.transferProject:
        return WorkspacePolicyDecision(
          allowed:
              membership.role == WorkspaceRole.owner ||
              membership.role == WorkspaceRole.admin &&
                  teamPolicy.allowProjectTransfer &&
                  targetWorkspaceExists,
          reason:
              membership.role != WorkspaceRole.owner &&
                  !teamPolicy.allowProjectTransfer
              ? 'Project transfer is disabled by policy.'
              : !targetWorkspaceExists
              ? 'Target workspace does not exist.'
              : 'Project transfer is allowed.',
        );
      case WorkspaceAction.exportData:
        return WorkspacePolicyDecision(
          allowed:
              membership.role == WorkspaceRole.owner ||
              membership.role == WorkspaceRole.admin &&
                  workspacePolicy.canExportData(),
          reason: workspacePolicy.canExportData()
              ? 'Data export is allowed.'
              : 'Data export is disabled by workspace policy.',
        );
      case WorkspaceAction.deleteData:
      case WorkspaceAction.purgeRetention:
        return _roleDecision(
          membership.role,
          WorkspaceRole.admin,
          'Destructive data operations require administrator access.',
        );
      case WorkspaceAction.enablePlugin:
        return _roleDecision(
          membership.role,
          WorkspaceRole.admin,
          'Plugin enablement requires administrator access.',
        );
      case WorkspaceAction.consumeUsage:
        if (entitlement == null || usageMetric == null) {
          return const WorkspacePolicyDecision(
            allowed: false,
            reason: 'An entitlement snapshot and usage metric are required.',
          );
        }
        final decision = UsageGate.evaluate(
          entitlement: entitlement!,
          metric: usageMetric,
          currentUsage: currentUsage,
          requestedDelta: requestedDelta,
          now: now,
        );
        return WorkspacePolicyDecision(
          allowed: decision.allowed,
          overage: decision.overage,
          reason: decision.reason,
        );
    }
  }

  WorkspacePolicyDecision _roleDecision(
    WorkspaceRole actual,
    WorkspaceRole required,
    String deniedReason,
  ) {
    final allowed = _roleRank(actual) >= _roleRank(required);
    return WorkspacePolicyDecision(
      allowed: allowed,
      reason: allowed ? 'Workspace action is allowed.' : deniedReason,
    );
  }
}

int _roleRank(WorkspaceRole role) => switch (role) {
  WorkspaceRole.guest => 0,
  WorkspaceRole.viewer => 1,
  WorkspaceRole.commenter => 2,
  WorkspaceRole.editor => 3,
  WorkspaceRole.admin => 4,
  WorkspaceRole.owner => 5,
};
