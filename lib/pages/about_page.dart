// --- MODIFIED: AboutPage (Removes biometric mention) ---
import 'package:flutter/material.dart'; // Already listed
import 'package:package_info_plus/package_info_plus.dart'; // Already listed
import '../utils/constants.dart'; // New relative import
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Password Manager', // Default name
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
  );
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
     if (mounted) {
        setState(() => _isLoading = true);
     }
    try {
      final info = await PackageInfo.fromPlatform();
       if (mounted) {
          setState(() {
            _packageInfo = info;
            _isLoading = false;
          });
       }
    } catch (e) {
      print("Error loading package info: $e");
      if (mounted) {
        setState(() => _isLoading = false); // Stop loading even on error
      }
    }
  }

  // Helper to build text sections
  Widget _buildSection(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary, // Use primary color for titles
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5), // Add line spacing
        ),
        const SizedBox(height: 24), // Spacing after section
      ],
    );
  }

   // Helper to build list items
  Widget _buildListItem(BuildContext context, IconData icon, String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView( // Use ListView for scrolling
              padding: const EdgeInsets.all(20.0),
              children: <Widget>[
                // App Icon and Name/Version
                Row(
                  children: [
                     Icon(Icons.security_rounded, size: 52, color: colorScheme.primary),
                     const SizedBox(width: 16),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             _packageInfo.appName, // Use dynamic app name
                             style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                           ),
                           Text(
                            'Version ${_packageInfo.version} (Build ${_packageInfo.buildNumber})',
                             style: textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
                           ),
                         ],
                       ),
                     ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),

                // Purpose
                _buildSection(
                  context,
                  'Purpose',
                  'This application is designed to simplify your digital life by providing a secure and convenient place to store your website logins, passwords, and other sensitive credentials directly on your device.'
                ),

                // Security Commitment
                 _buildSection(
                  context,
                  'Our Commitment to Security',
                  'Your security is fundamental to this application. Here\'s how we protect your data:'
                ),
                _buildListItem(context, Icons.shield_outlined,
                  'Master Password: Your vault is protected by a single Master Password that *only you* know. We **never** store your Master Password directly. Instead, we store a unique, cryptographically secure derived key (using PBKDF2 with a random salt) which is used only to verify your identity when you unlock the app.'
                ),
                 _buildListItem(context, Icons.storage_rounded,
                  'Local, Encrypted Storage: All your credential data is stored exclusively on this device\'s local storage using the operating system\'s secure storage mechanisms (Keychain on iOS, Keystore/EncryptedSharedPreferences on Android). Your data is **never** sent to any external servers or cloud services by this app.'
                ),
                _buildListItem(context, Icons.enhanced_encryption_outlined, // NEW Icon
                  'Entry Encryption: Your saved entries (including passwords) are individually encrypted using AES-GCM before being stored, adding an extra layer of security.' // NEW Text
                ),
                _buildListItem(context, Icons.timer_outlined,
                  'Automatic Locking: The app automatically locks after ${inactivityTimeout.inMinutes} minutes of inactivity, or when the app is sent to the background (except when adding a new password).'
                ),
                 _buildListItem(context, Icons.content_cut_rounded,
                  'Secure Clipboard Handling: Passwords copied from the app are automatically removed from the system clipboard after ${clipboardClearDelay.inSeconds} seconds to minimize accidental exposure.'
                ),
                 const SizedBox(height: 24), // Spacing after list items

                 // Key Features (Could be a list as well)
                 _buildSection(
                  context,
                  'Key Features',
                  '• Securely add, view, edit, and delete login credentials.\n' // Added Edit
                  '• Strong Master Password protection (PBKDF2, salted & iterated).\n'
                  '• Entry data encryption using AES-GCM.\n'
                  '• Automatic lock on inactivity and backgrounding.\n'
                  '• Automatic clipboard clearing for copied passwords.\n'
                  '• Password generator for creating strong passwords.\n'
                  '• Sorting options for the password list.\n'
                  '• Theme selection (Light/Dark Mode, Color).'
                 ),

                 // Important Reminders
                 _buildSection(
                  context,
                  'Important Reminders',
                  '• Master Password Responsibility: Your Master Password is the only key to your vault. Choose something strong and memorable, but **please understand that there is absolutely no way to recover your data if you forget your Master Password.** Keep it safe!\n\n'
                  '• Local Data & Backups: Since data is stored only locally, ensure you have a reliable backup strategy for your entire device (e.g., iCloud Backup, Google Drive Backup) if you want to restore your data if your device is lost or damaged. This app does not include its own backup or sync feature.\n\n'
                  '• Device Security: The security of this app also depends on the overall security of your device (e.g., using a strong device passcode/biometrics).'
                 ),

                 // How to Use
                 _buildSection(
                  context,
                  'How to Use',
                  '1. Set a strong Master Password on first launch (use the generator for help!).\n'
                  '2. Use the \'+\' button on the home screen to add new login entries.\n'
                  '3. Tap an entry to view details or copy the username/password.\n'
                  '4. Use the edit icon (pencil) on an entry to modify it.\n' // Added Edit step
                  '5. Use the menu icon (⋮) on the home screen for other options like generating passwords, changing settings, or locking the app.' // Renumbered
                 ),

                 // Licenses Button
                 Center(
                   child: ElevatedButton.icon(
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('View Licenses'),
                      onPressed: () {
                        showLicensePage(
                          context: context,
                          applicationName: _packageInfo.appName,
                          applicationVersion: _packageInfo.version,
                          applicationIcon: Padding( // Add padding around icon
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                                Icons.security_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                           applicationLegalese: '© ${DateTime.now().year} [Your Name / Company Name Here]', // Placeholder
                        );
                      },
                      style: ElevatedButton.styleFrom(
                         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                 ),
                  const SizedBox(height: 24),
                  // Developed by
                  Text(
                    'Developed by: [Your Name / Company Name Here]', // Placeholder
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20), // Bottom padding
              ],
            ),
    );
  }
}
// --- END AboutPage ---