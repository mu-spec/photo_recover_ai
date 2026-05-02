import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryColor.withOpacity(0.1), AppTheme.primaryColor.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Privacy Policy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Last updated: April 3, 2026', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('App: Photo Recover  |  Package: com.photoRecoverAI.photo_recover_ai', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildSection('1. Introduction', [
              'Welcome to Photo Recover ("we", "our", or "the app"). We are committed to protecting your privacy and ensuring the security of your personal information. This Privacy Policy explains how we handle information when you use our Android application.',
              'By downloading, installing, or using the Photo Recover app, you agree to the terms outlined in this Privacy Policy. If you do not agree with any part of this policy, please uninstall and discontinue use of the application.',
            ]),

            _buildSection('2. Information We Collect', [
              'Photo Recover operates primarily offline and is designed to minimize data collection. Here is what we do and do not collect:',
              '• No Personal Information: We do NOT collect your name, email, phone number, address, or any personally identifiable information (PII).',
              '• No Account Required: The app does not require user registration, sign-up, or login of any kind.',
              '• No Server Communication for Files: Your photos, videos, and documents are NEVER uploaded, transmitted, or sent to any external server. All file scanning and recovery happens entirely on your device.',
              '• No Location Data: We do not collect or track your GPS location.',
              '• No Camera or Microphone Access: The app does not access your camera or microphone.',
            ]),

            _buildSection('3. How We Use Your Information', [
              'Since we do not collect personal data, there is minimal information usage. The app uses the following only for its core functionality:',
              '• File Scanning: The app reads file metadata (name, size, date, path) from your device storage to identify recoverable files. This data stays on your device.',
              '• File Recovery: Recovered files are copied to a local "PhotoRecover" folder on your device. No files leave your phone.',
              '• Local Database: The app uses a local SQLite database to store scan results and recovery records. This database is stored only on your device and is not shared externally.',
            ]),

            _buildSection('4. Permissions Required', [
              'Photo Recover requires the following Android permissions to function properly:',
              '• READ_EXTERNAL_STORAGE / MANAGE_EXTERNAL_STORAGE: Required to scan your device\'s directories for deleted or lost photos, videos, and files.',
              '• WRITE_EXTERNAL_STORAGE: Required to save recovered files to the "PhotoRecover" folder (Android 9 and below).',
              '• READ_MEDIA_IMAGES / READ_MEDIA_VIDEO / READ_MEDIA_AUDIO: Required on Android 13+ to access media files.',
              '• INTERNET / ACCESS_NETWORK_STATE: Required solely for displaying advertisements through Google AdMob. The app does not use internet access to send any user data.',
              'You can revoke these permissions at any time through your device\'s Settings > Apps > Photo Recover > Permissions.',
            ]),

            _buildSection('5. Third-Party Services (Google AdMob)', [
              'Photo Recover uses Google AdMob to display advertisements within the app. AdMob may collect certain device information for advertising purposes, including: Advertising ID (AAID), device model, operating system version, screen resolution, network type, and app version.',
              'This data is collected by Google in accordance with Google\'s Privacy Policy. We do not control Google\'s data collection practices.',
              'How to opt out of personalized ads: Go to Android Settings > Google > Ads > Delete advertising ID.',
            ]),

            _buildSection('6. Data Storage & Security', [
              'All data processed by Photo Recover is stored locally on your device:',
              '• Scanned file records are stored in a local SQLite database (photo_recover_ai.db)',
              '• Recovered files are saved to /storage/emulated/0/PhotoRecover/ folder',
              '• No cloud storage: We do not use any cloud services, servers, or external databases',
              '• No encryption needed: Since no data leaves your device, there is no risk of data interception',
              'When you uninstall Photo Recover, all local database records are removed automatically.',
            ]),

            _buildSection('7. Children\'s Privacy', [
              'Photo Recover is suitable for users of all ages. Since the app does not collect, store, or transmit any personal information from users of any age, we are fully compliant with the Children\'s Online Privacy Protection Act (COPPA) and other applicable children\'s privacy regulations.',
            ]),

            _buildSection('8. Data Retention', [
              'Photo Recover does not retain any user data beyond what is stored locally on your device. Scan results are stored locally until you perform a new scan or uninstall the app. Recovery records remain until you clear them or uninstall the app. Recovered files remain in the PhotoRecover folder until manually deleted by you.',
            ]),

            _buildSection('9. Third-Party Links', [
              'The app may contain links to external websites (e.g., Google Play Store, email client). These links are provided for your convenience. We are not responsible for the content, privacy policies, or practices of any third-party websites or services.',
            ]),

            _buildSection('10. Changes to This Policy', [
              'We may update this Privacy Policy from time to time to reflect changes in our practices, technology, legal requirements, or other factors. When we make changes, we will update the "Last updated" date and the in-app Privacy Policy screen. Your continued use of the app after any changes constitutes your acceptance of the updated Privacy Policy.',
            ]),

            _buildSection('11. Your Rights', [
              'Depending on your jurisdiction, you may have certain rights regarding your data:',
              '• Right to Access: You can view all scan results and recovery records within the app',
              '• Right to Delete: You can delete scan results, recovery records, and recovered files at any time',
              '• Right to Revoke Permissions: You can revoke any app permissions through your device settings',
              '• Right to Uninstall: You can uninstall the app at any time, which removes all local data',
            ]),

            _buildSection('12. Limitation of Liability', [
              'Photo Recover is provided "as is" without any warranties, express or implied. While we strive to provide a reliable file recovery experience, we cannot guarantee that all deleted files can be recovered, as recovery depends on various factors including device storage management, file system conditions, and whether the original data has been overwritten.',
            ]),

            _buildSection('13. Contact Us', [
              'If you have any questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact us at:\n\n📧 saaddkhan99@gmail.com\n\nWe will respond to all privacy-related inquiries within 7 business days.',
            ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> paragraphs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          ...paragraphs.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(p, style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF444444))),
          )),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
