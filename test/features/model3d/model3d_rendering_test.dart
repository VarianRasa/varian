import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/features/model3d/presentation/model3d_rendering.dart';

void main() {
  test('extracts indexed UV triangles and texture bytes', () {
    final texture = three.DataTexture(
      Uint8List.fromList(<int>[255, 0, 0, 255, 0, 255, 0, 255]),
      2,
      1,
      three.RGBAFormat,
      three.UnsignedByteType,
    )..needsUpdate = true;
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          0,
        ], 3),
      )
      ..setAttributeFromString(
        'uv',
        three.Float32BufferAttribute.fromList(<double>[0, 0, 1, 0, 0, 1], 2),
      )
      ..setIndex(<int>[0, 1, 2]);
    final material = three.MeshStandardMaterial()..map = texture;
    final mesh = three.Mesh(geometry, material);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(materialChannel: Model3DMaterialChannel.baseColor),
    );

    expect(presentation.snapshot.uvTriangles, hasLength(1));
    expect(presentation.snapshot.uvTriangles.single.u2, 1);
    expect(presentation.snapshot.textureBytes, isNotNull);
    expect(presentation.snapshot.textureWidth, 2);
    expect(presentation.snapshot.textureHeight, 1);
  });

  test('UV checker applies a repeating colored surface texture', () {
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          0,
        ], 3),
      )
      ..setAttributeFromString(
        'uv',
        three.Float32BufferAttribute.fromList(<double>[0, 0, 1, 0, 0, 1], 2),
      );
    final original = three.MeshStandardMaterial();
    final mesh = three.Mesh(geometry, original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(
        uvChecker: true,
        materialChannel: Model3DMaterialChannel.roughness,
      ),
      canvasColor: 0xFFF5F5F5,
    );

    final material = mesh.material!;
    final checker = material.map!;
    final image = checker.image as three.ImageElement;
    final data = image.data as Uint8List;

    expect(material, isA<three.MeshBasicMaterial>());
    expect(checker.wrapS, three.RepeatWrapping);
    expect(checker.wrapT, three.RepeatWrapping);
    expect(checker.magFilter, three.NearestFilter);
    expect(checker.minFilter, three.NearestFilter);
    expect(data.length, 64 * 64 * 4);
    expect(data.sublist((64 + 1) * 4, (64 + 2) * 4), <int>[124, 58, 237, 255]);
    expect(data.sublist(0, 4), <int>[17, 24, 39, 255]);

    presentation.restore();
    expect(identical(mesh.material, original), isTrue);

    presentation.apply(
      model,
      Model3DPayload(uvChecker: true),
      canvasColor: 0xFF0A0A0A,
    );
    final darkImage = presentation.snapshot;
    final darkChecker = mesh.material!.map!.image as three.ImageElement;
    final darkData = darkChecker.data as Uint8List;
    expect(darkImage.hasUv, isTrue);
    expect(darkData.sublist(0, 4), <int>[250, 250, 250, 255]);
  });

  test('wireframe rendering chooses a contrasting theme color', () {
    final geometry = three.BufferGeometry();
    final original = three.MeshStandardMaterial();
    final mesh = three.Mesh(geometry, original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();

    presentation.apply(
      model,
      Model3DPayload(
        geometryMode: Model3DGeometryMode.wireframe,
        wireframeColor: 0xFFFFFFFF,
        inspectorSelection: Model3DInspectorSelection.wireframe,
      ),
      canvasColor: 0xFFF5F5F5,
    );
    expect(mesh.material!.color.getHex(), 0x171717);

    presentation.restore();
    presentation.apply(
      model,
      Model3DPayload(
        geometryMode: Model3DGeometryMode.wireframe,
        wireframeColor: 0xFF171717,
        inspectorSelection: Model3DInspectorSelection.wireframe,
      ),
      canvasColor: 0xFF0A0A0A,
    );
    expect(mesh.material!.color.getHex(), 0xFAFAFA);

    presentation.dispose();
  });

  test('vertex normal overlays choose a contrasting theme color', () {
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          0,
        ], 3),
      )
      ..setAttributeFromString(
        'normal',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          1,
          0,
          0,
          1,
          0,
          0,
          1,
        ], 3),
      );
    final mesh = three.Mesh(geometry, three.MeshStandardMaterial());
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(
        geometryMode: Model3DGeometryMode.vertexNormals,
        inspectorSelection: Model3DInspectorSelection.vertexNormals,
      ),
      canvasColor: 0xFFF5F5F5,
    );
    expect(mesh.children.single.material!.color.getHex(), 0x171717);

    presentation.restore();
    presentation.apply(
      model,
      Model3DPayload(
        geometryMode: Model3DGeometryMode.vertexNormals,
        inspectorSelection: Model3DInspectorSelection.vertexNormals,
      ),
      canvasColor: 0xFF0A0A0A,
    );
    expect(mesh.children.single.material!.color.getHex(), 0xF59E0B);
  });

  test('Matcap surface remains available as a global selection', () {
    final original = three.MeshStandardMaterial();
    final mesh = three.Mesh(three.BufferGeometry(), original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();

    presentation.apply(
      model,
      Model3DPayload(
        geometryMode: Model3DGeometryMode.matcapSurface,
        inspectorSelection: Model3DInspectorSelection.matcapSurface,
      ),
    );

    final material = mesh.material!;
    expect(material, isA<three.MeshMatcapMaterial>());
    expect(material.matcap, isNotNull);
    expect(material.map, isNull);

    presentation.restore();
    expect(identical(mesh.material, original), isTrue);
  });

  test('restores original materials after a display override', () {
    final geometry = three.BufferGeometry()
      ..setAttributeFromString(
        'position',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          0,
        ], 3),
      )
      ..setAttributeFromString(
        'normal',
        three.Float32BufferAttribute.fromList(<double>[
          0,
          0,
          1,
          0,
          0,
          1,
          0,
          0,
          1,
        ], 3),
      );
    final original = three.MeshStandardMaterial();
    final mesh = three.Mesh(geometry, original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(
        renderMode: Model3DRenderMode.noPostProcessing,
        geometryMode: Model3DGeometryMode.vertexNormals,
        doubleSided: true,
        inspectorSelection: Model3DInspectorSelection.noPostProcessing,
      ),
    );

    expect(mesh.material, isA<three.MeshBasicMaterial>());
    expect(mesh.children, isEmpty);
    presentation.restore();

    expect(identical(mesh.material, original), isTrue);
    expect(original.side, three.FrontSide);
    expect(mesh.children, isEmpty);
  });

  test('preserves grouped materials when applying a display override', () {
    final firstTexture = three.DataTexture(
      Uint8List.fromList(const <int>[255, 0, 0, 255]),
      1,
      1,
      three.RGBAFormat,
      three.UnsignedByteType,
    );
    final secondTexture = three.DataTexture(
      Uint8List.fromList(const <int>[0, 255, 0, 255]),
      1,
      1,
      three.RGBAFormat,
      three.UnsignedByteType,
    );
    final original = three.GroupMaterial([
      three.MeshStandardMaterial()..map = firstTexture,
      three.MeshStandardMaterial()..map = secondTexture,
    ]);
    final geometry = three.BufferGeometry()
      ..addGroup(0, 3, 0)
      ..addGroup(3, 3, 1);
    final mesh = three.Mesh(geometry, original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(renderMode: Model3DRenderMode.noPostProcessing),
    );

    final override = mesh.material! as three.GroupMaterial;
    expect(override.children, hasLength(2));
    expect(override.children[0], isA<three.MeshBasicMaterial>());
    expect(override.children[1], isA<three.MeshBasicMaterial>());
    expect(override.children[0].map, same(firstTexture));
    expect(override.children[1].map, same(secondTexture));

    presentation.restore();
    expect(mesh.material, same(original));
    expect(original.children[0].map, same(firstTexture));
    expect(original.children[1].map, same(secondTexture));
  });

  test('canonical selection overrides conflicting legacy display fields', () {
    final original = three.MeshStandardMaterial();
    final mesh = three.Mesh(three.BufferGeometry(), original);
    final model = three.Object3D()..add(mesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(
        renderMode: Model3DRenderMode.noPostProcessing,
        materialChannel: Model3DMaterialChannel.roughness,
        geometryMode: Model3DGeometryMode.vertexNormals,
        uvChecker: true,
        inspectorSelection: Model3DInspectorSelection.finalRender,
      ),
    );

    expect(identical(mesh.material, original), isTrue);
    expect(mesh.children, isEmpty);
  });

  test('disables ANGLE-unsafe transmission and mipmaps temporarily', () {
    final texture =
        three.DataTexture(
            Uint8List.fromList(<int>[255, 255, 255, 255]),
            1,
            1,
            three.RGBAFormat,
            three.UnsignedByteType,
          )
          ..minFilter = three.LinearMipmapLinearFilter
          ..magFilter = three.NearestFilter
          ..generateMipmaps = true
          ..anisotropy = 4
          ..needsUpdate = true;
    final original = three.MeshPhysicalMaterial()
      ..map = texture
      ..transmission = 0.8
      ..transmissionMap = texture
      ..thickness = 0.35
      ..thicknessMap = texture;
    final mesh = three.Mesh(three.BufferGeometry(), original);
    final sharedMesh = three.Mesh(three.BufferGeometry(), original);
    final model = three.Object3D()
      ..add(mesh)
      ..add(sharedMesh);
    final presentation = Model3DScenePresentation();
    addTearDown(presentation.dispose);

    presentation.apply(
      model,
      Model3DPayload(inspectorSelection: Model3DInspectorSelection.finalRender),
    );
    expect(original.transmission, 0.8);
    expect(identical(original.transmissionMap, texture), isTrue);
    expect(texture.minFilter, three.LinearMipmapLinearFilter);
    expect(texture.magFilter, three.NearestFilter);
    expect(texture.generateMipmaps, isTrue);
    expect(texture.anisotropy, 4);
    presentation.restore();

    presentation.apply(
      model,
      Model3DPayload(inspectorSelection: Model3DInspectorSelection.finalRender),
      angleSafe: true,
    );

    expect(original.transmission, 0);
    expect(original.transmissionMap, isNull);
    expect(original.thicknessMap, isNull);
    expect(texture.minFilter, three.LinearFilter);
    expect(texture.magFilter, three.LinearFilter);
    expect(texture.generateMipmaps, isFalse);
    expect(texture.anisotropy, 1);

    presentation.restore();

    expect(identical(mesh.material, original), isTrue);
    expect(identical(sharedMesh.material, original), isTrue);
    expect(original.transmission, 0.8);
    expect(identical(original.transmissionMap, texture), isTrue);
    expect(original.thickness, 0.35);
    expect(identical(original.thicknessMap, texture), isTrue);
    expect(texture.minFilter, three.LinearMipmapLinearFilter);
    expect(texture.magFilter, three.NearestFilter);
    expect(texture.generateMipmaps, isTrue);
    expect(texture.anisotropy, 4);
  });
}
