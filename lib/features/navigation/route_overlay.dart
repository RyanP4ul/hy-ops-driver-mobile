import 'package:flutter/material.dart';

/// Keeps overlays mounted without intercepting gestures or accessibility focus
/// while hidden. The map and its GPS subscription live outside this widget.
class RouteOverlay extends StatelessWidget {
  final bool visible;
  final Widget child;
  const RouteOverlay({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: child,
      ),
    ),
  );
}
