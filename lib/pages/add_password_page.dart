// --- AddPasswordPage (Adds encryption on save) ---
import 'package:flutter/material.dart'; // Already listed
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Already listed
import 'dart:convert'; // Already listed
import 'package:encrypt/encrypt.dart' as encrypt; // Already listed

import '../models/password_entry.dart'; // New relative import
import '../services/encryption_key_service.dart'; // New relative import
import '../utils/constants.dart'; // Already listed (implicitly via helpers)
import '../utils/helpers.dart'; // Already listed
class AddPasswordPage extends StatefulWidget {
  const AddPasswordPage({super.key});

  @override
  State<AddPasswordPage> createState() => _AddPasswordPageState();
}

class _AddPasswordPageState extends State<AddPasswordPage> {
  final _serviceController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();
  bool _isPasswordVisible = false;
  bool _isSaving = false;

  Future<void> _savePasswordEntry() async {
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

    bool proceedSaving = true;
    final String originalServiceName = _serviceController.text.trim();
    final String storageKey = normalizeDomain(originalServiceName);

    final entry = PasswordEntry(
      service: originalServiceName,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      dateAdded: DateTime.now(),
    );

    try {
      final existingEntry = await _storage.read(key: storageKey, aOptions: _getAndroidOptions());
      if (existingEntry != null && mounted) {
        proceedSaving = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Entry Exists'),
              content: Text('An entry for "$originalServiceName" (or its equivalent "$storageKey") already exists. Overwrite?'),
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

      if (proceedSaving && mounted) {
        final jsonString = jsonEncode(entry.toJson());
        final iv = encrypt.IV.fromSecureRandom(12);
        final encrypted = encrypter.encrypt(jsonString, iv: iv);
        final storedValue = base64Encode(iv.bytes + encrypted.bytes);

        await _storage.write(key: storageKey, value: storedValue, aOptions: _getAndroidOptions());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password for "$originalServiceName" saved successfully!')),
          );
          Navigator.pop(context, true);
          return;
        }
      } else if (!proceedSaving) {
         if (mounted) setState(() => _isSaving = false);
      }

    } catch (e) {
      print("Error saving password entry: $e");
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving password: ${e.toString()}')),
        );
       }
    } finally {
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
        title: const Text('Add New Password'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              TextFormField(
                controller: _serviceController,
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
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                    : const Icon(Icons.save_alt),
                label: Text(_isSaving ? 'Saving...' : 'Save Password'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: _isSaving ? null : _savePasswordEntry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// --- END AddPasswordPage ---