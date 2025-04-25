// --- File: lib/services/encryption_key_service.dart ---

import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../utils/constants.dart'; // Import constants

// Service to hold the derived encryption key in memory
class EncryptionKeyService {
  // Singleton pattern
  static final EncryptionKeyService instance = EncryptionKeyService._internal();
  EncryptionKeyService._internal();

  encrypt.Key? _currentKey; // The derived AES key

  // Sets the key derived from the master password
  void setKey(List<int> keyBytes) {
    if (keyBytes.length == pbkdf2KeyLength) { // Ensure correct length from constants
      _currentKey = encrypt.Key(Uint8List.fromList(keyBytes));
      print("Encryption key set in memory.");
    } else {
      print("Error: Invalid key length provided to EncryptionKeyService.");
      _currentKey = null; // Ensure key is null if invalid
    }
  }

  // Clears the key from memory (on lock/logout)
  void clearKey() {
    _currentKey = null;
    print("Encryption key cleared from memory.");
  }

  // Retrieves the current key
  encrypt.Key? getKey() {
    return _currentKey;
  }

  // Checks if the key is currently set
  bool isKeySet() {
    return _currentKey != null;
  }
}