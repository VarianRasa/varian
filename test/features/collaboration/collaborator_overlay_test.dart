import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/collaboration/presentation/widgets/collaborator_overlay.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';

import '../../test_app.dart';

void main() {
  testWidgets('remote cursor overlay does not intercept local canvas taps', (
    tester,
  ) async {
    const scope = CollaborationProjectionScope(
      projectId: 'local-overlay-fixture',
      accountId: 'local-account-fixture',
    );
    var canvasTapped = false;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Column(
            children: [
              Consumer(
                builder: (context, ref, child) => TextButton(
                  onPressed: () => ref
                      .read(collaborationRemoteCursorsProvider(scope).notifier)
                      .updateCursor(
                        'remote-fixture',
                        'Local Collaborator',
                        Colors.purple,
                        24,
                        32,
                        selectedNodeIds: const {'local-node-fixture'},
                      ),
                  child: const Text('Show remote cursor'),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () => canvasTapped = true,
                        child: const SizedBox(
                          width: 160,
                          height: 120,
                          child: ColoredBox(
                            key: ValueKey('local-canvas-fixture'),
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    const CollaboratorOverlay(
                      nodes: [],
                      viewport: canvas_model.Viewport(),
                      projectionScope: scope,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show remote cursor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CollaboratorOverlay), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('local-canvas-fixture'))),
    );
    expect(canvasTapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
