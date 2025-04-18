# Flutter Password Manager

A secure, local password manager application built with Flutter.

## Overview

This application provides a secure way to store and manage your login credentials (service names, usernames, passwords) directly on your device. It emphasizes local storage and uses platform-specific security features to protect your data.

## Features

* **Master Password Protection:** Secure your vault with a single master password. Uses PBKDF2 with salting for strong key derivation.
* **Local Encrypted Storage:** Utilizes `flutter_secure_storage` which leverages Android Keystore and iOS Keychain for hardware-backed or platform-level encryption of stored data. **Data never leaves your device.**
* **Biometric Unlock:** Optionally unlock the app using Fingerprint or Face ID (requires device support and setup).
* **Credential Management:** Add, view, and delete login entries.
* **Password Generator:** Generate strong, random passwords with customizable options (length, character types).
* **Clipboard Auto-Clear:** Copied passwords are automatically cleared from the clipboard after a set duration (45 seconds) for enhanced security.
* **Inactivity Timeout:** Automatically locks the app after a period of inactivity (5 minutes).
* **Sorting:** Sort password entries alphabetically (A-Z) or by date added (Newest first).
* **Favicon Display:** Attempts to display website favicons in the list view, with a fallback avatar.
* **About Section:** Displays app version and provides access to open-source licenses.

## Screenshots

*(Consider adding screenshots of the main screens here)*

* [Screenshot of HomePage]
* [Screenshot of AddPasswordPage]
* [Screenshot of GeneratePasswordPage]
* [Screenshot of Lock Screen]

## Tech Stack & Dependencies

* **Framework:** Flutter
* **State Management:** `StatefulWidget` / `setState` (Implicit)
* **Secure Storage:** [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
* **Cryptography:** [`crypto`](https://pub.dev/packages/crypto) (for SHA-256 and PBKDF2)
* **Biometrics:** [`local_auth`](https://pub.dev/packages/local_auth)
* **App Info:** [`package_info_plus`](https://pub.dev/packages/package_info_plus)
* **Password Generation:** [`random_password_generator`](https://pub.dev/packages/random_password_generator)

## Getting Started

### Prerequisites

* Flutter SDK (Check version compatibility if needed)
* Android Studio / Xcode (for platform-specific setup and builds)
* An Android Emulator or Physical Device / iOS Simulator or Physical Device

### Installation & Setup

1.  **Clone the repository:**
    ```bash
    git clone [your-repository-url]
    cd [repository-folder-name]
    ```
2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Platform Setup (IMPORTANT for Biometrics):**

    * **Android:**
        * Ensure `android/app/src/main/AndroidManifest.xml` contains:
            ```xml
            <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
            ```
            *(outside the `<application>` tag)*
        * Ensure your `android/app/src/main/.../MainActivity.kt` (or `.java`) extends `FlutterFragmentActivity` instead of `FlutterActivity`. See [`local_auth` package instructions](https://pub.dev/packages/local_auth#android-integration).
    * **iOS:**
        * Ensure your `ios/Runner/Info.plist` contains a usage description key for Face ID:
            ```xml
            <key>NSFaceIDUsageDescription</key>
            <string>Please authenticate to access your passwords securely.</string>
            ```
4.  **Run the app:**
    ```bash
    flutter run
    ```

## Security Considerations

* **Master Password:** Your Master Password is critical. **If you forget it, there is NO recovery mechanism, and your stored data will be inaccessible.** Choose a strong, unique password you can remember.
* **Local Storage:** Data is stored only on the device. No cloud sync or backup is built into this app. Ensure you have a separate backup strategy for your device itself.
* **Encryption:** While `flutter_secure_storage` provides platform-level encryption, the data *within* that storage is not currently encrypted by a key derived from the master password in this version (though the master password itself is securely handled with PBKDF2).

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License


[MIT](https://choosealicense.com/licenses/mit/)
