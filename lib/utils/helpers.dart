// --- File: lib/utils/helpers.dart ---

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hashlib/hashlib.dart' show pbkdf2;
import 'constants.dart'; // Import constants

// Helper Function to Normalize Domain
String normalizeDomain(String url) {
  String text = url.trim().toLowerCase();
  // Handle cases where protocol might be missing but it's clearly a domain
  String parseInput = text.contains('://') ? text : 'http://$text';
  Uri? uri = Uri.tryParse(parseInput);

  if (uri != null && uri.host.isNotEmpty && uri.host.contains('.')) {
      String domain = uri.host;
      // Remove www. prefix if present
      if (domain.startsWith('www.')) {
        domain = domain.substring(4);
      }
      return domain;
  } else {
      // If not a valid URL/domain structure, return the original text cleaned of slashes
      // This handles simple names like "My Router" or "Local Service"
      return text.replaceAll(RegExp(r'[/\\]'), '');
  }
}

// Top-level function for PBKDF2 derivation (for compute)
// Needs to be top-level or static for compute isolate.
List<int> deriveKeyInBackground(Map<String, dynamic> params) {
  final String password = params['password'];
  final List<int> saltBytes = params['saltBytes'];

  // Perform PBKDF2 derivation (using hashlib package's pbkdf2)
  final derivedKeyDigest = pbkdf2(
     utf8.encode(password), // Ensure password is utf8 encoded
     saltBytes,
     pbkdf2Iterations, // Use constant
     pbkdf2KeyLength   // Use constant
  );
  // Return the bytes from the HashDigest object
  return derivedKeyDigest.bytes;
}

// Top-level function for Android Secure Storage options
// Needs to be accessible by main.dart and potentially other files
AndroidOptions getAndroidOptions() => const AndroidOptions(
      encryptedSharedPreferences: true,
    );

