import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard and PlatformException
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert'; // Required for jsonEncode, jsonDecode, utf8
import 'dart:math'; // Required for Random.secure()
import 'package:crypto/crypto.dart'; // Required for sha256
import 'dart:async'; // Required for Timer
import 'dart:ui' as ui; // Import dart:ui (still needed for other potential UI elements)
import 'package:local_auth/local_auth.dart'; // Import local_auth
// Import local_auth error constants if using newer versions or for clarity
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:package_info_plus/package_info_plus.dart'; // Import package_info_plus
import 'package:random_password_generator/random_password_generator.dart'; // NEW: Import generator package


// --- Constants for Secure Storage Keys ---
const String masterPasswordHashKey = 'master_password_hash';
const String masterPasswordSaltKey = 'master_password_salt';
// --- End Constants ---

// --- Timeout Durations ---
const Duration inactivityTimeout = Duration(minutes: 5);
const Duration clipboardClearDelay = Duration(seconds: 45); // Auto-clear clipboard after 45 seconds
// ---

// --- Global Navigator Key ---
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
// ---

// --- List of Authenticated Routes ---
// Routes where the inactivity timer should be active
const List<String> authenticatedRoutes = ['/home', '/add_password', '/generate_password', '/about'];
// ---

// --- List of Non-Authenticated Routes (where timer should be off) ---
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

// --- Inactivity Service (Singleton, Unchanged) ---
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
         final Widget initialWidget = route.builder(_navigatorKey!.currentContext!);
         if (initialWidget is AuthWrapper) {
             _currentRouteName = '/auth_wrapper';
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
        _resetTimer();
     } else {
        _cancelTimer();
     }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
     if (!_isInitialized) return;
    print("Global App Lifecycle State Changed: $state");
    if (state == AppLifecycleState.resumed) {
      print("App Resumed - Handling activity status check");
      _handleActivityStatus();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      print("App Paused/Inactive - Timer state depends on current route.");
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

  void _lockApp() {
     if (!_isInitialized) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    print("Global Inactivity timeout reached. Locking app.");
    _navigatorKey?.currentState?.pushNamedAndRemoveUntil(
      '/enter_master', (route) => false,
    );
  }
}
// --- END Inactivity Service ---

// --- Clipboard Service (Singleton, Unchanged) ---
class ClipboardService {
   static final ClipboardService instance = ClipboardService._internal();
   ClipboardService._internal(); // Private constructor

   Timer? _clipboardClearTimer;
   String? _lastCopiedSensitiveText;

   // Copies text and schedules clearing
   void copyAndClearAfterDelay(String textToCopy, {Duration delay = clipboardClearDelay}) {
      // Cancel any previous timer
      _clipboardClearTimer?.cancel();
      _lastCopiedSensitiveText = textToCopy; // Store what was copied

      // Copy to clipboard
      Clipboard.setData(ClipboardData(text: textToCopy));
      print("Copied sensitive data to clipboard.");

      // Schedule clearing
      _clipboardClearTimer = Timer(delay, _clearClipboardIfNeeded);
      print("Scheduled clipboard clear in ${delay.inSeconds} seconds.");
   }

   // Clears clipboard only if it still contains the last copied sensitive text
   Future<void> _clearClipboardIfNeeded() async {
      print("Clipboard clear timer fired.");
      if (_lastCopiedSensitiveText == null) {
         print("No sensitive text reference found, skipping clear.");
         return; // Nothing to check against
      }

      try {
         ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
         if (data != null && data.text == _lastCopiedSensitiveText) {
            await Clipboard.setData(const ClipboardData(text: '')); // Clear
            print("Clipboard cleared successfully.");
         } else {
            print("Clipboard content changed or is null, skipping clear.");
         }
      } catch (e) {
         print("Error accessing or clearing clipboard: $e");
      } finally {
         // Clear reference regardless of success/failure to prevent accidental future clears
         _lastCopiedSensitiveText = null;
         _clipboardClearTimer = null; // Timer has fired
      }
   }

   // Optional: Explicitly cancel timer if needed elsewhere
   void cancelClearTimer() {
      _clipboardClearTimer?.cancel();
      _clipboardClearTimer = null;
      _lastCopiedSensitiveText = null; // Also clear reference on manual cancel
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


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // InactivityService init moved to PasswordManagerApp initState
  runApp(const PasswordManagerApp());
}

// --- PasswordManagerApp (Stateful, Unchanged) ---
class PasswordManagerApp extends StatefulWidget {
  const PasswordManagerApp({super.key});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp> {

  @override
  void initState() {
    super.initState();
    InactivityService.instance.init(navigatorKey);
  }

   @override
  void dispose() {
    // Optional: Dispose service if needed
    // InactivityService.instance.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Secure Passwords', // Example App Name
      navigatorKey: navigatorKey,
      theme: ThemeData(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
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
      },
      builder: (context, child) {
        return child == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : InactivityDetector(child: child);
      },
    );
  }
}
// --- End PasswordManagerApp ---

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
    final hash = await _storage.read(
      key: masterPasswordHashKey,
      aOptions: _getAndroidOptions(),
    );
    return hash != null;
  }

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

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


// CreateMasterPasswordPage (Generator button added)
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

  String _hashPassword(String password, String salt) {
    final saltedPassword = utf8.encode(password + salt);
    final hash = sha256.convert(saltedPassword);
    return hash.toString();
  }

  Future<void> _saveMasterPassword() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() { _isSaving = true; });

      final password = _passwordController.text;
      final salt = _generateSalt();
      final hash = _hashPassword(password, salt);

      try {
        await _storage.write(
          key: masterPasswordHashKey,
          value: hash,
          aOptions: _getAndroidOptions(),
        );
        await _storage.write(
          key: masterPasswordSaltKey,
          value: salt,
          aOptions: _getAndroidOptions(),
        );

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Master password created successfully!')),
          );
          Navigator.pushReplacementNamed(context, '/home');
        }
      } catch (e) {
        print("Error saving master password: $e");
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving master password: ${e.toString()}')),
          );
           setState(() { _isSaving = false; });
         }
      }
    }
  }

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.person_add_alt_1, size: 60, color: Colors.blueGrey), // Use valid icon
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
                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    hintText: 'Enter your chosen password',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
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
                // Confirm Password Field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Confirm Master Password',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                     prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
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
                // Generate Password Button
                TextButton.icon(
                   icon: const Icon(Icons.casino_outlined, size: 18),
                   label: const Text('Need help? Generate a Strong Password'),
                   style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.secondary,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                   ),
                   onPressed: () {
                      // Navigate to the generator page
                      // User will copy/paste from there
                      Navigator.pushNamed(context, '/generate_password');
                   },
                ),
                const SizedBox(height: 24),
                // Save Button
                ElevatedButton.icon(
                  icon: _isSaving ? _buildLoadingIndicator() : const Icon(Icons.save_alt_outlined),
                  label: Text(_isSaving ? 'Saving...' : 'Create Master Password'),
                  style: _getButtonStyle(context),
                  onPressed: _isSaving ? null : _saveMasterPassword,
                ),
              ],
            ),
          ),
        ),
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

   Widget _buildLoadingIndicator() {
    return Container(
      width: 24, height: 24, padding: const EdgeInsets.all(2.0),
      child: CircularProgressIndicator(
        color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 3,
      ),
    );
  }
}


// EnterMasterPasswordPage (Biometrics Added, Unchanged from previous)
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
  bool _isChecking = false; // For password check
  String? _errorMessage;

  // Biometric State
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isBiometricAvailable = false;
  bool _isAuthenticatingBiometric = false; // For biometric check


  @override
  void initState() {
    super.initState();
    _checkBiometrics(); // Check for biometrics when page loads
  }

  // Check Biometric Availability
  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics = false;
    List<BiometricType> availableBiometrics = [];
    try {
      // Check if device has biometric hardware
      canCheckBiometrics = await _localAuth.canCheckBiometrics;
      if (canCheckBiometrics) {
        // Check if any biometrics are enrolled
        availableBiometrics = await _localAuth.getAvailableBiometrics();
      }
    } on PlatformException catch (e) {
      print("Error checking biometrics: $e");
      // Handle potential errors, e.g., platform not supported
      canCheckBiometrics = false;
    }
    // Update state only if the widget is still in the tree
    if (mounted) {
      setState(() {
        _isBiometricAvailable = canCheckBiometrics && availableBiometrics.isNotEmpty;
      });
      print("Biometrics available: $_isBiometricAvailable");
    }
  }


  // Authenticate with Biometrics
   Future<void> _authenticateWithBiometrics() async {
    // Prevent multiple simultaneous auth attempts
    if (_isAuthenticatingBiometric || _isChecking) return;

    if (mounted) {
       setState(() {
        _isAuthenticatingBiometric = true;
        _errorMessage = null; // Clear previous errors
       });
    }

    bool didAuthenticate = false;
    try {
      didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to unlock Password Manager',
        options: const AuthenticationOptions(
          stickyAuth: true, // Keep prompt open on backgrounding
          biometricOnly: true, // Do not allow device credential fallback
        ),
      );

      if (didAuthenticate) {
         if (mounted) {
           // Navigate to home on successful biometric auth
           Navigator.pushReplacementNamed(context, '/home');
           // Exit early as navigation has occurred
           return;
         }
      } else {
         // User likely cancelled or failed within the prompt
         print("Biometric authentication failed or cancelled by user.");
          if (mounted) {
           setState(() { _errorMessage = 'Biometric authentication cancelled.'; });
         }
      }
    } on PlatformException catch (e) {
      // Handle specific errors (e.g., lockout, not enrolled)
      print('Biometric authentication error: ${e.code} - ${e.message}');
       if (mounted) {
         String message = 'Biometric error occurred.';
         // Use imported constants for error codes
         if (e.code == auth_error.notAvailable) {
            message = 'Biometrics not available on this device.';
         } else if (e.code == auth_error.notEnrolled) {
            message = 'No biometrics enrolled. Please set up fingerprint/face ID.';
         } else if (e.code == auth_error.lockedOut || e.code == auth_error.permanentlyLockedOut) {
            message = 'Biometric locked due to too many attempts.';
         } else if (e.code == auth_error.passcodeNotSet) {
             message = 'Device passcode is not set.';
         }
         setState(() { _errorMessage = message; });
       }
    } catch (e) {
       // Catch any other unexpected errors
       print("Unexpected error during biometric auth: $e");
       if (mounted) {
         setState(() { _errorMessage = "An unexpected error occurred."; });
       }
    } finally {
       // Ensure the loading state is always reset
       if (mounted) {
         setState(() => _isAuthenticatingBiometric = false);
       }
    }
  }


  String _hashPassword(String password, String salt) {
    final saltedPassword = utf8.encode(password + salt);
    final hash = sha256.convert(saltedPassword);
    return hash.toString();
  }

  Future<void> _verifyMasterPassword() async {
    // Prevent multiple simultaneous auth attempts
    if (_isChecking || _isAuthenticatingBiometric) return;

    if (_formKey.currentState!.validate()) {
       if (!mounted) return;
      setState(() {
        _isChecking = true;
        _errorMessage = null;
      });

      final enteredPassword = _passwordController.text;

      try {
        final storedHash = await _storage.read(key: masterPasswordHashKey, aOptions: _getAndroidOptions());
        final storedSalt = await _storage.read(key: masterPasswordSaltKey, aOptions: _getAndroidOptions());

        if (storedHash == null || storedSalt == null) {
           print("Error: Master password hash or salt not found in storage.");
           setState(() {
              _errorMessage = 'Setup error: Master password data missing.';
           });
           return; // Exit early
        }

        final enteredHash = _hashPassword(enteredPassword, storedSalt);

        if (enteredHash == storedHash) {
           if (mounted) {
             // Navigate on success
             Navigator.pushReplacementNamed(context, '/home');
             return; // Exit after navigation
           }
        } else {
          if (mounted) {
            setState(() {
              _errorMessage = 'Incorrect master password. Please try again.';
              _passwordController.clear(); // Clear password field on error
            });
          }
        }
      } catch (e) {
         print("Error verifying master password: $e");
         if (mounted) {
           setState(() {
              _errorMessage = 'An error occurred: ${e.toString()}';
           });
         }
      } finally {
         // Always reset check state if still mounted
         if (mounted) {
           setState(() => _isChecking = false);
         }
      }
    }
  }

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

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
        automaticallyImplyLeading: false, // This removes the back button
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                 Icon(Icons.lock_open_outlined, size: 60, color: Theme.of(context).colorScheme.secondary), // Themed icon
                 const SizedBox(height: 20),
                 Text(
                  'Enter your Master Password',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                   autofocus: true, // Focus on password field automatically
                   enabled: !_isAuthenticatingBiometric, // Disable while biometric auth is running
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    prefixIcon: const Icon(Icons.password),
                    suffixIcon: IconButton(
                      icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                      // Disable visibility toggle during biometric auth
                      onPressed: _isAuthenticatingBiometric ? null : () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      tooltip: _isPasswordVisible ? 'Hide password' : 'Show password',
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your master password';
                    }
                    return null;
                  },
                  // Allow submitting from keyboard
                  onFieldSubmitted: (_) => _isChecking || _isAuthenticatingBiometric ? null : _verifyMasterPassword(),
                ),
                const SizedBox(height: 16),
                // Error Message Area
                AnimatedOpacity(
                  opacity: _errorMessage != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage ?? '', // Use empty string if null
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                // Row for Buttons
                 Row(
                   mainAxisAlignment: MainAxisAlignment.center, // Center buttons
                   children: [
                     // Unlock Button
                     Expanded( // Make unlock button take available space
                       child: ElevatedButton.icon(
                        icon: _isChecking ? _buildLoadingIndicator() : const Icon(Icons.login_outlined),
                        label: Text(_isChecking ? 'Checking...' : 'Unlock'),
                        style: _getButtonStyle(context),
                        // Disable if checking password or biometric
                        onPressed: _isChecking || _isAuthenticatingBiometric ? null : _verifyMasterPassword,
                       ),
                     ),
                      // Biometric Button
                     if (_isBiometricAvailable) ...[
                        const SizedBox(width: 16), // Spacing
                        IconButton.filledTonal( // Use a distinct style
                           icon: _isAuthenticatingBiometric
                              ? _buildLoadingIndicator(isBiometric: true) // Show loading inside button
                              : const Icon(Icons.fingerprint),
                           iconSize: 30,
                           tooltip: 'Unlock with Biometrics',
                           // Disable if checking password or biometric
                           onPressed: _isChecking || _isAuthenticatingBiometric ? null : _authenticateWithBiometrics,
                           style: IconButton.styleFrom(
                             minimumSize: const Size(50, 50), // Ensure decent size
                           ),
                        ),
                      ]
                   ],
                 ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _getButtonStyle(BuildContext context) {
     return ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50), // Take full width in row
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      );
  }

   Widget _buildLoadingIndicator({bool isBiometric = false}) {
     // Use different color for biometric button indicator if needed
     final color = isBiometric
        ? Theme.of(context).colorScheme.onSecondaryContainer // Example color
        : Theme.of(context).colorScheme.onPrimary;
    return Container(
      width: 24, height: 24, padding: const EdgeInsets.all(2.0),
      child: CircularProgressIndicator(
        color: color,
        strokeWidth: 3,
      ),
    );
  }
}
// --- END MODIFIED: EnterMasterPasswordPage ---


// PasswordEntry (Added dateAdded)
class PasswordEntry {
  final String service; // Stores the original user input
  final String username;
  final String password;
  final DateTime dateAdded; // NEW: Timestamp when entry was added

  PasswordEntry({
    required this.service,
    required this.username,
    required this.password,
    required this.dateAdded, // Require dateAdded in constructor
  });

  Map<String, dynamic> toJson() => {
        'service': service,
        'username': username,
        'password': password,
        // Store date as ISO 8601 string (standard format)
        'dateAdded': dateAdded.toIso8601String(),
      };

  factory PasswordEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['dateAdded'] != null) {
       try {
         parsedDate = DateTime.parse(json['dateAdded']);
       } catch (e) {
          print("Error parsing dateAdded '${json['dateAdded']}', using epoch as fallback.");
          parsedDate = DateTime.fromMillisecondsSinceEpoch(0); // Fallback for invalid format
       }
    } else {
       print("dateAdded field missing for '${json['service']}', using epoch as fallback.");
       parsedDate = DateTime.fromMillisecondsSinceEpoch(0); // Fallback for missing field (old data)
    }

    return PasswordEntry(
      service: json['service'] ?? 'Unknown Service',
      username: json['username'],
      password: json['password'],
      dateAdded: parsedDate, // Use parsed or fallback date
    );
  }
}
// --- End PasswordEntry Modification ---

// HomePage (Adds Sorting)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Enum for Sort Order
enum SortOrder { nameAZ, dateAdded }

class _HomePageState extends State<HomePage> {
  final _storage = const FlutterSecureStorage();
  List<PasswordEntry> _passwordEntries = [];
  bool _isLoading = true;
  // State for sorting
  SortOrder _currentSortOrder = SortOrder.nameAZ; // Default sort order


  @override
  void initState() {
    super.initState();
    _loadPasswordEntries();
  }

  @override
  void dispose() {
    super.dispose();
  }


  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  // Method to sort entries
  void _sortEntries() {
     if (_currentSortOrder == SortOrder.nameAZ) {
        // Sort A-Z by original service name
        _passwordEntries.sort((a, b) => a.service.toLowerCase().compareTo(b.service.toLowerCase()));
     } else { // dateAdded (Newest First)
        _passwordEntries.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
     }
  }


  Future<void> _loadPasswordEntries() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      final allStoredData = await _storage.readAll(aOptions: _getAndroidOptions());
      final Map<String, String> allEntries = Map.from(allStoredData)
        ..remove(masterPasswordHashKey)
        ..remove(masterPasswordSaltKey);

      final List<PasswordEntry> loadedEntries = [];
      allEntries.forEach((key, value) { // key is the normalized domain
        try {
          final Map<String, dynamic> json = jsonDecode(value);
          loadedEntries.add(PasswordEntry.fromJson(json));
        } catch (e) {
          print("Error decoding entry for key '$key': $e");
        }
      });

      _passwordEntries = loadedEntries;
      _sortEntries(); // Apply initial sort based on _currentSortOrder

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
          _loadPasswordEntries(); // Reload and re-sort
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

  void _showPasswordDetails(PasswordEntry entry) {
    if (!mounted) return;
    bool isPasswordVisible = false;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Show original service name in dialog title
            return AlertDialog(
              title: Text(entry.service), // Use original name
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    _buildDetailRow('Username:', entry.username, true),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isPasswordVisible ? entry.password : '••••••••',
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
                            // Use ClipboardService
                            ClipboardService.instance.copyAndClearAfterDelay(entry.password);
                            if (mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Password copied to clipboard! (Will clear soon)')), // Updated message
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
              actions: <Widget>[
                TextButton(
                  child: const Text('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    );
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
              // Keep direct copy for username for now
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
    // Use original service name for the initial letter now
    String serviceName = entry.service.trim();
    if (serviceName.isNotEmpty) {
        displayInitial = serviceName[0].toUpperCase();
    }

    return CircleAvatar(
      // Use original service name hash for color consistency
      backgroundColor: Colors.primaries[entry.service.hashCode % Colors.primaries.length].shade700,
      foregroundColor: Colors.white,
      child: Text(displayInitial),
    );
  }

  String _cleanDomainForFavicon(String serviceUrl) {
      // Use original service name for favicon lookup (keeps www.)
      String domain = serviceUrl.trim();
       // Try parsing as URI first
      Uri? uri = Uri.tryParse(domain.contains('://') ? domain : 'http://$domain');
      if (uri != null && uri.host.isNotEmpty && uri.host.contains('.')) {
          // Return the host; Google favicon service handles www. itself
          return uri.host;
      }
      // Fallback if not a valid URL structure (e.g., "My Router") - won't fetch favicon
      return ''; // Return empty if it doesn't look like a domain/URL
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
      case 'lock':
         // Manually lock the app
         navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/enter_master', (route) => false);
         break;
    }
  }

  // Toggle Sort Order
  void _toggleSortOrder() {
     setState(() {
        _currentSortOrder = (_currentSortOrder == SortOrder.nameAZ)
            ? SortOrder.dateAdded // Cycle to Date Added
            : SortOrder.nameAZ; // Cycle back to Name A-Z
        _sortEntries(); // Re-sort the list
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
    // Determine sort icon based on state
    final IconData sortIcon = _currentSortOrder == SortOrder.nameAZ
        ? Icons.sort_by_alpha // Icon for Name A-Z sort
        : Icons.history_toggle_off_rounded; // Icon for Date Added sort (example)

    final String sortTooltip = _currentSortOrder == SortOrder.nameAZ
        ? 'Sorted by Name (A-Z)'
        : 'Sorted by Date Added (Newest First)';


    return Scaffold(
        appBar: AppBar(
          title: const Text('Password Manager'),
          centerTitle: true,
          actions: [
            // Sort Button
            IconButton(
              icon: Icon(sortIcon), // Use dynamic icon
              tooltip: sortTooltip, // Use dynamic tooltip
              onPressed: _toggleSortOrder,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPasswordEntries,
              tooltip: 'Refresh List',
            ),
            // PopupMenuButton
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
                  ),
                ),
                 const PopupMenuItem<String>(
                  value: 'about',
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('About'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'lock',
                  child: ListTile(
                     leading: Icon(Icons.logout),
                     title: Text('Lock App'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _passwordEntries.isEmpty
                ? Center(
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
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _passwordEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _passwordEntries[index];
                      // Use helper to get domain suitable for favicon service
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
                                  // Simplified errorBuilder
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
                              : _buildFallbackAvatar(entry), // Show fallback if no valid domain for favicon
                          ),
                          // Display original service name
                          title: Text(entry.service, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(entry.username),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                                // Pass original service name for deletion confirmation
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


// --- AddPasswordPage (Adds dateAdded on save) ---
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

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  Future<void> _savePasswordEntry() async {
    if (_formKey.currentState!.validate()) {
      if (!mounted) return;
      setState(() { _isSaving = true; });

      bool proceedSaving = true;
      final String originalServiceName = _serviceController.text.trim();
      final String storageKey = normalizeDomain(originalServiceName);

      // Create PasswordEntry with timestamp
      final entry = PasswordEntry(
        service: originalServiceName,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        dateAdded: DateTime.now(), // Add current timestamp
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
          final String jsonEntry = jsonEncode(entry.toJson());
          await _storage.write(key: storageKey, value: jsonEntry, aOptions: _getAndroidOptions());

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Password for "$originalServiceName" saved successfully!')),
            );
            Navigator.pop(context, true);
            return;
          }
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


// --- GeneratePasswordPage (Implementation Added, Auto-generate on change) ---
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


// --- AboutPage (Incorporates expanded text, Unchanged) ---
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
                  'Master Password: Your vault is protected by a single Master Password that *only you* know. We **never** store your Master Password directly. Instead, we store a unique, cryptographically secure hash of it (using SHA-256 with a random salt) which is used only to verify your identity when you unlock the app.'
                ),
                 _buildListItem(context, Icons.storage_rounded,
                  'Local, Encrypted Storage: All your credential data is stored exclusively on this device\'s local storage using the operating system\'s secure storage mechanisms (Keychain on iOS, Keystore/EncryptedSharedPreferences on Android). Your data is **never** sent to any external servers or cloud services by this app.'
                ),
                 _buildListItem(context, Icons.fingerprint,
                  'Optional Biometrics: For quick access, you can enable unlocking via your device\'s built-in fingerprint or face recognition, using the secure systems provided by your phone\'s OS.'
                ),
                _buildListItem(context, Icons.timer_outlined,
                  'Automatic Locking: The app automatically locks after ${inactivityTimeout.inMinutes} minutes of inactivity to protect your data if you leave the app open.'
                ),
                 _buildListItem(context, Icons.content_cut_rounded,
                  'Secure Clipboard Handling: Passwords copied from the app are automatically removed from the system clipboard after ${clipboardClearDelay.inSeconds} seconds to minimize accidental exposure.'
                ),
                 const SizedBox(height: 24), // Spacing after list items

                 // Key Features (Could be a list as well)
                 _buildSection(
                  context,
                  'Key Features',
                  '• Securely add, view, and delete login credentials.\n'
                  '• Strong Master Password protection (hashed & salted).\n'
                  '• Optional Biometric unlock support.\n'
                  '• Automatic lock on inactivity.\n'
                  '• Automatic clipboard clearing for copied passwords.\n'
                  '• Clean display of normalized domain names.\n'
                  '• Menu for accessing additional features.'
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
                  '1. Set a strong Master Password on first launch.\n'
                  '2. Use the \'+\' button on the home screen to add new login entries.\n'
                  '3. Tap an entry to view details or copy the username/password.\n'
                  '4. Use the fingerprint icon (if available) on the lock screen for quick biometric access.\n'
                  '5. Use the menu icon (⋮) on the home screen for other options.'
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