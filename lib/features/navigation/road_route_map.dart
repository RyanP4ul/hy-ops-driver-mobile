import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/palette.dart';
import 'route_overlay.dart';

/// A location-following camera that stays mounted in distraction-free mode.
class RoadRouteMap extends StatefulWidget {
  final List<LatLng> route;
  final Position? position;
  final TileProvider? tileProvider;
  final Widget? header;
  final ValueChanged<bool>? onVisibilityChanged;
  const RoadRouteMap({
    super.key,
    required this.route,
    this.position,
    this.tileProvider,
    this.header,
    this.onVisibilityChanged,
  });

  @override
  State<RoadRouteMap> createState() => _RoadRouteMapState();
}

class _RoadRouteMapState extends State<RoadRouteMap>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _motion;
  bool _ready = false, _paused = false;
  bool _uiVisible = true;
  double _heading = 0;
  LatLng _from = const LatLng(0, 0), _to = const LatLng(0, 0);
  double _fromZoom = 0, _toZoom = 0, _fromRotation = 0, _rotationDelta = 0;

  @override
  void initState() {
    super.initState();
    _recordHeading();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addListener(_animate);
  }

  LatLng? get _location {
    final p = widget.position;
    if (p == null ||
        !p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180) {
      return null;
    }
    return LatLng(p.latitude, p.longitude);
  }

  void _recordHeading() {
    final p = widget.position;
    // GPS course is unreliable while stationary. Keep the last useful direction.
    if (p != null &&
        p.speed.isFinite &&
        p.speed >= 1 &&
        p.heading.isFinite &&
        p.heading >= 0 &&
        p.heading < 360) {
      _heading = p.heading;
    }
  }

  @override
  void didUpdateWidget(covariant RoadRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _recordHeading();
    if (identical(oldWidget.position, widget.position) &&
        identical(oldWidget.route, widget.route)) {
      return;
    }
    if (!_paused) {
      _follow();
    }
  }

  void _follow({bool animate = true}) {
    final location = _location;
    if (!_ready || location == null) return;
    _motion.stop();
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _map.moveAndRotate(location, 16.5, -_heading);
      return;
    }
    final camera = _map.camera;
    _from = camera.center;
    _to = location;
    _fromZoom = camera.zoom;
    _toZoom = 16.5;
    _fromRotation = camera.rotation;
    _rotationDelta = (-_heading - _fromRotation + 540) % 360 - 180;
    _motion.forward(from: 0);
  }

  void _animate() {
    if (!_ready || !mounted) return;
    final t = Curves.easeInOutCubic.transform(_motion.value);
    final longitudeDelta = (_to.longitude - _from.longitude + 540) % 360 - 180;
    final longitude = (_from.longitude + longitudeDelta * t + 540) % 360 - 180;
    _map.moveAndRotate(
      LatLng(_from.latitude + (_to.latitude - _from.latitude) * t, longitude),
      _fromZoom + (_toZoom - _fromZoom) * t,
      _fromRotation + _rotationDelta * t,
    );
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
    widget.onVisibilityChanged?.call(_uiVisible);
  }

  @override
  void dispose() {
    _ready = false;
    _motion.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Semantics(
        label: 'Road route map',
        hint: _uiVisible
            ? 'Tap to hide route controls'
            : 'Tap to show route controls',
        onTap: _toggleUi,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _location ?? widget.route.first,
            initialZoom: 16.5,
            minZoom: 3,
            maxZoom: 19,
            // Use the map's tap recognizer so drags, pinches, long presses and
            // double-tap zoom do not toggle the interface.
            onTap: (tapPosition, point) => _toggleUi(),
            onMapReady: () {
              _ready = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _follow(animate: false);
              });
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && !_paused) {
                _motion.stop();
                setState(() => _paused = true);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.hyops.driver',
              tileProvider: widget.tileProvider,
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.route,
                  strokeWidth: 5,
                  color: P.primary,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.route.last,
                  width: 44,
                  height: 44,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
                if (_location != null)
                  Marker(
                    point: _location!,
                    width: 44,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: P.surface,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6),
                        ],
                      ),
                      child: Transform.rotate(
                        angle: _heading * math.pi / 180,
                        child: Icon(
                          Icons.navigation,
                          color: P.primary,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Map attribution remains available in either visibility state.
            const SafeArea(
              top: false,
              child: RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ),
          ],
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: RouteOverlay(
          visible: _uiVisible,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.header != null) ...[
                  widget.header!,
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Material(
                      color: P.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          _paused
                              ? 'Camera paused'
                              : _location == null
                              ? 'Waiting for location'
                              : 'Following location',
                          style: T.small,
                        ),
                      ),
                    ),
                    if (_paused)
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _paused = false);
                          _follow();
                        },
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('Recenter'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: P.surface,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text('Tap map to hide controls', style: T.small),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
