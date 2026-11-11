import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/palette.dart';
import 'core/theme.dart';
import 'widgets/driver_ui.dart';
import 'features/auth/login_screen.dart';
import 'features/location/location_gate.dart';
import 'features/shell/main_shell.dart';
import 'state/app_state.dart';

class HyOpsApp extends StatefulWidget {
  final SharedPreferences prefs;
  final AppState? state;
  const HyOpsApp({super.key, required this.prefs, this.state});
  @override
  State<HyOpsApp> createState() => _HyOpsAppState();
}

class _HyOpsAppState extends State<HyOpsApp> with WidgetsBindingObserver {
  late final AppState _state = widget.state ?? AppState(widget.prefs);

  @override
  void initState() {
    super.initState();
    _state.initialize();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() => _state.refreshBrightness();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  FThemeData get _fTheme {
    final base = P.dark
        ? FTheme.neutral.dark.touch
        : FTheme.neutral.light.touch;

    return FThemeData(
      colors: base.colors.copyWith(
        primary: P.primary,
        primaryForeground: Colors.white,
        background: P.bg,
      ),
      typography: base.typography,
      style: base.style,
      icons: base.icons,
      touch: true,
    );
  }

  ThemeData get _material => driverTheme();

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (_, __) => MaterialApp(
          // New key when the theme flips, so every screen rebuilds with the new palette.
          key: ValueKey('${P.dark}:${_state.loggedIn}:${_state.driver.id}'),
          title: 'HYOps Driver',
          debugShowCheckedModeBanner: false,
          theme: _material,
          // The gate sits above the Navigator so it also covers pushed screens.
          builder: (context, child) => FTheme(
            data: _fTheme,
            child: Column(
              children: [
                if (_state.loggedIn && _state.assignmentNotice != null)
                  SafeArea(
                    bottom: false,
                    child: MaterialBanner(
                      content: Text(_state.assignmentNotice!),
                      leading: const Icon(Icons.notifications_active_outlined),
                      actions: [
                        TextButton(
                          onPressed: _state.dismissAssignmentNotice,
                          child: const Text('Dismiss'),
                        ),
                      ],
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
          ),
          home: !_state.initialized
              ? const DriverLoadingScreen()
              : _state.loggedIn
              ? MainShell()
              : LoginScreen(),
        ),
      ),
    );
  }
}
