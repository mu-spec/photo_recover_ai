import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
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
                  colors: [const Color(0xFF00D9A6).withOpacity(0.1), const Color(0xFF00B4D8).withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00D9A6).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gavel, color: const Color(0xFF00D9A6), size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Terms of Service', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Last updated: April 3, 2026', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('App: Photo Recover  |  Contact: saaddkhan99@gmail.com', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildSection('1. Acceptance of Terms', [
              'By downloading, installing, or using the Photo Recover mobile application ("App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to all of these Terms, you must not download, install, or use the App.',
              'These Terms constitute a legally binding agreement between you ("User") and the developer of Photo Recover ("Developer").',
            ]),

            _buildSection('2. Description of Service', [
              'Photo Recover is a free Android application that helps users scan their device storage for recoverable photos, videos, and documents. The App performs the following functions:',
              '• Scans device storage directories for photos, videos, and files with supported extensions',
              '• Displays a list of potentially recoverable files organized by source and type',
              '• Copies selected files to a designated "PhotoRecover" folder on the user\'s device',
              '• Allows users to preview, manage, and delete recovered files',
              '• Displays advertisements via Google AdMob to support the free service',
            ]),

            _buildSection('3. User Responsibilities', [
              'By using Photo Recover, you agree to:',
              '• Use the App only on devices that you own or have explicit permission to access',
              '• Not use the App for any illegal, unauthorized, or unethical purposes',
              '• Not attempt to reverse engineer, decompile, modify, or create derivative works of the App',
              '• Not use the App to access or recover files that do not belong to you',
              '• Be responsible for managing the files recovered by the App on your device',
            ]),

            _buildSection('4. Permitted Use', [
              'You may use Photo Recover for personal, non-commercial purposes to recover your own files. The App is designed to help users recover accidentally deleted or lost media files and documents from their own devices.',
            ]),

            _buildSection('5. Intellectual Property', [
              'All content, design, graphics, code, and other materials associated with Photo Recover are the intellectual property of the Developer. The App is protected by applicable copyright and intellectual property laws.',
              'You may not copy, reproduce, distribute, or publish any part of the App without written permission. You may not remove, alter, or obscure any proprietary notices on the App.',
            ]),

            _buildSection('6. Advertisements', [
              'Photo Recover is a free application supported by advertisements. By using the App, you acknowledge and agree that advertisements will be displayed within the App through Google AdMob. AdMob may collect device information as described in our Privacy Policy.',
              'We are not responsible for the content of third-party advertisements. Clicking on advertisements will redirect you to external websites over which we have no control.',
            ]),

            _buildSection('7. Disclaimer of Warranties', [
              'Photo Recover is provided on an "AS IS" and "AS AVAILABLE" basis, without any warranties of any kind, either express or implied.',
              'File recovery success depends on many factors including whether the original data has been overwritten, the device\'s file system management, storage conditions, and the time elapsed since deletion. We do not guarantee that any specific file can be recovered.',
            ]),

            _buildSection('8. Limitation of Liability', [
              'To the maximum extent permitted by applicable law, the Developer shall not be liable for any direct, indirect, incidental, special, consequential, or punitive damages arising from or related to: use of or inability to use the App, loss of data or files, unauthorized access to your device, errors or bugs in the App, or any content displayed through the App.',
            ]),

            _buildSection('9. Storage Permissions and Data', [
              'The App requires storage permissions to function. By granting these permissions, you acknowledge that the App will access your device\'s file system to scan for recoverable files. Recovered files are copied (not moved) to the PhotoRecover folder. Original files remain untouched unless you manually delete them.',
              'You are responsible for managing the disk space used by recovered files.',
            ]),

            _buildSection('10. Termination', [
              'The Developer reserves the right to modify, suspend, or discontinue the App at any time without prior notice. You may terminate your use of the App at any time by uninstalling it from your device.',
            ]),

            _buildSection('11. Changes to Terms', [
              'The Developer reserves the right to update or modify these Terms at any time. Changes will be reflected by updating the "Last updated" date. Continued use of the App following any changes constitutes your acceptance of the new Terms.',
            ]),

            _buildSection('12. Governing Law', [
              'These Terms shall be governed by and construed in accordance with applicable laws. Any disputes arising from these Terms or the use of the App shall be resolved through amicable negotiation first.',
            ]),

            _buildSection('13. Contact Us', [
              'If you have any questions or concerns about these Terms of Service, please contact us at:\n\n📧 saaddkhan99@gmail.com\n\nWe will respond to all inquiries within 7 business days.',
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
