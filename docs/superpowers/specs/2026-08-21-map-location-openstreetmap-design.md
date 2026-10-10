# Map Location OpenStreetMap Design

## Goal

Upgrade Map Location into a usable location editor using free OpenStreetMap tiles and Nominatim geocoding, while keeping canvas rendering lightweight.

## Scope

- Keep `flutter_map` and `latlong2` for interactive map rendering.
- Use the existing `http` dependency for Nominatim search and reverse geocoding.
- Keep the canvas preview as a lightweight painted preview; open the interactive editor from the map node or inspector.
- Persist title, address, latitude, longitude, and zoom in `MapPayload`.
- Add search, result selection, marker dragging/tapping, reverse geocoding, zoom persistence, OSM attribution, inspector controls, export metadata, and search metadata.

## Data and Validation

`MapPayload` remains the public data boundary with these fields:

- `locationTitle`
- `address`
- `latitude`
- `longitude`
- `zoomLevel`

Valid ranges:

- latitude: -90 to 90
- longitude: -180 to 180
- zoom: 1 to 19

Invalid or non-finite values are rejected before node updates. JSON parsing falls back safely to valid defaults. Existing documents remain compatible.

## Geocoding Service

Add a focused `MapLocationService` responsible for:

- Nominatim address search by a submitted query.
- Nominatim reverse geocoding by latitude and longitude.
- JSON decoding into a small internal result model.
- Request timeout and user-visible error results.
- An application User-Agent/header required by the public service.
- No autocomplete requests on every keystroke; search runs after a short debounce and only for a non-empty query.

The service does not own widget state or node persistence. It is injectable in tests and uses the existing `http` package.

## Map Viewer

`MapViewerScreen` will:

- Maintain text controllers in `initState` and dispose them correctly.
- Provide a search field and submit/search action.
- Show search results and move the map to the selected result.
- Show a draggable marker and update coordinates after tap or drag completion.
- Reverse geocode after a point change settles, updating the address without overwriting an explicitly edited title.
- Track camera zoom and save the current zoom.
- Validate all values before returning the updated payload.
- Show loading, empty, timeout, and failure states without crashing.
- Display OpenStreetMap attribution and a Nominatim attribution note.
- Preserve the existing SAVE callback flow.

Device location is excluded from this iteration to avoid platform permissions and an additional dependency.

## Inspector Panel

The Map Location section will add:

- Location name field.
- Address field.
- Latitude field.
- Longitude field.
- Zoom field or compact zoom control.
- Reverse-geocode action using the current coordinates.
- Open Map Editor action.

Updates use the existing immutable node update pattern. Invalid numeric input does not overwrite the last valid payload and shows an inline validation state.

## Canvas and Integrations

- Keep the current lightweight canvas preview and marker label.
- Ensure preview displays the current address/title data where space permits.
- Export includes title, address, latitude, longitude, and zoom.
- Search indexes location title and address.
- Existing node spawning and map editor navigation remain compatible.

## Error Handling

Network errors, timeouts, malformed responses, empty results, and invalid coordinates produce recoverable UI states. Failed reverse geocoding preserves the selected coordinates and existing address. No API key or secret is required.

## Testing

Add tests for:

- `MapPayload` round-trip, cloning, and invalid-value handling.
- Nominatim service request parsing, empty results, malformed responses, timeout/error mapping, and request headers.
- Map viewer save behavior for coordinate and zoom changes.
- Inspector coordinate and reverse-geocode updates where existing widget-test conventions support it.
- Export and search inclusion of address and coordinates.

## Non-goals

- Google Maps or Mapbox integration.
- Offline tile caching.
- Device GPS/location permissions.
- Real map tiles painted directly into the canvas preview.
- Continuous autocomplete requests.
