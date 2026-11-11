import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../api/api_client.dart';
import '../../data/models.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/workspace.dart';
import 'route_service.dart';
import 'road_route_map.dart';
import 'route_overlay.dart';

class NavigationScreen extends StatefulWidget {
  final String tripId;
  final String? stopId;
  final String? pickupId;
  const NavigationScreen({
    super.key,
    required this.tripId,
    this.stopId,
    this.pickupId,
  });
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _started = false, _loading = true;
  bool _uiVisible = true;
  String? _error;
  List<LatLng>? _route;
  Position? _position;
  StreamSubscription<Position>? _gps;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = AppScope.of(context);
      s.requireOnlineAction();
      await s.loadTrip(widget.tripId);
      final trip = s.tripById(widget.tripId);
      if (trip.status != TripStatus.inProgress &&
          trip.status != TripStatus.returning)
        throw StateError('This assignment is no longer active.');
      ReturnPickup? pickup;
      for (final candidate in trip.pickups) {
        if (candidate.id == widget.pickupId) pickup = candidate;
      }
      if (widget.pickupId != null &&
          (pickup == null ||
              pickup.status != 'assigned' ||
              !pickup.hasCoordinates))
        throw StateError(
          'Pickup coordinates are unavailable or collection is already recorded.',
        );
      Stop? stop;
      for (final candidate in trip.stops) {
        if (candidate.id == widget.stopId) stop = candidate;
      }
      if (widget.stopId != null && (stop == null || !stop.hasCoordinates))
        throw StateError('Stop coordinates are unavailable.');
      if (widget.stopId == null &&
          widget.pickupId == null &&
          !trip.hasWarehouseCoordinates)
        throw StateError('Warehouse coordinates are unavailable.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw StateError('Location permission is required for your route.');
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final destination = pickup != null
          ? LatLng(pickup.lat, pickup.lng)
          : stop == null
          ? LatLng(trip.warehouseLat, trip.warehouseLng)
          : LatLng(stop.lat, stop.lng);
      final route = await RoadRouteService().route(
        LatLng(p.latitude, p.longitude),
        destination,
      );
      if (!mounted) return;
      setState(() {
        _position = p;
        _route = route;
      });
      await _gps?.cancel();
      _gps =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (p) {
              if (mounted) setState(() => _position = p);
            },
            onError: (_) {
              if (mounted)
                setState(
                  () =>
                      _error = 'GPS unavailable. Route position may be stale.',
                );
            },
          );
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final trip = s.findTrip(widget.tripId);
    final active =
        trip != null &&
        (trip.status == TripStatus.inProgress ||
            trip.status == TripStatus.returning);
    ReturnPickup? pickupDestination;
    for (final pickup in trip?.pickups ?? <ReturnPickup>[]) {
      if (pickup.id == widget.pickupId) pickupDestination = pickup;
    }
    Stop? destination;
    for (final stop in trip?.stops ?? <Stop>[]) {
      if (stop.id == widget.stopId) destination = stop;
    }
    final mapHeader = Row(
      children: [
        _MapControl(
          tooltip: 'Back to trip',
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Material(
            color: P.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                widget.stopId == null && widget.pickupId == null
                    ? 'Return to warehouse'
                    : 'Road route',
                style: T.bodyBold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _MapControl(
          tooltip: 'Refresh route',
          icon: Icons.refresh,
          onPressed: _loading || !active || s.isOffline ? null : _load,
        ),
      ],
    );
    final hasRoute = _route != null && _route!.isNotEmpty && active;
    final details = Material(
      color: P.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Text('Destination', style: T.smallBold),
            const SizedBox(height: 6),
            Text(
              !active
                  ? 'Assignment is no longer active'
                  : destination?.customer ??
                        pickupDestination?.customer ??
                        trip.warehouse,
              style: T.title,
            ),
            if (destination != null)
              Text(destination.orderLabel, style: T.small),
            if (destination != null || pickupDestination != null)
              Text(
                destination?.address ?? pickupDestination!.address,
                style: T.body,
              ),
            const SizedBox(height: 8),
            if (!active)
              Text(
                'Return to Trips to see your current assignment.',
                style: T.small,
              )
            else if (s.isOffline)
              const FeedbackStrip(
                'Offline. Route updates require an internet connection.',
                warning: true,
              )
            else if (_error != null)
              FeedbackStrip(_error!)
            else
              Text(
                _loading
                    ? 'Finding your road route...'
                    : 'Route preview with live GPS.',
                style: T.small,
              ),
          ],
        ),
      ),
    );
    final map = Stack(
      fit: StackFit.expand,
      children: [
        if (hasRoute)
          RoadRouteMap(
            route: _route!,
            position: _position,
            header: mapHeader,
            onVisibilityChanged: (visible) =>
                setState(() => _uiVisible = visible),
          )
        else
          ColoredBox(
            color: P.bg,
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Icon(Icons.map_outlined, size: 48, color: P.muted),
            ),
          ),
        if (!hasRoute)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.all(16),
              child: mapHeader,
            ),
          ),
      ],
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 900;
          final warning = !active
              ? 'Assignment is no longer active. Return to Trips.'
              : s.isOffline
              ? 'Offline. Route updates require an internet connection.'
              : _error;
          return Stack(
            fit: StackFit.expand,
            children: [
              map,
              Positioned(
                left: wide ? null : 0,
                right: 0,
                bottom: 0,
                top: wide ? 110 : null,
                width: wide ? 300 : null,
                child: RouteOverlay(
                  // Before a map exists, keep recovery actions visible.
                  visible: !hasRoute || _uiVisible,
                  child: SafeArea(
                    top: false,
                    // Leave map attribution accessible below the panel.
                    minimum: const EdgeInsets.only(bottom: 36),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: bounds.maxHeight * (wide ? .75 : .38),
                      ),
                      child: details,
                    ),
                  ),
                ),
              ),
              if (hasRoute && !_uiVisible && warning != null)
                Positioned(
                  top: 0,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    bottom: false,
                    child: FeedbackStrip(warning, warning: s.isOffline),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _MapControl({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: P.surface,
    elevation: 2,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
  );
}
