import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi_alloc;
import 'package:flutter/foundation.dart';
import 'package:three_js/three_js.dart' as three;

typedef _GlTexSubImage2DNativeFunction =
    ffi.Void Function(
      ffi.Uint32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
    );
typedef _GlTexSubImage2DFunction =
    void Function(
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      ffi.Pointer<ffi.Void>,
    );

class Model3DTextureUploadRepair {
  static const _rgba = 0x1908;
  static const _unsignedByte = 0x1401;
  static const _float = 0x1406;

  _GlTexSubImage2DFunction? _upload;
  final Map<three.Texture, Function?> _previousCallbacks = {};
  final Map<three.Texture, Function> _repairCallbacks = {};
  final Map<three.Texture, Function> _disposeListeners = {};
  bool _reportedFailure = false;

  bool get isSupported => !kIsWeb && Platform.isWindows;

  void attach(three.Object3D model) {
    if (!isSupported) return;
    model.traverse((object) {
      final material = object.material;
      if (material != null) {
        for (final texture in _texturesFor(material)) {
          if (texture != null) _attachTexture(texture);
        }
      }
      if (object is three.SkinnedMesh) {
        final skeleton = object.skeleton;
        if (skeleton != null) {
          if (skeleton.boneTexture == null) skeleton.computeBoneTexture();
          final boneTexture = skeleton.boneTexture;
          if (boneTexture != null) _attachTexture(boneTexture);
        }
      }
    });
  }

  void _attachTexture(three.Texture texture) {
    final existingCallback = _repairCallbacks[texture];
    if (existingCallback != null) {
      if (identical(texture.onUpdate, existingCallback)) return;
      _detachTexture(texture);
    }
    final previous = texture.onUpdate;
    late final Function repairCallback;
    repairCallback = (_) {
      // The renderer has just bound this texture. Repair before a preserved
      // callback can change the active texture or pixel-store state.
      if (_repairCallbacks.containsKey(texture)) _repair(texture);
      if (previous != null) previous(texture);
    };
    late final Function disposeListener;
    disposeListener = (_) => _detachTexture(texture);

    _previousCallbacks[texture] = previous;
    _repairCallbacks[texture] = repairCallback;
    _disposeListeners[texture] = disposeListener;
    texture
      ..onUpdate = repairCallback
      ..addEventListener('dispose', disposeListener);
  }

  void _detachTexture(three.Texture texture) {
    final repairCallback = _repairCallbacks.remove(texture);
    final previous = _previousCallbacks.remove(texture);
    final disposeListener = _disposeListeners.remove(texture);
    if (disposeListener != null) {
      texture.removeEventListener('dispose', disposeListener);
    }
    if (repairCallback != null && identical(texture.onUpdate, repairCallback)) {
      texture.onUpdate = previous;
    }
  }

  void _repair(three.Texture texture) {
    try {
      if (texture is three.CubeTexture ||
          texture is three.DataArrayTexture ||
          texture is three.Data3DTexture) {
        return;
      }
      final image = texture.image;
      if (image is! three.ImageElement ||
          texture.format != three.RGBAFormat ||
          (texture.type != three.UnsignedByteType &&
              texture.type != three.FloatType)) {
        return;
      }
      final width = image.width.toInt();
      final height = image.height.toInt();
      if (width <= 0 || height <= 0) return;

      final data = image.data;
      if (data is! TypedData) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final bytesPerComponent = texture.type == three.FloatType ? 4 : 1;
      final requiredBytes = width * height * 4 * bytesPerComponent;
      if (bytes.length < requiredBytes) return;

      final pointer = ffi_alloc.calloc<ffi.Uint8>(requiredBytes);
      final glType = texture.type == three.FloatType ? _float : _unsignedByte;
      try {
        pointer.asTypedList(requiredBytes).setRange(0, requiredBytes, bytes);
        (_upload ??= _loadUpload())(
          0x0DE1,
          0,
          0,
          0,
          width,
          height,
          _rgba,
          glType,
          pointer.cast<ffi.Void>(),
        );
      } finally {
        ffi_alloc.calloc.free(pointer);
      }
    } catch (error) {
      if (!_reportedFailure) {
        _reportedFailure = true;
        debugPrint('[Model3D] Windows texture upload repair failed: $error');
      }
    }
  }

  _GlTexSubImage2DFunction _loadUpload() {
    final library = ffi.DynamicLibrary.open('libGLESv2.dll');
    return library.lookupFunction<
      _GlTexSubImage2DNativeFunction,
      _GlTexSubImage2DFunction
    >('glTexSubImage2D');
  }

  Iterable<three.Texture?> _texturesFor(three.Material material) sync* {
    if (material is three.GroupMaterial) {
      for (final child in material.children) {
        yield* _texturesFor(child);
      }
    }
    yield material.map;
    yield material.lightMap;
    yield material.aoMap;
    yield material.emissiveMap;
    yield material.bumpMap;
    yield material.normalMap;
    yield material.displacementMap;
    yield material.roughnessMap;
    yield material.metalnessMap;
    yield material.alphaMap;
    yield material.envMap;
    yield material.matcap;
    yield material.clearcoatMap;
    yield material.clearcoatRoughnessMap;
    yield material.clearcoatNormalMap;
    yield material.transmissionMap;
    yield material.thicknessMap;
    yield material.specularMap;
    yield material.specularIntensityMap;
    yield material.specularColorMap;
    yield material.sheenColorMap;
    yield material.sheenRoughnessMap;
    yield material.sheenTintMap;
    yield material.anisotropyMap;
    yield material.iridescenceMap;
    yield material.iridescenceThicknessMap;
    yield material.gradientMap;
  }

  void dispose() {
    for (final texture in _repairCallbacks.keys.toList()) {
      _detachTexture(texture);
    }
  }
}
