// --- File: lib/pages/auth/enter_master_password_page.dart ---

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert'; // For base64
import '../../services/encryption_key_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

// Page for entering the master password to unlock the app
class EnterMasterPasswordPage extends StatefulWidget {
  const EnterMasterPasswordPage({super.key});

  @override
  State<EnterMasterPasswordPage> createState() => _EnterMasterPasswordPageState();
}

class _EnterMasterPasswordPageState extends State<EnterMasterPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isPasswordVisible = false;
  bool _isChecking = false; // Loading state
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Ensure encryption key is cleared when lock screen is shown
    EncryptionKeyService.instance.clearKey();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // Verifies the entered master password against the stored hash
  Future<void> _verifyMasterPassword() async {
    if (_isChecking) return; // Prevent multiple checks

    if (_formKey.currentState!.validate()) {
       if (!mounted) return;
      setState(() {
        _isChecking = true; // Show loading indicator
        _errorMessage = null; // Clear previous error
      });

      final enteredPassword = _passwordController.text;

      try {
        // Retrieve the stored derived key hash and salt
        final storedDerivedKeyString = await _storage.read(key: masterPasswordHashKey, aOptions: getAndroidOptions());
        final storedSaltString = await _storage.read(key: masterPasswordSaltKey, aOptions: getAndroidOptions());

        if (storedDerivedKeyString == null || storedSaltString == null) {
           print("Error: Master password derived key or salt not found in storage.");
           if (mounted) {
             setState(() {
                _errorMessage = 'Setup error: Master password data missing. Please recreate.';
                _isChecking = false; // Hide loading
             });
           }
           return;
        }

        // Decode the stored salt
        final saltBytes = base64Decode(storedSaltString);

        // Derive key from entered password using compute
         final calculatedDerivedKeyBytes = await compute(deriveKeyInBackground, {
            'password': enteredPassword,
            'saltBytes': saltBytes,
         });

        // Encode the newly calculated key to Base64 for comparison
        final calculatedDerivedKeyString = base64Encode(calculatedDerivedKeyBytes);

        // Compare the calculated derived key with the stored one
        if (calculatedDerivedKeyString == storedDerivedKeyString) {
           // SUCCESS: Set the key in the service and navigate to home
           EncryptionKeyService.instance.setKey(calculatedDerivedKeyBytes);
           if (mounted) {
             setState(() { _isChecking = false; }); // Hide loading
             Navigator.pushReplacementNamed(context, homeRoute);
             return;
           }
        } else {
          // FAILURE: Incorrect password
          if (mounted) {
            setState(() {
              _errorMessage = 'Incorrect master password. Please try again.';
              _passwordController.clear(); // Clear password field
              _isChecking = false; // Hide loading
            });
          }
        }
      } catch (e) {
         print("Error verifying master password: $e");
         if (mounted) {
           setState(() {
              _errorMessage = 'An error occurred during verification.'; // Keep error generic for user
              _isChecking = false; // Hide loading
           });
         }
      }
    } else {
       // If form is invalid, ensure loading indicator is off
       if (mounted && _isChecking) {
          setState(() => _isChecking = false);
       }
    }
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Master Password'),
        automaticallyImplyLeading: false, // No back button
      ),
      body: Stack( // Use Stack for loading overlay
        children: [
          // Original Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                     Icon(Icons.lock_open_outlined, size: 60, color: Theme.of(context).colorScheme.secondary),
                     const SizedBox(height: 20),
                     Text(
                      'Enter your Master Password',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                       autofocus: true,
                       enabled: !_isChecking, // Disable field while checking
                      decoration: InputDecoration(
                        labelText: 'Master Password',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: _isChecking ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your master password';
                        }
                        return null;
                      },
                      // Submit on pressing enter key on keyboard
                      onFieldSubmitted: (_) => _isChecking ? null : _verifyMasterPassword(),
                    ),
                    const SizedBox(height: 16),
                    // Show error message if present
                    AnimatedOpacity(
                      opacity: _errorMessage != null ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage ?? '',
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                     ElevatedButton.icon(
                      icon: const Icon(Icons.login_outlined),
                      label: const Text('Unlock'),
                      style: _getButtonStyle(context),
                      onPressed: _isChecking ? null : _verifyMasterPassword, // Disable button while checking
                     ),
                  ],
                ),
              ),
            ),
          ),
           // Loading Overlay
          Visibility(
            visible: _isChecking, // Show overlay when checking password
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                 child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     CircularProgressIndicator(),
                     SizedBox(height: 16),
                     Text("Verifying password...", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper for button style
  ButtonStyle _getButtonStyle(BuildContext context) {
     return ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      );
  }
}