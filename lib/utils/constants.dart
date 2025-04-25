// --- File: lib/utils/constants.dart ---

import 'package:flutter/material.dart'; // Needed for Duration

// --- Secure Storage Keys ---
const String masterPasswordHashKey = 'master_password_key';
const String masterPasswordSaltKey = 'master_password_salt';

// --- SharedPreferences Keys ---
const String themeModePrefKey = 'theme_mode';
const String themeSeedColorPrefKey = 'theme_seed_color';
const String useAmoledDarkPrefKey = 'use_amoled_dark';
const String firstRunFlagKey = 'app_first_run_completed_flag';

// --- PBKDF2 Configuration ---
const int pbkdf2Iterations = 100000;
const int pbkdf2KeyLength = 32; // Key length in bytes (e.g., 32 for AES-256)

// --- Timeout Durations ---
const Duration inactivityTimeout = Duration(minutes: 5);
const Duration clipboardClearDelay = Duration(seconds: 45);

// --- Route Names ---
const String homeRoute = '/home';
const String addPasswordRoute = '/add_password';
const String editPasswordRoute = '/edit_password';
const String generatePasswordRoute = '/generate_password';
const String aboutRoute = '/about';
const String settingsRoute = '/settings';
const String authWrapperRoute = '/auth_wrapper'; // Although not directly navigated to by name usually
const String createMasterRoute = '/create_master';
const String enterMasterRoute = '/enter_master';

// --- List of Authenticated Routes ---
const List<String> authenticatedRoutes = [
  homeRoute,
  addPasswordRoute,
  editPasswordRoute,
  generatePasswordRoute,
  aboutRoute,
  settingsRoute
];

// --- List of Non-Authenticated Routes ---
// Note: '/' might map to AuthWrapper initially
const List<String> nonAuthenticatedRoutes = [
  '/', // Initial route might resolve here
  authWrapperRoute,
  createMasterRoute,
  enterMasterRoute
];

