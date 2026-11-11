import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyops_flutter/core/palette.dart';
import 'package:hyops_flutter/core/theme.dart';
import 'package:hyops_flutter/data/models.dart';
import 'package:hyops_flutter/state/app_state.dart';
import 'package:hyops_flutter/repositories/driver_repository.dart';
import 'package:hyops_flutter/features/auth/login_screen.dart';
import 'package:hyops_flutter/features/home/home_screen.dart';
import 'package:hyops_flutter/features/trips/trip_detail_screen.dart';
import 'package:hyops_flutter/features/trips/trips_screen.dart';
import 'package:hyops_flutter/features/history/history_screen.dart';
import 'package:hyops_flutter/features/profile/profile_screen.dart';
import 'package:hyops_flutter/features/shell/main_shell.dart';
import 'package:hyops_flutter/widgets/driver_ui.dart';

import 'widget_test.dart' as fixtures;

class UiRepository extends fixtures.FakeRepository {
  UiRepository(super.client);
  Map<String, dynamic> data({bool past = false}) {
    final trip = fixtures.tripJson()
      ..['id'] = past ? 99 : 12
      ..['status'] = past ? 'completed' : 'in_transit';
    final stop = (trip['stops'] as List<Map<String, dynamic>>).single;
    stop['canDeliver'] = !past;
    return trip;
  }

  @override
  Future<PageResult<Trip>> trips({int page = 0, bool past = false}) async =>
      PageResult([Trip.fromJson(data(past: past))], 1);
  @override
  Future<Trip> trip(String id) async => Trip.fromJson(data());

  @override
  Future<PageResult<HistoryEntry>> history({
    int page = 0,
    String? from,
    String? to,
    String? status,
  }) async {
    final trip = Trip.fromJson(data());
    return PageResult([
      HistoryEntry.fromStop(trip, trip.stops.single, outcome: 'Delivered'),
    ], 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<AppState> setup() async {
    SharedPreferences.setMockInitialValues({});
    final api = fixtures.FakeClient();
    final state = AppState(
      await SharedPreferences.getInstance(),
      api: api,
      driverRepository: UiRepository(api),
      realtime: false,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await state.login('driver@example.test', 'valid-password', remember: false);
    return state;
  }

  test('Home keeps the current delivery when Trips shows past runs', () async {
    final state = await setup();
    expect(state.activeTrip?.id, '12');
    await state.setTripPage(0, past: true);
    expect(state.trips.single.id, '99');
    expect(state.activeTrip?.id, '12');
  });
  testWidgets(
    'driver pages adapt across viewport sizes and support enlarged text and both themes',
    (tester) async {
      final state = await setup();
      final capture = Platform.environment['HYOPS_UI_CAPTURE'] == 'true';
      String? previewFont;
      if (capture) {
        await tester.runAsync(() async {
          final fontFile = File('C:/Windows/Fonts/segoeui.ttf');
          if (await fontFile.exists()) {
            final loader = FontLoader('DriverPreview')
              ..addFont(
                fontFile.readAsBytes().then((b) => ByteData.sublistView(b)),
              );
            await loader.load();
            previewFont = 'DriverPreview';
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
            final lucide = FontLoader('packages/forui_lucide/ForuiLucideIcons')
              ..addFont(
                rootBundle.load('packages/forui_lucide/assets/lucide.ttf'),
              );
            await lucide.load();
          }
        });
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(() => P.dark = false);
      final pages = <String, Widget>{
        'shell': const MainShell(),
        'home': const HomeScreen(),
        'trips': const TripsScreen(),
        'history': const HistoryScreen(),
        'profile': const ProfileScreen(),
        'delivery': const TripDetailScreen(tripId: '12'),
        'login': const LoginScreen(),
        'loading': const DriverLoadingScreen(),
      };
      for (final dark in [false, true]) {
        P.dark = dark;
        for (final entry in pages.entries) {
          for (final size in [
            const Size(390, 844),
            const Size(320, 568),
            const Size(800, 700),
            const Size(1280, 800),
          ]) {
            tester.view.physicalSize = size;
            final key = GlobalKey();
            await tester.pumpWidget(
              AppScope(
                state: state,
                child: MaterialApp(
                  theme: driverTheme(fontFamily: previewFont),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                        size.width == 320 ? 1.6 : 1,
                      ),
                    ),
                    child: FTheme(
                      data: dark
                          ? FTheme.neutral.dark.touch
                          : FTheme.neutral.light.touch,
                      child: child!,
                    ),
                  ),
                  home: RepaintBoundary(
                    key: key,
                    child: Scaffold(body: entry.value),
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key}, $size, dark=$dark',
            );
            if (entry.key == 'shell') {
              if (size.width < 720) {
                expect(find.byType(NavigationBar), findsOneWidget);
              } else {
                final rail = tester.widget<NavigationRail>(
                  find.byType(NavigationRail),
                );
                expect(rail.extended, size.width >= 1080);
              }
            }
            if (capture && (size.width == 390 || size.width == 1280)) {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage('assets/logo.png'),
                  key.currentContext!,
                ),
              );
              await tester.pump();
              await tester.runAsync(() async {
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await boundary.toImage(pixelRatio: 1);
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                picture.dispose();
                final file = File(
                  '../.tmp/driver-ui-preview/${entry.key}-${size.width.toInt()}-${dark ? 'dark' : 'light'}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              });
            }
            if (entry.key == 'history' && size.width == 390) {
              final record = find.text(state.history.single.customer);
              await tester.ensureVisible(record);
              await tester.tap(record);
              await tester.pumpAndSettle();
              expect(find.text('Delivery details'), findsOneWidget);
              await tester.tap(find.byTooltip('Close delivery record'));
              await tester.pumpAndSettle();
              expect(find.text('Delivery details'), findsNothing);
              expect(tester.takeException(), isNull);
            }
            if (entry.key == 'login' && size.width == 390) {
              await tester.showKeyboard(find.byType(TextField).last);
              await tester.testTextInput.receiveAction(TextInputAction.done);
              await tester.pump();
              expect(find.text('Enter your driver email.'), findsOneWidget);
              expect(find.text('Enter your password.'), findsOneWidget);
            }
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
}
