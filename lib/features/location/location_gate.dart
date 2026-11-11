import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';

/// Wraps the whole app (including pushed routes). While [active] and the phone's
/// location service is switched OFF, a full-screen "Turn on location" page is
/// shown on top. It disappears by itself the moment location is enabled.
class LocationGate extends StatefulWidget {
  final bool active;
  final Widget child;
  const LocationGate({super.key, required this.active, required this.child});
  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  bool _enabled = true; // assume on until checked, so nothing flashes at launch
  bool _checking = false;
  StreamSubscription<ServiceStatus>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    try {
      _sub = Geolocator.getServiceStatusStream().listen((s) {
        if (mounted) setState(() => _enabled = s == ServiceStatus.enabled);
      }, onError: (_) {});
    } catch (_) {
      // Platform without a service-status stream: we re-check on app resume instead.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<bool> _check() async {
    if (mounted) setState(() => _checking = true);
    var on = _enabled;
    try {
      on = await Geolocator.isLocationServiceEnabled();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _enabled = on;
        _checking = false;
      });
    }
    return on;
  }

  Future<void> _openSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }

  Future<void> _recheck(BuildContext pageContext) async {
    final on = await _check();
    if (!on && pageContext.mounted)
      toast(pageContext, 'Location is still off. Turn it on in settings.');
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.active && !_enabled;
    return Stack(
      children: [
        ExcludeFocus(
          excluding: show,
          child: ExcludeSemantics(excluding: show, child: widget.child),
        ),
        if (show)
          Positioned.fill(
            child: _LocationOffPage(
              checking: _checking,
              onOpenSettings: _openSettings,
              onRecheck: _recheck,
            ),
          ),
      ],
    );
  }
}

class _LocationOffPage extends StatelessWidget {
  final bool checking;
  final VoidCallback onOpenSettings;
  final Future<void> Function(BuildContext) onRecheck;
  const _LocationOffPage({
    required this.checking,
    required this.onOpenSettings,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: P.surface,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                minHeight: (bounds.maxHeight - 48)
                    .clamp(0.0, double.infinity)
                    .toDouble(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: DriverBrand(compact: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Ic.locationOff, size: 30, color: P.muted),
                        const SizedBox(height: 20),
                        Text(
                          'Location is off',
                          style: T.title.copyWith(fontSize: 26, height: 1.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Turn on your phone's location to share your position with dispatch and use delivery routes.",
                          style: T.body.copyWith(color: P.muted, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: onOpenSettings,
                        style: FilledButton.styleFrom(
                          backgroundColor: P.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Open location settings'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: checking ? null : () => onRecheck(context),
                        style: TextButton.styleFrom(
                          foregroundColor: P.muted,
                          minimumSize: const Size.fromHeight(48),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(checking ? 'Checking...' : 'Check again'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
