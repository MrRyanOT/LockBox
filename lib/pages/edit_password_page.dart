// --- NEW: Edit Password Page ---
import 'package:flutter/material.dart'; // Already listed
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Already listed
import 'dart:convert'; // Already listed
import 'package:encrypt/encrypt.dart' as encrypt; // Already listed

import '../models/password_entry.dart'; // New relative import
import '../services/encryption_key_service.dart'; // New relative import
import '../utils/constants.dart'; // Already listed (implicitly via helpers)
import '../utils/helpers.dart'; // Already listed

class EditPasswordPage extends StatefulWidget {
  final String originalServiceName; // Needed to find/delete old entry if service name changes
  final PasswordEntry entry; // The fully decrypted entry to edit

  const EditPasswordPage({
    super.key,
    required this.originalServiceName,
    required this.entry,
  });

  @override
  State<EditPasswordPage> createState() => _EditPasswordPageState();
}

class EditPasswordPageState extends State<EditPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _serviceController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  final _storage = const FlutterSecureStorage();
  bool _isPasswordVisible = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill controllers with existing data
    _serviceController = TextEditingController(text: widget.entry.service);
    _usernameController = TextEditingController(text: widget.entry.username);
    _passwordController = TextEditingController(text: widget.entry.password);
    _isPasswordVisible = false; // Start with password obscured
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!mounted) return;

    final key = EncryptionKeyService.instance.getKey();
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Encryption key not available. Please re-login.')),
      );
      return;
    }
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    setState(() { _isSaving = true; });

    final String newServiceName = _serviceController.text.trim();
    final String newUsername = _usernameController.text.trim();
    final String newPassword = _passwordController.text;
    final String originalStorageKey = normalizeDomain(widget.originalServiceName);
    final String newStorageKey = normalizeDomain(newServiceName);

    // Create the updated entry object
    final updatedEntry = PasswordEntry(
      service: newServiceName,
      username: newUsername,
      password: newPassword,
      dateAdded: widget.entry.dateAdded, // Keep original date or update? Let's keep original for now.
      // dateAdded: DateTime.now(), // Alternative: Update date on edit
    );

    try {
      bool proceedSaving = true;

      // --- Handle Service Name Change ---
      if (originalStorageKey != newStorageKey) {
        // Check if an entry *already exists* for the NEW key
        final existingEntryCheck = await _storage.read(key: newStorageKey, aOptions: _getAndroidOptions());
        if (existingEntryCheck != null && mounted) {
          proceedSaving = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Entry Exists'),
                    content: Text('An entry for "$newServiceName" (or its equivalent "$newStorageKey") already exists. Overwrite?'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                        child: const Text('Overwrite'),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  );
                },
              ) ?? false;
        }
      }
      // --- End Handle Service Name Change ---

      if (proceedSaving && mounted) {
        // Encrypt the updated data
        final jsonString = jsonEncode(updatedEntry.toJson());
        final iv = encrypt.IV.fromSecureRandom(12);
        final encrypted = encrypter.encrypt(jsonString, iv: iv);
        final storedValue = base64Encode(iv.bytes + encrypted.bytes);

        // If service name changed, delete the old entry first
        if (originalStorageKey != newStorageKey) {
           print("Service name changed. Deleting old entry: $originalStorageKey");
           await _storage.delete(key: originalStorageKey, aOptions: _getAndroidOptions());
        }

        // Write the new/updated entry (using the new key if name changed)
        await _storage.write(key: newStorageKey, value: storedValue, aOptions: _getAndroidOptions());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password for "$newServiceName" updated successfully!')),
          );
          Navigator.pop(context, true); // Return true to signal success
          return;
        }
      } else if (!proceedSaving) {
         // If user cancelled overwrite, reset saving state
         if (mounted) setState(() => _isSaving = false);
      }

    } catch (e) {
      print("Error saving updated password entry: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating password: ${e.toString()}')),
        );
      }
    } finally {
      // Ensure saving state is reset if mounted and saving was true
      if (mounted && _isSaving) {
         setState(() { _isSaving = false; });
      }
    }
  }


  @override
  void dispose() {
    _serviceController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Password'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              TextFormField(
                controller: _serviceController,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'Service Name or URL',
                  hintText: 'e.g., Google, My Router, https://...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.label_important_outline),
                ),
                keyboardType: TextInputType.text,
                autocorrect: false,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                     return 'Please enter a name for this entry';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                enabled: !_isSaving,
                decoration: InputDecoration(
                  labelText: 'Username/Email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                 validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter a username or email';
                  return null;
                 },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                enabled: !_isSaving,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                    onPressed: _isSaving ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                  ),
                ),
                 validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a password';
                  return null;
                 },
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: _isSaving
                    ? Container(
                        width: 24, height: 24, padding: const EdgeInsets.all(2.0),
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 3,
                        ),
                      )
                    : const Icon(Icons.save), // Changed icon
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'), // Changed text
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: _isSaving ? null : _saveChanges,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- END Edit Password Page ---