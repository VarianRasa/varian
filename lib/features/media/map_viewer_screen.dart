import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/media/map_location_service.dart';

class MapViewerScreen extends StatefulWidget {
  final MapPayload initialPayload;
  final void Function(MapPayload updatedPayload) onSaveAndExit;
  final MapLocationService? locationService;

  const MapViewerScreen({
    super.key,
    required this.initialPayload,
    required this.onSaveAndExit,
    this.locationService,
  });

  @override
  State<MapViewerScreen> createState() => _MapViewerScreenState();
}

class _MapViewerScreenState extends State<MapViewerScreen> {
  late MapPayload _payload;
  late LatLng _center;
  late final TextEditingController _titleController;
  late final TextEditingController _addressController;
  late final TextEditingController _searchController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  final MapController _mapController = MapController();
  late final MapLocationService _locationService;
  List<MapLocationResult> _results = const [];
  bool _isSearching = false;
  Timer? _reverseTimer;
  String? _error;
  String? _coordinateError;
  bool _editingCoordinates = false;

  @override
  void initState() {
    super.initState();
    _payload = widget.initialPayload;
    _center = LatLng(_payload.latitude, _payload.longitude);
    _titleController = TextEditingController(text: _payload.locationTitle);
    _addressController = TextEditingController(text: _payload.address);
    _searchController = TextEditingController();
    _latitudeController = TextEditingController(
      text: _payload.latitude.toStringAsFixed(6),
    );
    _longitudeController = TextEditingController(
      text: _payload.longitude.toStringAsFixed(6),
    );
    _locationService = widget.locationService ?? MapLocationService();
  }

  @override
  void dispose() {
    _reverseTimer?.cancel();
    _titleController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _updatePoint(
    LatLng point, {
    bool reverse = true,
    bool recenter = false,
  }) {
    setState(() {
      _center = point;
      _payload = MapPayload(
        locationTitle: _payload.locationTitle,
        address: _payload.address,
        latitude: point.latitude,
        longitude: point.longitude,
        zoomLevel: _payload.zoomLevel,
      );
      _latitudeController.text = point.latitude.toStringAsFixed(6);
      _longitudeController.text = point.longitude.toStringAsFixed(6);
      _coordinateError = null;
    });
    if (recenter) _mapController.move(point, _payload.zoomLevel);
    if (!reverse) return;
    _reverseTimer?.cancel();
    _reverseTimer = Timer(const Duration(milliseconds: 700), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    try {
      final result = await _locationService.reverse(
        _payload.latitude,
        _payload.longitude,
      );
      if (!mounted || result == null) return;
      setState(() {
        _addressController.text = result.displayName;
        _payload = MapPayload(
          locationTitle: _payload.locationTitle,
          address: result.displayName,
          latitude: _payload.latitude,
          longitude: _payload.longitude,
          zoomLevel: _payload.zoomLevel,
        );
        _error = null;
      });
    } on MapLocationServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _search() async {
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final results = await _locationService.search(_searchController.text);
      if (mounted) setState(() => _results = results);
    } on MapLocationServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectResult(MapLocationResult result) {
    _addressController.text = result.displayName;
    _updatePoint(LatLng(result.latitude, result.longitude), reverse: false);
    setState(() {
      _payload = MapPayload(
        locationTitle: _payload.locationTitle,
        address: result.displayName,
        latitude: result.latitude,
        longitude: result.longitude,
        zoomLevel: _payload.zoomLevel,
      );
      _results = const [];
    });
  }

  void _toggleManualCoordinates() {
    setState(() {
      _editingCoordinates = !_editingCoordinates;
      _coordinateError = null;
      if (_editingCoordinates) {
        _latitudeController.text = _payload.latitude.toStringAsFixed(6);
        _longitudeController.text = _payload.longitude.toStringAsFixed(6);
      }
    });
  }

  void _applyManualCoordinates() {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || !MapPayload.isValidLatitude(latitude)) {
      setState(() => _coordinateError = 'Enter a latitude from -90 to 90.');
      return;
    }
    if (longitude == null || !MapPayload.isValidLongitude(longitude)) {
      setState(() => _coordinateError = 'Enter a longitude from -180 to 180.');
      return;
    }
    _updatePoint(LatLng(latitude, longitude), reverse: false, recenter: true);
    setState(() => _editingCoordinates = false);
  }

  String get _selectedCoordinateSemantics =>
      'Selected map coordinates: ${_payload.latitude.toStringAsFixed(6)}, ${_payload.longitude.toStringAsFixed(6)}';

  void _saveAndExit() {
    widget.onSaveAndExit(_payload);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final titleField = UiTextField(
      controller: _titleController,
      label: 'Location Title',
      onChanged: (value) => setState(
        () => _payload = MapPayload(
          locationTitle: value,
          address: _payload.address,
          latitude: _payload.latitude,
          longitude: _payload.longitude,
          zoomLevel: _payload.zoomLevel,
        ),
      ),
    );
    final addressField = UiTextField(
      controller: _addressController,
      label: 'Address',
      onChanged: (value) => setState(
        () => _payload = MapPayload(
          locationTitle: _payload.locationTitle,
          address: value,
          latitude: _payload.latitude,
          longitude: _payload.longitude,
          zoomLevel: _payload.zoomLevel,
        ),
      ),
    );
    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: _payload.zoomLevel,
        minZoom: 1,
        maxZoom: 19,
        onTap: (_, point) => _updatePoint(point),
        onPositionChanged: (position, _) {
          final zoom = position.zoom;
          if (MapPayload.isValidZoom(zoom) && zoom != _payload.zoomLevel) {
            setState(
              () => _payload = MapPayload(
                locationTitle: _payload.locationTitle,
                address: _payload.address,
                latitude: _payload.latitude,
                longitude: _payload.longitude,
                zoomLevel: zoom,
              ),
            );
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.varian',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _center,
              width: 40,
              height: 40,
              child: Icon(Icons.location_on, color: tokens.danger, size: 40),
            ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
    final coordinateSummary = Semantics(
      label: _selectedCoordinateSemantics,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            '${_payload.latitude.toStringAsFixed(6)}, ${_payload.longitude.toStringAsFixed(6)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
        ),
      ),
    );
    final headerControls = Padding(
      padding: AppResponsive.pagePadding(context),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: UiTextField(
                  controller: _searchController,
                  label: 'Search address',
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              UiIconButton(
                icon: Icons.search,
                tooltip: 'Search address',
                onPressed: _isSearching ? null : _search,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: UiButton(
              onPressed: _toggleManualCoordinates,
              variant: UiButtonVariant.outline,
              selected: _editingCoordinates,
              prefix: const Icon(Icons.edit_location_alt_outlined),
              child: const Text('Set coordinates manually'),
            ),
          ),
          if (_editingCoordinates) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: UiTextField(
                    key: const ValueKey('map-latitude-field'),
                    controller: _latitudeController,
                    label: 'Latitude',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: UiTextField(
                    key: const ValueKey('map-longitude-field'),
                    controller: _longitudeController,
                    label: 'Longitude',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_coordinateError != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _coordinateError!,
                  style: TextStyle(color: tokens.danger),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: UiButton(
                onPressed: _applyManualCoordinates,
                prefix: const Icon(Icons.my_location_outlined),
                child: const Text('Update map location'),
              ),
            ),
          ],
          if (_isSearching)
            const UiLinearProgressIndicator(
              semanticsLabel: 'Searching addresses',
            ),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: TextStyle(color: tokens.danger)),
            ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return UiButton(
                    onPressed: () => _selectResult(result),
                    variant: UiButtonVariant.ghost,
                    mainAxisSize: MainAxisSize.max,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        result.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
    final locationFields = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.compact;
        return Padding(
          padding: EdgeInsets.all(
            AppResponsive.isCompact(context) ? AppSpacing.md : AppSpacing.page,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    titleField,
                    const SizedBox(height: AppSpacing.sm),
                    addressField,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleField),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: addressField),
                  ],
                ),
        );
      },
    );
    return UiPageScaffold(
      title: Text(
        'MAP LOCATION',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: 'Back',
      ),
      actions: [
        UiButton(
          onPressed: _saveAndExit,
          prefix: const Icon(Icons.check, size: 16),
          child: const Text('SAVE'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 480) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  headerControls,
                  SizedBox(height: 200, child: map),
                  coordinateSummary,
                  locationFields,
                ],
              ),
            );
          }
          return Column(
            children: [
              headerControls,
              Expanded(child: map),
              coordinateSummary,
              locationFields,
            ],
          );
        },
      ),
    );
  }
}
