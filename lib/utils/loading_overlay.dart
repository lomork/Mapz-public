// lib/utils/loading_overlay.dart

import 'package:flutter/material.dart';
import 'loading_ripple.dart';

class LoadingOverlay {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext context) {
    if (_overlayEntry != null) {
      return; // Overlay is already showing
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        // Use the app's theme to determine the dimming color
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final Color overlayColor = isDarkMode
            ? Colors.black.withOpacity(0.6)
            : Colors.white.withOpacity(0.6);

        return Scaffold(
          backgroundColor: overlayColor,
          body: const Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: LoadingRipple(),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}