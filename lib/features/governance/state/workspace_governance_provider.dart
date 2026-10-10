import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/supabase_service.dart';
import '../../../data/remote/supabase_sync_provider.dart';
import '../../../domain/models/workspace_governance.dart';

@immutable
class WorkspaceGovernanceKey {
  const WorkspaceGovernanceKey({
    required this.projectId,
    required this.expectedUserId,
  });

  final String projectId;
  final String expectedUserId;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceGovernanceKey &&
      other.projectId == projectId &&
      other.expectedUserId == expectedUserId;

  @override
  int get hashCode => Object.hash(projectId, expectedUserId);
}

@immutable
class WorkspaceDeletionGovernance {
  const WorkspaceDeletionGovernance({
    required this.snapshot,
    required this.eligibility,
  });

  final WorkspaceGovernanceSnapshot snapshot;
  final WorkspaceOwnerEligibility eligibility;
}

@immutable
class WorkspaceGovernanceControllerState {
  const WorkspaceGovernanceControllerState({
    this.governance = const AsyncValue.loading(),
    this.isMutating = false,
    this.actionError,
  });

  final AsyncValue<WorkspaceDeletionGovernance> governance;
  final bool isMutating;
  final Object? actionError;

  WorkspaceGovernanceControllerState copyWith({
    AsyncValue<WorkspaceDeletionGovernance>? governance,
    bool? isMutating,
    Object? actionError = _unchanged,
  }) => WorkspaceGovernanceControllerState(
    governance: governance ?? this.governance,
    isMutating: isMutating ?? this.isMutating,
    actionError: identical(actionError, _unchanged)
        ? this.actionError
        : actionError,
  );

  static const Object _unchanged = Object();
}

final workspaceGovernanceProvider =
    StateNotifierProvider.family<
      WorkspaceGovernanceController,
      WorkspaceGovernanceControllerState,
      WorkspaceGovernanceKey
    >((ref, key) {
      final service = ref.watch(supabaseSyncServiceProvider);
      final controller = WorkspaceGovernanceController(service, key);
      unawaited(controller.load());
      return controller;
    });

class WorkspaceGovernanceController
    extends StateNotifier<WorkspaceGovernanceControllerState> {
  WorkspaceGovernanceController(this._service, this._key)
    : super(const WorkspaceGovernanceControllerState());

  final SupabaseSyncService _service;
  final WorkspaceGovernanceKey _key;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      governance: const AsyncValue.loading(),
      actionError: null,
    );
    try {
      final value = await _fetch();
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        governance: AsyncValue.data(value),
        actionError: null,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        governance: AsyncValue.error(error, stackTrace),
        actionError: error,
      );
    }
  }

  Future<bool> requestDeletion() => _mutate(cancelRequest: false);

  Future<bool> cancelDeletion() => _mutate(cancelRequest: true);

  Future<WorkspaceDeletionGovernance> _fetch() async {
    final userId = _requireExpectedAccount();
    final results = await Future.wait<Object>([
      _service.getWorkspaceOwnerEligibility(
        _key.projectId,
        expectedUserId: userId,
      ),
      _service.getWorkspaceGovernance(_key.projectId, expectedUserId: userId),
    ]);
    _requireExpectedAccount();
    final eligibility = results[0] as WorkspaceOwnerEligibility;
    final snapshot = results[1] as WorkspaceGovernanceSnapshot;
    if (eligibility.projectId != _key.projectId ||
        snapshot.projectId != _key.projectId) {
      throw const FormatException(
        'Workspace governance response belongs to another project.',
      );
    }
    return WorkspaceDeletionGovernance(
      snapshot: snapshot,
      eligibility: eligibility,
    );
  }

  Future<bool> _mutate({required bool cancelRequest}) async {
    if (state.isMutating) return false;
    final before = state.governance.valueOrNull;
    try {
      _requireExpectedAccount();
      if (before == null ||
          !before.eligibility.isOwner ||
          before.snapshot.projectId != _key.projectId ||
          before.snapshot.hasPendingDeletionRequest != cancelRequest) {
        throw const SyncException(
          'Workspace ownership or deletion status is unavailable.',
        );
      }
    } catch (error, stackTrace) {
      state = state.copyWith(
        governance: AsyncValue.error(error, stackTrace),
        actionError: error,
      );
      return false;
    }

    state = state.copyWith(isMutating: true, actionError: null);
    final generation = ++_generation;
    try {
      final userId = _requireExpectedAccount();
      if (cancelRequest) {
        await _service.cancelProjectDeletion(
          _key.projectId,
          expectedUserId: userId,
        );
      } else {
        await _service.requestProjectDeletion(
          _key.projectId,
          expectedUserId: userId,
        );
      }
      _requireExpectedAccount();
      final refreshed = await _fetch();
      if (!refreshed.eligibility.isOwner ||
          refreshed.snapshot.hasPendingDeletionRequest == cancelRequest) {
        throw const FormatException(
          'Workspace deletion status did not reflect the requested action.',
        );
      }
      if (!mounted || generation != _generation) return false;
      state = state.copyWith(
        governance: AsyncValue.data(refreshed),
        actionError: null,
        isMutating: false,
      );
      return true;
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return false;
      state = state.copyWith(
        governance: AsyncValue.error(error, stackTrace),
        actionError: error,
        isMutating: false,
      );
      return false;
    }
  }

  String _requireExpectedAccount() {
    if (_service.currentUserId != _key.expectedUserId) {
      throw const SyncException(
        'The cloud account changed during this action.',
      );
    }
    return _key.expectedUserId;
  }
}
