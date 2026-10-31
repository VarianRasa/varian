import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/home/state/home_provider.dart';
import 'package:varian/features/search/search_service.dart';

class SearchDialog extends ConsumerStatefulWidget {
  final void Function(String nodeId)? onSelectNode;

  const SearchDialog({super.key, this.onSelectNode});

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(homeProjectsProvider).isLoading) return;
      unawaited(ref.read(homeProjectsProvider.notifier).loadProjects());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(documentNodesProvider);
    final projectState = ref.watch(homeProjectsProvider);
    final projects = projectState.value ?? [];
    final nodeResults = SearchService.searchNodes(nodes, _query);
    final projectResults = projects.where((p) {
      return p.name.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();
    final availableHeight =
        (AppResponsive.dialogHeight(context, preferred: 468) -
                MediaQuery.viewInsetsOf(context).vertical)
            .clamp(0.0, 468.0)
            .toDouble();
    final width = AppResponsive.dialogWidth(context, preferred: 420);
    final height = availableHeight;

    return UiDialog(
      semanticsLabel: 'Search canvas objects and projects',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 420,
        maxHeight: height,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: UiTextField(
                      controller: _controller,
                      label: 'Search canvas objects and projects',
                      hint: 'Search canvas objects & projects...',
                      autofocus: true,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close search',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _query.trim().isEmpty
                    ? SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 1),
                          child: const UiEmptyState(
                            icon: Icons.search,
                            title: 'TYPE TO SEARCH',
                            message:
                                'Find canvas objects and project documents.',
                          ),
                        ),
                      )
                    : (nodeResults.isEmpty && projectResults.isEmpty)
                    ? SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 1),
                          child: UiEmptyState(
                            icon: Icons.search_off,
                            title: 'NO RESULTS',
                            message: 'Try another search term.',
                            action: projectState.hasError
                                ? UiButton(
                                    variant: UiButtonVariant.outline,
                                    onPressed: () => ref
                                        .read(homeProjectsProvider.notifier)
                                        .loadProjects(),
                                    child: const Text('Retry projects'),
                                  )
                                : null,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          if (projectResults.isNotEmpty) ...[
                            _sectionHeader('PROJECTS'),
                            ...projectResults.map(_projectTile),
                          ],
                          if (nodeResults.isNotEmpty) ...[
                            _sectionHeader('CANVAS OBJECTS'),
                            ...nodeResults.map(_nodeTile),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.xs,
      AppSpacing.xs,
    ),
    child: UiSectionHeader(title: label),
  );

  Widget _projectTile(LocalProjectMetadata project) {
    final tokens = context.appTokens;
    return UiButton(
      onPressed: () => Navigator.pop(context),
      variant: UiButtonVariant.ghost,
      prefix: Icon(Icons.folder_outlined, size: 18, color: tokens.accent),
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.text),
            ),
            Text(
              'Project',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nodeTile(SearchResult result) {
    final tokens = context.appTokens;
    return UiButton(
      onPressed: () {
        final nodeId = result.nodeId;
        if (nodeId == null) return;
        widget.onSelectNode?.call(nodeId);
        Navigator.pop(context);
      },
      variant: UiButtonVariant.ghost,
      prefix: Icon(result.icon, size: 18, color: result.color),
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.text),
            ),
            Text(
              result.subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
