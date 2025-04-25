// --- File: lib/pages/settings_page.dart ---

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Uint8List if needed elsewhere
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert'; // For jsonEncode, utf8, base64Decode
import 'dart:typed_data'; // For Uint8List

import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart'; // For getAndroidOptions

// Settings Page Widget
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ThemeService _themeService = ThemeService.instance;
  final _storage = const FlutterSecureStorage(); // For export

  // Theme color options displayed in the settings
  final Map<String, Color> _themeColors = {
    'Blue Grey (Default)': Colors.blueGrey,
    'Green': Colors.green,
    'Purple': Colors.purple,
    'Neon Cyan': Colors.cyan,
    'Orange': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    // Listen to theme changes to rebuild UI elements like switches/radios
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  // Callback function to rebuild the state when theme changes
  void _onThemeChanged() {
    setState(() {});
  }

  // --- Export Function ---
  Future<void> _exportData() async {
    // 1. Show confirmation dialog with warnings
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Encrypted Data'),
        content: const SingleChildScrollView( // Ensure content scrolls if needed
          child: ListBody(
            children: <Widget>[
              Text('This will export your encrypted password entries and the necessary salt to decrypt them later.'),
              SizedBox(height: 12),
              Text(
                'IMPORTANT:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('• The exported file contains ENCRYPTED data.'),
              Text('• It is ONLY useful if you remember your Master Password.'),
              Text('• Store the exported file SECURELY.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return; // User cancelled or widget unmounted
    }

    // Show loading indicator (optional)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing export...')),
    );

    // 2. Gather data
    try {
      final String? saltBase64 = await _storage.read(key: masterPasswordSaltKey, aOptions: getAndroidOptions());
      final Map<String, String> allStoredData = await _storage.readAll(aOptions: getAndroidOptions());

      if (saltBase64 == null) {
         throw Exception('Master password salt not found!');
      }

      // Filter out non-entry keys (like master key hash, theme settings, etc.)
      final Map<String, String> encryptedEntries = Map.from(allStoredData)
        ..remove(masterPasswordHashKey)
        ..remove(masterPasswordSaltKey)
        ..remove(themeModePrefKey)
        ..remove(themeSeedColorPrefKey)
        ..remove(useAmoledDarkPrefKey)
        ..remove(firstRunFlagKey);

      // 3. Prepare export structure (WITHOUT PBKDF2 params as requested)
      final exportData = {
        'metadata': {
          'exportDate': DateTime.now().toIso8601String(),
          // 'pbkdf2Iterations': pbkdf2Iterations, // REMOVED as requested
          // 'pbkdf2KeyLength': pbkdf2KeyLength, // REMOVED as requested
          'saltBase64': saltBase64,
          'appVersion': (await PackageInfo.fromPlatform()).version, // Add app version
        },
        'encryptedEntries': encryptedEntries,
      };

      // 4. Encode to JSON
      // Use an encoder with indentation for better readability of the backup file
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(exportData);
      final jsonDataBytes = utf8.encode(jsonString); // Encode to bytes for saving

      // 5. Use file_picker to save
      // Suggest a filename including the date
      final String fileName = 'password_manager_backup_${DateTime.now().toIso8601String().split('T')[0]}.json';

      // Let user pick location and save file
      String? outputFile = await FilePicker.platform.saveFile(
         dialogTitle: 'Save Encrypted Backup',
         fileName: fileName,
         bytes: Uint8List.fromList(jsonDataBytes), // Pass bytes directly
         type: FileType.custom, // Use custom to allow .json
         allowedExtensions: ['json'], // Suggest .json extension
      );

      if (outputFile != null && mounted) {
         print('Export saved.'); // Avoid printing path for privacy
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Export successful! File saved.')),
         );
      } else if (mounted) {
         print('Export cancelled by user.');
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Export cancelled.')),
         );
      }

    } catch (e) {
       print("Error during export: $e");
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: ${e.toString()}')),
          );
       }
    }
  }
  // --- End Export Function ---


  @override
  Widget build(BuildContext context) {
    final bool isCurrentlyDark = _themeService.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: <Widget>[
          // --- Theme Section ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold
                  ),
            ),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            secondary: Icon(isCurrentlyDark
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined),
            value: isCurrentlyDark,
            onChanged: (bool value) {
              _themeService.toggleTheme();
            },
          ),
           SwitchListTile(
            title: const Text('Use True Black Background (AMOLED)'),
            subtitle: Text('Saves power on OLED screens', style: TextStyle(color: !isCurrentlyDark ? Colors.grey : null)),
            secondary: Icon(Icons.contrast_rounded, color: !isCurrentlyDark ? Colors.grey : null),
            value: _themeService.useAmoledDark,
            onChanged: isCurrentlyDark ? (bool value) {
              _themeService.setAmoledDark(value);
            } : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 8, 16, 8), // Indent color options
            child: Text(
              'Theme Color',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ..._themeColors.entries.map((entry) {
             final String name = entry.key;
             final Color color = entry.value;
             return RadioListTile<Color>(
                title: Text(name),
                value: color,
                groupValue: _themeService.selectedSeedColor,
                onChanged: (Color? newColor) {
                  if (newColor != null) {
                     _themeService.changeSeedColor(newColor);
                  }
                },
                secondary: CircleAvatar(backgroundColor: color, radius: 12),
                activeColor: Theme.of(context).colorScheme.primary,
                contentPadding: const EdgeInsets.only(left: 72.0, right: 16.0), // Indent
             );
          }).toList(),
          const Divider(),
          // --- Data Management Section ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Data Management',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold
                  ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export Encrypted Data'),
            subtitle: const Text('Save an encrypted backup file.'),
            onTap: _exportData, // Call the export function
          ),
          // TODO: Add Import Tile later
          // ListTile(
          //   leading: Icon(Icons.download_for_offline_outlined),
          //   title: Text('Import Data'),
          //   subtitle: Text('Restore from an encrypted backup file.'),
          //   onTap: () {
          //     // Implement import logic
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       SnackBar(content: Text('Import not implemented yet.')),
          //     );
          //   },
          // ),
        ],
      ),
    );
  }
}
// --- END Settings Page ---
