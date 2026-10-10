import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/supabase_bootstrap.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/secure_share_screen.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';
import '../../test_app.dart';

void main() {
  testWidgets('compact password share surface keeps its controls bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SecureShareScreen(
            projectId: 'compact-password',
            token: 'fixture-share-token',
            reader:
                ({
                  required projectId,
                  required token,
                  String? passwordDigest,
                }) async => throw const SharedCanvasPasswordRequired(
                  snapshotId: 'compact-snapshot',
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byType(UiSurface).first);
    expect(surface.left, greaterThanOrEqualTo(0));
    expect(surface.right, lessThanOrEqualTo(320));
    expect(surface.top, greaterThanOrEqualTo(0));
    expect(surface.bottom, lessThanOrEqualTo(480));
    for (final control in [
      find.byKey(const ValueKey('secure-share-password')),
      find.byKey(const ValueKey('secure-share-password-submit')),
    ]) {
      final bounds = tester.getRect(control);
      expect(bounds.left, greaterThanOrEqualTo(surface.left));
      expect(bounds.right, lessThanOrEqualTo(surface.right));
      expect(bounds.top, greaterThanOrEqualTo(surface.top));
      expect(bounds.bottom, lessThanOrEqualTo(surface.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact share error surface bounds its retry action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SecureShareScreen(
            projectId: 'compact-error',
            token: 'fixture-share-token',
            reader:
                ({
                  required projectId,
                  required token,
                  String? passwordDigest,
                }) async => throw const SyncException('Local share failure.'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byType(UiSurface).first);
    expect(surface.left, greaterThanOrEqualTo(0));
    expect(surface.right, lessThanOrEqualTo(320));
    expect(surface.top, greaterThanOrEqualTo(0));
    expect(surface.bottom, lessThanOrEqualTo(480));
    final retry = tester.getRect(
      find.byKey(const ValueKey('secure-share-retry')),
    );
    expect(retry.left, greaterThanOrEqualTo(surface.left));
    expect(retry.right, lessThanOrEqualTo(surface.right));
    expect(retry.top, greaterThanOrEqualTo(surface.top));
    expect(retry.bottom, lessThanOrEqualTo(surface.bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('password-protected share retries with the snapshot digest', (
    tester,
  ) async {
    const projectId = 'secure-project';
    const token = 'fixture-share-token';
    const snapshotId = 'snapshot-1';
    var attempts = 0;
    String? receivedDigest;

    await tester.pumpWidget(
      MaterialApp(
        home: SecureShareScreen(
          projectId: projectId,
          token: token,
          reader:
              ({
                required projectId,
                required token,
                String? passwordDigest,
              }) async {
                attempts++;
                receivedDigest = passwordDigest;
                throw SharedCanvasPasswordRequired(
                  snapshotId: snapshotId,
                  rejected: passwordDigest != null,
                );
              },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Password-protected canvas'), findsOneWidget);
    expect(find.byKey(const ValueKey('secure-share-password')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('secure-share-password')),
      'correct horse',
    );
    await tester.tap(
      find.byKey(const ValueKey('secure-share-password-submit')),
    );
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      receivedDigest,
      PublishedSnapshot.passwordDigestFor(snapshotId, 'correct horse'),
    );
    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
  });

  testWidgets('waits for cloud bootstrap before a cold share read', (
    tester,
  ) async {
    var bootstrapAttempts = 0;
    var readerAttempts = 0;
    final bootstrap = SupabaseBootstrapController(
      initialize: () async {
        bootstrapAttempts++;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SecureShareScreen(
          projectId: 'cold-share-project',
          token: 'fixture-share-token',
          bootstrap: bootstrap,
          reader:
              ({
                required projectId,
                required token,
                String? passwordDigest,
              }) async {
                readerAttempts++;
                throw const SyncException('Share unavailable in fixture.');
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(bootstrapAttempts, 1);
    expect(readerAttempts, 1);
    expect(find.text('Share unavailable in fixture.'), findsOneWidget);
    bootstrap.dispose();
  });

  test(
    'shared download policy disables exports only when explicitly disabled',
    () {
      final document = CanvasDocument(
        projectId: 'policy-project',
        updatedAt: DateTime.utc(2026, 9, 14),
      );

      expect(
        SharedCanvasData(
          document: document,
          downloadPolicy: PublishedDownloadPolicy.disabled,
        ).canExport,
        isFalse,
      );
      expect(
        SharedCanvasData(
          document: document,
          downloadPolicy: PublishedDownloadPolicy.exportOnly,
        ).canExport,
        isTrue,
      );
    },
  );
}
