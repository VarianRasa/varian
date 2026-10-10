import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/collaboration/presentation/widgets/collaborator_overlay.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';

import '../../test_app.dart';

void main() {
  testWidgets('reduced motion applies remote cursor updates immediately', (
    tester,
  ) async {
    const scope = CollaborationProjectionScope(
      projectId: 'reduced-motion-cursor-fixture',
      accountId: 'local-account-fixture',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const CollaboratorOverlay(
              nodes: [],
              viewport: canvas_model.Viewport(),
              projectionScope: scope,
            ),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CollaboratorOverlay)),
      listen: false,
    );
    container
        .read(collaborationRemoteCursorsProvider(scope).notifier)
        .updateCursor(
          'remote-fixture',
          'Local Collaborator',
          Colors.blue,
          120,
          80,
        );
    await tester.pump();

    final controller =
        tester
                .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
                .firstWhere(
                  (builder) => builder.animation is AnimationController,
                )
                .animation
            as AnimationController;
    expect(controller.isAnimating, isFalse);
    expect(find.byType(CollaboratorOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
