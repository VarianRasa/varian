import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/home/presentation/widgets/project_preview.dart';
import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the saved canvas content in a project preview', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 9, 14, 12);
    final project = LocalProjectMetadata(
      id: 'preview-project',
      name: 'Preview project',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await LocalStorageService().saveProjectMetadata(project);
    await LocalStorageService().saveDocument(
      CanvasDocument(
        projectId: project.id,
        updatedAt: timestamp,
        nodes: [
          CanvasNode(
            id: 'shape',
            type: NodeType.rectangle,
            x: 0,
            y: 0,
            width: 180,
            height: 100,
            payload: ShapePayload(
              fill: const Color(0xFF10B981),
              stroke: const Color(0xFF6EE7B7),
            ),
          ),
          CanvasNode(
            id: 'label',
            type: NodeType.text,
            x: 24,
            y: 28,
            width: 132,
            height: 36,
            payload: TextPayload(
              text: 'Canvas preview',
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 300,
          height: 170,
          child: ProjectPreview(project: project),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMPTY CANVAS'), findsNothing);
    expect(find.text('PREVIEW UNAVAILABLE'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter?.runtimeType.toString() == '_ProjectPreviewPainter',
      ),
      findsOneWidget,
    );
  });
  testWidgets('renders a local empty preview without reading project storage', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 10, 3);
    final project = LocalProjectMetadata(
      id: 'empty-preview-fixture',
      name: 'Empty preview fixture',
      createdAt: timestamp,
      updatedAt: timestamp,
      isPinned: true,
      collaborationRoomCode: 'local-fixture',
    );
    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 300,
          height: 170,
          child: ProjectPreview(
            project: project,
            documentFuture: Future.value(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMPTY CANVAS'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('ROOM local-fixture'), findsOneWidget);
    final badgePositions = tester
        .widgetList<Positioned>(find.byType(Positioned))
        .where((position) => position.child is UiBadge)
        .toList();
    expect(badgePositions, hasLength(3));
    expect(badgePositions[0].top, AppSpacing.sm + AppSpacing.xxs);
    expect(badgePositions[0].left, AppSpacing.sm + AppSpacing.xxs);
    expect(badgePositions[1].top, AppSpacing.sm + AppSpacing.xxs);
    expect(badgePositions[1].right, AppSpacing.sm + AppSpacing.xxs);
    expect(badgePositions[2].left, AppSpacing.sm + AppSpacing.xxs);
    expect(badgePositions[2].bottom, AppSpacing.sm + AppSpacing.xxs);
    expect(tester.takeException(), isNull);
  });
}
