// --- GeneratePasswordPage (Implementation Added, Unchanged) ---
import 'package:flutter/material.dart'; // Already listed
import 'dart:math'; // Already listed
import '../services/clipboard_service.dart'; // New relative import
class GeneratePasswordPage extends StatefulWidget {
  const GeneratePasswordPage({super.key});

  @override
  State<GeneratePasswordPage> createState() => _GeneratePasswordPageState();
}

class _GeneratePasswordPageState extends State<GeneratePasswordPage> {
  // State variables for generator options
  double _passwordLength = 16.0;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  String _generatedPassword = '';

  // Character sets
  static const String _uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
  static const String _numberChars = '0123456789';
  static const String _symbolChars = '!@#\$%^&*()_+-=[]{}|;:,.<>/?~';

  @override
  void initState() {
    super.initState();
    // Generate an initial password when the page loads
    _generatePassword();
  }

  // Generate password based on current options
  void _generatePassword() {
    // Build the character pool
    String charPool = '';
    List<String> requiredCharsPool = []; // Keep track of required types

    if (_includeUppercase) {
       charPool += _uppercaseChars;
       requiredCharsPool.add(_uppercaseChars);
    }
    if (_includeLowercase) {
       charPool += _lowercaseChars;
       requiredCharsPool.add(_lowercaseChars);
    }
    if (_includeNumbers) {
       charPool += _numberChars;
       requiredCharsPool.add(_numberChars);
    }
    if (_includeSymbols) {
       charPool += _symbolChars;
       requiredCharsPool.add(_symbolChars);
    }


    // Ensure at least one character type is selected
    if (charPool.isEmpty) {
      setState(() {
        _generatedPassword = 'Select at least one character type!';
      });
      return;
    }

    final random = Random.secure();
    int length = _passwordLength.round();
    String password = '';

    // Ensure password length is sufficient for required characters
    if(length < requiredCharsPool.length) {
        print("Warning: Password length is less than the number of required character types. Increasing length.");
        length = requiredCharsPool.length;
    }

    // Generate the main part of the password
    List<String> passwordChars = List.generate(length, (index) {
      final randomIndex = random.nextInt(charPool.length);
      return charPool[randomIndex];
    });

    // Ensure at least one character from each required pool is included
    for (int i = 0; i < requiredCharsPool.length; i++) {
       passwordChars[i] = requiredCharsPool[i][random.nextInt(requiredCharsPool[i].length)];
    }

    // Shuffle the list to ensure required chars are not just at the beginning
    passwordChars.shuffle(random);
    password = passwordChars.join();


    setState(() {
      _generatedPassword = password;
    });
  }

  // Copy generated password to clipboard
  void _copyPassword() {
    if (_generatedPassword.isNotEmpty && !_generatedPassword.startsWith('Select')) {
      ClipboardService.instance.copyAndClearAfterDelay(_generatedPassword);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generated password copied! (Will clear soon)'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Password'),
      ),
      body: ListView( // Use ListView for scrolling on smaller screens
        padding: const EdgeInsets.all(16.0),
        children: [
          // Display Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant, // Background color
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _generatedPassword.isEmpty ? ' ' : _generatedPassword, // Show space if empty initially
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'monospace', // Use monospace for passwords
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy Password',
                  onPressed: _copyPassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Length Slider
          Text('Password Length: ${_passwordLength.round()}', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _passwordLength,
            min: 8.0,
            max: 64.0,
            divisions: 56, // (64 - 8)
            label: _passwordLength.round().toString(),
            onChanged: (value) {
              setState(() { // Update state AND regenerate
                _passwordLength = value;
                _generatePassword(); // Call generator here
              });
            },
          ),
          const SizedBox(height: 16),

          // Options
          Text('Include Characters:', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Uppercase Letters (A-Z)'),
            value: _includeUppercase,
            onChanged: (value) => setState(() { // Update state AND regenerate
                _includeUppercase = value;
                _generatePassword();
            }),
            secondary: const Icon(Icons.text_fields_rounded),
          ),
          SwitchListTile(
            title: const Text('Lowercase Letters (a-z)'),
            value: _includeLowercase,
            onChanged: (value) => setState(() { // Update state AND regenerate
                _includeLowercase = value;
                _generatePassword();
            }),
             secondary: const Icon(Icons.text_fields),
          ),
          SwitchListTile(
            title: const Text('Numbers (0-9)'),
            value: _includeNumbers,
            onChanged: (value) => setState(() { // Update state AND regenerate
                _includeNumbers = value;
                _generatePassword();
            }),
             secondary: const Icon(Icons.pin_outlined), // Example icon
          ),
          SwitchListTile(
            title: const Text('Symbols (!@#...)'),
            value: _includeSymbols,
            onChanged: (value) => setState(() { // Update state AND regenerate
                _includeSymbols = value;
                _generatePassword();
            }),
             secondary: const Icon(Icons.alternate_email_rounded), // Example icon
          ),
          const SizedBox(height: 32),

          // Generate Button (Optional now, but kept for explicit refresh)
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Generate New Password'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: _generatePassword, // Call generation logic
          ),
        ],
      ),
    );
  }
}
// --- END GeneratePasswordPage ---