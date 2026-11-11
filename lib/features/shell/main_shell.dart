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
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 720;
    final extended = width >= 1080;
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
                    backgroundColor: P.surface,
                    scrollable: true,
                    indicatorColor: P.primarySoft,
                    extended: extended,
                    minExtendedWidth: 184,
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
                      for (final (icon, label) in _destinations)
                        NavigationRailDestination(
                          icon: Icon(icon),
                          label: Text(label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: pages),
                ],
              )
            : pages,
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              height: 64,
              selectedIndex: state.tab,
              onDestinationSelected: state.setTab,
              destinations: [
                for (final (icon, label) in _destinations)
                  NavigationDestination(icon: Icon(icon), label: label),
              ],
            ),
    );
  }
}
