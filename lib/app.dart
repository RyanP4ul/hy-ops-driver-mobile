import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/icons.dart';
import 'core/palette.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/location/location_gate.dart';
import 'features/shell/main_shell.dart';
import 'features/trips/trip_detail_screen.dart';
import 'state/app_state.dart';
import 'widgets/driver_ui.dart';
import 'widgets/sync_panel.dart';

class HyOpsApp extends StatefulWidget {
  final SharedPreferences prefs;
  final AppState? state;
  const HyOpsApp({super.key, required this.prefs, this.state});
  @override
  State<HyOpsApp> createState() => _HyOpsAppState();
}

class _HyOpsAppState extends State<HyOpsApp> with WidgetsBindingObserver {
  late final AppState _state = widget.state ?? AppState(widget.prefs);
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late String _sessionKey = '${_state.loggedIn}:${_state.driver.id}';

  @override
  void initState() {
    super.initState();
    _state.addListener(_handleSessionChange);
    _state.initialize();
    WidgetsBinding.instance.addObserver(this);
  }

  void _handleSessionChange() {
    final next = '${_state.loggedIn}:${_state.driver.id}';
    if (next == _sessionKey) return;
    _sessionKey = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _navKey.currentState?.popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void didChangePlatformBrightness() => _state.refreshBrightness();

  @override
  Future<bool> didPopRoute() async => _state.isSyncing;

  @override
  void dispose() {
    _state.removeListener(_handleSessionChange);
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  void _openAssignedTrip() {
    final tripId = _state.assignmentTripId;
    _state.dismissAssignmentNotice();
    if (tripId != null && _state.findTrip(tripId) != null) {
      _navKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => TripDetailScreen(tripId: tripId),
        ),
      );
      return;
    }
    _state.setTab(1);
    _navKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (_, _) => MaterialApp(
          navigatorKey: _navKey,
          title: 'HYOps Driver',
          debugShowCheckedModeBanner: false,
          theme: driverTheme(brightness: Brightness.light),
          darkTheme: driverTheme(brightness: Brightness.dark),
          themeMode: switch (_state.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          // The gate sits above the Navigator so it also covers pushed screens.
          builder: (context, child) {
            final c = HyOpsColors.of(context);
            final sync = _state.repository.sync;
            return SyncGate(
              active: _state.isSyncing,
              uploadingOutbox: sync.syncing,
              uploadedBytes: sync.uploadedBytes,
              uploadBytesTotal: sync.uploadBytesTotal,
              child: Column(
                children: [
                  if (_state.loggedIn && _state.assignmentNotice != null)
                    Material(
                      color: c.primarySoft,
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: c.primary.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Ic.bell, size: 18, color: c.actionInk),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _state.assignmentNotice!,
                                  style: T.bodyBoldFor(c).copyWith(
                                    fontSize: 14,
                                    color: c.actionInk,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _openAssignedTrip,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 40),
                                  foregroundColor: c.actionInk,
                                ),
                                child: const Text('Open'),
                              ),
                              Semantics(
                                button: true,
                                label: 'Dismiss',
                                child: IconButton(
                                  onPressed: _state.dismissAssignmentNotice,
                                  icon: Icon(
                                    Ic.close,
                                    size: 18,
                                    color: c.actionInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: LocationGate(
                      active: _state.loggedIn && !_state.isOffline,
                      child: child!,
                    ),
                  ),
                ],
              ),
            );
          },
          home: const _SessionGate(),
        ),
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.initialized) return const DriverLoadingScreen();
    if (!state.loggedIn) return const LoginScreen();
    return const MainShell();
  }
}
