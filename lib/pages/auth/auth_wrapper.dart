// --- File: lib/pages/auth/auth_wrapper.dart ---

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../utils/constants.dart'; // Import constants
import '../../utils/helpers.dart'; // Import helpers for options

// Initial route widget to check if master password is set up
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _storage = const FlutterSecureStorage();
  // Use Future to prevent multiple checks during build phases
  late Future<bool> _hasMasterPasswordFuture;

  @override
  void initState() {
    super.initState();
    _hasMasterPasswordFuture = _checkMasterPassword();
  }

  // Check secure storage for the master password derived key
  Future<bool> _checkMasterPassword() async {
    final storedKey = await _storage.read(
      key: masterPasswordHashKey,
      aOptions: getAndroidOptions(), // Use helper
    );
    print("Checked for master password key. Found: ${storedKey != null}");
    return storedKey != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasMasterPasswordFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading indicator while checking storage
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          // Show error if storage check fails
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Error checking secure storage: ${snapshot.error}'),
              ),
            ),
          );
        } else {
          // Decide where to navigate based on whether key exists
          final bool hasMasterPassword = snapshot.data ?? false;
          // Schedule navigation after the frame is built
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (!mounted) return; // Check if widget is still mounted
             if (hasMasterPassword) {
               Navigator.pushReplacementNamed(context, enterMasterRoute);
             } else {
               Navigator.pushReplacementNamed(context, createMasterRoute);
             }
          });
          // Show loading indicator briefly while navigation is scheduled
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
      },
    );
  }
}