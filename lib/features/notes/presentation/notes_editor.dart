import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/assets/data/asset_service.dart'
    show readPlatformFileBytes;
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_dialog.dart';
import 'package:varian/features/notes/data/workspace_note_attachment_repository.dart';
import 'package:varian/features/notes/data/workspace_note_repository.dart';
import 'package:varian/features/notes/domain/note_markdown_metadata.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/domain/workspace_note_attachments.dart';
import 'package:varian/features/notes/domain/workspace_note_callouts.dart';
import 'package:varian/features/notes/domain/workspace_note_checklist.dart';
import 'package:varian/features/notes/domain/workspace_note_links.dart';
import 'package:varian/features/notes/domain/workspace_note_template.dart';
import 'package:varian/features/notes/domain/note_template_expansion.dart';
import 'package:varian/features/notes/domain/workspace_note_version.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/note_crdt_document.dart';
import 'package:varian/features/notes/domain/note_crdt_operation.dart';
import 'package:varian/features/notes/state/notes_collaboration_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/features/notes/presentation/notes_history_panel.dart';
import 'package:varian/features/notes/presentation/notes_markdown_syntax.dart';
import 'package:varian/features/notes/presentation/notes_properties_panel.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:go_router/go_router.dart';

typedef NotesAttachmentPicker =
    Future<({String name, Uint8List bytes})?> Function();

const _maxNoteAttachmentPreviewBytes = 50 * 1024 * 1024;

class _BoldMarkdownIntent extends Intent {
  const _BoldMarkdownIntent();
}

class _ItalicMarkdownIntent extends Intent {
  const _ItalicMarkdownIntent();
}

class _UndoMarkdownIntent extends Intent {
  const _UndoMarkdownIntent();
}

class _RedoMarkdownIntent extends Intent {
  const _RedoMarkdownIntent();
}

class NotesEditor extends ConsumerStatefulWidget {
  const NotesEditor({
    required this.noteId,
    this.anchorFragment,
    this.exportFileSaver,
    this.attachmentPicker,
    super.key,
  });

  final String noteId;
  final String? anchorFragment;
  final ExportFileSaver? exportFileSaver;
  final NotesAttachmentPicker? attachmentPicker;

  @override
  ConsumerState<NotesEditor> createState() => _NotesEditorState();
}

class _NotesEditorState extends ConsumerState<NotesEditor> {
  final _titleController = TextEditingController();
  final _markdownController = TextEditingController();
  final _markdownFocusNode = FocusNode();
  final _markdownUndoController = UndoHistoryController();
  final _markdownUndoStack = <TextEditingValue>[];
  final _markdownRedoStack = <TextEditingValue>[];
  TextEditingValue _lastMarkdownValue = TextEditingValue.empty;
  bool _applyingMarkdownHistory = false;
  Timer? _saveTimer;
  WorkspaceNote? _note;
  WorkspaceNote? _conflictRemote;
  bool _sourceMode = false;
  bool _dirty = false;
  bool _historyOpen = false;
  bool _historyLoading = false;
  List<WorkspaceNoteVersion> _versions = const [];
  bool _settingControllers = false;
  int _loadGeneration = 0;
  String? _loadingAccountId;
  String? _attemptedAccountId;
  String? _attemptedNoteId;
  bool _loading = false;
  bool _loadFailed = false;
  bool _accountChangedDuringLoad = false;
  String? _renameFailureMessage;
  bool _renameBlocked = false;
  String? _wikiQuery;
  int? _wikiQueryStart;
  int? _wikiQueryEnd;
  int _wikiCreateGeneration = 0;
  bool _wikiCreateInFlight = false;
  final _calloutStates = <int, bool>{};
  late WorkspaceNotesNotifier _notesNotifier;
  String? _observedAccountId;
  WorkspaceNote? _inFlightSnapshot;
  Future<WorkspaceNoteSaveOutcome?> _saveQueue = Future.value();
  NoteCrdtDocument? _crdtDocument;
  final _pendingCrdtOperations = <NoteCrdtOperation>[];
  final _replicaId = const Uuid().v4();
  NotesCollaborationController? _collaborationController;
  bool _applyingRemoteMarkdown = false;
  bool _crdtMaterializationDirty = false;
  DialogRoute<void>? _propertiesDialogRoute;
  String? _anchorNavigationMessage;
  final Map<String, WorkspaceNoteAttachment> _attachmentMetadata = {};
  final Map<String, Uint8List> _attachmentBytes = {};
  final Set<String> _loadingAttachmentIds = {};
  final Set<String> _failedAttachmentIds = {};
  bool _attachmentMetadataReady = false;
  bool _attachmentMetadataLoading = false;
  bool _uploadingAttachment = false;

  @override
  void initState() {
    super.initState();
    _notesNotifier = ref.read(workspaceNotesProvider.notifier);
    _observedAccountId = ref.read(workspaceNotesProvider).accountId;
    _titleController.addListener(_onEdited);
    _markdownController.addListener(_onMarkdownEdited);
    _load();
  }

  @override
  void didUpdateWidget(covariant NotesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _clearAttachmentState();
      _flushPendingSave();
      _leaveCollaboration();
      _crdtDocument = null;
      _pendingCrdtOperations.clear();
      _calloutStates.clear();
      _note = null;
      _dirty = false;
      _historyOpen = false;
      _historyLoading = false;
      _versions = const [];
      _loadFailed = false;
      _inFlightSnapshot = null;
      _attemptedAccountId = null;
      _attemptedNoteId = null;
      _titleController.clear();
      _setMarkdownText('');
      _accountChangedDuringLoad = false;
      _anchorNavigationMessage = null;
      _load();
    }
    final anchorFragment = widget.anchorFragment;
    if (oldWidget.anchorFragment != anchorFragment &&
        anchorFragment != null &&
        _note != null) {
      _navigateToAnchor(anchorFragment);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flushPendingSave();
    _leaveCollaboration();
    _titleController.dispose();
    _markdownController.dispose();
    _markdownFocusNode.dispose();
    _markdownUndoController.dispose();
    super.dispose();
  }

  void _leaveCollaboration() {
    final controller = _collaborationController;
    _collaborationController = null;
    if (controller == null) return;
    controller.onRemoteOperation = null;
    unawaited(controller.leave());
  }

  void _flushPendingSave() {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null ||
        accountId == null ||
        accountId != _observedAccountId ||
        (note.projectId == null && note.ownerUserId != accountId)) {
      return;
    }
    final hasNewEdits = _dirty;
    final pending = hasNewEdits ? _editedNote(note) : _inFlightSnapshot;
    if (pending == null) return;
    _dirty = false;
    _inFlightSnapshot = pending;
    if (pending.title != note.title &&
        (_renameBlocked || _renameFailureMessage != null)) {
      if (hasNewEdits && pending.markdownContent != note.markdownContent) {
        _queueSave(pending.copyWith(title: note.title));
      }
      return;
    }
    if (pending.title != note.title) {
      if (pending.markdownContent == note.markdownContent) {
        unawaited(
          Future<void>.delayed(Duration.zero, () async {
            await _notesNotifier.renameNoteWithLinks(
              noteId: pending.id,
              title: pending.title,
            );
          }),
        );
      } else if (hasNewEdits) {
        _queueSave(pending.copyWith(title: note.title));
      }
      return;
    }
    _inFlightSnapshot = pending;
    final save = _queueSave(pending);
    if (hasNewEdits) unawaited(save);
  }

  Future<WorkspaceNoteSaveOutcome?> _queueSave(WorkspaceNote note) {
    final accountId = _loadingAccountId;
    final next = _saveQueue.then((_) => _notesNotifier.saveNote(note));
    _saveQueue = next.catchError((Object _) {
      if (mounted && _observedAccountId == accountId) {
        _dirty = true;
        setState(() {});
      }
      return null;
    });
    return _saveQueue;
  }

  WorkspaceNote _editedNote(WorkspaceNote note) => note.copyWith(
    title: _titleController.text.trim().isEmpty
        ? 'Untitled Note'
        : _titleController.text.trim(),
    markdownContent: _markdownController.text,
    updatedAt: DateTime.now().toUtc(),
  );

  void _clearAttachmentState() {
    _attachmentMetadata.clear();
    _attachmentBytes.clear();
    _loadingAttachmentIds.clear();
    _failedAttachmentIds.clear();
    _attachmentMetadataReady = false;
    _attachmentMetadataLoading = false;
    _uploadingAttachment = false;
  }

  void _handleAccountChange(String? accountId) {
    if (accountId == _observedAccountId) return;
    _clearAttachmentState();
    final propertiesRoute = _propertiesDialogRoute;
    _propertiesDialogRoute = null;
    if (mounted && propertiesRoute?.isActive == true) {
      Navigator.of(context, rootNavigator: true).removeRoute(propertiesRoute!);
    }
    _flushPendingSave();
    _leaveCollaboration();
    _crdtDocument = null;
    _pendingCrdtOperations.clear();
    _calloutStates.clear();
    _observedAccountId = accountId;
    _loadGeneration++;
    _wikiCreateGeneration++;
    _wikiCreateInFlight = false;
    _clearWikiSuggestion();
    _saveTimer?.cancel();
    _dirty = false;
    _historyOpen = false;
    _historyLoading = false;
    _versions = const [];
    _note = null;
    _loadingAccountId = null;
    _titleController.clear();
    _setMarkdownText('');
    _attemptedAccountId = accountId;
    _attemptedNoteId = accountId == null ? null : widget.noteId;
    _loading = false;
    _loadFailed = false;
    _accountChangedDuringLoad = accountId != null;
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final accountId = ref.read(workspaceNotesProvider).accountId;
    if (accountId == null) {
      setState(() {
        _accountChangedDuringLoad = false;
        _note = null;
        _loadingAccountId = null;
        _attemptedAccountId = null;
        _attemptedNoteId = null;
        _loading = false;
        _loadFailed = false;
        _dirty = false;
        _titleController.clear();
        _setMarkdownText('');
      });
      return;
    }
    _loadingAccountId = accountId;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    final noteId = widget.noteId;
    final note = await ref
        .read(workspaceNotesProvider.notifier)
        .openNote(noteId);
    if (!mounted || generation != _loadGeneration) return;
    final accountStillCurrent =
        ref.read(workspaceNotesProvider).accountId == accountId;
    if (!accountStillCurrent ||
        note == null ||
        (note.projectId == null && note.ownerUserId != accountId)) {
      setState(() {
        _note = null;
        _loadingAccountId = accountStillCurrent ? accountId : null;
        _attemptedAccountId = accountId;
        _attemptedNoteId = noteId;
        _loading = false;
        _loadFailed = accountStillCurrent;
        _accountChangedDuringLoad = !accountStillCurrent;
        _dirty = false;
        _titleController.clear();
        _setMarkdownText('');
      });
      return;
    }
    setState(() {
      _note = note;
      _loadingAccountId = accountId;
      _attemptedAccountId = accountId;
      _attemptedNoteId = noteId;
      _loading = false;
      _loadFailed = false;
      _accountChangedDuringLoad = false;
      _dirty = false;
    });
    _titleController.text = note.title;
    _setMarkdownText(note.markdownContent);
    unawaited(_loadAttachmentMetadata(note, accountId, generation));
    final anchorFragment = widget.anchorFragment;
    if (anchorFragment != null) {
      _navigateToAnchor(anchorFragment);
    } else {
      _anchorNavigationMessage = null;
    }
    _dirty = false;
    _saveTimer?.cancel();
    unawaited(_initializeCrdt(note, generation));
  }

  Future<void> _initializeCrdt(WorkspaceNote note, int generation) async {
    final notifier = ref.read(workspaceNotesProvider.notifier);
    NoteCrdtDocument document;
    try {
      final snapshot = await notifier.loadCrdtSnapshot(note.id);
      if (!mounted || generation != _loadGeneration || _note?.id != note.id) {
        return;
      }
      final rawState = snapshot?['state_json'];
      if (rawState is Map && rawState['noteId'] == note.id) {
        document = NoteCrdtDocument.fromSnapshot(
          Map<String, dynamic>.from(rawState),
        );
      } else {
        document = NoteCrdtDocument.fromMarkdown(note.id, note.markdownContent);
      }
      final delta = await notifier.loadCrdtDelta(
        noteId: note.id,
        versionVector: document.versionVector.toJson(),
      );
      for (final operation in delta) {
        try {
          document.applyRemoteOperation(NoteCrdtOperation.fromJson(operation));
        } catch (_) {
          // Ignore malformed operations; the server remains the access boundary.
        }
      }
      if (!mounted || generation != _loadGeneration || _note?.id != note.id) {
        return;
      }
      _crdtDocument = document;
      final currentMarkdown = _markdownController.text;
      if (currentMarkdown != note.markdownContent) {
        final localOperation = document.applyLocalEdit(
          replicaId: _replicaId,
          markdown: currentMarkdown,
        );
        if (localOperation != null) _pendingCrdtOperations.add(localOperation);
        _crdtMaterializationDirty = true;
      } else if (document.visibleMarkdown != currentMarkdown) {
        _applyRemoteMarkdown(document.visibleMarkdown);
      }
      final operations = List<NoteCrdtOperation>.of(_pendingCrdtOperations);
      final updated = await notifier.syncCrdtEdit(
        note: _note ?? note,
        document: NoteCrdtDocument.fromSnapshot(document.snapshotState()),
        operations: operations,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (updated == null) {
        _crdtDocument = null;
        _pendingCrdtOperations.clear();
        _crdtMaterializationDirty = false;
        return;
      }
      _pendingCrdtOperations.removeWhere(operations.contains);
      _note = updated;
      _crdtMaterializationDirty = _pendingCrdtOperations.isNotEmpty;
      if (updated.projectId != null) {
        _joinProjectCollaboration(updated);
      }
    } catch (_) {
      _crdtDocument = null;
      _pendingCrdtOperations.clear();
      _crdtMaterializationDirty = false;
      // Leave ordinary note saving in place when collaboration is unavailable.
    }
  }

  void _joinProjectCollaboration(WorkspaceNote note) {
    final projectId = note.projectId;
    if (projectId == null) return;
    try {
      final controller = ref.read(notesCollaborationProvider.notifier);
      _collaborationController = controller;
      controller.onRemoteOperation = _handleRemoteCrdtOperation;
      unawaited(
        controller
            .join(noteId: note.id, projectId: projectId)
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Normal note editing remains available if Realtime is unavailable.
    }
  }

  void _applyRemoteMarkdown(String markdown) {
    final oldValue = _markdownController.value;
    final selection = oldValue.selection;
    final boundedSelection = selection.isValid
        ? TextSelection(
            baseOffset: selection.baseOffset.clamp(0, markdown.length),
            extentOffset: selection.extentOffset.clamp(0, markdown.length),
          )
        : TextSelection.collapsed(offset: markdown.length);
    _applyingRemoteMarkdown = true;
    _settingControllers = true;
    _markdownController.value = TextEditingValue(
      text: markdown,
      selection: boundedSelection,
      composing: TextRange.empty,
    );
    _lastMarkdownValue = _markdownController.value;
    _settingControllers = false;
    _applyingRemoteMarkdown = false;
  }

  void _handleRemoteCrdtOperation(Map<String, dynamic> json) {
    final document = _crdtDocument;
    final note = _note;
    if (document == null || note == null || json['noteId'] != note.id) return;
    try {
      final operation = NoteCrdtOperation.fromJson(json);
      final status = document.applyRemoteOperation(operation);
      if (status != CrdtApplyStatus.applied) return;
      final markdown = document.visibleMarkdown;
      if (markdown != _markdownController.text) _applyRemoteMarkdown(markdown);
      _note = note.copyWith(markdownContent: markdown);
      _crdtMaterializationDirty = true;
      _dirty = true;
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 650), _save);
    } catch (_) {
      // Invalid remote envelopes are ignored without disturbing the local draft.
    }
  }

  void _setMarkdownText(String text) {
    _settingControllers = true;
    _markdownController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _settingControllers = false;
    _lastMarkdownValue = _markdownController.value;
    _markdownUndoStack.clear();
    _markdownRedoStack.clear();
    _loadReferencedAttachmentBytes();
  }

  Future<void> _loadAttachmentMetadata(
    WorkspaceNote note,
    String accountId,
    int generation,
  ) async {
    _attachmentMetadataLoading = true;
    try {
      final attachments = await ref
          .read(workspaceNoteAttachmentRepositoryProvider)
          .listForNote(
            accountId: accountId,
            noteId: note.id,
            expectedProjectId: note.projectId,
          );
      if (!_isCurrentAttachmentContext(note, accountId) ||
          generation != _loadGeneration) {
        return;
      }
      _attachmentMetadata
        ..clear()
        ..addEntries(attachments.map((item) => MapEntry(item.id, item)));
      _attachmentBytes.removeWhere(
        (id, _) => !_attachmentMetadata.containsKey(id),
      );
      _failedAttachmentIds.clear();
      _attachmentMetadataReady = true;
      _attachmentMetadataLoading = false;
      setState(() {});
      _loadReferencedAttachmentBytes();
    } catch (_) {
      if (!_isCurrentAttachmentContext(note, accountId) ||
          generation != _loadGeneration) {
        return;
      }
      _attachmentMetadataReady = true;
      _attachmentMetadataLoading = false;
      _failedAttachmentIds.addAll(
        parseWorkspaceNoteAttachmentEmbeds(
          _markdownController.text,
        ).map((embed) => embed.attachmentId),
      );
      setState(() {});
    }
  }

  bool _isCurrentAttachmentContext(WorkspaceNote note, String accountId) {
    return mounted &&
        ref.read(workspaceNotesProvider).accountId == accountId &&
        _observedAccountId == accountId &&
        _loadingAccountId == accountId &&
        _note?.id == note.id &&
        _note?.projectId == note.projectId;
  }

  void _loadReferencedAttachmentBytes() {
    if (!_attachmentMetadataReady || !_noteIsCurrent) return;
    final referencedIds = parseWorkspaceNoteAttachmentEmbeds(
      _markdownController.text,
    ).map((embed) => embed.attachmentId).toSet();
    for (final id in referencedIds) {
      if (_attachmentMetadata.containsKey(id) &&
          !_attachmentBytes.containsKey(id) &&
          !_loadingAttachmentIds.contains(id) &&
          !_failedAttachmentIds.contains(id)) {
        unawaited(_loadAttachmentPreviewBytes(id));
      }
    }
  }

  Future<void> _loadAttachmentPreviewBytes(String attachmentId) async {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null || accountId == null || !_noteIsCurrent) return;
    final markdown = _markdownController.text;
    final repository = ref.read(workspaceNoteAttachmentRepositoryProvider);
    _loadingAttachmentIds.add(attachmentId);
    if (mounted) setState(() {});
    try {
      var bytes = await repository.readCachedBytes(
        accountId: accountId,
        noteId: note.id,
        noteMarkdown: markdown,
        attachmentId: attachmentId,
        projectId: note.projectId,
      );
      if (!_isCurrentAttachmentContext(note, accountId)) return;
      if (bytes == null) {
        bytes = await repository.readBytes(
          accountId: accountId,
          noteId: note.id,
          attachmentId: attachmentId,
          expectedProjectId: note.projectId,
        );
      }
      if (!_isCurrentAttachmentContext(note, accountId) ||
          !parseWorkspaceNoteAttachmentEmbeds(
            _markdownController.text,
          ).any((embed) => embed.attachmentId == attachmentId)) {
        return;
      }
      final usedBytes = _attachmentBytes.values.fold<int>(
        0,
        (total, value) => total + value.length,
      );
      if (usedBytes + bytes.length > _maxNoteAttachmentPreviewBytes) {
        _failedAttachmentIds.add(attachmentId);
      } else {
        _attachmentBytes[attachmentId] = bytes;
      }
    } catch (_) {
      if (_isCurrentAttachmentContext(note, accountId)) {
        _failedAttachmentIds.add(attachmentId);
      }
    } finally {
      _loadingAttachmentIds.remove(attachmentId);
      if (mounted) setState(() {});
    }
  }

  String _renderNoteAttachmentEmbeds(String markdown) {
    final embeds = parseWorkspaceNoteAttachmentEmbeds(markdown);
    if (embeds.isEmpty) return markdown;
    final output = StringBuffer();
    var cursor = 0;
    for (final embed in embeds) {
      final attachment = _attachmentMetadata[embed.attachmentId];
      if (attachment == null) continue;
      output.write(markdown.substring(cursor, embed.start));
      final destination = Uri(
        scheme: 'varian-note-attachment',
        host: attachment.id,
      );
      output.write('![Attachment]($destination)');
      cursor = embed.end;
    }
    if (cursor == 0) return markdown;
    output.write(markdown.substring(cursor));
    return output.toString();
  }

  void _onMarkdownEdited() {
    final value = _markdownController.value;
    if (value.text != _lastMarkdownValue.text) {
      _loadReferencedAttachmentBytes();
    }
    final textChanged = value.text != _lastMarkdownValue.text;
    final document = _crdtDocument;
    if (!_settingControllers &&
        !_applyingRemoteMarkdown &&
        textChanged &&
        document != null) {
      final operation = document.applyLocalEdit(
        replicaId: _replicaId,
        markdown: value.text,
      );
      if (operation != null) {
        _pendingCrdtOperations.add(operation);
        _crdtMaterializationDirty = true;
      }
    }
    if (!_settingControllers && !_applyingMarkdownHistory && textChanged) {
      _markdownUndoStack.add(_lastMarkdownValue);
      _markdownRedoStack.clear();
    }
    _lastMarkdownValue = value;
    if (!_settingControllers) _updateWikiSuggestion(value);
    _onEdited();
  }

  void _updateWikiSuggestion(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _clearWikiSuggestion();
      return;
    }
    final caret = selection.extentOffset;
    final beforeCaret = value.text.substring(0, caret);
    final open = beforeCaret.lastIndexOf('[[');
    if (open < 0 || beforeCaret.indexOf(']]', open) >= 0) {
      _clearWikiSuggestion();
      return;
    }
    final query = beforeCaret.substring(open + 2);
    if (query.contains('\n') || query.contains(']')) {
      _clearWikiSuggestion();
      return;
    }
    _wikiQuery = query;
    _wikiQueryStart = open;
    _wikiQueryEnd = caret;
  }

  void _clearWikiSuggestion() {
    _wikiQuery = null;
    _wikiQueryStart = null;
    _wikiQueryEnd = null;
  }

  List<WorkspaceNote> _wikiSuggestions(List<WorkspaceNote> notes) {
    final source = _note;
    if (source == null) return const [];
    final query = _wikiQuery?.trim().toLowerCase() ?? '';
    return notes
        .where(
          (note) =>
              note.deletedAt == null &&
              notesShareLinkScope(source, note) &&
              (query.isEmpty || note.title.toLowerCase().contains(query)),
        )
        .take(6)
        .toList(growable: false);
  }

  void _insertWikiLink(WorkspaceNote target) {
    final start = _wikiQueryStart;
    final end = _wikiQueryEnd;
    final value = _markdownController.value;
    if (start == null ||
        end == null ||
        start > end ||
        end > value.text.length) {
      _clearWikiSuggestion();
      return;
    }
    final inserted = '[[${target.title}]]<!--varian-note-id:${target.id}-->';
    final text = value.text.replaceRange(start, end, inserted);
    _markdownController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    _clearWikiSuggestion();
    _markdownFocusNode.requestFocus();
  }

  Future<void> _createWikiTarget() async {
    final source = _note;
    final accountId = _loadingAccountId;
    final query = _wikiQuery;
    final title = query?.trim() ?? '';
    final start = _wikiQueryStart;
    final end = _wikiQueryEnd;
    final text = _markdownController.text;
    if (_wikiCreateInFlight ||
        source == null ||
        accountId == null ||
        title.isEmpty ||
        query == null ||
        start == null ||
        end == null ||
        !_noteIsCurrent ||
        end > text.length ||
        text.substring(start + 2, end) != query) {
      return;
    }

    final generation = ++_wikiCreateGeneration;
    setState(() => _wikiCreateInFlight = true);
    try {
      final target = await _notesNotifier.createNote(
        title: title,
        projectId: source.projectId,
      );
      if (!mounted || target == null) return;
      final currentState = ref.read(workspaceNotesProvider);
      final currentText = _markdownController.text;
      if (currentState.accountId != accountId ||
          _loadingAccountId != accountId ||
          _note?.id != source.id ||
          _note?.projectId != source.projectId ||
          !_noteIsCurrent ||
          _wikiQuery != query ||
          _wikiQueryStart != start ||
          _wikiQueryEnd != end ||
          end > currentText.length ||
          currentText.substring(start + 2, end) != query ||
          !notesShareLinkScope(source, target)) {
        return;
      }
      _insertWikiLink(target);
    } finally {
      if (mounted && generation == _wikiCreateGeneration) {
        setState(() => _wikiCreateInFlight = false);
      }
    }
  }

  Widget _blockedNoteImage(Uri uri, String? title, String? alt) {
    final alternative = alt?.trim();
    final imageTitle = title?.trim();
    final label = alternative != null && alternative.isNotEmpty
        ? alternative
        : imageTitle != null && imageTitle.isNotEmpty
        ? imageTitle
        : uri.scheme == 'file'
        ? 'Local image'
        : 'Image';
    return Text('$label is unavailable. Use an approved Notes attachment.');
  }

  Widget _notePreviewImage(Uri uri, String? title, String? alt) {
    if (uri.scheme != 'varian-note-attachment' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty) {
      return _blockedNoteImage(uri, title, alt);
    }
    final attachmentId = uri.host.toLowerCase();
    final attachment = _attachmentMetadata[attachmentId];
    final bytes = _attachmentBytes[attachmentId];
    if (attachment == null) {
      return Text(
        _attachmentMetadataLoading
            ? 'Loading Notes attachment…'
            : 'Notes attachment is unavailable.',
      );
    }
    if (bytes == null) {
      final loading = _loadingAttachmentIds.contains(attachmentId);
      return Card(
        child: ListTile(
          leading: Icon(
            attachment.type == WorkspaceNoteAttachmentType.pdf
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
          ),
          title: Text(attachment.originalName),
          subtitle: Text(
            loading ? 'Loading attachment…' : 'Attachment bytes unavailable.',
          ),
          trailing: IconButton(
            tooltip: 'Delete attachment',
            onPressed: loading
                ? null
                : () => unawaited(_deleteNoteAttachment(attachmentId)),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      );
    }
    if (attachment.type == WorkspaceNoteAttachmentType.pdf) {
      return Card(
        child: ListTile(
          key: ValueKey('note-attachment-$attachmentId'),
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(attachment.originalName),
          subtitle: const Text('PDF attachment'),
          onTap: () => unawaited(_openAttachmentPdf(attachmentId)),
          trailing: IconButton(
            tooltip: 'Delete attachment',
            onPressed: () => unawaited(_deleteNoteAttachment(attachmentId)),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Image.memory(
          bytes,
          key: ValueKey('note-attachment-$attachmentId'),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('Image attachment is invalid.'),
        ),
        IconButton(
          tooltip: 'Delete attachment',
          onPressed: () => unawaited(_deleteNoteAttachment(attachmentId)),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  String _renderNotePreviewMarkdown(List<WorkspaceNote> notes) {
    final markdown = _renderNoteAttachmentEmbeds(_markdownController.text);
    final checklists = renderWorkspaceTaskCheckboxes(markdown);
    final callouts = renderWorkspaceCallouts(
      checklists,
      collapsedCallouts: _calloutStates,
    );
    return renderWorkspaceMarkdown(callouts, notes);
  }

  void _togglePreviewCallout(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.scheme != 'varian-callout' ||
        uri.host != 'toggle' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        !_noteIsCurrent) {
      return;
    }
    final markerStart = int.tryParse(uri.pathSegments[0]);
    final collapsed = int.tryParse(uri.pathSegments[1]);
    if (markerStart == null || (collapsed != 0 && collapsed != 1)) return;
    setState(() => _calloutStates[markerStart] = collapsed == 0);
  }

  void _togglePreviewTask(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.scheme != 'varian-task' ||
        uri.host != 'toggle' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        !_noteIsCurrent) {
      return;
    }
    final markerStart = int.tryParse(uri.pathSegments.single);
    if (markerStart == null) return;
    final current = _markdownController.value;
    final updated = toggleWorkspaceTaskCheckbox(current.text, markerStart);
    if (updated == null) return;
    _markdownController.value = current.copyWith(
      text: updated,
      composing: TextRange.empty,
    );
  }

  Future<({String name, Uint8List bytes})?> _pickNoteAttachment() async {
    final injectedPicker = widget.attachmentPicker;
    if (injectedPicker != null) return injectedPicker();
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'pdf'],
    );
    if (file == null) return null;
    final bytes = await readPlatformFileBytes(
      file,
      maxBytes: workspaceNoteAttachmentMaxBytes,
    );
    if (bytes == null) {
      throw const FormatException(
        'Attachment is empty, unreadable, or larger than 25 MiB.',
      );
    }
    return (name: file.name, bytes: bytes);
  }

  Future<void> _insertNoteAttachment() async {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null ||
        accountId == null ||
        !_noteIsCurrent ||
        _uploadingAttachment) {
      return;
    }
    setState(() => _uploadingAttachment = true);
    try {
      final picked = await _pickNoteAttachment();
      if (picked == null ||
          !mounted ||
          !_isCurrentAttachmentContext(note, accountId)) {
        return;
      }
      if (detectWorkspaceNoteAttachmentType(picked.bytes) == null) {
        throw const FormatException('Unsupported Notes attachment.');
      }
      final attachment = await ref
          .read(workspaceNoteAttachmentRepositoryProvider)
          .upload(
            accountId: accountId,
            noteId: note.id,
            expectedProjectId: note.projectId,
            originalName: picked.name,
            bytes: picked.bytes,
          );
      if (!mounted || !_isCurrentAttachmentContext(note, accountId)) return;
      _attachmentMetadata[attachment.id] = attachment;
      _attachmentBytes[attachment.id] = picked.bytes;
      _failedAttachmentIds.remove(attachment.id);
      final current = _markdownController.value;
      final selection = current.selection;
      final start = selection.isValid ? selection.start : current.text.length;
      final end = selection.isValid ? selection.end : current.text.length;
      final embed = '![[attachment:${attachment.id}]]';
      final insertion = '${start > 0 ? '\n' : ''}$embed\n';
      final updated = current.text.replaceRange(start, end, insertion);
      _markdownController.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: start + insertion.length),
      );
      setState(() {});
    } catch (_) {
      if (mounted && _isCurrentAttachmentContext(note, accountId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attachment upload failed. Check access and retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  Future<void> _openAttachmentPdf(String attachmentId) async {
    final note = _note;
    final accountId = _loadingAccountId;
    final attachment = _attachmentMetadata[attachmentId];
    if (note == null ||
        accountId == null ||
        attachment == null ||
        attachment.type != WorkspaceNoteAttachmentType.pdf ||
        !_noteIsCurrent) {
      return;
    }
    if (!_attachmentBytes.containsKey(attachmentId)) {
      await _loadAttachmentPreviewBytes(attachmentId);
    }
    if (!mounted || !_isCurrentAttachmentContext(note, accountId)) return;
    final bytes = _attachmentBytes[attachmentId];
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF attachment is unavailable offline.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => PdfViewerDialog(
        payload: FilePayload(
          fileName: attachment.originalName,
          fileExtension: 'PDF',
          fileSizeText: '${attachment.sizeBytes} bytes',
          base64Data: base64Encode(bytes),
        ),
      ),
    );
  }

  Future<void> _deleteNoteAttachment(String attachmentId) async {
    final note = _note;
    final accountId = _loadingAccountId;
    final attachment = _attachmentMetadata[attachmentId];
    if (note == null ||
        accountId == null ||
        attachment == null ||
        !_noteIsCurrent) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete attachment?'),
        content: Text(
          'Delete ${attachment.originalName} and remove all of its embeds from this Note?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        !_isCurrentAttachmentContext(note, accountId)) {
      return;
    }
    try {
      await ref
          .read(workspaceNoteAttachmentRepositoryProvider)
          .delete(
            accountId: accountId,
            noteId: note.id,
            attachmentId: attachmentId,
            expectedProjectId: note.projectId,
          );
      if (!mounted || !_isCurrentAttachmentContext(note, accountId)) return;
      final value = _markdownController.value;
      var updated = value.text;
      final embeds = parseWorkspaceNoteAttachmentEmbeds(updated)
          .where((embed) => embed.attachmentId == attachmentId)
          .toList(growable: false);
      for (final embed in embeds.reversed) {
        updated = updated.replaceRange(embed.start, embed.end, '');
      }
      _attachmentBytes.remove(attachmentId);
      _attachmentMetadata.remove(attachmentId);
      _failedAttachmentIds.remove(attachmentId);
      _markdownController.value = value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(
          offset: value.selection.isValid
              ? value.selection.extentOffset.clamp(0, updated.length)
              : updated.length,
        ),
        composing: TextRange.empty,
      );
      setState(() {});
    } catch (_) {
      if (mounted && _isCurrentAttachmentContext(note, accountId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attachment deletion failed. Retry while online.'),
          ),
        );
      }
    }
  }

  Future<void> _openPreviewLink(String? href) async {
    if (href == null) return;
    if (href.startsWith('varian-callout://')) {
      _togglePreviewCallout(href);
      return;
    }
    if (href.startsWith('varian-task://')) {
      _togglePreviewTask(href);
      return;
    }
    if (!href.startsWith('varian-note://')) return;
    final uri = Uri.tryParse(href);
    final id = uri == null
        ? null
        : Uri.decodeComponent(
            uri.host.isNotEmpty ? uri.host : uri.pathSegments.firstOrNull ?? '',
          );
    final state = ref.read(workspaceNotesProvider);
    final accountId = state.accountId;
    final source = _note;
    if (uri == null ||
        id == null ||
        id.isEmpty ||
        accountId == null ||
        source == null) {
      return;
    }
    final target = state.notes
        .where(
          (note) =>
              note.id == id &&
              notesShareLinkScope(source, note) &&
              note.deletedAt == null,
        )
        .firstOrNull;
    if (target == null) return;
    await ref
        .read(activeDocumentTabControllerProvider)
        .select(OpenDocumentTab.note(target));
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return;
    }
    final anchorQuery = uri.fragment.isEmpty
        ? ''
        : '?anchor=${Uri.encodeQueryComponent(uri.fragment)}';
    context.go('/notes/${Uri.encodeComponent(target.id)}$anchorQuery');
  }

  void _applyMarkdown(String prefix, String suffix) {
    final value = _markdownController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final updated = value.text.replaceRange(
      start,
      end,
      '$prefix$selected$suffix',
    );
    _markdownController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: start + prefix.length + selected.length + suffix.length,
      ),
    );
  }

  void _undoMarkdown() {
    if (_markdownUndoStack.isEmpty) return;
    _markdownRedoStack.add(_markdownController.value);
    final previous = _markdownUndoStack.removeLast();
    _applyingMarkdownHistory = true;
    _markdownController.value = previous;
    _applyingMarkdownHistory = false;
    _lastMarkdownValue = previous;
  }

  void _redoMarkdown() {
    if (_markdownRedoStack.isEmpty) return;
    _markdownUndoStack.add(_markdownController.value);
    final next = _markdownRedoStack.removeLast();
    _applyingMarkdownHistory = true;
    _markdownController.value = next;
    _applyingMarkdownHistory = false;
    _lastMarkdownValue = next;
  }

  Future<void> _insertTemplate() async {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null || accountId == null || !_noteIsCurrent) return;
    final selection = _markdownController.selection;
    final noteId = note.id;
    try {
      final templates = await ref
          .read(workspaceNoteRepositoryProvider)
          .listTemplates(
            projectId: note.projectId,
            expectedAccountId: accountId,
          );
      if (!mounted ||
          ref.read(workspaceNotesProvider).accountId != accountId ||
          _note?.id != noteId ||
          _note?.projectId != note.projectId ||
          !_noteIsCurrent) {
        return;
      }
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No templates are available here.')),
        );
        return;
      }
      final choice =
          await showDialog<({WorkspaceNoteTemplate template, bool replace})>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Insert a template'),
              content: SizedBox(
                width: 520,
                height: 360,
                child: ListView.builder(
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final template = templates[index];
                    return ListTile(
                      key: ValueKey('apply-template-${template.id}'),
                      title: Text(template.title),
                      subtitle: Text(
                        template.markdownContent.split('\\n').first,
                      ),
                      onTap: () => Navigator.pop(dialogContext, (
                        template: template,
                        replace: false,
                      )),
                      trailing: IconButton(
                        tooltip: 'Replace note with ${template.title}',
                        icon: const Icon(Icons.drive_file_rename_outline),
                        onPressed: () => Navigator.pop(dialogContext, (
                          template: template,
                          replace: true,
                        )),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
      if (choice == null || !mounted) return;
      if (choice.replace) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace this Note?'),
            content: const Text(
              'The current title and Markdown will be replaced by the template.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      if (ref.read(workspaceNotesProvider).accountId != accountId ||
          _note?.id != noteId ||
          _note?.projectId != note.projectId ||
          !_noteIsCurrent) {
        return;
      }
      final expanded = expandWorkspaceNoteTemplate(
        template: choice.template.markdownContent,
        localDate: DateTime.now(),
        title: _titleController.text,
        aliases: workspaceNoteTemplateAliases(_markdownController.text),
      );
      final text = _markdownController.text;
      if (choice.replace) {
        _markdownController.value = TextEditingValue(
          text: expanded,
          selection: TextSelection.collapsed(offset: expanded.length),
        );
      } else {
        final start = selection.isValid
            ? selection.start.clamp(0, text.length)
            : text.length;
        final end = selection.isValid
            ? selection.end.clamp(start, text.length)
            : text.length;
        final updated = text.replaceRange(start, end, expanded);
        _markdownController.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: start + expanded.length),
        );
      }
      _markdownFocusNode.requestFocus();
    } catch (_) {
      if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Template could not be applied. Check access and retry.',
          ),
        ),
      );
    }
  }

  Future<void> _openProperties() async {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null || accountId == null || !_noteIsCurrent) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 560,
          height: 560,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: NotesPropertiesPanel(
              markdown: _markdownController.text,
              onMarkdownChanged: (markdown) {
                if (!mounted ||
                    ref.read(workspaceNotesProvider).accountId != accountId ||
                    _loadingAccountId != accountId ||
                    _note?.id != note.id ||
                    !_noteIsCurrent) {
                  return;
                }
                _applyPropertiesMarkdown(markdown);
              },
            ),
          ),
        ),
      ),
    );
    _propertiesDialogRoute = route;
    try {
      await navigator.push(route);
    } finally {
      if (identical(_propertiesDialogRoute, route)) {
        _propertiesDialogRoute = null;
      }
    }
    if (mounted &&
        ref.read(workspaceNotesProvider).accountId == accountId &&
        _note?.id == note.id) {
      _markdownFocusNode.requestFocus();
    }
  }

  void _applyPropertiesMarkdown(String markdown) {
    final previous = _markdownController.value;
    final previousBodyOffset =
        previous.text.length -
        parseNoteMarkdownMetadata(previous.text).body.length;
    final updatedBodyOffset =
        markdown.length - parseNoteMarkdownMetadata(markdown).body.length;
    int mapOffset(int offset) {
      if (offset >= previousBodyOffset) {
        return (updatedBodyOffset + offset - previousBodyOffset)
            .clamp(0, markdown.length)
            .toInt();
      }
      return offset.clamp(0, updatedBodyOffset).toInt();
    }

    final selection = previous.selection.isValid
        ? TextSelection(
            baseOffset: mapOffset(previous.selection.baseOffset),
            extentOffset: mapOffset(previous.selection.extentOffset),
          )
        : TextSelection.collapsed(offset: markdown.length);
    _markdownController.value = TextEditingValue(
      text: markdown,
      selection: selection,
    );
  }

  void _navigateToAnchor(String fragment) {
    final markdown = _markdownController.text;
    final anchor = resolveWorkspaceNoteAnchor(markdown, fragment);
    if (anchor == null) {
      _anchorNavigationMessage =
          'Anchor "$fragment" is missing or ambiguous in this Note.';
      if (mounted) setState(() {});
      return;
    }
    final body = parseNoteMarkdownMetadata(markdown).body;
    final lines = body.split('\n');
    if (anchor.line >= lines.length) return;
    var offset = markdown.length - body.length;
    for (var line = 0; line < anchor.line; line++) {
      offset += lines[line].length + 1;
    }
    _sourceMode = true;
    _anchorNavigationMessage = null;
    _settingControllers = true;
    _markdownController.value = _markdownController.value.copyWith(
      selection: TextSelection.collapsed(offset: offset),
    );
    _settingControllers = false;
    _lastMarkdownValue = _markdownController.value;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.anchorFragment == fragment) {
        _markdownFocusNode.requestFocus();
      }
    });
  }

  void _onEdited() {
    if (_settingControllers || _note == null || !_noteIsCurrent) return;
    if (_titleController.text.trim() != _note!.title) _renameBlocked = false;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), _save);
    if (mounted) setState(() {});
  }

  bool get _noteIsCurrent {
    final note = _note;
    final accountId = _observedAccountId;
    return note != null &&
        accountId != null &&
        accountId == _loadingAccountId &&
        (note.projectId != null || note.ownerUserId == accountId);
  }

  Future<void> _save() async {
    final note = _note;
    final accountId = _loadingAccountId;
    if (note == null ||
        accountId == null ||
        accountId != _observedAccountId ||
        !_dirty ||
        !_noteIsCurrent) {
      return;
    }
    final edited = _editedNote(note);
    _dirty = false;
    _inFlightSnapshot = edited;
    if (_crdtDocument != null &&
        (_crdtMaterializationDirty || _pendingCrdtOperations.isNotEmpty)) {
      await _saveCrdtDraft(note, edited, accountId);
      return;
    }
    if (edited.title != note.title) {
      await _saveAndRename(note, edited, accountId);
      return;
    }
    final outcome = await _queueSave(edited);
    if (!mounted) return;
    if (ref.read(workspaceNotesProvider).accountId != accountId) {
      _handleAccountChange(ref.read(workspaceNotesProvider).accountId);
      return;
    }
    switch (outcome) {
      case WorkspaceNoteSaveSuccess(:final note):
        _note = note;
        _conflictRemote = null;
        _inFlightSnapshot = null;
        break;
      case WorkspaceNoteSaveConflict(:final remoteNote):
        _conflictRemote = remoteNote;
        _inFlightSnapshot = edited;
        break;
      case WorkspaceNoteSaveUnavailable():
      case null:
        _dirty = true;
        break;
    }
    setState(() {});
  }

  Future<void> _saveCrdtDraft(
    WorkspaceNote note,
    WorkspaceNote edited,
    String accountId,
  ) async {
    final document = _crdtDocument;
    if (document == null) return;
    final operations = List<NoteCrdtOperation>.of(_pendingCrdtOperations);
    final latest = ref
        .read(workspaceNotesProvider)
        .notes
        .where((item) => item.id == note.id)
        .firstOrNull;
    final baseNote = latest != null && latest.revision > note.revision
        ? latest
        : note;
    try {
      final updated = await _notesNotifier.syncCrdtEdit(
        note: baseNote,
        document: NoteCrdtDocument.fromSnapshot(document.snapshotState()),
        operations: operations,
      );
      if (!mounted) return;
      if (ref.read(workspaceNotesProvider).accountId != accountId) {
        _handleAccountChange(ref.read(workspaceNotesProvider).accountId);
        return;
      }
      if (updated == null) {
        _dirty = true;
        return;
      }
      _pendingCrdtOperations.removeWhere(operations.contains);
      _note = updated;
      _inFlightSnapshot = null;
      _conflictRemote = null;
      _crdtMaterializationDirty =
          _pendingCrdtOperations.isNotEmpty ||
          document.visibleMarkdown != updated.markdownContent;
      if (edited.title != updated.title) {
        await _saveAndRename(updated, _editedNote(updated), accountId);
      } else if (_crdtMaterializationDirty) {
        _dirty = true;
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 650), _save);
      }
    } catch (_) {
      _dirty = true;
      _inFlightSnapshot = edited;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveAndRename(
    WorkspaceNote original,
    WorkspaceNote edited,
    String accountId,
  ) async {
    var base = original;
    if (edited.markdownContent != original.markdownContent) {
      final bodyOnly = edited.copyWith(title: original.title);
      final saveOutcome = await _queueSave(bodyOnly);
      if (!mounted) return;
      if (ref.read(workspaceNotesProvider).accountId != accountId) {
        _handleAccountChange(ref.read(workspaceNotesProvider).accountId);
        return;
      }
      switch (saveOutcome) {
        case WorkspaceNoteSaveSuccess(:final note):
          base = note;
          _note = note;
          _inFlightSnapshot = edited.copyWith(revision: note.revision);
        case WorkspaceNoteSaveConflict(:final remoteNote):
          _conflictRemote = remoteNote;
          _dirty = true;
          setState(() {});
          return;
        case WorkspaceNoteSaveUnavailable():
        case null:
          _renameFailureMessage =
              'Could not save this Note before renaming. Your draft is preserved.';
          _dirty = true;
          setState(() {});
          return;
      }
    }

    final outcome = await _notesNotifier.renameNoteWithLinks(
      noteId: base.id,
      title: edited.title,
    );
    if (!mounted) return;
    if (ref.read(workspaceNotesProvider).accountId != accountId) {
      _handleAccountChange(ref.read(workspaceNotesProvider).accountId);
      return;
    }
    switch (outcome) {
      case WorkspaceNoteRenameSuccess(:final notes):
        final renamed = notes.where((item) => item.id == base.id).firstOrNull;
        if (renamed == null ||
            renamed.ownerUserId != base.ownerUserId ||
            renamed.projectId != base.projectId) {
          _renameFailureMessage =
              'Could not confirm the Note rename. Your draft is preserved.';
          _dirty = true;
          break;
        }
        _note = renamed;
        _renameBlocked = false;
        _conflictRemote = null;
        _inFlightSnapshot = null;
        _renameFailureMessage = null;
        if (_markdownController.text == edited.markdownContent &&
            renamed.markdownContent != edited.markdownContent) {
          _setMarkdownText(renamed.markdownContent);
        }
        _dirty =
            _titleController.text.trim() != renamed.title ||
            _markdownController.text != renamed.markdownContent;
      case WorkspaceNoteRenameBlocked(:final ambiguousSourceIds):
        _renameBlocked = true;
        _dirty = true;
        _inFlightSnapshot = edited;
        await _showBlockedRenameDialog(ambiguousSourceIds);
      case WorkspaceNoteRenameConflict():
        _renameFailureMessage =
            'This Note changed elsewhere. Your draft is preserved.';
        _dirty = true;
      case WorkspaceNoteRenameUnavailable():
        _renameFailureMessage =
            'This Note is unavailable for this account. Your draft is preserved.';
        _dirty = true;
      case WorkspaceNoteRenameFailure():
        _renameFailureMessage =
            'Could not rename this Note and update its links. Your draft is preserved.';
        _dirty = true;
      case null:
        _renameFailureMessage =
            'Could not rename this Note and update its links. Your draft is preserved.';
        _dirty = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _showBlockedRenameDialog(Set<String> sourceIds) async {
    final state = ref.read(workspaceNotesProvider);
    final sources = state.notes
        .where((item) => sourceIds.contains(item.id) && item.deletedAt == null)
        .toList(growable: false);
    final resolved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve ambiguous links first'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This title appears in notes where the target is ambiguous.',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final source in sources)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(source.title),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Resolve links'),
          ),
        ],
      ),
    );
    if (resolved == true && mounted) {
      final query = sourceIds.map(Uri.encodeComponent).join(',');
      context.go('/notes?resolveLinks=$query');
    }
  }

  Future<void> _retryRename() async {
    final accountId = _loadingAccountId;
    final note = _note;
    if (accountId == null || note == null) return;
    await _notesNotifier.load();
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return;
    }
    final latest = ref
        .read(workspaceNotesProvider)
        .notes
        .where((item) => item.id == note.id && notesShareLinkScope(note, item))
        .firstOrNull;
    if (latest == null) {
      _renameFailureMessage =
          'This Note is unavailable for this account. Your draft is preserved.';
      setState(() {});
      return;
    }
    _note = latest;
    _renameFailureMessage = null;
    _dirty = true;
    setState(() {});
    await _save();
  }

  Future<void> _reloadRename() async {
    final accountId = _loadingAccountId;
    final note = _note;
    if (accountId == null || note == null) return;
    await _notesNotifier.load();
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return;
    }
    final remote = ref
        .read(workspaceNotesProvider)
        .notes
        .where((item) => item.id == note.id && notesShareLinkScope(note, item))
        .firstOrNull;
    if (remote == null) return;
    setState(() {
      _note = remote;
      _titleController.text = remote.title;
      _setMarkdownText(remote.markdownContent);
      _dirty = false;
      _conflictRemote = null;
      _inFlightSnapshot = null;
      _renameFailureMessage = null;
      _renameBlocked = false;
    });
  }

  void _reloadRemote() {
    final remote = _conflictRemote;
    if (remote == null) return;
    setState(() {
      _note = remote;
      _conflictRemote = null;
      _inFlightSnapshot = null;
      _dirty = false;
      _settingControllers = true;
      _titleController.text = remote.title;
      _setMarkdownText(remote.markdownContent);
      _settingControllers = false;
    });
  }

  Future<void> _recoverLocalDraft() async {
    final remote = _conflictRemote;
    if (remote == null) return;
    setState(() {
      _note = remote;
      _conflictRemote = null;
      _dirty = true;
    });
    await _save();
  }

  Future<void> _exportNote() async {
    final note = _note;
    if (note == null || !_noteIsCurrent) return;
    final title = _titleController.text.trim().isEmpty
        ? 'Untitled Note'
        : _titleController.text.trim();
    final markdown = _markdownController.text;
    try {
      final outcome = await (widget.exportFileSaver ?? ExportFileSaver()).save(
        fileName: '$title.md',
        bytes: Uint8List.fromList(utf8.encode(markdown)),
        mimeType: 'text/markdown',
      );
      if (!mounted ||
          outcome == ExportSaveOutcome.saved ||
          outcome == ExportSaveOutcome.canceled) {
        return;
      }
    } catch (_) {
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not export this Note. Try again.')),
    );
  }

  Future<void> _confirmDelete() async {
    final note = _note;
    final ownerId = _loadingAccountId;
    if (note == null ||
        ownerId == null ||
        (note.projectId == null && note.ownerUserId != ownerId)) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move Note to Trash?'),
        content: const Text('You can restore this Note from Trash.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (approved != true ||
        !mounted ||
        ref.read(workspaceNotesProvider).accountId != ownerId) {
      return;
    }
    _saveTimer?.cancel();
    _flushPendingSave();
    await _saveQueue;
    if (!mounted || ref.read(workspaceNotesProvider).accountId != ownerId) {
      return;
    }
    final latestNote =
        ref
            .read(workspaceNotesProvider)
            .notes
            .where(
              (item) => item.id == note.id && notesShareLinkScope(note, item),
            )
            .firstOrNull ??
        note;
    final deleted = await _notesNotifier.deleteNote(latestNote);
    if (!deleted ||
        !mounted ||
        ref.read(workspaceNotesProvider).accountId != ownerId) {
      return;
    }
    final tab = OpenDocumentTab(
      documentId: note.id,
      name: note.title,
      type: OpenDocumentTabType.note,
      ownerAccountId: ownerId,
      noteProjectId: note.projectId,
    );
    await ref
        .read(openNoteTabsProvider.notifier)
        .closeDeletedNote(note.id, ownerId);
    ref.read(activeDocumentTabControllerProvider).clearIfActive(tab);
    if (mounted) context.go('/notes');
  }

  Future<void> _toggleHistory() async {
    final open = !_historyOpen;
    setState(() => _historyOpen = open);
    if (!open || _note == null) return;
    setState(() => _historyLoading = true);
    final versions = await _notesNotifier.listNoteVersions(_note!.id);
    if (!mounted) return;
    setState(() {
      _versions = versions;
      _historyLoading = false;
    });
  }

  Future<bool> _restoreHistoryVersion(WorkspaceNoteVersion version) async {
    final note = _note;
    final accountId = ref.read(workspaceNotesProvider).accountId;
    if (note == null || accountId == null) return false;
    _saveTimer?.cancel();
    await _saveQueue;
    if (!mounted || ref.read(workspaceNotesProvider).accountId != accountId) {
      return false;
    }
    final latest = ref
        .read(workspaceNotesProvider)
        .notes
        .where((item) => item.id == note.id)
        .firstOrNull;
    if (latest == null) return false;
    final restored = await _notesNotifier.restoreNoteVersion(
      noteId: note.id,
      versionId: version.id,
      expectedRevision: latest.revision,
    );
    if (!restored || !mounted) return false;
    final updated = ref
        .read(workspaceNotesProvider)
        .notes
        .where((item) => item.id == note.id)
        .firstOrNull;
    if (updated == null) return false;
    setState(() {
      _note = updated;
      _titleController.text = updated.title;
      _setMarkdownText(updated.markdownContent);
      _dirty = false;
    });
    final versions = await _notesNotifier.listNoteVersions(note.id);
    if (mounted) setState(() => _versions = versions);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(workspaceNotesProvider);
    final accountId = notesState.accountId;
    if (accountId != _observedAccountId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleAccountChange(accountId);
      });
    }
    final targetChanged =
        accountId != null &&
        (accountId != _attemptedAccountId || widget.noteId != _attemptedNoteId);
    if (accountId != null && targetChanged && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentAccountId = ref.read(workspaceNotesProvider).accountId;
        if (currentAccountId != null &&
            (currentAccountId != _attemptedAccountId ||
                widget.noteId != _attemptedNoteId)) {
          unawaited(_load());
        }
      });
    }
    if (accountId == null) {
      return const Center(child: Text('Sign in to access private Notes.'));
    }
    if (_accountChangedDuringLoad && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The signed-in account changed. Reopen this Note.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            UiButton(
              onPressed: () {
                _accountChangedDuringLoad = false;
                _attemptedAccountId = null;
                _attemptedNoteId = null;
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_loading || targetChanged) {
      return const Center(child: UiLoadingState());
    }
    if (_note == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _accountChangedDuringLoad
                  ? 'The signed-in account changed. Reopen this Note.'
                  : _loadFailed
                  ? 'This Note is unavailable for this account.'
                  : 'This Note could not be opened.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            UiButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final tokens = context.appTokens;
    final narrow = AppResponsive.isNarrow(context);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _BoldMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _BoldMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, control: true):
            _ItalicMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            _ItalicMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _UndoMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            _UndoMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
            _RedoMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _RedoMarkdownIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _RedoMarkdownIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _BoldMarkdownIntent: CallbackAction<_BoldMarkdownIntent>(
            onInvoke: (_) {
              if (_markdownFocusNode.hasFocus) _applyMarkdown('**', '**');
              return null;
            },
          ),
          _ItalicMarkdownIntent: CallbackAction<_ItalicMarkdownIntent>(
            onInvoke: (_) {
              if (_markdownFocusNode.hasFocus) _applyMarkdown('*', '*');
              return null;
            },
          ),
          _UndoMarkdownIntent: CallbackAction<_UndoMarkdownIntent>(
            onInvoke: (_) {
              if (_markdownFocusNode.hasFocus) _undoMarkdown();
              return null;
            },
          ),
          _RedoMarkdownIntent: CallbackAction<_RedoMarkdownIntent>(
            onInvoke: (_) {
              if (_markdownFocusNode.hasFocus) _redoMarkdown();
              return null;
            },
          ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: tokens.panel,
                border: Border(bottom: BorderSide(color: tokens.panelBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('note-title-field'),
                      controller: _titleController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Untitled Note',
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('note-template-insert-action'),
                    tooltip: 'Insert template',
                    onPressed: _insertTemplate,
                    icon: const Icon(Icons.post_add_outlined),
                  ),
                  IconButton(
                    key: const ValueKey('note-properties-action'),
                    tooltip: 'Edit Properties',
                    onPressed: _openProperties,
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  if (narrow)
                    IconButton(
                      key: const ValueKey('note-source-preview-toggle'),
                      tooltip: _sourceMode
                          ? 'Show Markdown preview'
                          : 'Edit Markdown source',
                      onPressed: () =>
                          setState(() => _sourceMode = !_sourceMode),
                      icon: Icon(
                        _sourceMode ? Icons.visibility_outlined : Icons.code,
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('note-history-action'),
                    tooltip: _historyOpen ? 'Hide history' : 'Show history',
                    onPressed: _toggleHistory,
                    icon: const Icon(Icons.history),
                  ),
                  IconButton(
                    key: const ValueKey('note-export-action'),
                    tooltip: 'Export Markdown',
                    onPressed: _exportNote,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    key: const ValueKey('note-delete-action'),
                    tooltip: 'Move to Trash',
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  if (notesState.savingNoteIds.contains(_note!.id))
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: UiProgressIndicator(
                        semanticsLabel: 'Saving note',
                        size: 16,
                      ),
                    )
                  else if (_dirty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: Text(
                        'Unsaved',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
            if (_historyOpen)
              NotesHistoryPanel(
                versions: _versions,
                loading: _historyLoading,
                onRestore: _restoreHistoryVersion,
              ),
            if (notesState.queuedNoteIds.contains(_note!.id))
              MaterialBanner(
                content: Text(
                  notesState.accessPausedNoteIds.contains(_note!.id)
                      ? 'Project access could not be verified. Your encrypted draft stays on this device and will not sync until access is restored.'
                      : 'Encrypted changes are queued on this device and will retry when access is available.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => unawaited(
                      ref
                          .read(workspaceNotesProvider.notifier)
                          .retryOfflineSync(),
                    ),
                    child: Text(
                      notesState.accessPausedNoteIds.contains(_note!.id)
                          ? 'Check access'
                          : 'Retry sync',
                    ),
                  ),
                ],
              ),
            if (_conflictRemote case final remote?)
              MaterialBanner(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This Note changed elsewhere. Your draft is preserved.',
                    ),
                    Text('Original base title: ${_note!.title}'),
                    Text('Original base Markdown: ${_note!.markdownContent}'),
                    Text('Latest remote revision: ${remote.revision}'),
                    Text('Remote title: ${remote.title}'),
                    Text('Remote Markdown: ${remote.markdownContent}'),
                    Text('Your draft title: ${_titleController.text}'),
                    Text('Your draft Markdown: ${_markdownController.text}'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: _reloadRemote,
                    child: const Text('Reload remote'),
                  ),
                  TextButton(
                    onPressed: _recoverLocalDraft,
                    child: const Text('Keep my draft'),
                  ),
                ],
              ),
            if (_renameFailureMessage != null)
              MaterialBanner(
                content: Text(_renameFailureMessage!),
                actions: [
                  TextButton(
                    onPressed: _retryRename,
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: _reloadRename,
                    child: const Text('Reload'),
                  ),
                ],
              ),
            if (_anchorNavigationMessage case final message?)
              MaterialBanner(
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () =>
                        setState(() => _anchorNavigationMessage = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            if (notesState.error != null &&
                _conflictRemote == null &&
                _renameFailureMessage == null)
              MaterialBanner(
                content: Text(
                  'Note save failed: ${workspaceNotesFailureMessage(notesState.error, accountId: notesState.accountId)}',
                ),
                actions: [
                  TextButton(onPressed: _save, child: const Text('Retry')),
                ],
              ),
            if (!narrow || _sourceMode)
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('markdown-bold-action'),
                      tooltip: 'Bold',
                      onPressed: () => _applyMarkdown('**', '**'),
                      icon: const Icon(Icons.format_bold),
                    ),
                    IconButton(
                      key: const ValueKey('markdown-italic-action'),
                      tooltip: 'Italic',
                      onPressed: () => _applyMarkdown('*', '*'),
                      icon: const Icon(Icons.format_italic),
                    ),
                    IconButton(
                      key: const ValueKey('markdown-undo-action'),
                      tooltip: 'Undo',
                      onPressed: _markdownUndoStack.isEmpty
                          ? null
                          : _undoMarkdown,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      key: const ValueKey('markdown-redo-action'),
                      tooltip: 'Redo',
                      onPressed: _markdownRedoStack.isEmpty
                          ? null
                          : _redoMarkdown,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      key: const ValueKey('markdown-heading-action'),
                      tooltip: 'Heading',
                      onPressed: () => _applyMarkdown('## ', ''),
                      icon: const Icon(Icons.title),
                    ),
                    IconButton(
                      key: const ValueKey('note-attachment-insert-action'),
                      tooltip: 'Attach image or PDF',
                      onPressed: _uploadingAttachment
                          ? null
                          : _insertNoteAttachment,
                      icon: _uploadingAttachment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file),
                    ),
                  ],
                ),
              ),
            if (_wikiQuery != null && (!narrow || _sourceMode))
              SizedBox(
                height:
                    (_wikiSuggestions(notesState.notes).length.clamp(1, 4) * 48)
                        .toDouble(),
                child: Material(
                  color: tokens.panel,
                  child: _wikiSuggestions(notesState.notes).isEmpty
                      ? _wikiQuery!.trim().isEmpty
                            ? const Center(child: Text('No matching notes'))
                            : ListTile(
                                dense: true,
                                key: const ValueKey(
                                  'wiki-create-target-action',
                                ),
                                leading: const Icon(Icons.note_add_outlined),
                                title: Text('Create "${_wikiQuery!.trim()}"'),
                                trailing: _wikiCreateInFlight
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                                onTap: _wikiCreateInFlight
                                    ? null
                                    : _createWikiTarget,
                              )
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final suggestion in _wikiSuggestions(
                              notesState.notes,
                            ))
                              ListTile(
                                dense: true,
                                key: ValueKey(
                                  'wiki-suggestion-${suggestion.id}',
                                ),
                                leading: const Icon(Icons.note_outlined),
                                title: Text(suggestion.title),
                                onTap: () => _insertWikiLink(suggestion),
                              ),
                          ],
                        ),
                ),
              ),
            Expanded(
              child: _sourceMode
                  ? TextField(
                      key: const ValueKey('note-markdown-source'),
                      controller: _markdownController,
                      focusNode: _markdownFocusNode,
                      undoController: _markdownUndoController,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        height: 1.55,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(AppSpacing.lg),
                        hintText: '# Start writing in Markdown…',
                      ),
                    )
                  : narrow
                  ? Markdown(
                      key: const ValueKey('note-markdown-preview'),
                      data: _renderNotePreviewMarkdown(notesState.notes),
                      selectable: true,
                      imageBuilder: _notePreviewImage,
                      blockSyntaxes: const [NotesBlockMathSyntax()],
                      inlineSyntaxes: [NotesInlineMathSyntax()],
                      builders: notesMarkdownElementBuilders,
                      onTapLink: (text, href, title) => _openPreviewLink(href),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('note-markdown-editor'),
                            controller: _markdownController,
                            focusNode: _markdownFocusNode,
                            undoController: _markdownUndoController,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(height: 1.55),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(AppSpacing.lg),
                              hintText: 'Write your note…',
                            ),
                          ),
                        ),
                        VerticalDivider(width: 1, color: tokens.panelBorder),
                        Expanded(
                          child: Markdown(
                            key: const ValueKey('note-markdown-preview'),
                            data: _renderNotePreviewMarkdown(notesState.notes),
                            selectable: true,
                            imageBuilder: _notePreviewImage,
                            blockSyntaxes: const [NotesBlockMathSyntax()],
                            inlineSyntaxes: [NotesInlineMathSyntax()],
                            builders: notesMarkdownElementBuilders,
                            onTapLink: (text, href, title) =>
                                _openPreviewLink(href),
                            padding: const EdgeInsets.all(AppSpacing.lg),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
