import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/features/navigation/road_route_map.dart';
import 'package:hyops_flutter/features/navigation/route_overlay.dart';

const route = [LatLng(14.5, 121), LatLng(14.55, 121.05), LatLng(14.6, 121.1)];
Position fix({
  double lat = 14.5,
  double lng = 121,
  double heading = 90,
  double speed = 5,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 11, 6),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
);

class BlankTiles extends TileProvider {
  final image = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      image;
}

void main() {
  Future<void> showMap(
    WidgetTester tester,
    ValueNotifier<Position?> position, {
    double scale = 1,
    bool disableAnimations = false,
    List<LatLng> routePoints = route,
  }) async {
    final tiles = BlankTiles();
    await tester.pumpWidget(
      MaterialApp(
        theme: driverTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: ValueListenableBuilder<Position?>(
              valueListenable: position,
              builder: (_, value, _) => RoadRouteMap(
                route: routePoints,
                position: value,
                tileProvider: tiles,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MapCamera camera(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera;
  void atDriver(WidgetTester tester, Position position) {
    expect(
      camera(tester).center.latitude,
      closeTo(position.latitude, 0.0000001),
    );
    expect(
      camera(tester).center.longitude,
      closeTo(position.longitude, 0.0000001),
    );
  }

  testWidgets(
    'map camera defaults to following GPS and keeps stable course while stationary',
    (tester) async {
      final position = ValueNotifier<Position?>(fix());
      addTearDown(position.dispose);
      await showMap(tester, position);
      expect(find.text('Following location'), findsOneWidget);
      atDriver(tester, position.value!);
      expect(camera(tester).zoom, closeTo(16.5, 0.01));
      expect(camera(tester).rotation % 360, closeTo(270, 0.01));
      position.value = fix(lat: 14.51, lng: 121.01, heading: 180);
      await tester.pump();
      await tester.pumpAndSettle();
      atDriver(tester, position.value!);
      expect(camera(tester).rotation % 360, closeTo(180, 0.01));
      position.value = fix(lat: 14.511, lng: 121.011, heading: -1, speed: 0);
      await tester.pump();
      await tester.pumpAndSettle();
      atDriver(tester, position.value!);
      expect(camera(tester).rotation % 360, closeTo(180, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single taps toggle controls while GPS following and the map stay alive',
    (tester) async {
      final position = ValueNotifier<Position?>(fix());
      addTearDown(position.dispose);
      await showMap(tester, position);
      expect(find.text('Normal map'), findsNothing);
      final mapState = tester.state(find.byType(FlutterMap));
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(RouteOverlay),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0);
      position.value = fix(lat: 14.52, lng: 121.02, heading: 180);
      await tester.pump();
      await tester.pumpAndSettle();
      atDriver(tester, position.value!);
      expect(tester.state(find.byType(FlutterMap)), same(mapState));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      expect(find.text('Following location'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden map remains pannable and gestures do not toggle controls',
    (tester) async {
      final position = ValueNotifier<Position?>(fix());
      addTearDown(position.dispose);
      await showMap(tester, position);
      await tester.drag(find.byType(FlutterMap), const Offset(100, 80));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final center = camera(tester).center;
      await tester.drag(find.byType(FlutterMap), const Offset(-100, 80));
      await tester.pumpAndSettle();
      expect(camera(tester).center, isNot(center));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      final pinchZoom = camera(tester).zoom;
      final firstFinger = await tester.startGesture(
        const Offset(300, 350),
        pointer: 1,
      );
      final secondFinger = await tester.startGesture(
        const Offset(450, 350),
        pointer: 2,
      );
      await tester.pump();
      await firstFinger.moveTo(const Offset(250, 350));
      await secondFinger.moveTo(const Offset(500, 350));
      await tester.pump();
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(camera(tester).zoom, greaterThan(pinchZoom));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      final zoom = camera(tester).zoom;
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(camera(tester).zoom, greaterThan(zoom));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      await tester.tapAt(const Offset(200, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Recenter'), findsOneWidget);
      await tester.tap(find.text('Recenter'));
      await tester.pumpAndSettle();
      atDriver(tester, position.value!);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging pauses camera following until Recenter is tapped', (
    tester,
  ) async {
    final position = ValueNotifier<Position?>(fix());
    addTearDown(position.dispose);
    await showMap(tester, position);
    await tester.drag(find.byType(FlutterMap), const Offset(100, 80));
    await tester.pumpAndSettle();
    expect(find.text('Camera paused'), findsOneWidget);
    final center = camera(tester).center;
    position.value = fix(lat: 14.53, lng: 121.03, heading: 45);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(camera(tester).center, center);
    await tester.tap(find.text('Recenter'));
    await tester.pumpAndSettle();
    atDriver(tester, position.value!);
    expect(find.text('Following location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'camera crosses north using the short rotation and supports reduced motion',
    (tester) async {
      final position = ValueNotifier<Position?>(fix(heading: 359));
      addTearDown(position.dispose);
      await showMap(tester, position);
      position.value = fix(heading: 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      final rotation = camera(tester).rotation % 360;
      expect(rotation < 3 || rotation > 357, true);
      await tester.pumpAndSettle();
      expect(camera(tester).rotation % 360, closeTo(359, 0.01));
      await showMap(tester, position, disableAnimations: true);
      position.value = fix(lat: 14.54, lng: 121.04, heading: 90);
      await tester.pump();
      atDriver(tester, position.value!);
      expect(camera(tester).rotation % 360, closeTo(270, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map controls support small screens and enlarged text without a GPS fix',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final position = ValueNotifier<Position?>(null);
      addTearDown(position.dispose);
      await showMap(tester, position, scale: 1.6);
      expect(find.text('Waiting for location'), findsOneWidget);
      expect(find.text('Normal map'), findsNothing);
      await tester.tapAt(const Offset(160, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(RouteOverlay),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
