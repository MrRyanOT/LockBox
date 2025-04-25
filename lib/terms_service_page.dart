import 'package:flutter/material.dart';

class TermsServicePage extends StatelessWidget {
  const TermsServicePage({super.key});

   // --- IMPORTANT ---
  // Replace this placeholder string with your actual, legally reviewed Terms of Service.
  // Use \n for new paragraphs or structure using multiple Text widgets if needed.
   final String termsText = """
Last updated: April 21, 2025

**PLEASE READ THESE TERMS OF SERVICE CAREFULLY BEFORE USING THE [Your App Name] APPLICATION.**

**1. Acceptance of Terms**
By downloading, installing, or using the [Your App Name] mobile application ("App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.

**2. Description of Service**
The App provides a facility to store and manage password credentials locally on your mobile device. Data is encrypted using your Master Password and stored only on your device.

**3. User Responsibilities**
  * **Master Password:** You are solely responsible for creating a strong Master Password and keeping it confidential. **If you forget your Master Password, you will permanently lose access to the data stored in the App. We cannot recover your Master Password or your data.**
  * **Data Accuracy:** You are responsible for the accuracy of the credentials you enter into the App.
  * **Device Security:** The security of the data stored in the App depends on the overall security of your device (e.g., device passcode, keeping the OS updated).
  * **Backups:** The App stores data locally. You are responsible for backing up your device and/or using the App's export feature to create encrypted backups of your vault data. We are not responsible for data loss due to device failure, loss, theft, or user error.
  * **Lawful Use:** You agree to use the App only for lawful purposes and in accordance with these Terms.

**4. Data Storage and Security**
The App stores all your data locally on your device and uses encryption (AES-GCM for entries, PBKDF2 for Master Password derivation) to protect it. No data is transmitted to us or any third-party servers. While we implement security measures, no system is impenetrable.

**5. Intellectual Property**
The App and its original content, features, and functionality are owned by [Your Name / Company Name] and are protected by international copyright, trademark, and other intellectual property laws. You are granted a limited, non-exclusive, non-transferable license to use the App for personal, non-commercial purposes according to these Terms.

**6. Disclaimers**
THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.

**7. Limitation of Liability**
TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, [Your Name / Company Name] SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES, WHETHER INCURRED DIRECTLY OR INDIRECTLY, OR ANY LOSS OF DATA, USE, GOODWILL, OR OTHER INTANGIBLE LOSSES, RESULTING FROM (a) YOUR ACCESS TO OR USE OF OR INABILITY TO ACCESS OR USE THE APP; (b) ANY UNAUTHORIZED ACCESS TO OR USE OF OUR SYSTEMS OR ANY PERSONAL INFORMATION STORED THEREIN; (c) ANY INTERRUPTION OR CESSATION OF FUNCTIONALITY OF THE APP; OR (d) THE LOSS OF YOUR MASTER PASSWORD AND SUBSEQUENT INABILITY TO ACCESS YOUR DATA.

**8. Changes to Terms**
We reserve the right to modify these Terms at any time. We will notify you of significant changes by posting the new Terms within the App or through other reasonable means. Your continued use of the App after such changes constitutes your acceptance of the new Terms.

**9. Governing Law**
These Terms shall be governed by and construed in accordance with the laws of South Africa, without regard to its conflict of law principles.

**10. Contact Us**
If you have any questions about these Terms, please contact us at: [Your Email Address or Contact Method]
""";
  // --- END IMPORTANT ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          termsText,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}