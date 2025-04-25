import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard and PlatformException, Uint8List
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert'; // Required for jsonEncode, jsonDecode, utf8, base64Encode/Decode
import 'dart:math'; // Required for Random.secure()
import 'package:crypto/crypto.dart' show sha256; // Only import sha256 from crypto
import 'dart:async'; // Required for Timer
import 'dart:ui' as ui; // Import dart:ui (still needed for other potential UI elements)
import 'package:package_info_plus/package_info_plus.dart'; // Import package_info_plus
import 'package:random_password_generator/random_password_generator.dart'; // Import generator package
// --- Import hashlib ---
import 'package:hashlib/hashlib.dart' show pbkdf2; // Import pbkdf2 from hashlib
// --- End hashlib import ---
// --- Import for compute ---
import 'package:flutter/foundation.dart'; // Import for compute (works cross-platform)
// --- Import for Isolate (needed by compute's target function) ---
import 'dart:isolate';
// --- Import encryption package ---
import 'package:encrypt/encrypt.dart' as encrypt;
// --- Import SharedPreferences ---
import 'package:shared_preferences/shared_preferences.dart';
// --- NEW: Import file_picker and path_provider (optional but good practice) ---
import 'package:file_picker/file_picker.dart';
import 'dart:io'; // Import for File
import 'package:screen_protector/screen_protector.dart';
import 'privacy_policy_page.dart'; // Import the new privacy page
import 'terms_service_page.dart'; // Import the new terms page
// import 'package:path_provider/path_provider.dart'; // For directory access if needed later
// ---

// --- Constants for Secure Storage Keys ---
const String masterPasswordHashKey = 'master_password_key'; // Stores derived key now
const String masterPasswordSaltKey = 'master_password_salt';
// --- End Constants ---

// --- SharedPreferences Keys ---
const String themeModePrefKey = 'theme_mode';
const String themeSeedColorPrefKey = 'theme_seed_color';
const String useAmoledDarkPrefKey = 'use_amoled_dark';
const String firstRunFlagKey = 'app_first_run_completed_flag';
// ---

// --- PBKDF2 Configuration (Used by hashlib) ---
const int pbkdf2Iterations = 600000;
const int pbkdf2KeyLength = 32;
// ---

// --- Timeout Durations ---
const Duration inactivityTimeout = Duration(minutes: 5);
const Duration clipboardClearDelay = Duration(seconds: 45);
// ---

// --- Global Navigator Key ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// ---

// --- List of Authenticated Routes ---
const List<String> authenticatedRoutes = ['/home', '/add_password', '/edit_password', '/generate_password', '/about', '/settings'];
// ---

// --- List of Non-Authenticated Routes ---
const List<String> nonAuthenticatedRoutes = ['/', '/auth_wrapper', '/create_master', '/enter_master'];
// ---

// --- Helper Function to Normalize Domain ---
String normalizeDomain(String url) {
  String text = url.trim().toLowerCase();
  String parseInput = text.contains('://') ? text : 'http://$text';
  Uri? uri = Uri.tryParse(parseInput);

  if (uri != null && uri.host.isNotEmpty && uri.host.contains('.')) {
      String domain = uri.host;
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }
      return domain;
  } else {
      return text.replaceAll(RegExp(r'[/\\]'), '');
  }
}
// --- End Helper Function ---

// --- Top-level function for PBKDF2 derivation (for compute) ---
List<int> _deriveKeyInBackground(Map<String, dynamic> params) {
  final String password = params['password'];
  final List<int> saltBytes = params['saltBytes'];

  final derivedKeyDigest = pbkdf2(
     utf8.encode(password),
     saltBytes,
     pbkdf2Iterations,
     pbkdf2KeyLength
  );
  return derivedKeyDigest.bytes;
}
// --- End Top-level function ---

// --- Top-level function for Android Secure Storage options ---
AndroidOptions _getAndroidOptions() => const AndroidOptions(
      encryptedSharedPreferences: true,
    );
// ---

// --- Service to hold encryption key in memory ---
class EncryptionKeyService {
  static final EncryptionKeyService instance = EncryptionKeyService._internal();
  EncryptionKeyService._internal();

  encrypt.Key? _currentKey;

  void setKey(List<int> keyBytes) {
    if (keyBytes.length == pbkdf2KeyLength) {
      _currentKey = encrypt.Key(Uint8List.fromList(keyBytes));
      print("Encryption key set in memory.");
    } else {
      print("Error: Invalid key length provided to EncryptionKeyService.");
      _currentKey = null;
    }
  }

  void clearKey() {
    _currentKey = null;
    print("Encryption key cleared from memory.");
  }

  encrypt.Key? getKey() {
    return _currentKey;
  }

  bool isKeySet() {
    return _currentKey != null;
  }
}
// --- END EncryptionKeyService ---

// --- Theme Service (Adds AMOLED Preference) ---
class ThemeService with ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();
  ThemeService._internal();

  ThemeMode _themeMode = ThemeMode.dark;
  Color _selectedSeedColor = Colors.blueGrey;
  bool _useAmoledDark = false;
  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;
  Color get selectedSeedColor => _selectedSeedColor;
  bool get useAmoledDark => _useAmoledDark;

  Future<void> loadTheme() async {
    _prefs = await SharedPreferences.getInstance();

    // Load Theme Mode
    String? savedThemeMode = _prefs?.getString(themeModePrefKey);
    print("Loaded theme mode preference: $savedThemeMode");
    if (savedThemeMode == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.dark;
    }

    // Load Seed Color
    int? savedColorValue = _prefs?.getInt(themeSeedColorPrefKey);
    print("Loaded theme color preference: $savedColorValue");
    if (savedColorValue != null) {
        _selectedSeedColor = Color(savedColorValue);
    } else {
        _selectedSeedColor = Colors.blueGrey;
    }

    // Load AMOLED Preference
    _useAmoledDark = _prefs?.getBool(useAmoledDarkPrefKey) ?? false;
    print("Loaded AMOLED preference: $_useAmoledDark");

  }

  Future<void> toggleTheme() async {
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    print("Theme mode toggled to: $_themeMode");
    final String themeString = (_themeMode == ThemeMode.light) ? 'light' : 'dark';
    await _prefs?.setString(themeModePrefKey, themeString);
    print("Saved theme mode preference: $themeString");
    notifyListeners();
  }

  Future<void> changeSeedColor(Color newColor) async {
     if (_selectedSeedColor == newColor) return;
     _selectedSeedColor = newColor;
     print("Theme seed color changed to: $_selectedSeedColor");
     await _prefs?.setInt(themeSeedColorPrefKey, newColor.value);
     print("Saved theme color preference: ${newColor.value}");
     notifyListeners();
  }

  Future<void> setAmoledDark(bool value) async {
     if (_useAmoledDark == value) return;
     _useAmoledDark = value;
     print("AMOLED dark theme preference set to: $_useAmoledDark");
     await _prefs?.setBool(useAmoledDarkPrefKey, value);
     print("Saved AMOLED preference: $value");
     notifyListeners();
  }
}
// --- END Theme Service ---


// --- Inactivity Service (Unchanged from previous) ---
class InactivityService with WidgetsBindingObserver {
  static final InactivityService instance = InactivityService._internal();
  InactivityService._internal();

  Timer? _inactivityTimer;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _currentRouteName;
  bool _isInitialized = false;

  bool get isTimerActive => _inactivityTimer?.isActive ?? false;

  void init(GlobalKey<NavigatorState> key) {
    if (_isInitialized) return;
    _navigatorKey = key;
    WidgetsBinding.instance.addObserver(this);
    _isInitialized = true;
    print("InactivityService Initialized");
  }

  void dispose() {
    if (_isInitialized) {
        WidgetsBinding.instance.removeObserver(this);
        _inactivityTimer?.cancel();
        _isInitialized = false;
        print("InactivityService Disposed");
    }
  }

  void notifyRouteChanged(Route? route) {
     if (!_isInitialized) return;
     _currentRouteName = route?.settings.name;
     if (_currentRouteName == '/' && route is MaterialPageRoute && _navigatorKey?.currentContext != null) {
         try {
             final Widget initialWidget = route.builder(_navigatorKey!.currentContext!);
             if (initialWidget is AuthWrapper) {
                 _currentRouteName = '/auth_wrapper';
             }
             else if (initialWidget is CreateMasterPasswordPage) {
                 _currentRouteName = '/create_master';
             } else if (initialWidget is EnterMasterPasswordPage) {
                 _currentRouteName = '/enter_master';
             }
         } catch (e) {
             print("Error checking initial route widget: $e");
         }
     }
     print("Route changed: $_currentRouteName");
     _handleActivityStatus();
  }

  void handleInteraction() {
     if (!_isInitialized) return;
    if (_currentRouteName != null && authenticatedRoutes.contains(_currentRouteName)) {
       print("User interaction detected on authenticated route ($_currentRouteName). Resetting timer.");
       _resetTimer();
    } else {
       print("User interaction detected on non-authenticated route ($_currentRouteName). Timer not reset.");
    }
  }

  void _handleActivityStatus() {
     if (!_isInitialized) return;
     final bool shouldTimerBeActive = _currentRouteName != null && authenticatedRoutes.contains(_currentRouteName);
     print("Handling activity status. Current route: $_currentRouteName. Should timer be active? $shouldTimerBeActive");
     if (shouldTimerBeActive) {
        if (!EncryptionKeyService.instance.isKeySet() &&
            _currentRouteName != '/create_master' &&
            _currentRouteName != '/settings') {
            print("Warning: Entering authenticated route but encryption key is not set. Forcing lock.");
            _lockApp(forceClearKey: false);
            return;
        }
        _resetTimer();
     } else {
        _cancelTimer();
     }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;
    print("Global App Lifecycle State Changed: $state");

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_currentRouteName != null && authenticatedRoutes.contains(_currentRouteName)) {
          if (_currentRouteName != '/add_password' && _currentRouteName != '/edit_password' && _currentRouteName != '/settings') {
             print("App paused/inactive on authenticated route ($_currentRouteName). Locking now.");
             _cancelTimer();
             _lockApp();
          } else {
             print("App paused/inactive on Add/Edit Password or Settings page. Inactivity timer remains active.");
          }
      } else {
          print("App paused/inactive on non-authenticated route ($_currentRouteName). Not locking.");
      }
    } else if (state == AppLifecycleState.resumed) {
      print("App Resumed - Handling activity status check");
      _handleActivityStatus();
    }
  }

  void _resetTimer() {
     if (!_isInitialized) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(inactivityTimeout, _lockApp);
    print("Global Inactivity timer reset (Timeout: ${inactivityTimeout.inSeconds}s).");
  }

  void _cancelTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    print("Global Inactivity timer cancelled.");
  }

  void _lockApp({bool forceClearKey = true}) {
     if (!_isInitialized) return;
    if (_currentRouteName == '/enter_master') {
        print("Already on lock screen. Preventing duplicate lock.");
        return;
    }
    _cancelTimer();

    if (forceClearKey) {
       EncryptionKeyService.instance.clearKey();
    }

    print("Scheduling lock action. Navigating to /enter_master post-frame.");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navigatorKey?.currentState?.mounted == true) {
         print("Executing scheduled navigation to /enter_master.");
         _navigatorKey!.currentState!.pushNamedAndRemoveUntil(
           '/enter_master', (route) => false,
         );
         _currentRouteName = '/enter_master';
      } else {
         print("Scheduled navigation cancelled: Navigator state not available/mounted.");
      }
    });
  }
}
// --- END Inactivity Service ---

// --- Clipboard Service (Singleton, Unchanged) ---
class ClipboardService {
   static final ClipboardService instance = ClipboardService._internal();
   ClipboardService._internal();

   Timer? _clipboardClearTimer;
   String? _lastCopiedSensitiveText;

   void copyAndClearAfterDelay(String textToCopy, {Duration delay = clipboardClearDelay}) {
      _clipboardClearTimer?.cancel();
      _lastCopiedSensitiveText = textToCopy;
      Clipboard.setData(ClipboardData(text: textToCopy));
      print("Copied sensitive data to clipboard.");
      _clipboardClearTimer = Timer(delay, _clearClipboardIfNeeded);
      print("Scheduled clipboard clear in ${delay.inSeconds} seconds.");
   }

   Future<void> _clearClipboardIfNeeded() async {
      print("Clipboard clear timer fired.");
      if (_lastCopiedSensitiveText == null) {
         print("No sensitive text reference found, skipping clear.");
         return;
      }
      try {
         ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
         if (data != null && data.text == _lastCopiedSensitiveText) {
            await Clipboard.setData(const ClipboardData(text: ''));
            print("Clipboard cleared successfully.");
         } else {
            print("Clipboard content changed or is null, skipping clear.");
         }
      } catch (e) {
         print("Error accessing or clearing clipboard: $e");
      } finally {
         _lastCopiedSensitiveText = null;
         _clipboardClearTimer = null;
      }
   }

   void cancelClearTimer() {
      _clipboardClearTimer?.cancel();
      _clipboardClearTimer = null;
      _lastCopiedSensitiveText = null;
      print("Clipboard clear timer cancelled manually.");
   }
}
// --- END Clipboard Service ---


// --- Route Observer (Unchanged) ---
class InactivityRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    InactivityService.instance.notifyRouteChanged(route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    InactivityService.instance.notifyRouteChanged(previousRoute);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    InactivityService.instance.notifyRouteChanged(newRoute);
  }
}
// --- END Route Observer ---

// --- Data Model (Unchanged) ---
class PasswordEntry {
  final String service;
  final String username;
  final String password;
  final DateTime dateAdded;

  PasswordEntry({
    required this.service,
    required this.username,
    required this.password,
    required this.dateAdded,
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'username': username,
        'password': password,
        'dateAdded': dateAdded.toIso8601String(),
      };

  factory PasswordEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['dateAdded'] != null) {
       try {
         parsedDate = DateTime.parse(json['dateAdded']);
       } catch (e) {
          print("Error parsing dateAdded '${json['dateAdded']}', using epoch as fallback.");
          parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
       }
    } else {
       print("dateAdded field missing for '${json['service']}', using epoch as fallback.");
       parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return PasswordEntry(
      service: json['service'] ?? 'Unknown Service',
      username: json['username'],
      password: json['password'],
      dateAdded: parsedDate,
    );
  }
}
// --- End Data Model ---

// --- Pages / Widgets (Defined before MaterialApp) ---

// --- Simplified InactivityDetector (Stateless, Unchanged) ---
class InactivityDetector extends StatelessWidget {
  final Widget child;

  const InactivityDetector({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => InactivityService.instance.handleInteraction(),
      onPointerMove: (_) => InactivityService.instance.handleInteraction(),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
// --- END Simplified InactivityDetector ---


// AuthWrapper (Unchanged)
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _storage = const FlutterSecureStorage();
  late Future<bool> _hasMasterPasswordFuture;

  @override
  void initState() {
    super.initState();
    _hasMasterPasswordFuture = _checkMasterPassword();
  }

  Future<bool> _checkMasterPassword() async {
    final storedKey = await _storage.read(
      key: masterPasswordHashKey,
      aOptions: _getAndroidOptions(),
    );
    return storedKey != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasMasterPasswordFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Error checking storage: ${snapshot.error}'),
            ),
          );
        } else {
          final bool hasMasterPassword = snapshot.data ?? false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (!mounted) return;
             if (hasMasterPassword) {
               Navigator.pushReplacementNamed(context, '/enter_master');
             } else {
               Navigator.pushReplacementNamed(context, '/create_master');
             }
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
      },
    );
  }
}


// CreateMasterPasswordPage (Sets key in service, Unchanged)
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
  bool _isSaving = false;

  String _generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (index) => random.nextInt(256));
    return base64Encode(saltBytes);
  }

  Future<void> _saveMasterPassword() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() { _isSaving = true; });

      final password = _passwordController.text;
      final saltString = _generateSalt();
      final saltBytes = base64Decode(saltString);

      try {
        final derivedKeyBytes = await compute(_deriveKeyInBackground, {
          'password': password,
          'saltBytes': saltBytes,
        });

        final derivedKeyString = base64Encode(derivedKeyBytes);

        await _storage.write(
          key: masterPasswordHashKey,
          value: derivedKeyString,
          aOptions: _getAndroidOptions(),
        );
        await _storage.write(
          key: masterPasswordSaltKey,
          value: saltString,
          aOptions: _getAndroidOptions(),
        );

        EncryptionKeyService.instance.setKey(derivedKeyBytes);

        if (mounted) {
           setState(() { _isSaving = false; });
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Master password created successfully!')),
          );
          Navigator.pushReplacementNamed(context, '/home');
        }
      } catch (e) {
        print("Error deriving key or saving master password: $e");
         if (mounted) {
           setState(() { _isSaving = false; });
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error setting master password: ${e.toString()}')),
          );
         }
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
      appBar: AppBar(title: const Text('Create Master Password')),
      body: Stack(
        children: [
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
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: 'Master Password',
                        hintText: 'Enter your chosen password',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: _isSaving ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: 'Confirm Master Password',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                         prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility),
                          onPressed: _isSaving ? null : () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
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
                       onPressed: _isSaving ? null : () {
                          Navigator.pushNamed(context, '/generate_password');
                       },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('Create Master Password'),
                      style: _getButtonStyle(context),
                      onPressed: _isSaving ? null : _saveMasterPassword,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Visibility(
            visible: _isSaving,
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     CircularProgressIndicator(),
                     SizedBox(height: 16),
                     Text("Creating secure key...", style: TextStyle(color: Colors.white, fontSize: 16)),
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


// --- MODIFIED: EnterMasterPasswordPage (Sets key, removed biometrics) ---
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
  bool _isChecking = false; // Controls loading overlay visibility
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    EncryptionKeyService.instance.clearKey();
  }
  String _unlockingText = "Verifying password..."; // Initial text

  Future<void> _verifyMasterPassword() async {
    if (_isChecking) return;

    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() {
        _isChecking = true;
        _errorMessage = null;
      });

      final enteredPassword = _passwordController.text;

      try {
        final storedDerivedKeyString = await _storage.read(
          key: masterPasswordHashKey,
          aOptions: _getAndroidOptions(),
        );
        final storedSaltString = await _storage.read(
          key: masterPasswordSaltKey,
          aOptions: _getAndroidOptions(),
        );

        if (storedDerivedKeyString == null || storedSaltString == null) {
          print(
              "Error: Master password derived key or salt not found in storage.");
          if (mounted) {
            setState(() {
              _errorMessage =
                  'Setup error: Master password data missing. Please recreate.';
              _isChecking = false;
            });
          }
          return;
        }

        final saltBytes = base64Decode(storedSaltString);

        final calculatedDerivedKeyBytes = await compute(_deriveKeyInBackground, {
          'password': enteredPassword,
          'saltBytes': saltBytes,
        });

        final calculatedDerivedKeyString =
            base64Encode(calculatedDerivedKeyBytes);

        if (calculatedDerivedKeyString == storedDerivedKeyString) {
          EncryptionKeyService.instance.setKey(calculatedDerivedKeyBytes);

          // Sequence of updates with delays
          if (mounted) {
            setState(() {
              _unlockingText = "Verifying password...";
            });
          }
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            setState(() {
              _unlockingText = "Encrypting data...";
            });
          }
           await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            setState(() {
              _unlockingText = "Loading your vault...";
            });
          }
          await Future.delayed(const Duration(seconds: 1));

          if (mounted) {
            setState(() {
              _isChecking = false; //  Move this to the end of the sequence
            });
            Navigator.pushReplacementNamed(context, '/home');
            return;
          }
        } else {
          if (mounted) {
            setState(() {
              _errorMessage = 'Incorrect master password. Please try again.';
              _passwordController.clear();
              _isChecking = false;
            });
          }
        }
      } catch (e) {
        print("Error verifying master password: $e");
        if (mounted) {
          setState(() {
            _errorMessage =
                'An error occurred during verification: ${e.toString()}';
            _isChecking = false;
          });
        }
      }
    } else {
      if (mounted && _isChecking) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Master Password'),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.lock_open_outlined,
                        size: 60,
                        color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(height: 20),
                    Text(
                      'Enter your Master Password',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      autofocus: true,
                      enabled: !_isChecking,
                      decoration: InputDecoration(
                        labelText: 'Master Password',
                        border: const OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(12))),
                        prefixIcon: const Icon(Icons.password),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: _isChecking
                              ? null
                              : () => setState(() =>
                                  _isPasswordVisible = !_isPasswordVisible),
                          tooltip: _isPasswordVisible
                              ? 'Hide password'
                              : 'Show password',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your master password';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) =>
                          _isChecking ? null : _verifyMasterPassword(),
                    ),
                    const SizedBox(height: 16),
                    AnimatedOpacity(
                      opacity: _errorMessage != null ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage ?? '',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login_outlined),
                      label: const Text('Unlock'),
                      style: _getButtonStyle(context),
                      onPressed: _isChecking ? null : _verifyMasterPassword,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Visibility(
            visible: _isChecking,
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child:  Center(
                 child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const CircularProgressIndicator(),
                     const SizedBox(height: 16),
                     Text(_unlockingText, style: const TextStyle(color: Colors.white, fontSize: 16)),
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
// --- End EnterMasterPasswordPage ---


// --- MODIFIED: HomePage (Adds Search/Filter, Edit Button in Dialog) ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Enum for Sort Order
enum SortOrder { nameAZ, dateAdded }

class _HomePageState extends State<HomePage> {
  final _storage = const FlutterSecureStorage();
  List<PasswordEntry> _displayEntries = []; // Holds entries with cleared passwords for display
  Map<String, String> _encryptedDataMap = {}; // Holds original encrypted data
  List<PasswordEntry> _filteredDisplayEntries = []; // Holds filtered display entries
  bool _isLoading = true;
  SortOrder _currentSortOrder = SortOrder.nameAZ;

  // --- NEW: Search State ---
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  // ---

  @override
  void initState() {
    super.initState();
    _loadPasswordEntries();
    // --- NEW: Add listener for search controller ---
    _searchController.addListener(_onSearchChanged);
    // ---
  }

  @override
  void dispose() {
    // --- NEW: Dispose search controller ---
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    // ---
    super.dispose();
  }

  // --- NEW: Handle search query changes ---
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterEntries(); // Re-filter the list when search query changes
    });
  }
  // ---

  // --- NEW: Filter logic ---
  void _filterEntries() {
    if (_searchQuery.isEmpty) {
      // If search is empty, show all display entries (already sorted)
      _filteredDisplayEntries = List.from(_displayEntries);
    } else {
      final query = _searchQuery.toLowerCase();
      // Filter the display entries based on service or username containing the query
      _filteredDisplayEntries = _displayEntries.where((entry) {
        final serviceMatch = entry.service.toLowerCase().contains(query);
        final usernameMatch = entry.username.toLowerCase().contains(query);
        return serviceMatch || usernameMatch;
      }).toList();
    }
    // No need to call setState here as it's called by _onSearchChanged or after load/sort
  }
  //---

  // Method to sort display entries
  void _sortEntries() {
     if (_currentSortOrder == SortOrder.nameAZ) {
        _displayEntries.sort((a, b) => a.service.toLowerCase().compareTo(b.service.toLowerCase()));
     } else { // dateAdded (Newest First)
        _displayEntries.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
     }
     _filterEntries(); // --- MODIFIED: Re-apply filter after sorting ---
  }


  Future<void> _loadPasswordEntries() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    final key = EncryptionKeyService.instance.getKey();
    if (key == null) {
       print("Error: Encryption key not available for loading entries. Locking app.");
       if (mounted) {
         InactivityService.instance._lockApp(forceClearKey: false);
       }
       return;
    }
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    try {
      final allStoredData = await _storage.readAll(aOptions: _getAndroidOptions());
      final Map<String, String> allEntries = Map.from(allStoredData)
        ..remove(masterPasswordHashKey)
        ..remove(masterPasswordSaltKey);

      final List<PasswordEntry> loadedDisplayEntries = [];
      final Map<String, String> loadedEncryptedData = {};

      allEntries.forEach((storageKey, storedValue) {
        try {
          final combinedBytes = base64Decode(storedValue);
          if (combinedBytes.length < 12) {
             throw Exception('Stored data too short to contain IV.');
          }
          final iv = encrypt.IV(combinedBytes.sublist(0, 12));
          final ciphertextBytes = combinedBytes.sublist(12);
          final encryptedData = encrypt.Encrypted(ciphertextBytes);

          final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
          final Map<String, dynamic> json = jsonDecode(decryptedJson);
          final fullEntry = PasswordEntry.fromJson(json);

          final displayEntry = PasswordEntry(
            service: fullEntry.service,
            username: fullEntry.username,
            password: "••••••••", // Placeholder
            dateAdded: fullEntry.dateAdded,
          );
          loadedDisplayEntries.add(displayEntry);
          loadedEncryptedData[fullEntry.service] = storedValue;

        } catch (e) {
          print("Error decoding/decrypting entry for key '$storageKey': $e. Skipping entry.");
        }
      });

      _displayEntries = loadedDisplayEntries;
      _encryptedDataMap = loadedEncryptedData;

      _sortEntries(); // Sort the main display list
      _filterEntries(); // Initialize the filtered list

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading password entries: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading passwords: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deletePasswordEntry(String originalServiceName) async {
    if (!mounted) return;
    final String storageKey = normalizeDomain(originalServiceName);

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the password for "$originalServiceName"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true && mounted) {
      try {
        await _storage.delete(key: storageKey, aOptions: _getAndroidOptions());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password for "$originalServiceName" deleted.')),
          );
          _loadPasswordEntries(); // Reload and re-sort/re-filter
        }
      } catch (e) {
        print("Error deleting password entry: $e");
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting password: ${e.toString()}')),
          );
         }
      }
    }
  }

  // --- MODIFIED: Decrypts on demand, moved showDialog inside try block ---
  void _showPasswordDetails(PasswordEntry displayEntry) async {
    if (!mounted) return;

    final key = EncryptionKeyService.instance.getKey();
    if (key == null) {
       print("Error: Encryption key not available for showing details. Locking app.");
       InactivityService.instance._lockApp(forceClearKey: false);
       return;
    }
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final String? storedValue = _encryptedDataMap[displayEntry.service];

    if (storedValue == null) {
        print("Error: Could not find encrypted data for service ${displayEntry.service}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error retrieving entry data.')),
        );
        return;
    }

    PasswordEntry? fullEntry; // Make it nullable here
    try {
      final combinedBytes = base64Decode(storedValue);
      final iv = encrypt.IV(combinedBytes.sublist(0, 12));
      final ciphertextBytes = combinedBytes.sublist(12);
      final encryptedData = encrypt.Encrypted(ciphertextBytes);
      final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
      final Map<String, dynamic> json = jsonDecode(decryptedJson);
      fullEntry = PasswordEntry.fromJson(json); // Assign here

      // --- MOVED showDialog INSIDE try block after successful decryption ---
      if (fullEntry == null || !mounted) return; // Check again before showing dialog

      bool isPasswordVisible = false;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          // Use a local variable for the dialog to ensure non-null access
          final PasswordEntry entryToShow = fullEntry!;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(entryToShow.service),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      _buildDetailRow('Username:', entryToShow.username, true),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isPasswordVisible ? entryToShow.password : '••••••••',
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setDialogState(() => isPasswordVisible = !isPasswordVisible),
                            tooltip: isPasswordVisible ? 'Hide password' : 'Show password',
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              ClipboardService.instance.copyAndClearAfterDelay(entryToShow.password);
                              if (mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password copied to clipboard! (Will clear soon)')),
                                  );
                              }
                            },
                            tooltip: 'Copy password',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // --- MODIFIED: Add Edit Button to Dialog Actions ---
                actions: <Widget>[
                  TextButton(
                    child: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(context); // Close the dialog first
                      // Pass the original displayEntry which contains the service name needed by _navigateToEditPage
                      _navigateToEditPage(displayEntry);
                    },
                  ),
                  TextButton(
                    child: const Text('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
                // --- End Modification ---
              );
            },
          );
        },
      );
      // --- End moving showDialog ---

    } catch (e) {
       print("Error decrypting entry for details view: $e");
       if (mounted) { // Check mounted before showing SnackBar
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Error decrypting entry.')),
         );
       }
       return;
    }
  }
  // --- End Modification ---


  // Navigate to Edit Page
  void _navigateToEditPage(PasswordEntry displayEntry) async {
     if (!mounted) return;

     // Decrypt the full entry first
     final key = EncryptionKeyService.instance.getKey();
     if (key == null) {
        print("Error: Encryption key not available for editing. Locking app.");
        InactivityService.instance._lockApp(forceClearKey: false);
        return;
     }
     final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
     final String? storedValue = _encryptedDataMap[displayEntry.service];

     if (storedValue == null) {
         print("Error: Could not find encrypted data for service ${displayEntry.service}");
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Error retrieving entry data for editing.')),
         );
         return;
     }

     PasswordEntry? fullEntry;
     try {
       final combinedBytes = base64Decode(storedValue);
       final iv = encrypt.IV(combinedBytes.sublist(0, 12));
       final ciphertextBytes = combinedBytes.sublist(12);
       final encryptedData = encrypt.Encrypted(ciphertextBytes);
       final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
       final Map<String, dynamic> json = jsonDecode(decryptedJson);
       fullEntry = PasswordEntry.fromJson(json);
     } catch (e) {
        print("Error decrypting entry for edit view: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error decrypting entry for editing.')),
        );
        return;
     }

     if (fullEntry == null || !mounted) return;

     // Navigate to the Edit page, passing the original service name and the full entry
     final result = await Navigator.pushNamed(
       context,
       '/edit_password',
       arguments: {
         'originalServiceName': fullEntry.service, // Pass original name
         'entry': fullEntry, // Pass fully decrypted entry
       },
     );

     // Refresh list if edit was successful
     if (result == true && mounted) {
       _loadPasswordEntries();
     }
  }


  Widget _buildDetailRow(String label, String value, bool allowCopy) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
        if (allowCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied to clipboard!')),
                );
              }
            },
            tooltip: 'Copy $label',
          ),
        if (!allowCopy) const SizedBox(width: 48),
      ],
    );
  }

  void _navigateToAddPasswordPage() async {
    if (!mounted) return;
    final result = await Navigator.pushNamed(context, '/add_password');
    if (result == true && mounted) {
      _loadPasswordEntries(); // Reload and re-sort
    }
  }

  Widget _buildFallbackAvatar(PasswordEntry entry) {
    String displayInitial = '?';
    String serviceName = entry.service.trim();
    if (serviceName.isNotEmpty) {
        displayInitial = serviceName[0].toUpperCase();
    }

    return CircleAvatar(
      backgroundColor: Colors.primaries[entry.service.hashCode % Colors.primaries.length].shade700,
      foregroundColor: Colors.white,
      child: Text(displayInitial),
    );
  }

  String _cleanDomainForFavicon(String serviceUrl) {
      String domain = serviceUrl.trim();
      Uri? uri = Uri.tryParse(domain.contains('://') ? domain : 'http://$domain');
      if (uri != null && uri.host.isNotEmpty && uri.host.contains('.')) {
          return uri.host;
      }
      return '';
  }

  // Handle Menu Selection
  void _onMenuItemSelected(String value) {
    switch (value) {
      case 'generate_password':
        Navigator.pushNamed(context, '/generate_password');
        break;
      case 'about':
         Navigator.pushNamed(context, '/about');
        break;
      case 'settings':
         Navigator.pushNamed(context, '/settings');
         break;
      case 'lock':
         EncryptionKeyService.instance.clearKey();
         navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/enter_master', (route) => false);
         break;
    }
  }

  // Toggle Sort Order
  void _toggleSortOrder() {
     setState(() {
        _currentSortOrder = (_currentSortOrder == SortOrder.nameAZ)
            ? SortOrder.dateAdded
            : SortOrder.nameAZ;
        _sortEntries(); // Re-sort the display list and re-filter
     });
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('Sorted by: ${_currentSortOrder == SortOrder.nameAZ ? "Name (A-Z)" : "Date Added (Newest)"}'),
         duration: const Duration(seconds: 1),
       ),
     );
  }


  @override
  Widget build(BuildContext context) {
    final IconData sortIcon = _currentSortOrder == SortOrder.nameAZ
        ? Icons.sort_by_alpha
        : Icons.history_toggle_off_rounded;

    final String sortTooltip = _currentSortOrder == SortOrder.nameAZ
        ? 'Sorted by Name (A-Z)'
        : 'Sorted by Date Added (Newest First)';

    Widget bodyContent;
    if (_isLoading) {
       bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_displayEntries.isEmpty) {
       bodyContent = Center(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: Text(
             'No passwords saved yet.\nTap the + button to add one!',
             textAlign: TextAlign.center,
             style: Theme.of(context).textTheme.headlineSmall?.copyWith(
               color: Theme.of(context).colorScheme.onSurfaceVariant
             ),
           ),
         ),
       );
    } else if (_filteredDisplayEntries.isEmpty) {
       bodyContent = Center(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: Text(
             'No entries match your search.',
             textAlign: TextAlign.center,
             style: Theme.of(context).textTheme.titleMedium?.copyWith(
               color: Theme.of(context).colorScheme.onSurfaceVariant
             ),
           ),
         ),
       );
    } else {
       bodyContent = ListView.builder(
         padding: const EdgeInsets.only(bottom: 80, top: 0),
         itemCount: _filteredDisplayEntries.length,
         itemBuilder: (context, index) {
           final entry = _filteredDisplayEntries[index];
           final String domainForFavicon = _cleanDomainForFavicon(entry.service);
           final String faviconUrl = domainForFavicon.isNotEmpty
             ? 'https://www.google.com/s2/favicons?domain=$domainForFavicon&sz=64'
             : '';

           return Card(
             margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
             elevation: 2,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
             child: ListTile(
               leading: SizedBox(
                 width: 40,
                 height: 40,
                 child: faviconUrl.isNotEmpty
                   ? Image.network(
                       faviconUrl,
                       fit: BoxFit.contain,
                       width: 40,
                       height: 40,
                       errorBuilder: (context, error, stackTrace) {
                         print("Error loading favicon for $domainForFavicon: $error");
                         return _buildFallbackAvatar(entry);
                       },
                       loadingBuilder: (context, child, loadingProgress) {
                         if (loadingProgress == null) return child;
                         return Center(
                           child: CircularProgressIndicator(
                             strokeWidth: 2.0,
                             value: loadingProgress.expectedTotalBytes != null
                                 ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                 : null,
                           ),
                         );
                       },
                     )
                   : _buildFallbackAvatar(entry),
               ),
               title: Text(entry.service, style: const TextStyle(fontWeight: FontWeight.w500)),
               subtitle: Text(entry.username),
               trailing: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   IconButton(
                     icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.secondary),
                     onPressed: () => _navigateToEditPage(entry),
                     tooltip: 'Edit Entry',
                   ),
                   IconButton(
                     icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                     onPressed: () => _deletePasswordEntry(entry.service),
                     tooltip: 'Delete Entry',
                   ),
                   IconButton(
                     icon: Icon(Icons.visibility_outlined, color: Theme.of(context).colorScheme.secondary),
                     onPressed: () => _showPasswordDetails(entry),
                     tooltip: 'View Details',
                   ),
                 ],
               ),
               onTap: () => _showPasswordDetails(entry),
             ),
           );
         },
       );
    }


    return Scaffold(
        appBar: AppBar(
          title: const Text('Password Manager'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(sortIcon),
              tooltip: sortTooltip,
              onPressed: _toggleSortOrder,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPasswordEntries,
              tooltip: 'Refresh List',
            ),
            PopupMenuButton<String>(
              onSelected: _onMenuItemSelected,
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'generate_password',
                  child: ListTile(
                    leading: Icon(Icons.password_rounded),
                    title: Text('Generate Password'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                 const PopupMenuItem<String>(
                  value: 'about',
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('About'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'lock',
                  child: ListTile(
                     leading: Icon(Icons.logout),
                     title: Text('Lock App'),
                     contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
           children: [
             Padding(
               padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 8.0),
               child: TextField(
                 controller: _searchController,
                 decoration: InputDecoration(
                   labelText: 'Search',
                   hintText: 'Search by Service or Username...',
                   prefixIcon: const Icon(Icons.search),
                   suffixIcon: _searchQuery.isNotEmpty
                       ? IconButton(
                           icon: const Icon(Icons.clear),
                           tooltip: 'Clear Search',
                           onPressed: () {
                             _searchController.clear();
                           },
                         )
                       : null,
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12.0),
                   ),
                   contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                 ),
               ),
             ),
             Expanded(
               child: bodyContent,
             ),
           ],
         ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _navigateToAddPasswordPage,
          tooltip: 'Add New Password',
          icon: const Icon(Icons.add),
          label: const Text('Add Password'),
        ),
      );
  }
}
// --- End HomePage ---


// --- AddPasswordPage (Adds encryption on save) ---
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

// --- NEW: Edit Password Page ---
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

class _EditPasswordPageState extends State<EditPasswordPage> {
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


// --- GeneratePasswordPage (Implementation Added, Unchanged) ---
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


// --- MODIFIED: AboutPage (Removes biometric mention) ---
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

// --- MODIFIED: Settings Page (Added Export Option) ---
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ThemeService _themeService = ThemeService.instance;
  

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
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  // --- MODIFIED: Export Function (Removed Iterations/KeyLength) ---
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
      const storage = FlutterSecureStorage();
      final String? saltBase64 = await storage.read(key: masterPasswordSaltKey, aOptions: _getAndroidOptions());
      final Map<String, String> allStoredData = await storage.readAll(aOptions: _getAndroidOptions());

      if (saltBase64 == null) {
         throw Exception('Master password salt not found!');
      }

      // Filter out non-entry keys
      final Map<String, String> encryptedEntries = Map.from(allStoredData)
        ..remove(masterPasswordHashKey)
        ..remove(masterPasswordSaltKey)
        ..remove(themeModePrefKey) // Remove theme prefs etc.
        ..remove(themeSeedColorPrefKey)
        ..remove(useAmoledDarkPrefKey)
        ..remove(firstRunFlagKey);

      // 3. Prepare export structure (WITHOUT PBKDF2 params)
      final exportData = {
        'metadata': {
          'exportDate': DateTime.now().toIso8601String(),
          // 'pbkdf2Iterations': pbkdf2Iterations, // REMOVED
          // 'pbkdf2KeyLength': pbkdf2KeyLength, // REMOVED
          'saltBase64': saltBase64,
          'appVersion': (await PackageInfo.fromPlatform()).version, // Add app version
        },
        'encryptedEntries': encryptedEntries,
      };

      // 4. Encode to JSON
      // Use an encoder with indentation for better readability
      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(exportData);
      final jsonDataBytes = utf8.encode(jsonString); // Encode to bytes

      // 5. Use file_picker to save
      final String timestampString = DateTime.now().millisecondsSinceEpoch.toString();
      final String encodedTimestamp = base64UrlEncode(utf8.encode(timestampString))
          .replaceAll('=', ''); // Encode timestamp and remove padding for cleaner look
      final String fileName = 'vault_data_$encodedTimestamp.lockbox'; // Combine parts


      // Let user pick location and save file
      String? outputFile = await FilePicker.platform.saveFile(
         dialogTitle: 'Save Encrypted Backup',
         fileName: fileName,
         bytes: Uint8List.fromList(jsonDataBytes), // Pass bytes directly
         type: FileType.custom, // Use custom to allow .json
         allowedExtensions: ['lockbox'], // Suggest .json extension
      );

      if (outputFile != null && mounted) {
         print('Export saved.'); // Don't print path for privacy/security
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
  

  // --- Inside _SettingsPageState in SettingsPage ---

    // ---  Import Function ---
      // ---  Import Function ---
  Future<void> _importData(BuildContext context) async { // Added BuildContext
    // 1. File Selection
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true, // Ensure bytes are loaded for cross-platform compatibility
      //allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import cancelled.')),
        );
      }
      return;
    }

    final String? filePath = result.files.single.path; // <-- Problematic part
    if (filePath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: Could not get selected file path.')),
        );
      }
      return;
    }

    // 2. Data Reading and Validation
    try {
      final file = File(filePath); // <-- Fails on Web
      final String jsonString = await file.readAsString();
      final Map<String, dynamic> importData = jsonDecode(jsonString);

      // Validate data structure
      if (importData['metadata'] == null ||
          importData['encryptedEntries'] == null) {
        throw Exception(
            'Invalid import file format: Missing metadata or entries.');
      }

      final String? saltBase64 = importData['metadata']['saltBase64'];
      if (saltBase64 == null || saltBase64.isEmpty) {
        throw Exception('Invalid import file format: Missing salt.');
      }

      final Map<String, dynamic> encryptedEntries =
          importData['encryptedEntries'];

      // 3. Prompt for Master Password
      final String? masterPassword = await _showMasterPasswordDialog(context);
      if (masterPassword == null || masterPassword.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Import cancelled: Master Password required.')),
          );
        }
        return;
      }

      // 4. Decryption and Data Saving
      final saltBytes = base64Decode(saltBase64);
       List<int> derivedKeyBytes;

      try {
        derivedKeyBytes = await compute(_deriveKeyInBackground, {
          'password': masterPassword,
          'saltBytes': saltBytes,
        });
      } catch (e) {
        print('Error deriving key in background isolate: $e');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: ${e.toString()}')),
          );
        }
        return; // IMPORTANT:  Return after showing error
      }


      final key = encrypt.Key(Uint8List.fromList(derivedKeyBytes));
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      final storage = const FlutterSecureStorage();

      int importedCount = 0;
      for (final String storageKey in encryptedEntries.keys) {
        try {
          final encryptedData = encryptedEntries[storageKey] as String?;
          if (encryptedData == null || encryptedData.isEmpty) {
            print(
                'Skipping import of entry with empty or null encrypted data for key: $storageKey');
            continue;
          }

          final combinedBytes = base64Decode(encryptedData);
          final iv = encrypt.IV(combinedBytes.sublist(0, 12));
          final ciphertextBytes = combinedBytes.sublist(12);
          final encrypted = encrypt.Encrypted(ciphertextBytes);
          final decryptedJson = encrypter.decrypt(encrypted, iv: iv);
          final Map<String, dynamic> json = jsonDecode(decryptedJson);
          final PasswordEntry entry = PasswordEntry.fromJson(json);

          await storage.write(
              key: normalizeDomain(entry.service),
              value: encryptedData,
              aOptions: _getAndroidOptions()); // Save the original encrypted data
          importedCount++;
        } catch (e) {
          print('Error importing entry for key $storageKey: $e');
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Import failed. Invalid data.')),
            );
          }
          // Optionally, handle specific decryption or saving errors
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $importedCount entries successfully.')),
        );
      }
    } catch (e) {
      print('Error during import: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: ${e.toString()}')),
        );
      }
    }
  }


  // Helper function to show a dialog for the master password
  Future<String?> _showMasterPasswordDialog(BuildContext context) async {
    final _passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // Must enter password
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Master Password'),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Master Password'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
            TextButton(
              child: const Text('Import'),
              onPressed: () => Navigator.of(context).pop(_passwordController.text),
            ),
          ],
        );
      },
    );
  }

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
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Import Data'),
            subtitle: const Text('Restore from an encrypted backup file.'),
            onTap: () => _importData(context), // Pass context here // Add this line
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
          // ),// --- NEW: Legal Section ---
    Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        'Legal',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold
            ),
      ),
    ),
    ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: const Text('Privacy Policy'),
      onTap: () {
        Navigator.pushNamed(context, '/privacy_policy'); // Navigate to privacy page
      },
    ),
    ListTile(
      leading: const Icon(Icons.gavel_outlined),
      title: const Text('Terms of Service'),
      onTap: () {
        Navigator.pushNamed(context, '/terms_service'); // Navigate to terms page
      },
    ),
        ],
      ),
    );
  }
}
// --- END Settings Page ---


// --- Application Entry Point ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService.instance.loadTheme();

  final prefs = await SharedPreferences.getInstance();
  final bool alreadyRun = prefs.getBool(firstRunFlagKey) ?? false;
  if (!alreadyRun) {
    print("First run detected after install/data clear. Wiping secure storage.");
    const storage = FlutterSecureStorage();
    await storage.deleteAll(aOptions: _getAndroidOptions());
    EncryptionKeyService.instance.clearKey();
    await prefs.setBool(firstRunFlagKey, true);
    print("Secure storage wiped and first run flag set.");
  }

  runApp(const PasswordManagerApp());
}
// --- End main() ---

// --- MODIFIED: Main Application Widget (Adds Edit Route) ---
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
    InactivityService.instance.init(navigatorKey);
    _themeService.addListener(_onThemeChanged);
    _applyScreenProtection(); // <-- Call the protection method
  }
  Future<void> _applyScreenProtection() async {
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.preventScreenshotOn(); // Uses FLAG_SECURE on Android
        print("Screen recording/screenshot protection enabled for Android.");
      } else if (Platform.isIOS) {
        await ScreenProtector.preventScreenshotOn(); // Attempts iOS protection
        // Optional: Add protection for when app is in background/switcher on iOS
        // await ScreenProtector.protectDataLeakageWithBlur(); // Or .protectDataLeakageWithColor(Colors.white);
        print("Screen recording/screenshot protection enabled for iOS.");
      }
    } catch (e) {
      print("Error applying screen protection: $e");
    }
  }
   @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Secure Passwords',
      navigatorKey: navigatorKey,
      themeMode: _themeService.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: _themeService.selectedSeedColor,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: _themeService.selectedSeedColor,
        useMaterial3: true,
         scaffoldBackgroundColor: _themeService.useAmoledDark ? Colors.black : null,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [InactivityRouteObserver()],
      routes: {
        '/home': (context) => const HomePage(),
        '/create_master': (context) => const CreateMasterPasswordPage(),
        '/enter_master': (context) => const EnterMasterPasswordPage(),
        '/add_password': (context) => const AddPasswordPage(),
        '/generate_password': (context) => const GeneratePasswordPage(),
        '/about': (context) => const AboutPage(),
        '/settings': (context) => const SettingsPage(),
        '/privacy_policy': (context) => const PrivacyPolicyPage(),
        '/terms_service': (context) => const TermsServicePage(),
        '/edit_password': (context) {
           final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
           if (args == null || args['entry'] == null || args['originalServiceName'] == null) {
              print("Error: Missing arguments for edit page.");
              return const Scaffold(body: Center(child: Text("Error loading edit page.")));
           }
           return EditPasswordPage(
              originalServiceName: args['originalServiceName'] as String,
              entry: args['entry'] as PasswordEntry,
           );
        },
      },
      builder: (context, child) {
        return child == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : InactivityDetector(child: child);
      },
    );
  }
}