// --- File: lib/pages/auth/create_master_password_page.dart ---

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart'; // For import
import 'package:shared_preferences/shared_preferences.dart'; // For first run flag

import '../../services/encryption_key_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

// Page for setting up the initial master password
class CreateMasterPasswordPage extends StatefulWidget {
  const CreateMasterPasswordPage({super.key});

  @override
  State<CreateMasterPasswordPage> createState() => _CreateMasterPasswordPageState();
}

class _CreateMasterPasswordPageState extends State<CreateMasterPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSaving = false; // Loading state for creating password
  bool _isImporting = false; // Loading state for importing data

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Generates a secure random salt
  String _generateSalt() {
    final random = Random.secure();
    // 16 bytes = 128 bits, common practice for salt length
    final saltBytes = List<int>.generate(16, (index) => random.nextInt(256));
    return base64Encode(saltBytes); // Store as Base64 string
  }

  // Saves the new master password
  Future<void> _saveMasterPassword() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() { _isSaving = true; }); // Show loading indicator

      final password = _passwordController.text;
      final saltString = _generateSalt();
      final saltBytes = base64Decode(saltString);

      try {
        // Derive the key using PBKDF2 in a background isolate
        final derivedKeyBytes = await compute(deriveKeyInBackground, {
          'password': password,
          'saltBytes': saltBytes,
        });

        final derivedKeyString = base64Encode(derivedKeyBytes);

        // Store the derived key hash and the salt securely
        await _storage.write(
          key: masterPasswordHashKey,
          value: derivedKeyString,
          aOptions: getAndroidOptions(),
        );
        await _storage.write(
          key: masterPasswordSaltKey,
          value: saltString,
          aOptions: getAndroidOptions(),
        );

        // Set the derived key in the in-memory service for immediate use
        EncryptionKeyService.instance.setKey(derivedKeyBytes);

        // Set first run flag after successful setup
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(firstRunFlagKey, true);

        if (mounted) {
           setState(() { _isSaving = false; }); // Hide loading
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Master password created successfully!')),
          );
          // Navigate to home page, removing setup route from stack
          Navigator.pushReplacementNamed(context, homeRoute);
        }
      } catch (e) {
        print("Error deriving key or saving master password: $e");
         if (mounted) {
           setState(() { _isSaving = false; }); // Hide loading on error
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error setting master password: ${e.toString()}')),
          );
         }
      }
    }
  }

  // Handles the import process
  Future<void> _handleImport() async {
     if (_isImporting || _isSaving) return; // Prevent concurrent operations

     // 1. Pick File
     FilePickerResult? result = await FilePicker.platform.pickFiles(
       type: FileType.custom,
       allowedExtensions: ['json'],
       withData: true, // Ensure bytes are loaded for cross-platform compatibility
     );

     if (result == null || result.files.single.bytes == null) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Import cancelled: No file selected or content unavailable.')),
         );
       }
       return;
     }

     // 2. Read File Bytes
     setState(() => _isImporting = true); // Show loading indicator
     String? jsonString;
     try {
       final fileBytes = result.files.single.bytes!;
       jsonString = utf8.decode(fileBytes); // Decode bytes to string
     } catch (e) {
       print("Error decoding backup file content: $e");
       if (mounted) {
         setState(() => _isImporting = false);
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error reading file content: ${e.toString()}')),
         );
       }
       return;
     }

     if (jsonString.isEmpty) {
       if (mounted) {
         setState(() => _isImporting = false);
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Import failed: File is empty.')),
         );
       }
       return;
     }

     // 3. Parse & Validate JSON
     Map<String, dynamic> importData;
     String? saltBase64;
     Map<String, dynamic>? encryptedEntriesMap;

     try {
       importData = jsonDecode(jsonString);
       // Basic validation of structure
       if (importData['metadata'] is! Map || importData['encryptedEntries'] is! Map) {
         throw const FormatException("Invalid backup file structure: Missing 'metadata' or 'encryptedEntries'.");
       }
       saltBase64 = importData['metadata']['saltBase64'] as String?;
       encryptedEntriesMap = importData['encryptedEntries'] as Map<String, dynamic>?;

       if (saltBase64 == null || encryptedEntriesMap == null) {
         throw const FormatException("Invalid backup file structure: Missing salt or entries map.");
       }
       // Ensure map values are strings
       encryptedEntriesMap = encryptedEntriesMap.map((key, value) => MapEntry(key, value.toString()));

     } catch (e) {
       print("Error parsing backup file: $e");
       if (mounted) {
         setState(() => _isImporting = false);
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Import failed: Invalid file format or content. ${e is FormatException ? e.message : ""}')),
         );
       }
       return;
     }

     // 4. Prompt for Master Password associated with the backup
     final String? backupPassword = await _showImportPasswordDialog();
     if (backupPassword == null || backupPassword.isEmpty || !mounted) {
       setState(() => _isImporting = false);
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Import cancelled: Password not provided.')),
       );
       return;
     }

     // 5. Confirm Overwrite
     final bool? confirmOverwrite = await _showOverwriteWarningDialog();
     if (confirmOverwrite != true || !mounted) {
       setState(() => _isImporting = false);
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Import cancelled.')),
       );
       return;
     }

     // 6. Perform Import (inside try-catch)
     try {
       final saltBytes = base64Decode(saltBase64);

       // Derive key using imported salt and entered password
       final derivedKeyBytes = await compute(deriveKeyInBackground, {
         'password': backupPassword,
         'saltBytes': saltBytes,
       });
       final derivedKeyString = base64Encode(derivedKeyBytes);

       // Clear existing data
       await _storage.deleteAll(aOptions: getAndroidOptions());
       print("Cleared existing secure storage.");

       // Store imported salt and the derived key hash
       await _storage.write(key: masterPasswordSaltKey, value: saltBase64, aOptions: getAndroidOptions());
       await _storage.write(key: masterPasswordHashKey, value: derivedKeyString, aOptions: getAndroidOptions());
       print("Stored imported salt and derived key hash.");

       // Write imported entries
       for (var entry in encryptedEntriesMap.entries) {
         await _storage.write(key: entry.key, value: entry.value, aOptions: getAndroidOptions());
       }
       print("Stored ${encryptedEntriesMap.length} imported entries.");

       // Set key in memory for immediate use
       EncryptionKeyService.instance.setKey(derivedKeyBytes);

       // Set first run flag
       final prefs = await SharedPreferences.getInstance();
       await prefs.setBool(firstRunFlagKey, true);

       if (mounted) {
         setState(() => _isImporting = false);
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Import successful!')),
         );
         // Navigate to home page, replacing the setup route
         Navigator.pushNamedAndRemoveUntil(context, homeRoute, (route) => false);
       }

     } catch (e) {
       print("Error during import process: $e");
       if (mounted) {
         setState(() => _isImporting = false);
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Import failed during processing: ${e.toString()}')),
         );
       }
     }
  }

  // Helper Dialog to get password for the backup file
  Future<String?> _showImportPasswordDialog() async {
    final passwordController = TextEditingController();
    bool isDialogPasswordVisible = false;
    final formKey = GlobalKey<FormState>(); // Key for dialog form

    return showDialog<String>(
      context: context,
      barrierDismissible: false, // User must explicitly cancel or submit
      builder: (context) {
        return StatefulBuilder( // To update visibility icon
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Enter Backup Password'),
              content: Form( // Add form for validation
                key: formKey,
                child: TextFormField(
                  controller: passwordController,
                  obscureText: !isDialogPasswordVisible,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master Password for Backup',
                    hintText: 'Enter password',
                    suffixIcon: IconButton(
                      icon: Icon(isDialogPasswordVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDialogState(() => isDialogPasswordVisible = !isDialogPasswordVisible),
                    ),
                  ),
                  validator: (value) { // Basic validation
                    if (value == null || value.isEmpty) {
                      return 'Please enter the password';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null), // Cancel
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                       Navigator.pop(context, passwordController.text); // Submit
                    }
                  },
                  child: const Text('Import'),
                ),
              ],
            );
          }
        );
      },
    ).whenComplete(() => passwordController.dispose()); // Dispose controller
  }

  // Helper Dialog to confirm overwriting data
  Future<bool?> _showOverwriteWarningDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Import'),
        content: const Text(
            'Importing from a backup will ERASE all currently stored passwords in this app. Are you sure you want to continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error, // Make it look dangerous
            ),
            onPressed: () => Navigator.pop(context, true), // Confirm
            child: const Text('Overwrite and Import'),
          ),
        ],
      ),
    );
  }
  // --- End Import Logic ---


  @override
  Widget build(BuildContext context) {
     // Combine loading states
     final bool isLoading = _isSaving || _isImporting;

     return Scaffold(
      appBar: AppBar(title: const Text('Create Master Password')),
      body: Stack( // Use Stack for overlay
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
                    const Icon(Icons.person_add_alt_1, size: 60, color: Colors.blueGrey),
                    const SizedBox(height: 20),
                    Text(
                      'Set up your Master Password',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This single password protects all your stored data. Make it strong and unique!',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                     const SizedBox(height: 4),
                     Text(
                      '(Aim for >12 characters with uppercase, lowercase, numbers, and symbols)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      enabled: !isLoading, // Disable if saving or importing
                      decoration: InputDecoration(
                        labelText: 'Master Password',
                        hintText: 'Enter your chosen password',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: isLoading ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a master password';
                        }
                        if (value.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      enabled: !isLoading, // Disable if saving or importing
                      decoration: InputDecoration(
                        labelText: 'Confirm Master Password',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                         prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: isLoading ? null : () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                          tooltip: _isConfirmPasswordVisible ? 'Hide password' : 'Show password',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your master password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                       icon: const Icon(Icons.casino_outlined, size: 18),
                       label: const Text('Need help? Generate a Strong Password'),
                       style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                       ),
                       onPressed: isLoading ? null : () {
                          Navigator.pushNamed(context, generatePasswordRoute);
                       },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('Create Master Password'),
                      style: _getButtonStyle(context),
                      onPressed: isLoading ? null : _saveMasterPassword,
                    ),
                    const SizedBox(height: 20),
                    // --- NEW: Import Button ---
                    TextButton.icon(
                       icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                       label: const Text('Import from Backup'),
                       style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                       ),
                       onPressed: isLoading ? null : _handleImport,
                    ),
                    // ---
                  ],
                ),
              ),
            ),
          ),
          // Loading Overlay
          Visibility(
            visible: isLoading, // Show if saving OR importing
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const CircularProgressIndicator(),
                     const SizedBox(height: 16),
                     Text(
                       _isSaving ? "Creating secure key..." : "Importing data...", // Dynamic text
                       style: const TextStyle(color: Colors.white, fontSize: 16)
                     ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
// --- End CreateMasterPasswordPage ---