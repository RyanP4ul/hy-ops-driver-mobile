import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/driver_ui.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trips_screen.dart';

const _destinations = [
  (Ic.home, 'Home'),
  (Ic.trips, 'Trips'),
  (Ic.history, 'History'),
  (Ic.profile, 'Profile'),
];

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = HyOpsColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 720;
    final extended = width >= 1080;
    final hasActiveTrip = state.activeTrip != null;
    final hasSyncAlert =
        state.isOffline || state.pendingSyncCount > 0 || state.error != null;

    Widget buildNavIcon(int index, IconData icon) {
      if (index == 1 && hasActiveTrip) {
        return Badge(
          backgroundColor: c.primary,
          smallSize: 8,
          child: Icon(icon),
        );
      }
      if (index == 3 && hasSyncAlert) {
        return Badge(
          backgroundColor: state.error != null ? c.danger : c.warn,
          smallSize: 8,
          child: Icon(icon),
        );
      }
      return Icon(icon);
    }

    final pages = IndexedStack(
      index: state.tab,
      children: const [
        HomeScreen(),
        TripsScreen(),
        HistoryScreen(),
        ProfileScreen(),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: useRail,
        child: useRail
            ? Row(
                children: [
                  NavigationRail(
                    backgroundColor: c.surface,
                    scrollable: true,
                    indicatorColor: c.primarySoft,
                    extended: extended,
                    minExtendedWidth: 188,
                    labelType: extended ? null : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: extended
                          ? const DriverBrand(compact: true)
                          : Image.asset(
                              'assets/logo.png',
                              width: 32,
                              semanticLabel: 'HYOps Driver',
                            ),
                    ),
                    selectedIndex: state.tab,
                    onDestinationSelected: state.setTab,
                    destinations: [
                      for (var i = 0; i < _destinations.length; i++)
                        NavigationRailDestination(
                          icon: buildNavIcon(i, _destinations[i].$1),
                          label: Text(_destinations[i].$2),
                        ),
                    ],
                  ),
                  VerticalDivider(width: 1, color: c.line),
                  Expanded(child: pages),
                ],
              )
            : pages,
      ),
      bottomNavigationBar: useRail
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: NavigationBar(
                height: 68,
                selectedIndex: state.tab,
                onDestinationSelected: state.setTab,
                destinations: [
                  for (var i = 0; i < _destinations.length; i++)
                    NavigationDestination(
                      icon: buildNavIcon(i, _destinations[i].$1),
                      label: _destinations[i].$2,
                    ),
                ],
              ),
            ),
    );
  }
}
