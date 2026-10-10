import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/document_asset_dependencies.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

CanvasNode imageNode(String nodeId, {String? assetId, String? storagePath}) =>
    CanvasNode(
      id: nodeId,
      type: NodeType.image,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: ImagePayload(assetId: assetId, storagePath: storagePath),
    );

void main() {
  test(
    'collects component template, fallback, and slot-content descendants',
    () {
      final templateChild = imageNode('template', assetId: 'template-asset');
      final fallbackChild = imageNode('fallback', assetId: 'fallback-asset');
      final slotContentChild = imageNode(
        'slot-content',
        storagePath: 'project-1/assets/slot-content.png',
      );
      final component = CanvasNode(
        id: 'component',
        type: NodeType.component,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ComponentPayload(
          masterComponentId: 'master',
          componentName: 'Card',
          templateChildren: [templateChild],
          slots: [
            ComponentSlot(
              id: 'body',
              name: 'Body',
              fallbackChildren: [fallbackChild],
            ),
          ],
          slotContent: {
            'body': [slotContentChild],
          },
        ),
      );

      final closure = collectDocumentAssetDependencies([component]);

      expect(
        closure.assetIds,
        containsAll(<String>['template-asset', 'fallback-asset']),
      );
      expect(
        closure.unkeyed.map((dependency) => dependency.durableReference),
        contains('project-1/assets/slot-content.png'),
      );
    },
  );

  test('collects drawing-paper preview and reference-image dependencies', () {
    final paper = CanvasNode(
      id: 'paper',
      type: NodeType.drawingPaper,
      x: 0,
      y: 0,
      width: 100,
      height: 100,
      payload: DrawingPaperPayload(
        compositePreviewRef: 'project-1/previews/paper.png',
        referenceConfig: const ReferenceImageConfig(
          storagePath: 'project-1/references/reference.png',
        ),
      ),
    );

    final closure = collectDocumentAssetDependencies([paper]);

    expect(
      closure.unkeyed.map((dependency) => dependency.durableReference),
      containsAll(<String>[
        'project-1/previews/paper.png',
        'project-1/references/reference.png',
      ]),
    );
  });
}
