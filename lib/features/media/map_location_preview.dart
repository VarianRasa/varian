import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/domain/models/node_payload.dart';

class MapLocationPreview extends StatelessWidget {
  final MapPayload payload;
  const MapLocationPreview({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    final hasLocation =
        payload.locationTitle.trim().isNotEmpty ||
        payload.address.trim().isNotEmpty;
    if (!hasLocation) {
      return const ColoredBox(
        color: Color(0xFF1E293B),
        child: Center(
          child: Text(
            'Set location',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }
    final point = LatLng(payload.latitude, payload.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: payload.zoomLevel,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.varian',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 32,
                    height: 32,
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFFEF4444),
                      size: 32,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.black87),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs + AppSpacing.xxs / 2,
                ),
                child: Text(
                  payload.locationTitle.trim().isEmpty
                      ? payload.address
                      : payload.locationTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            right: 4,
            bottom: 2,
            child: Text(
              '© OpenStreetMap',
              style: TextStyle(color: Colors.white70, fontSize: 7),
            ),
          ),
        ],
      ),
    );
  }
}
