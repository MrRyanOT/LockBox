// --- File: lib/app.dart ---

import 'package:flutter/material.dart';
import 'services/theme_service.dart';
import 'services/inactivity_service.dart';
import 'widgets/inactivity_detector.dart';
import 'utils/constants.dart'; // Import constants for routes
import 'utils/helpers.dart'; // Import helpers if needed indirectly
// Import Pages
import 'pages/auth/auth_wrapper.dart';
import 'pages/auth/create_master_password_page.dart';
import 'pages/auth/enter_master_password_page.dart';
import 'pages/home_page.dart';
import 'pages/add_password_page.dart';
import 'pages/edit_password_page.dart';
import 'pages/generate_password_page.dart';
import 'pages/about_page.dart';
import 'pages/settings_page.dart';
// Import Models (needed for EditPasswordPage route argument)
import 'models/password_entry.dart';

// Main Application Widget
class PasswordManagerApp extends StatefulWidget {
  const PasswordManagerApp({super.key});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp> {
  final ThemeService _themeService = ThemeService.instance;

  @override
  void initState() {
    super.initState();
    // Initialize inactivity service with the global navigator key
    InactivityService.instance.init(navigatorKey);
    // Listen to theme changes to rebuild MaterialApp
    _themeService.addListener(_onThemeChanged);
  }

   @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    // Consider disposing InactivityService here if appropriate,
    // though as a singleton it might live for the app's lifetime.
    // InactivityService.instance.dispose();
    super.dispose();
  }

  // Rebuilds the MaterialApp when theme settings change
  void _onThemeChanged() {
    setState(() {
      // Trigger rebuild to apply new theme
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Secure Passwords', // Consider making this configurable
      navigatorKey: navigatorKey, // Use global key for navigation access from services
      themeMode: _themeService.themeMode, // Control light/dark mode
      // Define Light Theme
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: _themeService.selectedSeedColor,
        useMaterial3: true,
      ),
      // Define Dark Theme (with optional AMOLED black background)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: _themeService.selectedSeedColor,
        useMaterial3: true,
         scaffoldBackgroundColor: _themeService.useAmoledDark ? Colors.black : null, // Use null for default M3 dark
      ),
      // --- RESTORED: Use AuthWrapper and routes ---
      home: const AuthWrapper(), // Start with AuthWrapper
      debugShowCheckedModeBanner: false, // Disable debug banner
      navigatorObservers: [InactivityRouteObserver()], // Add route observer for inactivity service
      routes: {
        // Use constants for route names
        homeRoute: (context) => const HomePage(),
        createMasterRoute: (context) => const CreateMasterPasswordPage(),
        enterMasterRoute: (context) => const EnterMasterPasswordPage(),
        addPasswordRoute: (context) => const AddPasswordPage(),
        generatePasswordRoute: (context) => const GeneratePasswordPage(),
        aboutRoute: (context) => const AboutPage(),
        settingsRoute: (context) => const SettingsPage(),
        editPasswordRoute: (context) {
           // Route definition for editing requires extracting arguments
           final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
           // Validate arguments before creating the page
           if (args == null || args['entry'] == null || args['originalServiceName'] == null) {
              print("Error: Missing arguments for edit page.");
              // Return an error page or navigate back gracefully
              return const Scaffold(
                body: Center(child: Text("Error loading edit page: Missing arguments."))
              );
           }
           // Create EditPasswordPage with the required arguments
           return EditPasswordPage(
              originalServiceName: args['originalServiceName'] as String,
              entry: args['entry'] as PasswordEntry,
           );
        },
      },
      // --- END RESTORED ---
      // Add the InactivityDetector wrapper around the app content
      builder: (context, child) {
        // Ensure child is not null before wrapping
        return child == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator())) // Placeholder if child is null
            : InactivityDetector(child: child);
      },
    );
  }
}