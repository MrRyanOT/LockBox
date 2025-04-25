// --- File: lib/models/password_entry.dart ---

import 'dart:convert'; // For jsonDecode if needed elsewhere, though factory handles it

// Data Model for Password Entries
class PasswordEntry {
  final String service;
  final String username;
  final String password; // Holds the actual password
  final DateTime dateAdded;

  PasswordEntry({
    required this.service,
    required this.username,
    required this.password,
    required this.dateAdded,
  });

  // Method to create a copy with password cleared (for display list)
  PasswordEntry copyWithClearedPassword() {
    return PasswordEntry(
      service: service,
      username: username,
      password: "••••••••", // Placeholder
      dateAdded: dateAdded,
    );
  }

  // Convert PasswordEntry object to JSON format for storage
  Map<String, dynamic> toJson() => {
        'service': service,
        'username': username,
        'password': password, // Include password when converting TO json
        'dateAdded': dateAdded.toIso8601String(),
      };

  // Create PasswordEntry object from JSON map
  factory PasswordEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['dateAdded'] != null) {
       try {
         parsedDate = DateTime.parse(json['dateAdded']);
       } catch (e) {
          print("Error parsing dateAdded '${json['dateAdded']}', using epoch as fallback.");
          // Use current time or epoch as fallback if parsing fails
          parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
       }
    } else {
       print("dateAdded field missing for '${json['service']}', using epoch as fallback.");
       parsedDate = DateTime.fromMillisecondsSinceEpoch(0); // Fallback date
    }

    return PasswordEntry(
      service: json['service'] ?? 'Unknown Service', // Provide default if null
      username: json['username'] ?? '', // Provide default if null
      password: json['password'] ?? '', // Provide default if null
      dateAdded: parsedDate,
    );
  }
}