import 'dart:math' as math;
import 'dart:typed_data';

import 'package:three_js/three_js.dart' as three;

import '../../../domain/models/model3d_payload.dart';

class Model3DUvTriangle {
  final double u1;
  final double v1;
  final double u2;
  final double v2;
  final double u3;
  final double v3;

  const Model3DUvTriangle({
    required this.u1,
    required this.v1,
    required this.u2,
    required this.v2,
    required this.u3,
    required this.v3,
  });
}

class Model3DSceneSnapshot {
  final List<Model3DUvTriangle> uvTriangles;
  final Uint8List? textureBytes;
  final String? textureUrl;
  final int textureWidth;
  final int textureHeight;
  final int fallbackColor;
  final String channelLabel;

  const Model3DSceneSnapshot({
    this.uvTriangles = const [],
    this.textureBytes,
    this.textureUrl,
    this.textureWidth = 0,
    this.textureHeight = 0,
    this.fallbackColor = 0xFF808080,
    this.channelLabel = 'Base Color',
  });

  bool get hasUv => uvTriangles.isNotEmpty;
  bool get hasTexture =>
      textureBytes != null || textureUrl?.trim().isNotEmpty == true;
}

class Model3DScenePresentation {
  final Map<three.Object3D, three.Material> _originalMaterials = {};
  final Map<three.Material, _OriginalMaterialState> _originalStates = {};
  final Map<three.Texture, _OriginalTextureState> _originalTextures = {};
  final Set<three.Material> _temporaryMaterials = {};
  final Set<three.Texture> _generatedTextures = {};
  final List<three.Object3D> _overlayObjects = [];
  int _canvasColor = 0x0A0A0A;

  Model3DSceneSnapshot _snapshot = const Model3DSceneSnapshot();

  Model3DSceneSnapshot get snapshot => _snapshot;

  void apply(
    three.Object3D model,
    Model3DPayload payload, {
    int canvasColor = 0x0A0A0A,
    bool angleSafe = false,
  }) {
    restore();
    _canvasColor = canvasColor & 0x00FFFFFF;
    final activePayload = payload.copyWithInspectorSelection(
      payload.inspectorSelection,
    );

    final renderables = <three.Object3D>[];
    final meshes = <three.Mesh>[];
    model.traverse((object) {
      if (object.geometry == null || object.material == null) return;
      if (object is three.Mesh ||
          object is three.Line ||
          object is three.Points) {
        renderables.add(object);
        if (object is three.Mesh) meshes.add(object);
      }
    });

    for (final renderable in renderables) {
      final material = renderable.material!;
      _originalMaterials[renderable] = material;
      for (final sourceMaterial in _materialsIn(material)) {
        _originalStates.putIfAbsent(
          sourceMaterial,
          () => _OriginalMaterialState(
            side: sourceMaterial.side,
            wireframe: sourceMaterial.wireframe,
            toneMapped: sourceMaterial.toneMapped,
            transmission: sourceMaterial.transmission,
            transmissionMap: sourceMaterial.transmissionMap,
            thickness: sourceMaterial.thickness,
            thicknessMap: sourceMaterial.thicknessMap,
          ),
        );
        if (angleSafe) _normalizeMaterialForAngle(sourceMaterial);
      }

      final override = _buildMaterialOverride(
        material,
        activePayload,
        renderable: renderable,
      );
      if (override != null) {
        renderable.material = override;
        _temporaryMaterials.add(override);
      }
      _applyMaterialFlags(renderable.material!, activePayload);
    }

    if (activePayload.geometryMode == Model3DGeometryMode.vertexNormals) {
      _addVertexNormalOverlays(meshes);
    }

    _snapshot = _buildSnapshot(renderables, activePayload);
  }

  void restore() {
    for (final overlay in _overlayObjects) {
      overlay.parent?.remove(overlay);
      overlay.dispose();
    }
    _overlayObjects.clear();

    for (final entry in _originalMaterials.entries) {
      final renderable = entry.key;
      final material = entry.value;
      renderable.material = material;
      for (final sourceMaterial in _materialsIn(material)) {
        final state = _originalStates[sourceMaterial];
        if (state == null) continue;
        sourceMaterial
          ..side = state.side
          ..wireframe = state.wireframe
          ..toneMapped = state.toneMapped
          ..transmission = state.transmission
          ..transmissionMap = state.transmissionMap
          ..thickness = state.thickness
          ..thicknessMap = state.thicknessMap
          ..needsUpdate = true;
      }
    }
    _originalMaterials.clear();
    _originalStates.clear();

    for (final entry in _originalTextures.entries) {
      final texture = entry.key;
      final state = entry.value;
      texture
        ..magFilter = state.magFilter
        ..minFilter = state.minFilter
        ..generateMipmaps = state.generateMipmaps
        ..anisotropy = state.anisotropy
        ..needsUpdate = true;
    }
    _originalTextures.clear();

    for (final material in _temporaryMaterials) {
      _detachTextures(material);
      material.dispose();
    }
    _temporaryMaterials.clear();

    for (final texture in _generatedTextures) {
      texture.dispose();
    }
    _generatedTextures.clear();
    _snapshot = const Model3DSceneSnapshot();
  }

  void dispose() => restore();

  void _normalizeMaterialForAngle(three.Material material) {
    final textures = <three.Texture?>[
      material.map,
      material.lightMap,
      material.aoMap,
      material.emissiveMap,
      material.bumpMap,
      material.normalMap,
      material.displacementMap,
      material.roughnessMap,
      material.metalnessMap,
      material.alphaMap,
      material.envMap,
      material.matcap,
      material.clearcoatMap,
      material.clearcoatRoughnessMap,
      material.clearcoatNormalMap,
      material.transmissionMap,
      material.thicknessMap,
      material.specularMap,
      material.specularIntensityMap,
      material.specularColorMap,
      material.sheenColorMap,
      material.sheenRoughnessMap,
      material.sheenTintMap,
      material.anisotropyMap,
      material.iridescenceMap,
      material.iridescenceThicknessMap,
      material.gradientMap,
    ];
    for (final texture in textures) {
      if (texture == null || _generatedTextures.contains(texture)) continue;
      _originalTextures.putIfAbsent(
        texture,
        () => _OriginalTextureState(
          magFilter: texture.magFilter,
          minFilter: texture.minFilter,
          generateMipmaps: texture.generateMipmaps,
          anisotropy: texture.anisotropy,
        ),
      );
      texture
        ..magFilter = three.LinearFilter
        ..minFilter = three.LinearFilter
        ..generateMipmaps = false
        ..anisotropy = 1
        ..needsUpdate = true;
    }

    // ponytail: Preserve opaque ANGLE previews until the renderer stops
    // allocating mipmapped multisample targets for transmission.
    if (material.transmission > 0 ||
        material.transmissionMap != null ||
        material.thicknessMap != null) {
      material
        ..transmission = 0
        ..transmissionMap = null
        ..thickness = 0
        ..thicknessMap = null
        ..needsUpdate = true;
    }
  }

  three.Material? _buildMaterialOverride(
    three.Material original,
    Model3DPayload payload, {
    required three.Object3D renderable,
  }) {
    if (original is three.GroupMaterial) {
      if (original.children.isEmpty) return null;
      final children = <three.Material>[];
      for (final child in original.children) {
        final override = _buildMaterialOverride(
          child,
          payload,
          renderable: renderable,
        );
        if (override == null) return null;
        children.add(override);
      }
      return three.GroupMaterial(children);
    }

    final geometryMode = payload.geometryMode;
    if (geometryMode == Model3DGeometryMode.matcap ||
        geometryMode == Model3DGeometryMode.matcapSurface) {
      final map = payload.uvChecker
          ? _createCheckerTexture()
          : geometryMode == Model3DGeometryMode.matcapSurface
          ? original.map
          : null;
      if (renderable is! three.Mesh) {
        return _createBasicMaterial(
          renderable,
          color: payload.uvChecker ? 0xFFFFFFFF : original.color.getHex(),
          map: map,
          transparent: original.transparent,
          opacity: original.opacity,
        );
      }
      return three.MeshMatcapMaterial({
        three.MaterialProperty.color: payload.uvChecker
            ? 0xFFFFFFFF
            : original.color.getHex(),
        three.MaterialProperty.map: map,
        three.MaterialProperty.matcap: _createMatcapTexture(),
        three.MaterialProperty.transparent: original.transparent,
        three.MaterialProperty.opacity: original.opacity,
      });
    }

    if (geometryMode == Model3DGeometryMode.wireframe) {
      return _createBasicMaterial(
        renderable,
        color: _contrastSafeColor(payload.wireframeColor),
        wireframe: true,
      );
    }

    final channelTexture = _textureForChannel(
      original,
      payload.materialChannel,
    );
    final useChecker = payload.uvChecker;
    final useChannel =
        payload.materialChannel != Model3DMaterialChannel.baseColor;
    final useBasic = payload.renderMode == Model3DRenderMode.noPostProcessing;
    if (!useChecker && !useChannel && !useBasic) return null;

    final fallbackColor = _fallbackColor(original, payload.materialChannel);
    return _createBasicMaterial(
      renderable,
      color: useChecker
          ? 0xFFFFFFFF
          : channelTexture == null
          ? fallbackColor
          : 0xFFFFFFFF,
      map: useChecker ? _createCheckerTexture() : channelTexture,
      opacity: original.opacity,
      transparent:
          original.transparent ||
          payload.materialChannel == Model3DMaterialChannel.opacity,
    );
  }

  three.Material _createBasicMaterial(
    three.Object3D renderable, {
    required int color,
    three.Texture? map,
    double opacity = 1,
    bool transparent = false,
    bool wireframe = false,
  }) {
    final parameters = <three.MaterialProperty, dynamic>{
      three.MaterialProperty.color: color,
      three.MaterialProperty.map: map,
      three.MaterialProperty.opacity: opacity,
      three.MaterialProperty.transparent: transparent,
      three.MaterialProperty.wireframe: wireframe,
    };
    if (renderable is three.Points) {
      return three.PointsMaterial(parameters);
    }
    if (renderable is three.Line) {
      return three.LineBasicMaterial(parameters);
    }
    return three.MeshBasicMaterial(parameters);
  }

  void _applyMaterialFlags(three.Material material, Model3DPayload payload) {
    for (final child in _materialsIn(material)) {
      child.side = payload.doubleSided ? three.DoubleSide : three.FrontSide;
      if (payload.geometryMode == Model3DGeometryMode.wireframe) {
        child.color.setFrom(
          three.Color.fromHex32(_contrastSafeColor(payload.wireframeColor)),
        );
        child.wireframe = true;
      }
      child.needsUpdate = true;
    }
  }

  Iterable<three.Material> _materialsIn(three.Material material) sync* {
    if (material is three.GroupMaterial) {
      for (final child in material.children) {
        yield* _materialsIn(child);
      }
    } else {
      yield material;
    }
  }

  void _addVertexNormalOverlays(List<three.Mesh> meshes) {
    for (final mesh in meshes) {
      final geometry = mesh.geometry;
      final positions = geometry?.attributes['position'];
      final normals = geometry?.attributes['normal'];
      if (positions is! three.BufferAttribute ||
          normals is! three.BufferAttribute) {
        continue;
      }

      final values = <double>[];
      final count = math.min(positions.count, normals.count);
      final stride = math.max(1, (count / 2500).ceil());
      for (var index = 0; index < count; index += stride) {
        final x = positions.getX(index)?.toDouble();
        final y = positions.getY(index)?.toDouble();
        final z = positions.getZ(index)?.toDouble();
        final nx = normals.getX(index)?.toDouble();
        final ny = normals.getY(index)?.toDouble();
        final nz = normals.getZ(index)?.toDouble();
        if ([
          x,
          y,
          z,
          nx,
          ny,
          nz,
        ].any((value) => value == null || !value.isFinite)) {
          continue;
        }

        final normalLength = math.sqrt(nx! * nx + ny! * ny + nz! * nz);
        if (normalLength <= 0.0001) continue;
        const length = 0.08;
        values
          ..add(x!)
          ..add(y!)
          ..add(z!)
          ..add(x + nx / normalLength * length)
          ..add(y + ny / normalLength * length)
          ..add(z + nz / normalLength * length);
      }
      if (values.isEmpty) continue;

      final overlayGeometry = three.BufferGeometry()
        ..setAttributeFromString(
          'position',
          three.Float32BufferAttribute.fromList(values, 3),
        );
      final overlay =
          three.LineSegments(
              overlayGeometry,
              three.LineBasicMaterial({
                three.MaterialProperty.color: _contrastSafeColor(0xFFF59E0B),
              }),
            )
            ..frustumCulled = false
            ..renderOrder = 10;
      mesh.add(overlay);
      _overlayObjects.add(overlay);
    }
  }

  Model3DSceneSnapshot _buildSnapshot(
    List<three.Object3D> renderables,
    Model3DPayload payload,
  ) {
    final triangles = <Model3DUvTriangle>[];
    three.Texture? previewTexture;
    three.Material? previewMaterial;

    for (final renderable in renderables) {
      if (renderable is three.Mesh) {
        final geometry = renderable.geometry;
        final uv = geometry?.attributes['uv'];
        final position = geometry?.attributes['position'];
        if (uv is three.BufferAttribute &&
            position is three.BufferAttribute &&
            geometry != null) {
          _collectUvTriangles(geometry, uv, triangles);
        }
      }
      final material = _originalMaterials[renderable] ?? renderable.material;
      if (material != null && previewTexture == null) {
        final candidate = _textureForChannel(material, payload.materialChannel);
        if (candidate != null) {
          previewTexture = candidate;
          previewMaterial = material;
        }
      }
    }

    previewMaterial ??= renderables
        .map(
          (renderable) => _originalMaterials[renderable] ?? renderable.material,
        )
        .whereType<three.Material>()
        .firstOrNull;
    final image = previewTexture == null ? null : _textureImage(previewTexture);
    return Model3DSceneSnapshot(
      uvTriangles: List.unmodifiable(triangles),
      textureBytes: image?.bytes,
      textureUrl: image?.url,
      textureWidth: image?.width ?? 0,
      textureHeight: image?.height ?? 0,
      fallbackColor: _fallbackColor(previewMaterial, payload.materialChannel),
      channelLabel: _channelLabel(payload.materialChannel),
    );
  }

  void _collectUvTriangles(
    three.BufferGeometry geometry,
    three.BufferAttribute uv,
    List<Model3DUvTriangle> output,
  ) {
    if (uv.itemSize < 2 || output.length >= 12000) return;
    final index = geometry.index;
    final triangleCount = index == null ? uv.count ~/ 3 : index.count ~/ 3;
    for (
      var triangle = 0;
      triangle < triangleCount && output.length < 12000;
      triangle++
    ) {
      final base = triangle * 3;
      final a = index == null ? base : index.getX(base)?.toInt();
      final b = index == null ? base + 1 : index.getX(base + 1)?.toInt();
      final c = index == null ? base + 2 : index.getX(base + 2)?.toInt();
      if (a == null ||
          b == null ||
          c == null ||
          a < 0 ||
          b < 0 ||
          c < 0 ||
          a >= uv.count ||
          b >= uv.count ||
          c >= uv.count) {
        continue;
      }
      final u1 = uv.getX(a)?.toDouble();
      final v1 = uv.getY(a)?.toDouble();
      final u2 = uv.getX(b)?.toDouble();
      final v2 = uv.getY(b)?.toDouble();
      final u3 = uv.getX(c)?.toDouble();
      final v3 = uv.getY(c)?.toDouble();
      if ([
        u1,
        v1,
        u2,
        v2,
        u3,
        v3,
      ].any((value) => value == null || !value.isFinite)) {
        continue;
      }
      output.add(
        Model3DUvTriangle(u1: u1!, v1: v1!, u2: u2!, v2: v2!, u3: u3!, v3: v3!),
      );
    }
  }

  three.Texture? _textureForChannel(
    three.Material material,
    Model3DMaterialChannel channel,
  ) {
    if (material is three.GroupMaterial) {
      for (final child in material.children) {
        final texture = _textureForChannel(child, channel);
        if (texture != null) return texture;
      }
      return null;
    }

    switch (channel) {
      case Model3DMaterialChannel.baseColor:
        return material.map;
      case Model3DMaterialChannel.metalness:
        return material.metalnessMap;
      case Model3DMaterialChannel.roughness:
        return material.roughnessMap;
      case Model3DMaterialChannel.normalMap:
        return material.normalMap;
      case Model3DMaterialChannel.aoMap:
      case Model3DMaterialChannel.cavity:
        return material.aoMap;
      case Model3DMaterialChannel.opacity:
        return material.alphaMap;
      case Model3DMaterialChannel.specularF0:
        return material.specularColorMap ?? material.specularMap;
      case Model3DMaterialChannel.clearCoat:
        return material.clearcoatMap;
      case Model3DMaterialChannel.clearCoatRoughness:
        return material.clearcoatRoughnessMap;
      case Model3DMaterialChannel.clearCoatNormalMap:
        return material.clearcoatNormalMap;
    }
  }

  int _fallbackColor(three.Material? material, Model3DMaterialChannel channel) {
    if (material == null) return 0xFF808080;
    if (material is three.GroupMaterial) {
      for (final child in material.children) {
        return _fallbackColor(child, channel);
      }
      return 0xFF808080;
    }

    switch (channel) {
      case Model3DMaterialChannel.baseColor:
        return 0xFF000000 | material.color.getHex();
      case Model3DMaterialChannel.metalness:
        return _gray(material.metalness);
      case Model3DMaterialChannel.roughness:
        return _gray(material.roughness);
      case Model3DMaterialChannel.normalMap:
      case Model3DMaterialChannel.clearCoatNormalMap:
        return 0xFF8080FF;
      case Model3DMaterialChannel.aoMap:
      case Model3DMaterialChannel.cavity:
        return 0xFFCCCCCC;
      case Model3DMaterialChannel.opacity:
        return _gray(material.opacity);
      case Model3DMaterialChannel.specularF0:
        return 0xFF000000 |
            (material.specularColor ?? three.Color.fromHex32(0x444444))
                .getHex();
      case Model3DMaterialChannel.clearCoat:
        return _gray(material.clearcoat);
      case Model3DMaterialChannel.clearCoatRoughness:
        return _gray(material.clearcoatRoughness ?? 1);
    }
  }

  int _gray(double value) {
    final channel = (value.clamp(0, 1) * 255).round();
    return 0xFF000000 | channel << 16 | channel << 8 | channel;
  }

  String _channelLabel(Model3DMaterialChannel channel) {
    switch (channel) {
      case Model3DMaterialChannel.baseColor:
        return 'Base Color';
      case Model3DMaterialChannel.metalness:
        return 'Metalness';
      case Model3DMaterialChannel.roughness:
        return 'Roughness';
      case Model3DMaterialChannel.normalMap:
        return 'Normal Map';
      case Model3DMaterialChannel.aoMap:
        return 'AO map';
      case Model3DMaterialChannel.cavity:
        return 'Cavity';
      case Model3DMaterialChannel.opacity:
        return 'Opacity';
      case Model3DMaterialChannel.specularF0:
        return 'Specular F0';
      case Model3DMaterialChannel.clearCoat:
        return 'Clear Coat';
      case Model3DMaterialChannel.clearCoatRoughness:
        return 'Clear Coat Roughness';
      case Model3DMaterialChannel.clearCoatNormalMap:
        return 'Clear Coat Normal Map';
    }
  }

  int _contrastSafeColor(int color) {
    final candidate = color & 0x00FFFFFF;
    if (_contrastRatio(candidate, _canvasColor) >= 3) return candidate;

    const light = 0x00FAFAFA;
    const dark = 0x00171717;
    return _contrastRatio(light, _canvasColor) >=
            _contrastRatio(dark, _canvasColor)
        ? light
        : dark;
  }

  double _contrastRatio(int first, int second) {
    final firstLuminance = _relativeLuminance(first);
    final secondLuminance = _relativeLuminance(second);
    final lighter = math.max(firstLuminance, secondLuminance);
    final darker = math.min(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
  }

  double _relativeLuminance(int color) {
    double channel(int shift) {
      final value = ((color >> shift) & 0xFF) / 255;
      return value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return channel(16) * 0.2126 + channel(8) * 0.7152 + channel(0) * 0.0722;
  }

  three.Texture _createCheckerTexture() {
    const width = 64;
    const height = 64;
    const cellSize = 4;
    const colors = <int>[
      0xFF7C3AED,
      0xFF2563EB,
      0xFF06B6D4,
      0xFF16A34A,
      0xFFFACC15,
      0xFFF97316,
      0xFFEF4444,
      0xFFDB2777,
    ];
    final gridColor = _contrastSafeColor(0xFF111827);
    final data = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final cell = (x ~/ cellSize) + (y ~/ cellSize) * (width ~/ cellSize);
        final isGridLine = x % cellSize == 0 || y % cellSize == 0;
        final value = isGridLine ? gridColor : colors[cell % colors.length];
        final offset = (y * width + x) * 4;
        data[offset] = (value >> 16) & 0xFF;
        data[offset + 1] = (value >> 8) & 0xFF;
        data[offset + 2] = value & 0xFF;
        data[offset + 3] = 0xFF;
      }
    }
    final texture =
        three.DataTexture(
            data,
            width,
            height,
            three.RGBAFormat,
            three.UnsignedByteType,
          )
          ..wrapS = three.RepeatWrapping
          ..wrapT = three.RepeatWrapping
          ..magFilter = three.NearestFilter
          ..minFilter = three.NearestFilter
          ..generateMipmaps = false
          ..needsUpdate = true;
    _generatedTextures.add(texture);
    return texture;
  }

  three.Texture _createMatcapTexture() {
    const width = 64;
    const height = 64;
    final isLightCanvas = _relativeLuminance(_canvasColor) > 0.5;
    final baseShade = isLightCanvas ? 28 : 48;
    final highlightRange = isLightCanvas ? 185 : 205;
    final data = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = (x + 0.5) / width * 2 - 1;
        final ny = (y + 0.5) / height * 2 - 1;
        final distance = math.sqrt(nx * nx + ny * ny);
        final highlight = math.max(0, 1 - distance);
        final shade = (baseShade + highlight * highlightRange).round().clamp(
          0,
          255,
        );
        final offset = (y * width + x) * 4;
        data[offset] = shade;
        data[offset + 1] = (shade * 0.94).round();
        data[offset + 2] = (shade * 0.9).round();
        data[offset + 3] = distance <= 1 ? 0xFF : 0;
      }
    }
    final texture =
        three.DataTexture(
            data,
            width,
            height,
            three.RGBAFormat,
            three.UnsignedByteType,
          )
          ..magFilter = three.LinearFilter
          ..minFilter = three.LinearFilter
          ..generateMipmaps = false
          ..needsUpdate = true;
    _generatedTextures.add(texture);
    return texture;
  }

  _TextureImage? _textureImage(three.Texture texture) {
    final image = texture.image;
    if (image is! three.ImageElement) return null;
    final width = image.width.toInt();
    final height = image.height.toInt();
    final data = image.data;
    if (data is Uint8List && width > 0 && height > 0) {
      return _TextureImage(bytes: data, width: width, height: height);
    }
    if (data is List<int> && width > 0 && height > 0) {
      return _TextureImage(
        bytes: Uint8List.fromList(data),
        width: width,
        height: height,
      );
    }
    final rawUrl = image.src ?? image.url;
    final url = rawUrl is String ? rawUrl.trim() : null;
    if (url != null && _isPreviewUrl(url)) {
      return _TextureImage(url: url, width: width, height: height);
    }
    return null;
  }

  bool _isPreviewUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            uri.scheme == 'blob' ||
            uri.scheme == 'data');
  }

  void _detachTextures(three.Material material) {
    if (material is three.GroupMaterial) {
      for (final child in material.children) {
        _detachTextures(child);
      }
    }
    material
      ..matcap = null
      ..clearcoatMap = null
      ..clearcoatRoughnessMap = null
      ..clearcoatNormalMap = null
      ..displacementMap = null
      ..roughnessMap = null
      ..metalnessMap = null
      ..specularMap = null
      ..specularIntensityMap = null
      ..specularColorMap = null
      ..sheenColorMap = null
      ..anisotropyMap = null
      ..iridescenceMap = null
      ..iridescenceThicknessMap = null
      ..gradientMap = null
      ..sheenTintMap = null
      ..sheenRoughnessMap = null
      ..transmissionMap = null
      ..thicknessMap = null
      ..map = null
      ..lightMap = null
      ..aoMap = null
      ..alphaMap = null
      ..normalMap = null
      ..bumpMap = null
      ..emissiveMap = null
      ..envMap = null;
  }
}

class _OriginalMaterialState {
  final int side;
  final bool wireframe;
  final bool toneMapped;
  final double transmission;
  final three.Texture? transmissionMap;
  final double? thickness;
  final three.Texture? thicknessMap;

  const _OriginalMaterialState({
    required this.side,
    required this.wireframe,
    required this.toneMapped,
    required this.transmission,
    required this.transmissionMap,
    required this.thickness,
    required this.thicknessMap,
  });
}

class _OriginalTextureState {
  final int magFilter;
  final int minFilter;
  final bool generateMipmaps;
  final int anisotropy;

  const _OriginalTextureState({
    required this.magFilter,
    required this.minFilter,
    required this.generateMipmaps,
    required this.anisotropy,
  });
}

class _TextureImage {
  final Uint8List? bytes;
  final String? url;
  final int width;
  final int height;

  const _TextureImage({this.bytes, this.url, this.width = 0, this.height = 0});
}
