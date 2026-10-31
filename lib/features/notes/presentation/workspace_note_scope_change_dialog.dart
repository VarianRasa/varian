import 'dart:async';

import 'package:flutter/material.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_project_scope.dart';
import 'package:varian/features/notes/domain/workspace_note_scope_change_job.dart';

class WorkspaceNoteScopeChangeDialog extends StatefulWidget {
  const WorkspaceNoteScopeChangeDialog({
    required this.note,
    required this.accountId,
    required this.repository,
    required this.onScopeChanged,
    super.key,
  });

  final WorkspaceNote note;
  final String accountId;
  final WorkspaceNoteRepository repository;
  final Future<void> Function() onScopeChanged;

  @override
  State<WorkspaceNoteScopeChangeDialog> createState() =>
      _WorkspaceNoteScopeChangeDialogState();
}

class _WorkspaceNoteScopeChangeDialogState
    extends State<WorkspaceNoteScopeChangeDialog> {
  late _NoteScopeOption _selectedScope;
  WorkspaceNoteScopeChangeJob? _job;
  List<WorkspaceNoteProjectScope> _projectScopes = const [];
  String? _error;
  bool _checkingStatus = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _selectedScope = widget.note.projectId == null
        ? const _NoteScopeOption.private()
        : _NoteScopeOption.project(widget.note.projectId!);
    unawaited(_loadExistingStatus());
  }

  Future<void> _loadExistingStatus() async {
    try {
      final job = await widget.repository.getNoteScopeChangeStatus(
        noteId: widget.note.id,
        expectedAccountId: widget.accountId,
      );
      final activeJob =
          job != null && job.status != WorkspaceNoteScopeChangeStatus.complete
          ? job
          : null;
      final projectScopes = activeJob == null
          ? await widget.repository.listEditableNoteProjectScopes(
              expectedAccountId: widget.accountId,
            )
          : const <WorkspaceNoteProjectScope>[];
      if (!mounted) return;
      setState(() {
        _job = activeJob;
        _projectScopes = projectScopes;
        _checkingStatus = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingStatus = false;
        _error = CreativeStudioLocalizations.of(context).notesScopeChangeError;
      });
    }
  }

  Future<void> _moveNote() async {
    if (_working || _selectedScope.projectId == widget.note.projectId) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final jobId = await widget.repository.setNoteProject(
        noteId: widget.note.id,
        projectId: _selectedScope.projectId,
        expectedAccountId: widget.accountId,
      );
      if (!mounted) return;
      if (jobId == null) {
        await widget.onScopeChanged();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _job = WorkspaceNoteScopeChangeJob(
          jobId: jobId,
          status: WorkspaceNoteScopeChangeStatus.pending,
        );
      });
      await _refreshStatus(showBusy: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = CreativeStudioLocalizations.of(context).notesScopeChangeError;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshStatus({bool showBusy = true}) async {
    if (_working && showBusy) return;
    if (showBusy) setState(() => _working = true);
    setState(() => _error = null);
    try {
      final job = await widget.repository.getNoteScopeChangeStatus(
        noteId: widget.note.id,
        expectedAccountId: widget.accountId,
      );
      if (!mounted) return;
      if (job == null) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).notesScopeChangeError;
        });
        return;
      }
      setState(() => _job = job);
      if (job.status == WorkspaceNoteScopeChangeStatus.complete) {
        await widget.onScopeChanged();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = CreativeStudioLocalizations.of(
            context,
          ).notesScopeChangeError;
        });
      }
    } finally {
      if (mounted && showBusy) setState(() => _working = false);
    }
  }

  Future<void> _retry() async {
    final job = _job;
    if (job == null || job.status != WorkspaceNoteScopeChangeStatus.failed) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.repository.retryNoteScopeChange(
        jobId: job.jobId,
        expectedAccountId: widget.accountId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = CreativeStudioLocalizations.of(context).notesScopeChangeError;
      });
    }
    if (mounted) await _refreshStatus(showBusy: false);
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    return AlertDialog(
      title: Text(copy.notesMoveScopeTitle),
      content: SizedBox(
        width: 440,
        child: _checkingStatus
            ? const Center(child: CircularProgressIndicator())
            : _job != null
            ? _statusContent(copy, _job!)
            : _error != null
            ? _statusError(copy)
            : _scopePicker(copy),
      ),
      actions: _checkingStatus
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(copy.close),
              ),
            ]
          : _job != null
          ? _statusActions(copy, _job!)
          : _error != null
          ? [
              TextButton(
                onPressed: _working ? null : _loadExistingStatus,
                child: Text(copy.notesScopeChangeRefresh),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(copy.close),
              ),
            ]
          : [
              TextButton(
                onPressed: _working ? null : () => Navigator.of(context).pop(),
                child: Text(copy.cancel),
              ),
              FilledButton(
                onPressed:
                    _working ||
                        _selectedScope.projectId == widget.note.projectId
                    ? null
                    : _moveNote,
                child: Text(copy.notesScopeChangeConfirm),
              ),
            ],
    );
  }

  Widget _scopePicker(CreativeStudioLocalizations copy) {
    return SingleChildScrollView(
      child: RadioGroup<_NoteScopeOption>(
        groupValue: _selectedScope,
        onChanged: (value) {
          if (!_working && value != null) {
            setState(() => _selectedScope = value);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(copy.notesMoveScopeDescription(widget.note.title)),
            const SizedBox(height: 12),
            RadioListTile<_NoteScopeOption>(
              key: const ValueKey('notes-scope-target-private'),
              value: const _NoteScopeOption.private(),
              title: Text(copy.notesPrivateScopeLabel),
              contentPadding: EdgeInsets.zero,
            ),
            for (final project in _projectScopes)
              RadioListTile<_NoteScopeOption>(
                key: ValueKey('notes-scope-target-${project.id}'),
                value: _NoteScopeOption.project(project.id),
                title: Text(copy.notesProjectScopeLabel(project.name)),
                contentPadding: EdgeInsets.zero,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusContent(
    CreativeStudioLocalizations copy,
    WorkspaceNoteScopeChangeJob job,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        copy.notesScopeChangeStatusLabel(job.status.name),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      Text(copy.notesScopeChangeStatusMessage(job.status.name)),
      if (job.attemptCount > 0) ...[
        const SizedBox(height: 8),
        Text(copy.notesScopeChangeAttempts(job.attemptCount)),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _statusError(CreativeStudioLocalizations copy) => Text(
    _error ?? copy.notesScopeChangeError,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );

  List<Widget> _statusActions(
    CreativeStudioLocalizations copy,
    WorkspaceNoteScopeChangeJob job,
  ) => [
    TextButton(
      onPressed: _working ? null : () => _refreshStatus(),
      child: Text(copy.notesScopeChangeRefresh),
    ),
    if (job.status == WorkspaceNoteScopeChangeStatus.failed)
      FilledButton(
        onPressed: _working ? null : _retry,
        child: Text(copy.notesScopeChangeRetry),
      ),
    TextButton(
      onPressed: _working ? null : () => Navigator.of(context).pop(),
      child: Text(copy.close),
    ),
  ];
}

class _NoteScopeOption {
  const _NoteScopeOption.private() : projectId = null;
  const _NoteScopeOption.project(this.projectId);

  final String? projectId;

  @override
  bool operator ==(Object other) =>
      other is _NoteScopeOption && projectId == other.projectId;

  @override
  int get hashCode => projectId.hashCode;
}
