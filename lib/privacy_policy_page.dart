import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  // --- IMPORTANT ---
  // Replace this placeholder string with your actual, legally reviewed Privacy Policy.
  // Consider POPIA requirements for South Africa.
  // Use \n for new paragraphs or structure using multiple Text widgets if needed.
  final String privacyPolicyText = """
Last updated: April 21, 2025

**1. Introduction**
Welcome to [Your App Name]'s Privacy Policy. This policy describes how we handle information when you use our mobile application. Our commitment is to protect your privacy and handle your data responsibly. This app is designed to store your password credentials locally on your device only.

**2. Information We Collect (and Don't Collect)**
We collect and process the following information solely for the purpose of providing the password management service within the app:
  * **Credentials You Provide:** Service names, usernames, and passwords that you explicitly enter into the app.
  * **Master Password Derived Key & Salt:** When you set up your Master Password, we generate a unique salt and derive a cryptographic key using PBKDF2. We store this derived key and salt securely on your device using flutter_secure_storage. **We NEVER store your actual Master Password.**
  * **Settings:** We store your theme preferences locally using shared_preferences.

We **do not** collect:
  * Personal identification information (unless you enter it as a username/password).
  * Usage analytics or tracking data.
  * Location data.

**3. How We Use Information**
The information processed is used exclusively to:
  * Securely store and retrieve your credentials within the app.
  * Verify your Master Password to unlock the app.
  * Encrypt and decrypt your stored credentials using AES-GCM.
  * Allow you to manage your app settings (e.g., theme).
  * Enable import/export of your encrypted data locally.

**4. Data Storage and Security**
  * **Local Storage:** All your credential data, derived keys, salts, and settings are stored **ONLY locally on your device** using platform secure storage (`flutter_secure_storage`) and standard preferences (`shared_preferences`).
  * **No Cloud Sync/Backup:** This application **does not** automatically sync or back up your data to any external servers or cloud services. Backup is the user's responsibility via device backups or the app's encrypted export feature.
  * **Encryption:** Your individual password entries are encrypted using industry-standard AES-GCM encryption before being saved. The encryption key is derived from your Master Password.
  * **Master Password:** Access to your vault is protected by your Master Password. It is crucial to keep this password safe, as **it cannot be recovered if forgotten.**

**5. Data Sharing**
We **do not share** your stored credentials, Master Password derived key/salt, or settings with any third parties. All data remains on your device.

**6. Data Retention**
Your data is retained on your device as long as the app is installed or until you delete specific entries or the app itself. The exported data file is retained for as long as you keep the file.

**7. User Rights (POPIA)**
Under the Protection of Personal Information Act (POPIA) in South Africa, you have rights regarding your personal information. Within this app:
  * You have direct **access** to view, add, edit, and delete your credential data.
  * You implicitly **consent** to the local processing described herein by using the app.
  * You have the right to **complain** to the Information Regulator of South Africa if you believe your rights have been infringed.

**8. Children's Privacy**
This app is not intended for use by children under the age of 18 [Adjust age if necessary], and we do not knowingly collect data from them.

**9. Changes to This Policy**
We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy within the app. You are advised to review this Privacy Policy periodically for any changes.

**10. Contact Us**
If you have any questions about this Privacy Policy, please contact us at: [Your Email Address or Contact Method]
""";
  // --- END IMPORTANT ---


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          privacyPolicyText,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}