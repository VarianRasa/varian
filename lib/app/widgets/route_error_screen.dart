import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../localization/app_localizations.dart';
import '../theme.dart';
import 'ui_primitives.dart';

Widget buildRouteErrorScreen(BuildContext context, GoRouterState state) =>
    const RouteErrorScreen();

class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = CreativeStudioLocalizations.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: copy.routeErrorTitle,
      child: UiPageScaffold(
        title: const SizedBox.shrink(),
        childPad: true,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: UiSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.link_off_outlined,
                      size: 40,
                      color: context.appTokens.warning,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ExcludeSemantics(
                      child: Text(
                        copy.routeErrorTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      copy.routeErrorDescription,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appTokens.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    UiButton(
                      onPressed: () => context.go('/'),
                      prefix: const Icon(Icons.home_outlined),
                      child: Text(copy.routeErrorHomeAction),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
