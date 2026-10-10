import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/runtime_environment.dart';
import 'package:varian/app/localization/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/widgets/varian_logo.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/home/presentation/widgets/backend_settings_dialog.dart';
import 'package:varian/features/home/presentation/widgets/collaboration_profile_dialog.dart';
import 'package:varian/features/templates/data/diagram_templates.dart';
import 'package:varian/features/templates/domain/project_template.dart';
import 'package:varian/features/templates/presentation/template_picker_dialog.dart';
import 'package:varian/features/templates/presentation/project_template_wizard_dialog.dart';
import 'package:varian/features/onboarding/presentation/onboarding_dialog.dart';
import 'package:varian/features/onboarding/state/onboarding_provider.dart';
import '../../auth/state/auth_provider.dart';
import '../../auth/state/auth_recovery.dart';
import '../../canvas/state/autosave_controller.dart';
import '../../capture/presentation/capture_inbox_panel.dart';
import '../state/home_provider.dart';
import 'widgets/home_library_widgets.dart';
import 'widgets/project_card.dart';
import 'widgets/project_grid_layout.dart';

enum ProjectSort { lastModified, name, created }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _searchController;
  String _query = '';
  ProjectSort _sort = ProjectSort.lastModified;
  bool _firstFrameReady = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(homeProjectsProvider.notifier).loadProjects());
      unawaited(_maybeShowOnboarding());
      setState(() => _firstFrameReady = true);
    });
  }

  Future<void> _maybeShowOnboarding() async {
    if (isFlutterTestEnvironmentRuntime) return;
    final onboarding = ref.read(onboardingProvider.notifier);
    await onboarding.load();
    if (!mounted ||
        !ref.read(onboardingProvider).shouldShow ||
        ref.read(authCallbackCoordinatorProvider).status !=
            AuthCallbackStatus.idle) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted ||
        !ref.read(onboardingProvider).shouldShow ||
        ref.read(authCallbackCoordinatorProvider).status !=
            AuthCallbackStatus.idle) {
      return;
    }
    await showOnboardingDialog(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loadedProjects = ref.watch(homeProjectsProvider);
    final projectsAsync = _firstFrameReady
        ? loadedProjects
        : const AsyncValue<List<LocalProjectMetadata>>.loading();
    final selectedStatus = ref.watch(homeProjectStatusProvider);
    final user = ref.watch(authUserProvider).asData?.value;
    final localizations = CreativeStudioLocalizations.of(context);
    final tokens = context.appTokens;
    final compactHeader = AppResponsive.isNarrow(context);

    return UiPageScaffold(
      title: Semantics(
        label: 'Creative Workstation',
        child: compactHeader
            ? const VarianBrandMark(size: 24)
            : Row(
                children: [
                  const VarianBrandMark(size: 26),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'CREATIVE WORKSTATION',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        UiIconButton(
          icon: Icons.refresh,
          tooltip: localizations.homeRefreshProjects,
          onPressed: () =>
              ref.read(homeProjectsProvider.notifier).loadProjects(),
        ),
        const WorkspaceHelpButton(),
        const UiThemeModeButton(),
        if (compactHeader)
          UiMenuButton<String>(
            buttonKey: const ValueKey('home-more-actions'),
            tooltip: localizations.homeMoreActions,
            icon: Icons.more_horiz,
            items: [
              UiMenuAction<String>(
                value: 'join',
                label: localizations.homeJoinCollaborationRoom,
                icon: Icons.meeting_room_outlined,
              ),
              UiMenuAction<String>(
                value: 'backend',
                label: localizations.homeBackendIntegrations,
                icon: Icons.settings_ethernet,
              ),
              if (user != null)
                UiMenuAction<String>(
                  value: 'profile',
                  label: localizations.homeEditCollaborationProfile,
                  icon: Icons.account_circle_outlined,
                ),
              UiMenuAction<String>(
                value: 'auth',
                label: user == null
                    ? localizations.homeSignInToCollaborate
                    : localizations.homeSignOut,
                icon: user == null ? Icons.login : Icons.logout,
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case 'join':
                  _joinRoom(context);
                case 'backend':
                  showUiDialog(
                    context: context,
                    builder: (_) => const BackendSettingsDialog(),
                  );
                case 'profile':
                  showCollaborationProfileDialog(context);
                case 'auth':
                  if (user == null) {
                    context.push('/auth');
                  } else {
                    unawaited(_signOut(context));
                  }
              }
            },
          )
        else ...[
          UiIconButton(
            icon: Icons.meeting_room_outlined,
            tooltip: localizations.homeJoinCollaborationRoom,
            onPressed: () => _joinRoom(context),
          ),
          UiIconButton(
            icon: Icons.settings_ethernet,
            tooltip: localizations.homeBackendIntegrations,
            onPressed: () => showUiDialog(
              context: context,
              builder: (_) => const BackendSettingsDialog(),
            ),
          ),
          if (user != null)
            UiIconButton(
              icon: Icons.account_circle_outlined,
              tooltip: localizations.homeEditCollaborationProfile,
              onPressed: () => showCollaborationProfileDialog(context),
            ),
          UiIconButton(
            icon: user == null ? Icons.login : Icons.logout,
            tooltip: user == null
                ? localizations.homeSignInToCollaborate
                : localizations.homeSignOut,
            onPressed: user == null
                ? () => context.push('/auth')
                : () => unawaited(_signOut(context)),
          ),
        ],
      ],
      child: projectsAsync.when(
        loading: () => const UiLoadingState(),
        error: (err, _) => _buildLoadError(context, err),
        data: (projects) => _buildLibrary(context, projects, selectedStatus),
      ),
    );
  }

  Widget _buildLoadError(BuildContext context, Object _) {
    final tokens = context.appTokens;
    final copy = CreativeStudioLocalizations.of(context);
    return Center(
      child: UiSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: tokens.danger,
              size: AppControlSize.compact,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              copy.projectLibraryUnavailable,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              copy.projectLibraryUnavailableDescription,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            UiButton(
              onPressed: () =>
                  ref.read(homeProjectsProvider.notifier).loadProjects(),
              prefix: const Icon(Icons.refresh_outlined),
              child: Text(copy.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibrary(
    BuildContext context,
    List<LocalProjectMetadata> projects,
    ProjectStatus selectedStatus,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.medium;
        final pagePadding = AppResponsive.pagePadding(context);
        return SingleChildScrollView(
          padding: pagePadding.copyWith(bottom: AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.wide),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CaptureInboxPanel(initiallyExpanded: false),
                  const SizedBox(height: AppSpacing.md),
                  _buildIntro(context, compact),
                  const SizedBox(height: AppSpacing.md),
                  _buildToolbar(context, compact),
                  const SizedBox(height: AppSpacing.sm),
                  _buildStatusTabs(context, projects, selectedStatus),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntro(BuildContext context, bool compact) {
    final tokens = context.appTokens;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CreativeStudioLocalizations.of(context).homeProjectLibraryTitle,
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            color: tokens.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          CreativeStudioLocalizations.of(context).homeProjectLibraryDescription,
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
      ],
    );

    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: [
        UiButton(
          onPressed: () => _showTemplatePicker(context),
          variant: UiButtonVariant.outline,
          size: UiButtonSize.sm,
          prefix: const Icon(Icons.account_tree_outlined),
          child: Text(
            CreativeStudioLocalizations.of(context).homeTemplateAction,
          ),
        ),
        UiButton(
          onPressed: () => _createNewProject(context),
          size: UiButtonSize.sm,
          prefix: const Icon(Icons.add),
          child: Text(
            CreativeStudioLocalizations.of(context).homeNewDocumentAction,
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.md),
          actions,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        const SizedBox(width: AppSpacing.md),
        actions,
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, bool compact) {
    final search = UiTextField(
      key: const ValueKey('project-search-field'),
      controller: _searchController,
      label: CreativeStudioLocalizations.of(context).homeSearchLabel,
      hint: CreativeStudioLocalizations.of(context).homeSearchHint,
      prefix: const Icon(Icons.search_outlined),
      clearable: true,
      onChanged: (value) => setState(() => _query = value),
    );
    final sort = UiSelect<ProjectSort>(
      key: const ValueKey('project-sort-select'),
      items: {
        CreativeStudioLocalizations.of(context).homeSortLastModified:
            ProjectSort.lastModified,
        CreativeStudioLocalizations.of(context).homeSortName: ProjectSort.name,
        CreativeStudioLocalizations.of(context).homeSortCreated:
            ProjectSort.created,
      },
      value: _sort,
      label: CreativeStudioLocalizations.of(context).homeSortLabel,
      onChanged: (value) {
        if (value != null) setState(() => _sort = value);
      },
    );
    final clear = UiButton(
      key: const ValueKey('clear-project-filters'),
      onPressed: _clearFilters,
      variant: UiButtonVariant.ghost,
      size: UiButtonSize.sm,
      prefix: const Icon(Icons.filter_alt_off_outlined),
      child: Text(CreativeStudioLocalizations.of(context).homeClearFilters),
    );

    final content = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.sm),
              sort,
              if (_hasFilters) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(alignment: Alignment.centerLeft, child: clear),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: search),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(width: 168, child: sort),
              if (_hasFilters) ...[const SizedBox(width: AppSpacing.xs), clear],
            ],
          );

    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: content,
    );
  }

  Widget _buildStatusTabs(
    BuildContext context,
    List<LocalProjectMetadata> projects,
    ProjectStatus selectedStatus,
  ) {
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.compactStatusTabs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBulkActionBar(context, projects, selectedStatus),
        const SizedBox(height: AppSpacing.md),
        UiTabs(
          key: const ValueKey('project-status-tabs'),
          index: ProjectStatus.values.indexOf(selectedStatus),
          onChanged: (index) =>
              ref.read(homeProjectStatusProvider.notifier).state =
                  ProjectStatus.values[index],
          scrollable: true,
          tabs: [
            for (final status in ProjectStatus.values)
              UiTabEntry(
                label: ProjectStatusTabLabel(
                  label: _statusLabel(status),
                  count: _countFor(projects, status),
                  compact: compact,
                ),
                child: _buildProjectCollection(context, projects, status),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBulkActionBar(
    BuildContext context,
    List<LocalProjectMetadata> projects,
    ProjectStatus status,
  ) {
    final statusProjects = projects
        .where((project) => project.status == status)
        .toList(growable: false);
    if (statusProjects.isEmpty) return const SizedBox.shrink();

    final permanent = status == ProjectStatus.trashed;
    return Align(
      alignment: Alignment.centerRight,
      child: UiButton(
        key: ValueKey(
          permanent
              ? 'empty-trash-button'
              : 'move-all-${status.name}-to-trash-button',
        ),
        onPressed: () =>
            _confirmBulkAction(context, statusProjects, permanent: permanent),
        variant: UiButtonVariant.destructive,
        size: UiButtonSize.sm,
        prefix: Icon(
          permanent ? Icons.delete_forever_outlined : Icons.delete_outline,
        ),
        child: Text(
          permanent
              ? CreativeStudioLocalizations.of(context).homeEmptyTrashAction
              : CreativeStudioLocalizations.of(
                  context,
                ).homeMoveAllToTrashAction,
        ),
      ),
    );
  }

  Future<void> _confirmBulkAction(
    BuildContext context,
    List<LocalProjectMetadata> projects, {
    required bool permanent,
  }) async {
    if (projects.isEmpty) return;
    final status = projects.first.status;
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => BulkProjectActionDialog(
        status: status,
        count: projects.length,
        permanent: permanent,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final ids = projects.map((project) => project.id).toSet();
    final notifier = ref.read(homeProjectsProvider.notifier);
    await _runProjectAction(
      context,
      () async {
        if (permanent) {
          await notifier.purgeProjects(ids);
        } else {
          await notifier.moveProjectsToTrash(ids);
        }
      },
      successMessage: permanent
          ? CreativeStudioLocalizations.of(
              context,
            ).homeEmptyTrashSuccess(projects.length)
          : CreativeStudioLocalizations.of(
              context,
            ).homeMoveDocumentsToTrashSuccess(projects.length),
    );
  }

  bool _canAdoptProject(LocalProjectMetadata project, User? user) =>
      user != null &&
      !user.isAnonymous &&
      project.cloudOwnerId == null &&
      !project.isCollaborationRoom &&
      project.status != ProjectStatus.trashed;

  Future<void> _confirmAdoptProject(
    BuildContext context,
    LocalProjectMetadata project,
  ) async {
    final copy = CreativeStudioLocalizations.of(context);
    String? confirmedAccountId;
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: copy.homeProjectAdoptTitle,
        builder: (context, style) => Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(copy.homeProjectAdoptTitle, style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text(copy.homeProjectAdoptDescription(project.name)),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    variant: UiButtonVariant.ghost,
                    child: Text(copy.cancel.toUpperCase()),
                  ),
                  UiButton(
                    onPressed: () {
                      final client = ref.read(supabaseClientProvider);
                      confirmedAccountId =
                          client?.auth.currentUser?.id ??
                          client?.auth.currentSession?.user.id;
                      Navigator.of(dialogContext).pop(true);
                    },
                    prefix: const Icon(Icons.cloud_upload_outlined),
                    child: Text(copy.homeProjectAdoptConfirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final accountId = confirmedAccountId;
    final confirmedUser = ref.read(authUserProvider).asData?.value;
    if (accountId == null ||
        confirmedUser?.id != accountId ||
        confirmedUser?.isAnonymous != false) {
      showUiToast(
        context,
        copy.homeProjectAdoptRequiresSignIn,
        variant: UiToastVariant.error,
      );
      return;
    }

    await _runProjectAction(
      context,
      () => ref
          .read(homeProjectsProvider.notifier)
          .adoptProjectToCloud(project.id, expectedAccountId: accountId),
      successMessage: copy.homeProjectAdoptSuccess,
      failureMessage: copy.homeProjectAdoptFailure,
    );
  }

  Widget _buildProjectCollection(
    BuildContext context,
    List<LocalProjectMetadata> projects,
    ProjectStatus status,
  ) {
    final durableStore = ref.watch(durableProjectStoreProvider);
    final statusProjects = projects
        .where((project) => project.status == status)
        .toList(growable: false);
    final visibleProjects = _filterAndSort(statusProjects);

    if (visibleProjects.isEmpty) {
      if (statusProjects.isNotEmpty && _query.trim().isNotEmpty) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 260),
          child: UiEmptyState(
            icon: Icons.search_off_outlined,
            title: CreativeStudioLocalizations.of(context).homeNoMatchesTitle,
            message: CreativeStudioLocalizations.of(
              context,
            ).homeNoMatchesMessage(_query.trim()),
            action: UiButton(
              onPressed: _clearSearch,
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.close),
              child: Text(
                CreativeStudioLocalizations.of(context).homeClearSearch,
              ),
            ),
          ),
        );
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 260),
        child: _buildStatusEmptyState(context, status),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        if (!hasUsableProjectGridWidth(availableWidth)) {
          return const SizedBox.shrink();
        }
        final cardHeight = availableWidth < AppBreakpoints.compact
            ? 196.0
            : 214.0;
        return GridView.builder(
          key: ValueKey('project-grid-${status.name}'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.pageWide,
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: cardHeight,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
          ),
          itemCount: visibleProjects.length,
          itemBuilder: (context, index) {
            final project = visibleProjects[index];
            final notifier = ref.read(homeProjectsProvider.notifier);
            return ProjectCard(
              key: ValueKey(project.id),
              project: project,
              durableStore: durableStore,
              onTap: () => _openProject(context, project.id, project.name),
              onDelete: () => _confirmDelete(context, project),
              onAdopt:
                  _canAdoptProject(
                        project,
                        ref.watch(authUserProvider).asData?.value,
                      ) &&
                      ref
                              .watch(
                                homeProjectAdoptionEligibilityProvider(
                                  project.id,
                                ),
                              )
                              .asData
                              ?.value ==
                          true
                  ? () => _confirmAdoptProject(context, project)
                  : null,
              onRename: (newName) => _runProjectAction(
                context,
                () => notifier.renameProject(project.id, newName),
                successMessage: CreativeStudioLocalizations.of(
                  context,
                ).homeDocumentRenamedSuccess,
              ),
              onTogglePinned: () => _runProjectAction(
                context,
                () => notifier.togglePinned(project.id),
                successMessage: project.isPinned
                    ? CreativeStudioLocalizations.of(
                        context,
                      ).homeDocumentUnpinnedSuccess
                    : CreativeStudioLocalizations.of(
                        context,
                      ).homeDocumentPinnedSuccess,
              ),
              onArchive: () => _runProjectAction(
                context,
                () => notifier.archiveProject(project.id),
                successMessage: CreativeStudioLocalizations.of(
                  context,
                ).homeDocumentArchivedSuccess,
              ),
              onRestore: () => _runProjectAction(
                context,
                () => notifier.restoreProject(project.id),
                successMessage: CreativeStudioLocalizations.of(
                  context,
                ).homeDocumentRestoredSuccess,
              ),
              onDuplicate: () => _runProjectAction(
                context,
                () => notifier.duplicateProject(project.id),
                successMessage: CreativeStudioLocalizations.of(
                  context,
                ).homeDocumentDuplicatedSuccess,
              ),
              onPurge: () => _confirmDelete(context, project, permanent: true),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusEmptyState(BuildContext context, ProjectStatus status) {
    final Widget action;
    switch (status) {
      case ProjectStatus.active:
        action = Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            UiButton(
              onPressed: () => _createNewProject(context),
              prefix: const Icon(Icons.add),
              child: Text(
                CreativeStudioLocalizations.of(context).homeNewDocumentAction,
              ),
            ),
            UiButton(
              onPressed: () => _createFlowchartProject(context),
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.account_tree_outlined),
              child: Text(
                CreativeStudioLocalizations.of(context).homeUseTemplateAction,
              ),
            ),
          ],
        );
      case ProjectStatus.archived:
        action = UiButton(
          onPressed: () => _setStatus(ProjectStatus.active),
          variant: UiButtonVariant.outline,
          prefix: const Icon(Icons.folder_open_outlined),
          child: Text(
            CreativeStudioLocalizations.of(
              context,
            ).homeViewActiveDocumentsAction,
          ),
        );
      case ProjectStatus.trashed:
        action = UiButton(
          onPressed: () => _setStatus(ProjectStatus.active),
          variant: UiButtonVariant.outline,
          prefix: const Icon(Icons.arrow_back_outlined),
          child: Text(
            CreativeStudioLocalizations.of(context).homeBackToLibraryAction,
          ),
        );
    }

    return UiEmptyState(
      icon: _statusIcon(status),
      title: _emptyTitle(status),
      message: _emptyMessage(status),
      action: action,
    );
  }

  List<LocalProjectMetadata> _filterAndSort(
    List<LocalProjectMetadata> projects,
  ) {
    final query = _query.trim().toLowerCase();
    final visible = projects
        .where(
          (project) =>
              query.isEmpty || project.name.toLowerCase().contains(query),
        )
        .toList();

    visible.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return switch (_sort) {
        ProjectSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        ProjectSort.created => b.createdAt.compareTo(a.createdAt),
        ProjectSort.lastModified => b.updatedAt.compareTo(a.updatedAt),
      };
    });
    return visible;
  }

  bool get _hasFilters =>
      _query.trim().isNotEmpty || _sort != ProjectSort.lastModified;

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _sort = ProjectSort.lastModified;
    });
  }

  void _setStatus(ProjectStatus status) {
    ref.read(homeProjectStatusProvider.notifier).state = status;
  }

  int _countFor(List<LocalProjectMetadata> projects, ProjectStatus status) =>
      projects.where((project) => project.status == status).length;

  String _statusLabel(ProjectStatus status) {
    final copy = CreativeStudioLocalizations.of(context);
    return switch (status) {
      ProjectStatus.active => copy.homeStatusActive,
      ProjectStatus.archived => copy.homeStatusArchived,
      ProjectStatus.trashed => copy.homeStatusTrash,
    };
  }

  IconData _statusIcon(ProjectStatus status) => switch (status) {
    ProjectStatus.active => Icons.dashboard_customize_outlined,
    ProjectStatus.archived => Icons.archive_outlined,
    ProjectStatus.trashed => Icons.delete_outline,
  };

  String _emptyTitle(ProjectStatus status) {
    final copy = CreativeStudioLocalizations.of(context);
    return switch (status) {
      ProjectStatus.active => copy.homeNoActiveDocumentsTitle,
      ProjectStatus.archived => copy.homeArchiveEmptyTitle,
      ProjectStatus.trashed => copy.homeTrashEmptyTitle,
    };
  }

  String _emptyMessage(ProjectStatus status) {
    final copy = CreativeStudioLocalizations.of(context);
    return switch (status) {
      ProjectStatus.active => copy.homeNoActiveDocumentsMessage,
      ProjectStatus.archived => copy.homeArchivedDocumentsMessage,
      ProjectStatus.trashed => copy.homeTrashedDocumentsMessage,
    };
  }

  Future<void> _runProjectAction(
    BuildContext context,
    Future<void> Function() action, {
    String? successMessage,
    String? failureMessage,
  }) async {
    try {
      await action();
      if (context.mounted && successMessage != null) {
        showUiToast(context, successMessage, variant: UiToastVariant.success);
      }
    } catch (_) {
      if (context.mounted) {
        showUiToast(
          context,
          failureMessage ??
              CreativeStudioLocalizations.of(context).projectActionUnavailable,
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LocalProjectMetadata project, {
    bool permanent = false,
  }) async {
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => DeleteProjectDialog(
        project: project,
        permanent: permanent,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final notifier = ref.read(homeProjectsProvider.notifier);
    await _runProjectAction(
      context,
      permanent
          ? () => notifier.purgeProject(project.id)
          : () => notifier.deleteProject(project.id),
      successMessage: permanent
          ? CreativeStudioLocalizations.of(
              context,
            ).homeDocumentPermanentlyDeletedSuccess
          : CreativeStudioLocalizations.of(context).homeDocumentDeletedSuccess,
    );
  }

  Future<void> _createNewProject(
    BuildContext context, {
    bool replaceCurrent = false,
  }) async {
    try {
      final meta = await ref
          .read(homeProjectsProvider.notifier)
          .createProject('Untitled Doc');
      if (context.mounted) {
        await _openProject(
          context,
          meta.id,
          meta.name,
          replaceCurrent: replaceCurrent,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showUiToast(
          context,
          CreativeStudioLocalizations.of(context).projectActionUnavailable,
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (error) {
      if (!context.mounted) return;
      showUiToast(
        context,
        AuthService.friendlyError(error),
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _joinRoom(BuildContext context) async {
    final client = ref.read(supabaseClientProvider);
    final startingAccountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    final room = await context.push<CanvasRoom>('/join');
    if (!context.mounted || room == null) return;
    final currentClient = ref.read(supabaseClientProvider);
    final currentAccountId =
        currentClient?.auth.currentUser?.id ??
        currentClient?.auth.currentSession?.user.id;
    if (startingAccountId == null || currentAccountId != startingAccountId) {
      return;
    }
    await ref
        .read(homeProjectsProvider.notifier)
        .rememberCollaborationRoom(room, expectedAccountId: startingAccountId);
    await ref.read(homeProjectsProvider.notifier).loadProjects();
    if (!context.mounted) return;
    await _openProject(
      context,
      room.projectId,
      room.projectName,
      collaborationRole: CollaborationRole.fromWire(room.role),
    );
  }

  Future<void> _createFlowchartProject(BuildContext context) async {
    await _createTemplateProject(context, 'flowchart');
  }

  Future<void> _showTemplatePicker(BuildContext context) async {
    await showUiDialog<void>(
      context: context,
      builder: (_) => TemplatePickerDialog(
        onSelected: (template) {
          _createTemplateProject(context, template.id);
        },
        onOpenWizard: () => unawaited(_showProjectTemplateWizard(context)),
      ),
    );
  }

  Future<void> _showProjectTemplateWizard(BuildContext context) async {
    final storage = ref.read(localStorageServiceProvider);
    ProjectTemplateCatalog catalog;
    try {
      catalog = await storage.loadProjectTemplates('local');
    } catch (_) {
      catalog = ProjectTemplateCatalog.withBuiltIns();
    }
    if (!context.mounted) return;
    final request = await showUiDialog<StarterProjectRequest>(
      context: context,
      builder: (_) => ProjectTemplateWizardDialog(catalog: catalog),
    );
    if (!context.mounted || request == null) return;
    final template = catalog.templates
        .where((item) => item.id == request.templateId)
        .firstOrNull;
    final templateId = template?.diagramTemplateId;
    if (templateId == null) {
      await _createNewProject(context);
      return;
    }
    await _createTemplateProject(
      context,
      templateId,
      projectName: request.projectName,
    );
  }

  Future<void> _createTemplateProject(
    BuildContext context,
    String templateId, {
    String? projectName,
  }) async {
    try {
      final metadata = DiagramTemplates.listTemplates().firstWhere(
        (template) => template.id == templateId,
      );
      final meta = await ref
          .read(homeProjectsProvider.notifier)
          .createProject(projectName ?? metadata.name);
      final instance = DiagramTemplates.instantiate(templateId);
      await ref
          .read(localStorageServiceProvider)
          .saveDocument(
            CanvasDocument(
              projectId: meta.id,
              nodes: instance.nodes,
              edges: instance.edges,
              updatedAt: DateTime.now(),
            ),
          );
      if (context.mounted) {
        await _openProject(context, meta.id, meta.name, replaceCurrent: true);
      }
    } catch (_) {
      if (context.mounted) {
        showUiToast(
          context,
          CreativeStudioLocalizations.of(context).projectActionUnavailable,
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _openProject(
    BuildContext context,
    String projectId,
    String name, {
    bool replaceCurrent = false,
    CollaborationRole? collaborationRole,
  }) async {
    if (!context.mounted) return;
    final query = collaborationRole == null
        ? null
        : {'role': collaborationRole.wireName};
    final location = Uri(
      path: '/project/${Uri.encodeComponent(projectId)}',
      queryParameters: query,
    ).toString();
    if (replaceCurrent) {
      context.go(location);
    } else {
      await context.push(location);
    }
  }
}
