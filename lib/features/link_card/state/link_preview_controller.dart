import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/backend_config.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../../canvas/state/document_nodes_provider.dart';
import '../data/link_preview_service.dart';
import '../domain/link_url_policy.dart';

final linkPreviewServiceProvider = Provider<LinkPreviewService>((ref) {
  final config = ref.watch(backendConfigProvider);
  if (!kIsWeb || !config.isSupabaseConfigured) {
    return LinkPreviewService();
  }
  final endpoint = LinkPreviewProxy.endpointFor(config.supabaseUrl);
  if (endpoint == null || config.supabaseAnonKey.trim().isEmpty) {
    return LinkPreviewService();
  }
  return LinkPreviewService(
    proxy: LinkPreviewProxy(
      endpoint: endpoint,
      anonKey: config.supabaseAnonKey.trim(),
    ),
  );
});

final linkPreviewControllerProvider =
    StateNotifierProvider<LinkPreviewController, Map<String, int>>(
      (ref) => LinkPreviewController(ref),
    );

class LinkPreviewController extends StateNotifier<Map<String, int>> {
  final Ref _ref;

  LinkPreviewController(this._ref) : super(const {});

  Future<void> submit(CanvasNode node, String input) async {
    final uri = normalizeLinkUrl(input);
    final payload = node.payload as LinkPayload;
    final normalized = uri.toString();
    final cleared = payload
        .clearPreview(url: normalized)
        .copyWith(previewStatus: LinkPreviewStatus.loading);
    _updateExisting(node.id, node.copyWith(payload: cleared));
    await _fetch(node.id, normalized);
  }

  Future<void> refresh(CanvasNode node) async {
    final payload = node.payload as LinkPayload;
    final uri = normalizeLinkUrl(payload.url);
    final loading = payload.copyWith(
      previewStatus: LinkPreviewStatus.loading,
      clearPreviewError: true,
    );
    _updateExisting(node.id, node.copyWith(payload: loading));
    await _fetch(node.id, uri.toString());
  }

  void cancel(String nodeId) {
    state = {...state, nodeId: (state[nodeId] ?? 0) + 1};
  }

  Future<void> _fetch(String nodeId, String url) async {
    final generation = (state[nodeId] ?? 0) + 1;
    state = {...state, nodeId: generation};
    try {
      final metadata = await _ref.read(linkPreviewServiceProvider).fetch(url);
      final current = _current(nodeId, generation, url);
      if (current == null) return;
      final payload = current.payload as LinkPayload;
      _updateExisting(
        nodeId,
        current.copyWith(
          payload: payload.copyWith(
            title: metadata.title,
            description: metadata.description,
            faviconUrl: metadata.faviconUri?.toString(),
            imageUrl: metadata.imageUri?.toString(),
            siteName: metadata.siteName,
            mediaType: metadata.mediaType.name,
            fetchedAt: DateTime.now().toUtc(),
            previewStatus: LinkPreviewStatus.ready,
            clearDescription: metadata.description == null,
            clearFaviconUrl: metadata.faviconUri == null,
            clearImageUrl: metadata.imageUri == null,
            clearPreviewError: true,
          ),
        ),
      );
    } catch (error) {
      final current = _current(nodeId, generation, url);
      if (current == null) return;
      final payload = current.payload as LinkPayload;
      final message = error is LinkPreviewException
          ? error.message
          : error is LinkUrlValidationException
          ? error.message
          : 'Preview tidak dapat dimuat.';
      _updateExisting(
        nodeId,
        current.copyWith(
          payload: payload.copyWith(
            previewStatus: LinkPreviewStatus.error,
            previewError: message,
          ),
        ),
      );
    }
  }

  CanvasNode? _current(String nodeId, int generation, String url) {
    if (state[nodeId] != generation) return null;
    for (final node in _ref.read(documentNodesProvider)) {
      if (node.id == nodeId &&
          node.payload is LinkPayload &&
          (node.payload as LinkPayload).url == url) {
        return node;
      }
    }
    return null;
  }

  void _updateExisting(String nodeId, CanvasNode updated) {
    if (_ref.read(documentNodesProvider).any((node) => node.id == nodeId)) {
      _ref.read(documentNodesProvider.notifier).updateNode(updated);
    }
  }
}
