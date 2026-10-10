import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/collaboration/domain/crdt_engine.dart';
import 'package:varian/features/drawing_paper/domain/models/raster_edit_operation.dart';

void main() {
  group('CrdtDocumentSession', () {
    test('concurrent replacements converge before the next guest edit', () {
      final initial = _document();
      final host = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-z',
      );
      final guest = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final hostEdit = host.upsertNode(initial.nodes.single.copyWith(x: 100));
      final guestEdit = guest.upsertNode(initial.nodes.single.copyWith(x: 200));
      host.applyRemote(guestEdit);
      guest.applyRemote(hostEdit);
      expect(host.document.toJson(), guest.document.toJson());
      final next = guest.upsertNode(
        guest.document.nodes.single.copyWith(x: 300),
      );
      host.applyRemote(next);
      expect(host.document.nodes.single.x, 300);
      expect(guest.document.nodes.single.x, 300);

      final delayed = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'observer',
      );
      expect(delayed.applyRemote(next), CrdtApplyStatus.buffered);
      delayed.applyRemote(hostEdit);
      delayed.applyRemote(guestEdit);
      expect(delayed.document.toJson(), host.document.toJson());
      expect(delayed.hasCausalBuffer, isFalse);
      expect(delayed.applyRemote(next), CrdtApplyStatus.duplicate);
    });

    test('large embedded image previews do not inflate node operations', () {
      final node = CanvasNode(
        id: 'image-with-preview',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 320,
        height: 240,
        payload: ImagePayload(
          localPath: r'C:\assets\image.png',
          url: 'data:image/png;base64,${'a' * 200000}',
          backgroundMask: ImageMask(
            localPath: r'C:\assets\mask.png',
            url: 'data:image/png;base64,${'b' * 200000}',
          ),
        ),
      );
      final session = CrdtDocumentSession.fromDocument(
        CanvasDocument(
          projectId: 'project-1',
          nodes: [node],
          updatedAt: DateTime(2024),
        ),
        actorId: 'actor-a',
      );

      final operation = session.upsertNode(node);

      expect(
        operation.encode().length,
        lessThan(CrdtOperation.maxEncodedBytes),
      );
      final serializedPayload =
          (operation.value['node'] as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(serializedPayload['url'], isNull);
      expect(
        (serializedPayload['backgroundMask'] as Map<String, dynamic>)['url'],
        isNull,
      );
    });

    test('recreating a deleted node starts a fresh drawing generation', () {
      final session = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      session.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: _stroke('old-generation', 12),
      );
      session.deleteNode('paper-node');
      final recreated = session.upsertNode(
        _drawingDocument().nodes.single.copyWith(
          payload: DrawingPaperPayload(
            layers: [const DrawingLayer(id: 'layer-1', name: 'Fresh ink')],
          ),
        ),
      );

      expect(recreated.targetId, 'paper-node');
      final payload =
          session.document.nodes.single.payload as DrawingPaperPayload;
      expect(payload.layers.single.strokes, isEmpty);
    });

    test('causally newer node recreation wins over actor-order tombstones', () {
      final deleter = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-z',
      );
      final target = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'target',
      );
      final deletion = deleter.deleteNode('text-node');
      expect(target.applyRemote(deletion), CrdtApplyStatus.applied);

      final recreation = CrdtOperation.create(
        projectId: target.projectId,
        dot: const CrdtDot(actorId: 'actor-a', counter: 1),
        dependencies: CrdtVersionVector({'actor-z': 1}),
        kind: CrdtOperationKind.nodeUpsert,
        targetId: 'text-node',
        value: {
          'node': _document().nodes.single.copyWith(x: 99).toPersistenceJson(),
        },
      );

      expect(target.applyRemote(recreation), CrdtApplyStatus.applied);
      expect(target.document.nodes.single.x, 99);
    });

    test('causally newer node deletes win over actor-order node updates', () {
      final source = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-z',
      );
      final target = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      final update = source.upsertNode(
        _document().nodes.single.copyWith(x: 20),
      );
      expect(target.applyRemote(update), CrdtApplyStatus.applied);
      final deletion = CrdtOperation.create(
        projectId: target.projectId,
        dot: const CrdtDot(actorId: 'actor-a', counter: 1),
        dependencies: CrdtVersionVector({'actor-z': 1}),
        kind: CrdtOperationKind.nodeDelete,
        targetId: 'text-node',
      );

      expect(target.applyRemote(deletion), CrdtApplyStatus.applied);
      expect(target.document.nodes, isEmpty);
    });

    test('new node replacements supersede older field registers', () {
      final host = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-z',
      );
      host.setNodeField(nodeId: 'text-node', field: 'x', value: 44.0);
      final guest = CrdtDocumentSession.fromSnapshot(
        document: host.document,
        actorId: 'actor-a',
        version: host.version,
        state: host.snapshotState(),
      );
      final updated = guest.document.nodes.single.copyWith(x: 99);
      host.applyRemote(guest.upsertNode(updated));
      expect(host.document.nodes.single.x, 99);
      expect(guest.document.nodes.single.x, 99);
      final restored = CrdtDocumentSession.fromSnapshot(
        document: host.document,
        actorId: 'actor-next',
        version: host.version,
        state: host.snapshotState(),
      );
      expect(restored.document.nodes.single.x, 99);
    });

    test(
      'concurrent field and whole-node updates converge in either order',
      () {
        final initial = _document();
        final host = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-z',
        );
        final guest = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-a',
        );
        final replacement = host.upsertNode(
          initial.nodes.single.copyWith(x: 100),
        );
        final field = guest.setNodeField(
          nodeId: 'text-node',
          field: 'x',
          value: 200.0,
        );
        host.applyRemote(field);
        guest.applyRemote(replacement);
        expect(host.document.nodes.single.x, 100);
        expect(guest.document.nodes.single.x, 100);
      },
    );

    test(
      'alternating host and guest edits replace an older session snapshot',
      () {
        final previous = CrdtDocumentSession.fromDocument(
          _document(),
          actorId: 'actor-z-previous-session',
        );
        for (var edit = 0; edit < 5; edit++) {
          previous.upsertNode(previous.document.nodes.single.copyWith(x: 10));
        }
        final host = CrdtDocumentSession.fromSnapshot(
          document: previous.document,
          actorId: 'actor-b-host',
          version: previous.version,
          state: previous.snapshotState(),
        );
        final guest = CrdtDocumentSession.fromSnapshot(
          document: previous.document,
          actorId: 'actor-a-guest',
          version: previous.version,
          state: previous.snapshotState(),
        );

        for (var edit = 0; edit < 6; edit++) {
          final sender = edit.isEven ? guest : host;
          final receiver = edit.isEven ? host : guest;
          final updated = sender.document.nodes.single.copyWith(
            x: 100.0 + edit,
            y: 200.0 + edit,
            width: 250.0 + edit,
            height: 120.0 + edit,
            rotation: edit * 0.1,
            opacity: 0.5,
            payload: TextPayload(text: 'hello', fontSize: 24.0 + edit),
          );
          final operation = sender.upsertNode(updated);
          expect(receiver.applyRemote(operation), CrdtApplyStatus.applied);
          expect(sender.document.nodes.single.toJson(), updated.toJson());
          expect(receiver.document.nodes.single.toJson(), updated.toJson());
        }

        host.applyRemote(guest.deleteNode('text-node'));
        expect(host.document.nodes, isEmpty);
        expect(guest.document.nodes, isEmpty);
      },
    );

    test('later field edits win regardless of actor identity', () {
      final host = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-z-host',
      );
      final guest = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a-guest',
      );
      for (var edit = 0; edit < 10; edit++) {
        guest.applyRemote(
          host.setNodeField(
            nodeId: 'text-node',
            field: 'x',
            value: edit.toDouble(),
          ),
        );
      }
      host.applyRemote(
        guest.setNodeField(nodeId: 'text-node', field: 'x', value: 250.0),
      );
      expect(host.document.nodes.single.x, 250);
      expect(guest.document.nodes.single.x, 250);
    });

    test(
      'converges when concurrent nodes and edges arrive in opposite order',
      () {
        final initial = _document();
        final first = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-a',
        );
        final second = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-b',
        );

        final node = CanvasNode(
          id: 'node-b',
          type: NodeType.rectangle,
          x: 80,
          y: 90,
          width: 100,
          height: 60,
          payload: ShapePayload(),
        );
        final edge = _edge('edge-a');
        final nodeOperation = first.upsertNode(node);
        final edgeOperation = second.upsertEdge(edge);

        second.applyRemote(nodeOperation);
        first.applyRemote(edgeOperation);

        expect(first.document.toJson(), equals(second.document.toJson()));
        expect(
          first.document.nodes.any((value) => value.id == 'node-b'),
          isTrue,
        );
        expect(
          first.document.edges.any((value) => value.id == 'edge-a'),
          isTrue,
        );
      },
    );

    test('preserves concurrent inserts at the same text position', () {
      final initial = _document(text: 'hello');
      final first = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final second = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-b',
      );

      final firstOperation = first.replaceText(
        nodeId: 'text-node',
        field: 'payload.text',
        value: 'hello A',
      );
      final secondOperation = second.replaceText(
        nodeId: 'text-node',
        field: 'payload.text',
        value: 'hello B',
      );

      for (final operation in secondOperation) {
        first.applyRemote(operation);
      }
      for (final operation in firstOperation) {
        second.applyRemote(operation);
      }

      final firstText =
          (first.document.nodes.single.payload as TextPayload).text;
      final secondText =
          (second.document.nodes.single.payload as TextPayload).text;
      expect(firstText, equals(secondText));
      expect(firstText, contains('A'));
      expect(firstText, contains('B'));
    });

    test('buffers causally dependent operations and drains them later', () {
      final initial = _document(text: 'hello');
      final source = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-b',
      );

      final first = source.replaceText(
        nodeId: 'text-node',
        field: 'payload.text',
        value: 'hello one',
      );
      for (final operation in first) {
        expect(target.applyRemote(operation), CrdtApplyStatus.applied);
      }

      final second = source.replaceText(
        nodeId: 'text-node',
        field: 'payload.text',
        value: 'hello one two',
      );
      expect(target.applyRemote(second.last), CrdtApplyStatus.buffered);
      expect(
        (target.document.nodes.single.payload as TextPayload).text,
        'hello one',
      );

      for (final operation in second.take(second.length - 1)) {
        target.applyRemote(operation);
      }

      expect(
        (target.document.nodes.single.payload as TextPayload).text,
        'hello one two',
      );
    });

    test('rejects malformed node operations without advancing the clock', () {
      final session = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      final malformed = CrdtOperation.create(
        projectId: session.projectId,
        dot: const CrdtDot(actorId: 'remote', counter: 1),
        dependencies: CrdtVersionVector(),
        kind: CrdtOperationKind.nodeUpsert,
        targetId: 'text-node',
        value: const {},
      );

      expect(session.applyRemote(malformed), CrdtApplyStatus.rejected);
      expect(session.version['remote'], 0);
      expect(session.document.toJson(), equals(_document().toJson()));
    });

    test('rejects malformed stroke payloads without throwing', () {
      final session = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final malformed = CrdtOperation.create(
        projectId: session.projectId,
        dot: const CrdtDot(actorId: 'remote', counter: 1),
        dependencies: CrdtVersionVector(),
        kind: CrdtOperationKind.strokeUpsert,
        targetId: 'paper-node',
        value: const {
          'pageId': 'root-page',
          'layerId': 'layer-1',
          'strokeId': 'bad-stroke',
          'stroke': {'id': 'bad-stroke', 'points': 'not-a-list'},
        },
      );

      expect(session.applyRemote(malformed), CrdtApplyStatus.rejected);
      expect(session.version['remote'], 0);
    });

    test('duplicate delivery is idempotent', () {
      final session = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      final operation = session.setNodeField(
        nodeId: 'text-node',
        field: 'x',
        value: 44,
      );
      final before = session.document.toJson();

      expect(session.applyRemote(operation), CrdtApplyStatus.duplicate);
      expect(session.document.toJson(), equals(before));
    });

    test('converges concurrent drawing strokes on the same paper', () {
      final first = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final second = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-b',
      );
      final strokeA = _stroke('stroke-a', 10);
      final strokeB = _stroke('stroke-b', 40);
      final operationA = first.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: strokeA,
      );
      final operationB = second.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: strokeB,
      );

      second.applyRemote(operationA);
      first.applyRemote(operationB);

      final firstPayload =
          first.document.nodes.single.payload as DrawingPaperPayload;
      final secondPayload =
          second.document.nodes.single.payload as DrawingPaperPayload;
      expect(firstPayload.toJson(), equals(secondPayload.toJson()));
      expect(
        firstPayload.layers.single.strokes.map((s) => s.id),
        containsAll(<String>['stroke-a', 'stroke-b']),
      );
    });

    test(
      'converges same-stroke updates with equal revisions in either delivery order',
      () {
        final initial = _drawingDocument(
          strokes: [_stroke('stroke-shared', 10)],
        );
        final sourceA = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-a',
        );
        final sourceB = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-b',
        );
        final operationA = sourceA.upsertStroke(
          nodeId: 'paper-node',
          pageId: 'root-page',
          layerId: 'layer-1',
          stroke: _stroke('stroke-shared', 20),
        );
        final operationB = sourceB.upsertStroke(
          nodeId: 'paper-node',
          pageId: 'root-page',
          layerId: 'layer-1',
          stroke: _stroke('stroke-shared', 40),
        );
        final targetAB = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-ab',
        );
        final targetBA = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-ba',
        );

        expect(targetAB.applyRemote(operationA), CrdtApplyStatus.applied);
        expect(targetAB.applyRemote(operationB), CrdtApplyStatus.applied);
        expect(targetBA.applyRemote(operationB), CrdtApplyStatus.applied);
        expect(targetBA.applyRemote(operationA), CrdtApplyStatus.applied);

        final payloadAB =
            targetAB.document.nodes.single.payload as DrawingPaperPayload;
        final payloadBA =
            targetBA.document.nodes.single.payload as DrawingPaperPayload;
        expect(
          payloadAB.layers.single.strokes.single.toJson(),
          equals(payloadBA.layers.single.strokes.single.toJson()),
        );
        expect(payloadAB.rasterRevision, equals(payloadBA.rasterRevision));
        expect(targetAB.document.toJson(), equals(targetBA.document.toJson()));
      },
    );

    test('deletes a drawing stroke without deleting its paper node', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(strokes: [_stroke('stroke-a', 10)]),
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument(strokes: [_stroke('stroke-a', 10)]),
        actorId: 'actor-b',
      );

      final operation = source.deleteStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        strokeId: 'stroke-a',
      );
      target.applyRemote(operation);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(target.document.nodes.single.id, equals('paper-node'));
      expect(payload.layers.single.strokes, isEmpty);
    });

    test(
      'preserves a concurrent root stroke when a studio page node update arrives',
      () {
        final base = _drawingDocument();
        final first = CrdtDocumentSession.fromDocument(
          base,
          actorId: 'actor-a',
        );
        final second = CrdtDocumentSession.fromDocument(
          base,
          actorId: 'actor-b',
        );
        final originalPayload =
            base.nodes.single.payload as DrawingPaperPayload;
        final pageNode = base.nodes.single.copyWith(
          payload: originalPayload.copyWith(
            studioPages: [
              DrawingPaperPage(
                id: 'page-a',
                position: const Offset(400, 0),
                payload: DrawingPaperPayload(
                  layers: [
                    const DrawingLayer(id: 'page-layer', name: 'Page ink'),
                  ],
                ),
              ),
            ],
          ),
        );
        final pageOperation = first.upsertNode(pageNode);
        final strokeOperation = second.upsertStroke(
          nodeId: 'paper-node',
          pageId: 'root-page',
          layerId: 'layer-1',
          stroke: _stroke('root-b', 40),
        );

        expect(first.applyRemote(strokeOperation), CrdtApplyStatus.applied);
        expect(second.applyRemote(pageOperation), CrdtApplyStatus.applied);

        expect(first.document.toJson(), equals(second.document.toJson()));
        final payload =
            second.document.nodes.single.payload as DrawingPaperPayload;
        expect(
          payload.layers.single.strokes.map((stroke) => stroke.id),
          contains('root-b'),
        );
        expect(payload.studioPages.map((page) => page.id), contains('page-a'));
      },
    );

    test('preserves initial strokes when structural payloads omit them', () {
      final base = _drawingDocument(strokes: [_stroke('initial-stroke', 8)]);
      final first = CrdtDocumentSession.fromDocument(base, actorId: 'actor-a');
      final second = CrdtDocumentSession.fromDocument(base, actorId: 'actor-b');
      final payload = base.nodes.single.payload as DrawingPaperPayload;
      final structural = first.upsertNode(
        base.nodes.single.copyWith(
          payload: payload.copyWith(
            layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
            studioPages: [
              DrawingPaperPage(
                id: 'page-a',
                position: Offset.zero,
                payload: DrawingPaperPayload(
                  layers: const [
                    DrawingLayer(id: 'page-layer', name: 'Page ink'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      expect(second.applyRemote(structural), CrdtApplyStatus.applied);

      final merged =
          second.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        merged.layers.single.strokes.map((stroke) => stroke.id),
        contains('initial-stroke'),
      );
      expect(merged.studioPages.single.id, 'page-a');
    });

    test('buffers a stroke until its structural layer arrives', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final structuralSource = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-c',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument(strokes: const []).copyWith(
          nodes: [
            _drawingDocument(strokes: const []).nodes.single.copyWith(
              payload: DrawingPaperPayload(layers: const []),
            ),
          ],
        ),
        actorId: 'actor-b',
      );
      final stroke = source.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: _stroke('pending-stroke', 24),
      );
      final structuralNode = structuralSource.document.nodes.single.copyWith(
        payload: DrawingPaperPayload(
          layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
        ),
      );
      final structural = structuralSource.upsertNode(structuralNode);

      expect(target.applyRemote(stroke), CrdtApplyStatus.buffered);
      expect(target.applyRemote(structural), CrdtApplyStatus.applied);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        payload.layers.single.strokes.map((item) => item.id),
        contains('pending-stroke'),
      );
    });

    test('restores a buffered nested-page stroke from a snapshot', () {
      final nestedPayload = DrawingPaperPayload(
        layers: const [],
        studioPages: [
          DrawingPaperPage(
            id: 'outer-page',
            position: Offset.zero,
            payload: DrawingPaperPayload(
              layers: const [],
              studioPages: [
                DrawingPaperPage(
                  id: 'nested-page',
                  position: Offset.zero,
                  payload: DrawingPaperPayload(
                    layers: [
                      const DrawingLayer(
                        id: 'nested-layer',
                        name: 'Nested ink',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final nestedDocument = _drawingDocument().copyWith(
        nodes: [
          _drawingDocument().nodes.single.copyWith(payload: nestedPayload),
        ],
      );
      final source = CrdtDocumentSession.fromDocument(
        nestedDocument,
        actorId: 'actor-a',
      );
      final structuralSource = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-c',
      );
      final target = CrdtDocumentSession.fromDocument(
        nestedDocument.copyWith(
          nodes: [
            nestedDocument.nodes.single.copyWith(
              payload: DrawingPaperPayload(layers: const []),
            ),
          ],
        ),
        actorId: 'actor-b',
      );
      final stroke = source.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'nested-page',
        layerId: 'nested-layer',
        stroke: _stroke('nested-stroke', 32),
      );
      final structuralPayload = DrawingPaperPayload(
        layers: const [],
        studioPages: [
          DrawingPaperPage(
            id: 'outer-page',
            position: Offset.zero,
            payload: DrawingPaperPayload(
              layers: const [],
              studioPages: [
                DrawingPaperPage(
                  id: 'nested-page',
                  position: Offset.zero,
                  payload: DrawingPaperPayload(
                    layers: [
                      const DrawingLayer(
                        id: 'nested-layer',
                        name: 'Nested ink',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final structural = structuralSource.upsertNode(
        structuralSource.document.nodes.single.copyWith(
          payload: structuralPayload,
        ),
      );

      expect(target.applyRemote(stroke), CrdtApplyStatus.buffered);
      final restored = CrdtDocumentSession.fromSnapshot(
        document: target.document,
        actorId: 'actor-restored',
        version: target.version,
        state: target.snapshotState(),
      );

      expect(restored.applyRemote(structural), CrdtApplyStatus.applied);

      final root =
          restored.document.nodes.single.payload as DrawingPaperPayload;
      final outer = root.studioPages.single.payload;
      final nested = outer.studioPages.single.payload;
      expect(
        nested.layers.single.strokes.map((item) => item.id),
        contains('nested-stroke'),
      );
      expect(restored.hasCausalBuffer, isFalse);
    });

    test(
      'keeps a buffered stroke delete tombstoned after structure arrives',
      () {
        final source = CrdtDocumentSession.fromDocument(
          _drawingDocument(strokes: [_stroke('deleted-stroke', 16)]),
          actorId: 'actor-a',
        );
        final structuralSource = CrdtDocumentSession.fromDocument(
          _drawingDocument(strokes: [_stroke('deleted-stroke', 16)]),
          actorId: 'actor-c',
        );
        final target = CrdtDocumentSession.fromDocument(
          _drawingDocument(strokes: const []).copyWith(
            nodes: [
              _drawingDocument(strokes: const []).nodes.single.copyWith(
                payload: DrawingPaperPayload(layers: const []),
              ),
            ],
          ),
          actorId: 'actor-b',
        );
        final deletion = source.deleteStroke(
          nodeId: 'paper-node',
          pageId: 'root-page',
          layerId: 'layer-1',
          strokeId: 'deleted-stroke',
        );
        final structural = structuralSource.upsertNode(
          structuralSource.document.nodes.single,
        );

        expect(target.applyRemote(deletion), CrdtApplyStatus.buffered);
        expect(target.applyRemote(structural), CrdtApplyStatus.applied);

        final payload =
            target.document.nodes.single.payload as DrawingPaperPayload;
        expect(payload.layers.single.strokes, isEmpty);
        expect(target.hasCausalBuffer, isFalse);
      },
    );

    test('keeps a stroke delete tombstoned before its paper node arrives', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(strokes: [_stroke('deleted-before-node', 18)]),
        actorId: 'actor-a',
      );
      final structuralSource = CrdtDocumentSession.fromDocument(
        _drawingDocument(strokes: [_stroke('deleted-before-node', 18)]),
        actorId: 'actor-c',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument().copyWith(nodes: const []),
        actorId: 'actor-b',
      );
      final deletion = source.deleteStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        strokeId: 'deleted-before-node',
      );
      final structural = structuralSource.upsertNode(
        structuralSource.document.nodes.single,
      );

      expect(target.applyRemote(deletion), CrdtApplyStatus.buffered);
      expect(target.applyRemote(structural), CrdtApplyStatus.applied);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(payload.layers.single.strokes, isEmpty);
      expect(target.hasCausalBuffer, isFalse);
    });

    test(
      'materializes a raster edit delivered before its paper node arrives',
      () {
        final source = CrdtDocumentSession.fromDocument(
          _drawingDocument(),
          actorId: 'actor-a',
        );
        final structuralSource = CrdtDocumentSession.fromDocument(
          _drawingDocument(),
          actorId: 'actor-c',
        );
        final target = CrdtDocumentSession.fromDocument(
          _drawingDocument().copyWith(nodes: const []),
          actorId: 'actor-b',
        );
        const raster = RasterEditOperation(
          id: 'buffered-raster',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(2, 3),
          color: Color(0xFF00FF00),
        );

        final operation = source.addRasterOperation(
          nodeId: 'paper-node',
          operation: raster.toJson(),
        );
        final structural = structuralSource.upsertNode(
          structuralSource.document.nodes.single,
        );

        expect(target.applyRemote(operation), CrdtApplyStatus.buffered);
        expect(target.applyRemote(structural), CrdtApplyStatus.applied);

        final payload =
            target.document.nodes.single.payload as DrawingPaperPayload;
        expect(payload.rasterOperations.single.id, 'buffered-raster');
        expect(
          target.rasterOperationsFor('paper-node').single['id'],
          'buffered-raster',
        );
      },
    );

    test('materializes a stroke delivered before its paper node arrives', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final structuralSource = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-c',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument().copyWith(nodes: const []),
        actorId: 'actor-b',
      );
      final stroke = source.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: _stroke('missing-node-stroke', 24),
      );
      final structural = structuralSource.upsertNode(
        structuralSource.document.nodes.single,
      );

      expect(target.applyRemote(stroke), CrdtApplyStatus.buffered);
      expect(target.applyRemote(structural), CrdtApplyStatus.applied);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        payload.layers.single.strokes.map((item) => item.id),
        contains('missing-node-stroke'),
      );
      expect(target.hasCausalBuffer, isFalse);
    });

    test('materializes a deeply nested page stroke', () {
      final nested = DrawingPaperPayload(
        layers: const [],
        studioPages: [
          DrawingPaperPage(
            id: 'outer-page',
            position: Offset.zero,
            payload: DrawingPaperPayload(
              layers: const [],
              studioPages: [
                DrawingPaperPage(
                  id: 'inner-page',
                  position: Offset.zero,
                  payload: DrawingPaperPayload(
                    layers: [
                      const DrawingLayer(id: 'inner-layer', name: 'Inner ink'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final initial = _drawingDocument().copyWith(
        nodes: [_drawingDocument().nodes.single.copyWith(payload: nested)],
      );
      final source = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-b',
      );

      expect(
        target.applyRemote(
          source.upsertStroke(
            nodeId: 'paper-node',
            pageId: 'inner-page',
            layerId: 'inner-layer',
            stroke: _stroke('deep-stroke', 32),
          ),
        ),
        CrdtApplyStatus.applied,
      );

      final root = target.document.nodes.single.payload as DrawingPaperPayload;
      final inner = root.studioPages.single.payload.studioPages.single.payload;
      expect(
        inner.layers.single.strokes.map((item) => item.id),
        contains('deep-stroke'),
      );
    });

    test('materializes a buffered stroke revision after its layer arrives', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final structuralSource = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-c',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument().copyWith(
          nodes: [
            _drawingDocument().nodes.single.copyWith(
              payload: DrawingPaperPayload(layers: const []),
            ),
          ],
        ),
        actorId: 'actor-b',
      );
      final stroke = source.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: _stroke('buffered-revision', 24),
      );
      final structural = structuralSource.upsertNode(
        structuralSource.document.nodes.single,
      );

      expect(target.applyRemote(stroke), CrdtApplyStatus.buffered);
      expect(target.applyRemote(structural), CrdtApplyStatus.applied);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        payload.layers.single.strokes.map((item) => item.id),
        contains('buffered-revision'),
      );
      expect(payload.rasterRevision, 1);
      expect(target.hasCausalBuffer, isFalse);
    });

    test('buffers a node field until its missing node arrives', () {
      final fieldSource = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-z',
      );
      final nodeSource = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        _document().copyWith(nodes: const []),
        actorId: 'actor-b',
      );
      final field = fieldSource.setNodeField(
        nodeId: 'text-node',
        field: 'x',
        value: 99.0,
      );
      final node = nodeSource.upsertNode(
        nodeSource.document.nodes.single.copyWith(x: 10),
      );

      expect(target.applyRemote(field), CrdtApplyStatus.buffered);
      expect(target.applyRemote(node), CrdtApplyStatus.applied);
      expect(target.document.nodes.single.x, 99);
      expect(target.hasCausalBuffer, isFalse);
    });

    test('materializes raster edits into the replicated drawing payload', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-b',
      );
      const raster = RasterEditOperation(
        id: 'raster-fill-1',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(12, 18),
        color: Color(0xFF00FF00),
      );

      final operation = source.addRasterOperation(
        nodeId: 'paper-node',
        operation: raster.toJson(),
      );
      target.applyRemote(operation);

      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(payload.rasterOperations, hasLength(1));
      expect(payload.rasterOperations.single.toJson(), equals(raster.toJson()));
      expect(
        target.rasterOperationsFor('paper-node').single,
        equals(raster.toJson()),
      );
    });

    test('preserves persisted raster operations when a new edit is added', () {
      const persisted = RasterEditOperation(
        id: 'persisted-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(1, 1),
        color: Color(0xFF00FF00),
      );
      const next = RasterEditOperation(
        id: 'next-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(2, 2),
        color: Color(0xFFFF0000),
      );
      final initial = _drawingDocument().copyWith(
        nodes: [
          _drawingDocument().nodes.single.copyWith(
            payload: DrawingPaperPayload(
              layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
              rasterOperations: [persisted],
            ),
          ),
        ],
      );
      final session = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );

      session.addRasterOperation(
        nodeId: 'paper-node',
        operation: next.toJson(),
      );

      final payload =
          session.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        payload.rasterOperations.map((operation) => operation.id),
        equals(['persisted-raster', 'next-raster']),
      );
    });

    test('clears replicated raster operations with a page reset', () {
      const raster = RasterEditOperation(
        id: 'clearable-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(12, 18),
        color: Color(0xFF00FF00),
      );
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument().copyWith(
          nodes: [
            _drawingDocument().nodes.single.copyWith(
              payload: DrawingPaperPayload(
                layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
                rasterOperations: [raster],
              ),
            ),
          ],
        ),
        actorId: 'actor-a',
      );
      final target = CrdtDocumentSession.fromDocument(
        source.document,
        actorId: 'actor-b',
      );

      final reset = source.resetRasterOperations(
        nodeId: 'paper-node',
        pageId: 'root-page',
      );

      expect(target.applyRemote(reset), CrdtApplyStatus.applied);
      final payload =
          target.document.nodes.single.payload as DrawingPaperPayload;
      expect(payload.rasterOperations, isEmpty);
      expect(target.rasterOperationsFor('paper-node'), isEmpty);
    });

    test('converges concurrent raster operations in deterministic order', () {
      final initial = _drawingDocument();
      final sourceA = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final sourceB = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-b',
      );
      const rasterA = RasterEditOperation(
        id: 'raster-a',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(4, 4),
        color: Color(0xFFFF0000),
      );
      const rasterB = RasterEditOperation(
        id: 'raster-b',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(8, 8),
        color: Color(0xFF0000FF),
      );
      final operationA = sourceA.addRasterOperation(
        nodeId: 'paper-node',
        operation: rasterA.toJson(),
      );
      final operationB = sourceB.addRasterOperation(
        nodeId: 'paper-node',
        operation: rasterB.toJson(),
      );
      final targetAB = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-ab',
      );
      final targetBA = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-ba',
      );

      expect(targetAB.applyRemote(operationA), CrdtApplyStatus.applied);
      expect(targetAB.applyRemote(operationB), CrdtApplyStatus.applied);
      expect(targetBA.applyRemote(operationB), CrdtApplyStatus.applied);
      expect(targetBA.applyRemote(operationA), CrdtApplyStatus.applied);

      final payloadAB =
          targetAB.document.nodes.single.payload as DrawingPaperPayload;
      final payloadBA =
          targetBA.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        payloadAB.rasterOperations.map((operation) => operation.id),
        equals(['raster-a', 'raster-b']),
      );
      expect(
        payloadBA.rasterOperations.map((operation) => operation.id),
        equals(['raster-a', 'raster-b']),
      );
      expect(payloadAB.toJson(), equals(payloadBA.toJson()));
      expect(targetAB.document.toJson(), equals(targetBA.document.toJson()));
    });

    test('converges concurrent raster operations with the same payload ID', () {
      final initial = _drawingDocument();
      final sourceA = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-a',
      );
      final sourceB = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'actor-b',
      );
      const rasterA = RasterEditOperation(
        id: 'shared-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(4, 4),
        color: Color(0xFFFF0000),
      );
      const rasterB = RasterEditOperation(
        id: 'shared-raster',
        kind: RasterEditKind.bucketFill,
        seedPoint: Offset(8, 8),
        color: Color(0xFF0000FF),
      );
      final operationA = sourceA.addRasterOperation(
        nodeId: 'paper-node',
        operation: rasterA.toJson(),
      );
      final operationB = sourceB.addRasterOperation(
        nodeId: 'paper-node',
        operation: rasterB.toJson(),
      );
      final targetAB = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-ab',
      );
      final targetBA = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-ba',
      );

      expect(targetAB.applyRemote(operationA), CrdtApplyStatus.applied);
      expect(targetAB.applyRemote(operationB), CrdtApplyStatus.applied);
      expect(targetBA.applyRemote(operationB), CrdtApplyStatus.applied);
      expect(targetBA.applyRemote(operationA), CrdtApplyStatus.applied);

      final payloadAB =
          targetAB.document.nodes.single.payload as DrawingPaperPayload;
      final payloadBA =
          targetBA.document.nodes.single.payload as DrawingPaperPayload;
      expect(payloadAB.toJson(), equals(payloadBA.toJson()));
      expect(
        payloadAB.rasterOperations.map((operation) => operation.id),
        equals(['shared-raster', 'shared-raster']),
      );
      expect(targetAB.document.toJson(), equals(targetBA.document.toJson()));
    });

    test(
      'converges concurrent structural raster revisions in either order',
      () {
        final initial = _drawingDocument();
        final sourceA = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-a',
        );
        final sourceB = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-b',
        );
        final payloadA =
            sourceA.document.nodes.single.payload as DrawingPaperPayload;
        final payloadB =
            sourceB.document.nodes.single.payload as DrawingPaperPayload;
        final nodeA = sourceA.upsertNode(
          sourceA.document.nodes.single.copyWith(
            x: 40,
            payload: payloadA.copyWith(rasterRevision: 7),
          ),
        );
        final nodeB = sourceB.upsertNode(
          sourceB.document.nodes.single.copyWith(
            y: 60,
            payload: payloadB.copyWith(rasterRevision: 3),
          ),
        );
        final first = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-first',
        );
        final second = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-second',
        );

        expect(first.applyRemote(nodeA), CrdtApplyStatus.applied);
        expect(first.applyRemote(nodeB), CrdtApplyStatus.applied);
        expect(second.applyRemote(nodeB), CrdtApplyStatus.applied);
        expect(second.applyRemote(nodeA), CrdtApplyStatus.applied);

        expect(first.document.toJson(), equals(second.document.toJson()));
      },
    );

    test(
      'keeps root and nested raster revisions convergent in either order',
      () {
        final nestedPayload = DrawingPaperPayload(
          layers: [const DrawingLayer(id: 'root-layer', name: 'Root')],
          studioPages: [
            DrawingPaperPage(
              id: 'nested-page',
              position: Offset.zero,
              payload: DrawingPaperPayload(
                layers: [
                  const DrawingLayer(id: 'nested-layer', name: 'Nested'),
                ],
              ),
            ),
          ],
        );
        final initial = _drawingDocument().copyWith(
          nodes: [
            _drawingDocument().nodes.single.copyWith(payload: nestedPayload),
          ],
        );
        final nestedSource = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'nested-source',
        );
        final rootSource = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'root-source',
        );
        final nestedOperations = [
          for (var index = 1; index <= 3; index++)
            nestedSource.addRasterOperation(
              nodeId: 'paper-node',
              pageId: 'nested-page',
              operation: RasterEditOperation(
                id: 'nested-raster-$index',
                kind: RasterEditKind.bucketFill,
                seedPoint: Offset(index.toDouble(), index.toDouble()),
                color: const Color(0xFF00FF00),
              ).toJson(),
            ),
        ];
        final rootOperation = rootSource.addRasterOperation(
          nodeId: 'paper-node',
          operation: const RasterEditOperation(
            id: 'root-raster',
            kind: RasterEditKind.bucketFill,
            seedPoint: Offset(10, 10),
            color: Color(0xFFFF0000),
          ).toJson(),
        );
        final rootFirst = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-root-first',
        );
        final nestedFirst = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-nested-first',
        );

        expect(rootFirst.applyRemote(rootOperation), CrdtApplyStatus.applied);
        for (final operation in nestedOperations) {
          expect(rootFirst.applyRemote(operation), CrdtApplyStatus.applied);
        }
        for (final operation in nestedOperations) {
          expect(nestedFirst.applyRemote(operation), CrdtApplyStatus.applied);
        }
        expect(nestedFirst.applyRemote(rootOperation), CrdtApplyStatus.applied);

        expect(
          rootFirst.document.toJson(),
          equals(nestedFirst.document.toJson()),
        );
      },
    );

    test(
      'does not replay concurrent raster edits into a recreated node generation',
      () {
        final initial = _drawingDocument();
        final deleteSource = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'delete-source',
        );
        final rasterSource = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'raster-source',
        );
        final recreateSource = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'recreate-source',
        );
        final deletion = deleteSource.deleteNode('paper-node');
        expect(recreateSource.applyRemote(deletion), CrdtApplyStatus.applied);
        final recreation = recreateSource.upsertNode(
          initial.nodes.single.copyWith(
            payload: DrawingPaperPayload(
              layers: [const DrawingLayer(id: 'layer-1', name: 'Fresh ink')],
            ),
          ),
        );
        final raster = rasterSource.addRasterOperation(
          nodeId: 'paper-node',
          operation: const RasterEditOperation(
            id: 'concurrent-old-generation',
            kind: RasterEditKind.bucketFill,
            seedPoint: Offset(5, 5),
            color: Color(0xFF00FF00),
          ).toJson(),
        );
        final first = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-first',
        );
        final second = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'target-second',
        );

        expect(first.applyRemote(raster), CrdtApplyStatus.applied);
        expect(first.applyRemote(deletion), CrdtApplyStatus.applied);
        expect(first.applyRemote(recreation), CrdtApplyStatus.applied);
        expect(second.applyRemote(deletion), CrdtApplyStatus.applied);
        expect(second.applyRemote(recreation), CrdtApplyStatus.applied);
        expect(second.applyRemote(raster), CrdtApplyStatus.applied);

        final firstPayload =
            first.document.nodes.single.payload as DrawingPaperPayload;
        final secondPayload =
            second.document.nodes.single.payload as DrawingPaperPayload;
        expect(first.document.toJson(), equals(second.document.toJson()));
        expect(firstPayload.rasterOperations, isEmpty);
        expect(secondPayload.rasterOperations, isEmpty);
      },
    );

    test('does not replay raster edits into a recreated node generation', () {
      final session = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      session.addRasterOperation(
        nodeId: 'paper-node',
        operation: const RasterEditOperation(
          id: 'old-raster',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(4, 4),
          color: Color(0xFF00FF00),
        ).toJson(),
      );
      session.deleteNode('paper-node');
      session.upsertNode(
        _drawingDocument().nodes.single.copyWith(
          payload: DrawingPaperPayload(
            layers: [const DrawingLayer(id: 'layer-1', name: 'Fresh ink')],
          ),
        ),
      );

      final payload =
          session.document.nodes.single.payload as DrawingPaperPayload;
      expect(payload.rasterOperations, isEmpty);
      expect(session.rasterOperationsFor('paper-node'), isEmpty);
    });

    test(
      'preserves initial raster operations when structural payloads omit them',
      () {
        const raster = RasterEditOperation(
          id: 'initial-raster',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(8, 8),
          color: Color(0xFF0000FF),
        );
        final initial = _drawingDocument().copyWith(
          nodes: [
            _drawingDocument().nodes.single.copyWith(
              payload: DrawingPaperPayload(
                layers: [const DrawingLayer(id: 'layer-1', name: 'Ink')],
                rasterOperations: [raster],
              ),
            ),
          ],
        );
        final source = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-a',
        );
        final target = CrdtDocumentSession.fromDocument(
          initial,
          actorId: 'actor-b',
        );
        final structural = source.upsertNode(
          source.document.nodes.single.copyWith(
            payload:
                (source.document.nodes.single.payload as DrawingPaperPayload)
                    .copyWith(
                      layers: [
                        const DrawingLayer(id: 'layer-1', name: 'Renamed'),
                      ],
                      rasterOperations: const [],
                    ),
          ),
        );

        expect(target.applyRemote(structural), CrdtApplyStatus.applied);
        final payload =
            target.document.nodes.single.payload as DrawingPaperPayload;
        expect(
          payload.rasterOperations.map((operation) => operation.id),
          contains('initial-raster'),
        );
      },
    );

    test('materializes raster side registers while restoring a snapshot', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      source.addRasterOperation(
        nodeId: 'paper-node',
        operation: const RasterEditOperation(
          id: 'snapshot-raster',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(12, 12),
          color: Color(0xFFFFFF00),
        ).toJson(),
      );
      final state = source.snapshotState();
      final nodes = Map<String, dynamic>.from(state['nodes'] as Map);
      final node = Map<String, dynamic>.from(nodes['paper-node'] as Map);
      final payload = Map<String, dynamic>.from(node['payload'] as Map)
        ..['rasterOperations'] = const <Map<String, dynamic>>[];
      nodes['paper-node'] = {...node, 'payload': payload};
      state['nodes'] = nodes;

      final restored = CrdtDocumentSession.fromSnapshot(
        document: source.document,
        actorId: 'actor-b',
        version: source.version,
        state: state,
      );

      final restoredPayload =
          restored.document.nodes.single.payload as DrawingPaperPayload;
      expect(
        restoredPayload.rasterOperations.map((operation) => operation.id),
        contains('snapshot-raster'),
      );
    });

    test('restores stroke dots and materialized strokes from a snapshot', () {
      final source = CrdtDocumentSession.fromDocument(
        _drawingDocument(),
        actorId: 'actor-a',
      );
      source.upsertStroke(
        nodeId: 'paper-node',
        pageId: 'root-page',
        layerId: 'layer-1',
        stroke: _stroke('stroke-a', 10),
      );

      final restored = CrdtDocumentSession.fromSnapshot(
        document: source.document,
        actorId: 'actor-b',
        version: source.version,
        state: source.snapshotState(),
      );

      expect(restored.document.toJson(), equals(source.document.toJson()));
      expect(restored.snapshotState()['strokeDots'], isNotEmpty);
      expect(restored.hasCausalBuffer, isFalse);
    });

    test('converges a reset and a concurrent newer raster operation', () {
      final initial = _drawingDocument();
      final resetSource = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'reset-source',
      );
      final operationSource = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'operation-source',
      );
      final reset = resetSource.resetRasterOperations(nodeId: 'paper-node');
      final newer = operationSource.addRasterOperation(
        nodeId: 'paper-node',
        operation: const RasterEditOperation(
          id: 'after-reset',
          kind: RasterEditKind.bucketFill,
          seedPoint: Offset(5, 5),
          color: Color(0xFF00FFFF),
        ).toJson(),
      );
      final first = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-first',
      );
      final second = CrdtDocumentSession.fromDocument(
        initial,
        actorId: 'target-second',
      );

      expect(first.applyRemote(reset), CrdtApplyStatus.applied);
      expect(first.applyRemote(newer), CrdtApplyStatus.applied);
      expect(second.applyRemote(newer), CrdtApplyStatus.applied);
      expect(second.applyRemote(reset), CrdtApplyStatus.applied);

      expect(first.document.toJson(), equals(second.document.toJson()));
    });

    test('converges concurrent comment updates deterministically', () {
      final first = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      final second = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-b',
      );
      final commentA = CanvasComment(
        id: 'comment-1',
        authorId: 'actor-a',
        authorName: 'A',
        text: 'from A',
        x: 10,
        y: 10,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final commentB = commentA.copyWith(text: 'from B');
      final operationA = first.upsertComment(commentA);
      final operationB = second.upsertComment(commentB);

      second.applyRemote(operationA);
      first.applyRemote(operationB);

      expect(first.comments.single.text, equals(second.comments.single.text));
      expect(first.comments.single.text, equals('from B'));
    });

    test('converges concurrent comment replies and reactions', () {
      final base = _comment('comment-1');
      final first = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      )..seedComments([base]);
      final second = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-b',
      )..seedComments([base]);

      final replyA = first.insertCommentReply(
        commentId: base.id,
        reply: _reply('reply-a', 'A'),
      );
      final replyB = second.insertCommentReply(
        commentId: base.id,
        reply: _reply('reply-b', 'B'),
      );
      final reactionA = first.setCommentReaction(
        commentId: base.id,
        userId: 'actor-a',
        emoji: '👍',
        active: true,
      );
      final reactionB = second.setCommentReaction(
        commentId: base.id,
        userId: 'actor-b',
        emoji: '❤️',
        active: true,
      );

      for (final operation in [replyB, reactionB]) {
        first.applyRemote(operation);
      }
      for (final operation in [replyA, reactionA]) {
        second.applyRemote(operation);
      }

      expect(
        first.comments.single.toJson(),
        equals(second.comments.single.toJson()),
      );
      expect(
        first.comments.single.replies.map((reply) => reply.id),
        containsAll(<String>['reply-a', 'reply-b']),
      );
      expect(first.comments.single.reactions, equals({'👍': 1, '❤️': 1}));

      final editedReply = _reply(
        'reply-a',
        'actor-a',
      ).copyWith(text: 'A edited', editedAt: DateTime.utc(2026, 1, 9, 12));
      second.applyRemote(
        first.upsertCommentReply(commentId: base.id, reply: editedReply),
      );
      expect(
        second.comments.single.replies
            .singleWhere((reply) => reply.id == 'reply-a')
            .text,
        'A edited',
      );
      expect(
        second.comments.single.replies
            .singleWhere((reply) => reply.id == 'reply-a')
            .editedAt,
        editedReply.editedAt,
      );

      second.applyRemote(
        first.deleteCommentReply(commentId: base.id, replyId: 'reply-a'),
      );
      expect(
        second.comments.single.replies.map((reply) => reply.id),
        isNot(contains('reply-a')),
      );
    });

    test('resolves and deletes comments as independent operations', () {
      final base = _comment('comment-1');
      final source = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      )..seedComments([base]);
      final target = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-b',
      )..seedComments([base]);

      target.applyRemote(
        source.setCommentResolved(commentId: base.id, resolved: true),
      );
      expect(target.comments.single.resolved, isTrue);

      target.applyRemote(source.deleteComment(base.id));
      expect(target.comments, isEmpty);
    });

    test('restores comment thread registers from a snapshot', () {
      final source = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      )..seedComments([_comment('comment-1')]);
      source.insertCommentReply(
        commentId: 'comment-1',
        reply: _reply('reply-a', 'actor-a'),
      );
      source.setCommentReaction(
        commentId: 'comment-1',
        userId: 'actor-a',
        emoji: '👍',
        active: true,
      );
      source.setCommentResolved(commentId: 'comment-1', resolved: true);

      final restored = CrdtDocumentSession.fromSnapshot(
        document: source.document,
        actorId: 'actor-b',
        version: source.version,
        state: source.snapshotState(),
        comments: source.comments,
      );

      expect(
        restored.comments.single.toJson(),
        equals(source.comments.single.toJson()),
      );
      expect(restored.snapshotState()['commentReactionRegisters'], isNotEmpty);
      expect(restored.snapshotState()['commentResolveRegisters'], isNotEmpty);
    });

    test('rejects an asset snapshot map key that differs from asset ID', () {
      final document = CanvasDocument(
        projectId: 'project-1',
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final asset = DocumentAsset(
        id: 'asset-1',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.remote,
        name: 'Image',
        mimeType: 'image/png',
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );

      expect(
        () => CrdtDocumentSession.fromSnapshot(
          document: document,
          actorId: 'actor-b',
          version: CrdtVersionVector(),
          state: {
            'assets': {'wrong-key': asset.toPersistenceJson()},
          },
        ),
        throwsFormatException,
      );
    });

    test('ignores malformed snapshot entries while restoring valid state', () {
      final source = CrdtDocumentSession.fromDocument(
        _document(),
        actorId: 'actor-a',
      );
      source.setNodeField(nodeId: 'text-node', field: 'x', value: 44);
      final state = source.snapshotState();
      final nodes = Map<String, dynamic>.from(state['nodes'] as Map)
        ..['broken'] = {'type': 'unknown', 'payload': []};
      final dots = Map<String, dynamic>.from(state['nodeDots'] as Map)
        ..['broken'] = {'actorId': null, 'counter': 'bad'};
      final malformed = <String, dynamic>{
        ...state,
        'nodes': nodes,
        'nodeDots': dots,
        'strokeRegisters': {
          'broken': {'points': 'not-a-list'},
        },
      };

      final restored = CrdtDocumentSession.fromSnapshot(
        document: source.document,
        actorId: 'actor-b',
        version: source.version,
        state: malformed,
      );

      expect(restored.document.nodes.single.id, 'text-node');
      expect(restored.document.nodes.single.x, 44);
      expect(restored.snapshotState()['nodeDots'], isNot(contains('broken')));
    });

    test(
      'restores text atoms and field registers from a compacted snapshot',
      () {
        final source = CrdtDocumentSession.fromDocument(
          _document(),
          actorId: 'actor-a',
        );
        source.setNodeField(nodeId: 'text-node', field: 'x', value: 44);
        source.replaceText(
          nodeId: 'text-node',
          field: 'payload.text',
          value: 'hello snapshot',
        );

        final restored = CrdtDocumentSession.fromSnapshot(
          document: source.document,
          actorId: 'actor-b',
          version: source.version,
          state: source.snapshotState(),
        );

        expect(restored.document.toJson(), equals(source.document.toJson()));
        expect(restored.version, equals(source.version));
        expect(restored.hasCausalBuffer, isFalse);
      },
    );
  });
}

CanvasDocument _document({String text = 'hello'}) {
  return CanvasDocument(
    projectId: 'project-1',
    updatedAt: DateTime.utc(2026, 1, 1),
    nodes: [
      CanvasNode(
        id: 'text-node',
        type: NodeType.text,
        x: 0,
        y: 0,
        width: 200,
        height: 80,
        payload: TextPayload(text: text),
      ),
    ],
  );
}

CanvasEdge _edge(String id) =>
    CanvasEdge(id: id, sourceNodeId: 'text-node', targetNodeId: 'text-node');

CanvasDocument _drawingDocument({List<DrawingStroke> strokes = const []}) {
  return CanvasDocument(
    projectId: 'project-1',
    updatedAt: DateTime.utc(2026, 1, 1),
    nodes: [
      CanvasNode(
        id: 'paper-node',
        type: NodeType.drawingPaper,
        x: 0,
        y: 0,
        width: 400,
        height: 400,
        payload: DrawingPaperPayload(
          layers: [DrawingLayer(id: 'layer-1', name: 'Ink', strokes: strokes)],
        ),
      ),
    ],
  );
}

CanvasComment _comment(String id) => CanvasComment(
  id: id,
  authorId: 'author-a',
  authorName: 'Author A',
  text: 'Comment',
  x: 10,
  y: 20,
  createdAt: DateTime.utc(2026, 1, 1),
);

CommentReply _reply(String id, String authorId) => CommentReply(
  id: id,
  authorId: authorId,
  authorName: authorId,
  text: 'Reply',
  createdAt: DateTime.utc(2026, 1, 2),
);

DrawingStroke _stroke(String id, double x) => DrawingStroke(
  id: id,
  brush: StudioBrushCategory.gPen,
  color: const Color(0xFF000000),
  size: 4,
  opacity: 1,
  points: [
    DrawingStrokePoint(x: x, y: 10),
    DrawingStrokePoint(x: x + 20, y: 20),
  ],
);
