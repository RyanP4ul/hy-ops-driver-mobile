import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../api/api_client.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../services/external_actions.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/workspace.dart';
import 'road_route_map.dart';
import 'route_overlay.dart';
import 'route_service.dart';

class NavigationScreen extends StatefulWidget {
  final String tripId;
  final String? stopId;
  final String? pickupId;
  final RouteService? routeService;
  final TileProvider? tileProvider;
  final Future<Position> Function()? currentPosition;
  final Stream<Position> Function()? positionStream;

  const NavigationScreen({
    super.key,
    required this.tripId,
    this.stopId,
    this.pickupId,
    this.routeService,
    this.tileProvider,
    this.currentPosition,
    this.positionStream,
  });
  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  bool _started = false, _loading = true;
  bool _uiVisible = true;
  bool _cardHidden = false;
  String? _error;
  List<LatLng>? _route;
  double? _distanceMeters;
  double? _durationSeconds;
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
          trip.status != TripStatus.returning) {
        throw StateError('This assignment is no longer active.');
      }
      ReturnPickup? pickup;
      for (final candidate in trip.pickups) {
        if (candidate.id == widget.pickupId) pickup = candidate;
      }
      if (widget.pickupId != null &&
          (pickup == null ||
              pickup.status != 'assigned' ||
              !pickup.hasCoordinates)) {
        throw StateError(
          'Pickup coordinates are unavailable or collection is already recorded.',
        );
      }
      Stop? stop;
      for (final candidate in trip.stops) {
        if (candidate.id == widget.stopId) stop = candidate;
      }
      if (widget.stopId != null && (stop == null || !stop.hasCoordinates)) {
        throw StateError('Stop coordinates are unavailable.');
      }
      if (widget.stopId == null &&
          widget.pickupId == null &&
          !trip.hasWarehouseCoordinates) {
        throw StateError('Warehouse coordinates are unavailable.');
      }
      late final Position p;
      if (widget.currentPosition != null) {
        p = await widget.currentPosition!();
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw StateError('Location permission is required for your route.');
        }
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      }
      final destination = pickup != null
          ? LatLng(pickup.lat, pickup.lng)
          : stop == null
          ? LatLng(trip.warehouseLat, trip.warehouseLng)
          : LatLng(stop.lat, stop.lng);
      final summary = await (widget.routeService ?? RoadRouteService())
          .routeSummary(LatLng(p.latitude, p.longitude), destination);
      if (!mounted) return;
      setState(() {
        _position = p;
        _route = summary.points;
        _distanceMeters = summary.distanceMeters;
        _durationSeconds = summary.durationSeconds;
      });
      await _gps?.cancel();
      final stream =
          widget.positionStream?.call() ??
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          );
      _gps = stream.listen(
            (p) {
              if (mounted) setState(() => _position = p);
            },
            onError: (_) {
              if (mounted) {
                setState(
                  () =>
                      _error = 'GPS unavailable. Route position may be stale.',
                );
              }
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
    final c = HyOpsColors.of(context);
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

    final destPhone = destination?.phone ?? pickupDestination?.phone ?? '';

    final distanceText = _distanceMeters != null
        ? formatDistance(_distanceMeters!)
        : '';
    final durationText = _durationSeconds != null
        ? formatDuration(_durationSeconds!)
        : '';
    final etaBadge = [
      if (distanceText.isNotEmpty) distanceText,
      if (durationText.isNotEmpty) durationText,
    ].join(' · ');

    final mapHeader = Row(
      children: [
        _MapControl(
          tooltip: 'Back to trip',
          icon: Ic.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: c.surface,
            elevation: 2,
            shadowColor: Colors.black26,
            shape: StadiumBorder(side: BorderSide(color: c.line)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                widget.stopId == null && widget.pickupId == null
                    ? 'Return to warehouse'
                    : 'Road route',
                style: T.bodyBoldFor(c),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _MapControl(
          tooltip: 'Refresh route',
          icon: Ic.refresh,
          onPressed: _loading || !active || s.isOffline ? null : _load,
        ),
      ],
    );

    final hasRoute = _route != null && _route!.isNotEmpty && active;
    final destinationTitle = !active
        ? 'Assignment is no longer active'
        : destination?.customer ??
              pickupDestination?.customer ??
              trip.warehouse;
    final destinationAddress = destination != null || pickupDestination != null
        ? (destination?.address ?? pickupDestination!.address)
        : null;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 900;
          final warning = !active
              ? 'Assignment is no longer active. Return to Trips.'
              : s.isOffline
              ? 'Offline. Route updates require an internet connection.'
              : _error;
          final dockedReserve = !wide && (!hasRoute || _uiVisible)
              ? (_cardHidden
                    ? 68.0
                    : (bounds.maxHeight * 0.25).clamp(150.0, 230.0).toDouble())
              : 0.0;

          final map = Stack(
            fit: StackFit.expand,
            children: [
              if (hasRoute)
                RoadRouteMap(
                  route: _route!,
                  position: _position,
                  tileProvider: widget.tileProvider,
                  header: mapHeader,
                  attributionBottomOffset: dockedReserve,
                  onVisibilityChanged: (visible) =>
                      setState(() => _uiVisible = visible),
                )
              else
                ColoredBox(
                  color: c.bg,
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Icon(Ic.map, size: 48, color: c.muted),
                  ),
                ),
              if (!hasRoute)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: mapHeader,
                  ),
                ),
            ],
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              map,
              Positioned(
                left: wide ? null : 0,
                right: wide ? 16 : 0,
                bottom: wide ? 16 : 0,
                width: wide ? 340 : null,
                child: RouteOverlay(
                  // Before a map exists, keep recovery actions visible.
                  visible: !hasRoute || _uiVisible,
                  child: _RouteBottomCard(
                    collapsed: _cardHidden,
                    onCollapsedChanged: (hidden) =>
                        setState(() => _cardHidden = hidden),
                    wide: wide,
                    maxExpandedHeight: bounds.maxHeight * (wide ? 0.72 : 0.44),
                    loading: _loading,
                    active: active,
                    offline: s.isOffline,
                    error: _error,
                    destinationTitle: destinationTitle,
                    orderLabel: destination?.orderLabel,
                    address: destinationAddress,
                    etaBadge: etaBadge,
                    onCall: destPhone.isNotEmpty
                        ? () async {
                            final ok = await callPhoneNumber(destPhone);
                            if (!ok && context.mounted) {
                              toast(
                                context,
                                'Dialer unavailable (${formatPhoneDisplay(destPhone)})',
                              );
                            }
                          }
                        : null,
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

class _RouteBottomCard extends StatefulWidget {
  final bool collapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool wide;
  final double maxExpandedHeight;
  final bool loading;
  final bool active;
  final bool offline;
  final String? error;
  final String destinationTitle;
  final String? orderLabel;
  final String? address;
  final String etaBadge;
  final VoidCallback? onCall;

  const _RouteBottomCard({
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.wide,
    required this.maxExpandedHeight,
    required this.loading,
    required this.active,
    required this.offline,
    required this.error,
    required this.destinationTitle,
    required this.orderLabel,
    required this.address,
    required this.etaBadge,
    required this.onCall,
  });

  @override
  State<_RouteBottomCard> createState() => _RouteBottomCardState();
}

class _RouteBottomCardState extends State<_RouteBottomCard> {
  double _dragOffset = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      if (widget.collapsed) {
        _dragOffset = (_dragOffset + details.delta.dy).clamp(-72.0, 0.0);
      } else {
        _dragOffset = (_dragOffset + details.delta.dy).clamp(0.0, 220.0);
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final current = _dragOffset;
    setState(() => _dragOffset = 0);
    if (widget.collapsed) {
      if (velocity < -240 || current < -24) {
        widget.onCollapsedChanged(false);
      }
    } else {
      if (velocity > 280 || current > 44) {
        widget.onCollapsedChanged(true);
      }
    }
  }

  void _onVerticalDragCancel() {
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: widget.wide
          ? BorderRadius.circular(16)
          : const BorderRadius.vertical(top: Radius.circular(16)),
      side: BorderSide(color: c.line),
    );
    final animDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    final Widget sheet = widget.collapsed
        ? Material(
            key: const Key('route-card-collapsed-bar'),
            color: c.surface,
            elevation: 6,
            shadowColor: Colors.black26,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onCollapsedChanged(false),
              child: SafeArea(
                top: false,
                child: Semantics(
                  button: true,
                  label: 'Show route details',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DragPill(c: c),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Ic.pin, size: 16, color: c.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.destinationTitle,
                                style: T.bodyBoldFor(c),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.etaBadge.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: StatusPill(
                                  widget.etaBadge,
                                  tone: Tone.info,
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Icon(Ic.chevronUp, size: 18, color: c.muted),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxExpandedHeight),
            child: Material(
              key: const Key('route-card-expanded'),
              color: c.surface,
              elevation: 6,
              shadowColor: Colors.black26,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      key: const Key('route-card-drag-handle'),
                      padding: const EdgeInsets.fromLTRB(18, 10, 8, 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _DragPill(c: c),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'DESTINATION',
                                      style: T.smallBoldFor(c),
                                    ),
                                    if (widget.etaBadge.isNotEmpty)
                                      StatusPill(
                                        widget.etaBadge,
                                        tone: Tone.info,
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                key: const Key('route-card-hide-button'),
                                tooltip: 'Hide route details',
                                onPressed: () =>
                                    widget.onCollapsedChanged(true),
                                icon: Icon(
                                  Ic.chevronDown,
                                  size: 18,
                                  color: c.muted,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.loading) ...[
                              const LinearProgressIndicator(minHeight: 2),
                              const SizedBox(height: 10),
                            ],
                            Text(
                              widget.destinationTitle,
                              style: T.titleFor(c),
                            ),
                            if (widget.orderLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.orderLabel!,
                                style: T.smallBoldFor(c),
                              ),
                            ],
                            if (widget.address != null) ...[
                              const SizedBox(height: 4),
                              Text(widget.address!, style: T.bodyFor(c)),
                            ],
                            const SizedBox(height: 10),
                            if (!widget.active)
                              Text(
                                'Return to Trips to see your current assignment.',
                                style: T.smallFor(c),
                              )
                            else if (widget.offline)
                              const FeedbackStrip(
                                'Offline. Route updates require an internet connection.',
                                warning: true,
                              )
                            else if (widget.error != null)
                              FeedbackStrip(widget.error!)
                            else ...[
                              if (widget.loading)
                                Text(
                                  'Finding your road route...',
                                  style: T.smallFor(c),
                                ),
                              if (widget.onCall != null) ...[
                                if (widget.loading) const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: widget.onCall,
                                  icon: const Icon(Ic.phoneCall, size: 16),
                                  label: const Text('Call'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

    final visualOffset = widget.collapsed ? _dragOffset * 0.35 : _dragOffset;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: _onVerticalDragCancel,
      child: Transform.translate(
        offset: Offset(0, visualOffset),
        child: AnimatedSize(
          duration: animDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: sheet,
        ),
      ),
    );
  }
}

class _DragPill extends StatelessWidget {
  final HyOpsColors c;
  const _DragPill({required this.c});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: c.controlLine,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
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
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    return Material(
      color: c.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: CircleBorder(side: BorderSide(color: c.line)),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
    );
  }
}
