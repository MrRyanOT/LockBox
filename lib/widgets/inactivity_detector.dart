// --- File: lib/widgets/inactivity_detector.dart ---

import 'package:flutter/material.dart';
import '../services/inactivity_service.dart'; // Import service

// Wrapper widget to detect user interaction and reset inactivity timer
class InactivityDetector extends StatelessWidget {
  final Widget child;

  const InactivityDetector({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Listener captures pointer events anywhere within its child subtree
    return Listener(
      // Reset timer on any pointer down or move event
      onPointerDown: (_) => InactivityService.instance.handleInteraction(),
      onPointerMove: (_) => InactivityService.instance.handleInteraction(),
      // Ensure listener captures events even on transparent areas
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}