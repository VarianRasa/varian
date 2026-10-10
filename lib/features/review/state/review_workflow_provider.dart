import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/review/domain/review_workflow.dart';

final reviewWorkflowProvider =
    StateNotifierProvider.family<
      ReviewWorkflowNotifier,
      AsyncValue<ReviewWorkflow>,
      String
    >(
      (ref, projectId) =>
          ReviewWorkflowNotifier(LocalStorageService(), projectId),
    );

class ReviewWorkflowNotifier extends StateNotifier<AsyncValue<ReviewWorkflow>> {
  final LocalStorageService _storage;
  final String projectId;
  String? _actorId;
  bool _canEditCanvas = false;

  ReviewWorkflowNotifier(this._storage, this.projectId)
    : super(const AsyncValue.loading()) {
    load();
  }

  void configure({required String actorId, required bool canEditCanvas}) {
    _actorId = actorId.trim();
    _canEditCanvas = canEditCanvas;
  }

  Future<void> load() async {
    try {
      state = AsyncValue.data(await _storage.loadReviewWorkflow(projectId));
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> setApprovalState(ReviewApprovalState next) async {
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      return workflow.copyWith(
        approvalState: next,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> setReviewers(Iterable<String> reviewerIds) async {
    await _update((workflow, actorId) {
      _ensureEditor();
      final normalized = <String>[];
      final seen = <String>{};
      for (final value in reviewerIds) {
        final id = value.trim();
        if (id.isEmpty || !seen.add(id)) continue;
        normalized.add(id);
      }
      return workflow.copyWith(
        reviewerIds: List.unmodifiable(normalized),
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> setSpotlight(String? nodeId, {Duration? duration}) async {
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      final normalized = nodeId?.trim();
      if (normalized == null || normalized.isEmpty) {
        return workflow.copyWith(
          spotlightNodeId: null,
          spotlightExpiresAt: null,
          updatedBy: actorId,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      final expiresAt = duration == null
          ? null
          : DateTime.now().toUtc().add(duration);
      return workflow.copyWith(
        spotlightNodeId: normalized,
        spotlightExpiresAt: expiresAt,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> addChecklistItem(String label) async {
    final normalized = label.trim();
    if (normalized.isEmpty) return;
    await _update((workflow, actorId) {
      _ensureEditor();
      final item = ReviewChecklistItem(id: _newId('check'), label: normalized);
      return workflow.copyWith(
        handoffChecklist: [...workflow.handoffChecklist, item],
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> toggleChecklistItem(String itemId) async {
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      final index = workflow.handoffChecklist.indexWhere(
        (item) => item.id == itemId,
      );
      if (index < 0) return workflow;
      final current = workflow.handoffChecklist[index];
      final completed = !current.completed;
      final items = List<ReviewChecklistItem>.from(workflow.handoffChecklist)
        ..[index] = current.copyWith(
          completed: completed,
          completedBy: completed ? actorId : null,
          completedAt: completed ? DateTime.now().toUtc() : null,
        );
      return workflow.copyWith(
        handoffChecklist: items,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> removeChecklistItem(String itemId) async {
    await _update((workflow, actorId) {
      _ensureEditor();
      return workflow.copyWith(
        handoffChecklist: workflow.handoffChecklist
            .where((item) => item.id != itemId)
            .toList(growable: false),
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> upsertWalkthroughStep({
    String? id,
    required String title,
    String description = '',
    String? nodeId,
    int? order,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return;
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      final existingIndex = id == null
          ? -1
          : workflow.walkthrough.indexWhere((step) => step.id == id);
      final step = ReviewWalkthroughStep(
        id: id?.trim().isNotEmpty == true ? id!.trim() : _newId('step'),
        title: normalizedTitle,
        description: description.trim(),
        nodeId: nodeId?.trim().isEmpty == true ? null : nodeId?.trim(),
        order:
            order ??
            (existingIndex >= 0
                ? workflow.walkthrough[existingIndex].order
                : workflow.walkthrough.length),
      );
      final steps = List<ReviewWalkthroughStep>.from(workflow.walkthrough);
      if (existingIndex >= 0) {
        steps[existingIndex] = step;
      } else {
        steps.add(step);
      }
      return workflow.copyWith(
        walkthrough: steps,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> removeWalkthroughStep(String stepId) async {
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      return workflow.copyWith(
        walkthrough: workflow.walkthrough
            .where((step) => step.id != stepId)
            .toList(growable: false),
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> setSpeakerNotes(String frameId, String notes) async {
    final normalizedFrameId = frameId.trim();
    if (normalizedFrameId.isEmpty) return;
    await _update((workflow, actorId) {
      if (!_canReview(workflow, actorId)) return workflow;
      final nextNotes = Map<String, String>.from(workflow.speakerNotes);
      if (notes.trim().isEmpty) {
        nextNotes.remove(normalizedFrameId);
      } else {
        nextNotes[normalizedFrameId] = notes.trim();
      }
      return workflow.copyWith(
        speakerNotes: nextNotes,
        updatedBy: actorId,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  Future<void> _update(
    ReviewWorkflow Function(ReviewWorkflow workflow, String actorId) mutate,
  ) async {
    final workflow = state.asData?.value;
    final actorId = _actorId?.trim() ?? '';
    if (workflow == null || actorId.isEmpty) return;
    final next = mutate(workflow, actorId);
    if (identical(next, workflow) || _sameJson(next, workflow)) return;
    await _storage.saveReviewWorkflow(next);
    state = AsyncValue.data(next);
  }

  bool _canReview(ReviewWorkflow workflow, String actorId) =>
      workflow.canReview(actorId, canEditCanvas: _canEditCanvas);

  void _ensureEditor() {
    if (!_canEditCanvas) {
      throw StateError('Only an editor can manage review workflow settings.');
    }
  }

  static bool _sameJson(ReviewWorkflow first, ReviewWorkflow second) =>
      first.toJson().toString() == second.toJson().toString();

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}
