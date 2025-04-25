// --- File: lib/services/inactivity_service.dart ---

import 'dart:async';
import 'package:flutter/material.dart';
import 'encryption_key_service.dart'; // Import key service
import '../utils/constants.dart'; // Import constants

// Service to handle app locking due to inactivity or lifecycle events
class InactivityService with WidgetsBindingObserver {
  // Singleton pattern
  static final InactivityService instance = InactivityService._internal();
  InactivityService._internal();

  Timer? _inactivityTimer;
  GlobalKey<NavigatorState>? _navigatorKey; // Use the global key
  String? _currentRouteName;
  bool _isInitialized = false;

  bool get isTimerActive => _inactivityTimer?.isActive ?? false;

  // Initialize with the global navigator key
  void init(GlobalKey<NavigatorState> key) {
    if (_isInitialized) return;
    _navigatorKey = key;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    print("InactivityService Initialized");
  }

  // Clean up observer
  void dispose() {
    if (_isInitialized) {
        WidgetsBinding.instance.removeObserver(this);
        _inactivityTimer?.cancel();
        _isInitialized = false;
        print("InactivityService Disposed");
    }
  }

  // Called by RouteObserver when route changes
  void notifyRouteChanged(Route? route) {
     if (!_isInitialized) return;
     _currentRouteName = route?.settings.name;
     // Handle initial route mapping if necessary (e.g., '/' might be AuthWrapper)
     // This logic might need refinement depending on initial route setup
     if (_currentRouteName == '/' && route is MaterialPageRoute && _navigatorKey?.currentContext != null) {
         try {
             // Attempt to determine the actual initial widget if needed
             // final Widget initialWidget = route.builder(_navigatorKey!.currentContext!);
             // if (initialWidget is AuthWrapper) _currentRouteName = authWrapperRoute;
             // else if ...
         } catch (e) {
             print("Error checking initial route widget: $e");
         }
     }
     print("Route changed: $_currentRouteName");
     _handleActivityStatus();
  }

  // Called by InactivityDetector on user interaction
  void handleInteraction() {
     if (!_isInitialized) return;
    // Reset timer only if on an authenticated route
    if (_currentRouteName != null && authenticatedRoutes.contains(_currentRouteName)) {
       print("User interaction detected on authenticated route ($_currentRouteName). Resetting timer.");
       _resetTimer();
    } else {
       print("User interaction detected on non-authenticated route ($_currentRouteName). Timer not reset.");
    }
  }

  // Start/stop timer based on current route
  void _handleActivityStatus() {
     if (!_isInitialized) return;
     final bool shouldTimerBeActive = _currentRouteName != null && authenticatedRoutes.contains(_currentRouteName);
     print("Handling activity status. Current route: $_currentRouteName. Should timer be active? $shouldTimerBeActive");
     if (shouldTimerBeActive) {
        // Check if key is set before starting timer, except for specific routes
        if (!EncryptionKeyService.instance.isKeySet() &&
            _currentRouteName != createMasterRoute &&
            _currentRouteName != settingsRoute) { // Allow settings/create even if key isn't set yet
            print("Warning: Entering authenticated route ($_currentRouteName) but encryption key is not set. Forcing lock.");
            _lockApp(forceClearKey: false); // Key should already be clear or wasn't set
            return; // Prevent timer start
        }
        _resetTimer();
     } else {
        _cancelTimer();
     }
  }

  // Handle app lifecycle changes (pause, resume, etc.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;
    print("Global App Lifecycle State Changed: $state");

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Lock immediately if on an authenticated route WHEN APP GOES TO BACKGROUND,
      // UNLESS it's a page where data entry might be interrupted (Add/Edit/Settings).
      if (_currentRouteName != null && authenticatedRoutes.contains(_currentRouteName)) {
          if (_currentRouteName != addPasswordRoute &&
              _currentRouteName != editPasswordRoute &&
              _currentRouteName != settingsRoute) {
             print("App paused/inactive on authenticated route ($_currentRouteName). Locking now.");
             _cancelTimer(); // Cancel inactivity timer before locking
             _lockApp(); // Lock the app (will also clear key)
          } else {
             print("App paused/inactive on Add/Edit Password or Settings page. Inactivity timer remains active.");
          }
      } else {
          print("App paused/inactive on non-authenticated route ($_currentRouteName). Not locking.");
      }
    } else if (state == AppLifecycleState.resumed) {
      print("App Resumed - Handling activity status check");
      // Re-check timer status on resume
      _handleActivityStatus();
    }
  }

  // Reset the inactivity timer
  void _resetTimer() {
     if (!_isInitialized) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, _lockApp);
    print("Global Inactivity timer reset (Timeout: ${inactivityTimeout.inSeconds}s).");
  }

  // Cancel the inactivity timer
  void _cancelTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    print("Global Inactivity timer cancelled.");
  }

  // Lock the app (clear key, navigate to lock screen)
  // Schedules navigation using addPostFrameCallback to avoid navigator lock errors
  void _lockApp({bool forceClearKey = true}) {
     if (!_isInitialized) return;
    // Check if already on the lock screen to prevent multiple pushes
    if (_currentRouteName == enterMasterRoute) {
        print("Already on lock screen. Preventing duplicate lock.");
        return;
    }
    _cancelTimer(); // Ensure timer is cancelled before locking

    // Clear encryption key on lock
    if (forceClearKey) {
       EncryptionKeyService.instance.clearKey();
    }

    print("Scheduling lock action. Navigating to $enterMasterRoute post-frame.");

    // Schedule the navigation to occur after the current frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if navigator state is still available and mounted before navigating
      if (_navigatorKey?.currentState?.mounted == true) {
         print("Executing scheduled navigation to $enterMasterRoute.");
         _navigatorKey!.currentState!.pushNamedAndRemoveUntil(
           enterMasterRoute, (route) => false,
         );
         // Update current route name *after* scheduled navigation
         _currentRouteName = enterMasterRoute;
      } else {
         print("Scheduled navigation cancelled: Navigator state not available/mounted.");
      }
    });
  }
}