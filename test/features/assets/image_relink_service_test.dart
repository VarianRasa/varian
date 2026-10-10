import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/image_relink_service.dart';

void main() {
  test('matches selected images by filename and falls back by order', () {
    final nodes = [
      CanvasNode(
        id: 'hero',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(assetId: 'Hero.png'),
      ),
      CanvasNode(
        id: 'card',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(assetId: 'card-old.jpg'),
      ),
      CanvasNode(
        id: 'fallback',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(),
      ),
    ];
    final assets = [
      AssetPickerResult(name: 'card.webp'),
      AssetPickerResult(name: 'hero-new.png'),
      AssetPickerResult(name: 'fallback.png'),
    ];

    final assignments = planImageRelinks(nodes, assets);

    expect(assignments.map((item) => item.nodeId), [
      'hero',
      'card',
      'fallback',
    ]);
    expect(assignments.map((item) => item.asset.name), [
      'hero-new.png',
      'card.webp',
      'fallback.png',
    ]);
  });

  test('ignores non-image nodes and never reuses an asset', () {
    final nodes = [
      CanvasNode(
        id: 'text',
        type: NodeType.text,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: TextPayload(text: 'Text'),
      ),
      CanvasNode(
        id: 'image-a',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(assetId: 'same.png'),
      ),
      CanvasNode(
        id: 'image-b',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(assetId: 'same.png'),
      ),
    ];
    final assets = [
      AssetPickerResult(name: 'same.webp'),
      AssetPickerResult(name: 'other.webp'),
    ];

    final assignments = planImageRelinks(nodes, assets);

    expect(assignments.map((item) => item.nodeId), ['image-a', 'image-b']);
    expect(assignments.map((item) => item.asset.name), [
      'same.webp',
      'other.webp',
    ]);
  });
}
