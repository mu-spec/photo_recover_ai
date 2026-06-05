import 'package:flutter/material.dart';

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
            _buildSection('1. Acceptance', const [
              'By installing or using Media Rescue, you agree to these Terms.',
              'If you do not agree, please do not use the app.',
            ]),
            _buildSection('2. Service Scope', const [
              'The app is designed to find and restore accessible, cached, and recently deleted media where available.',
              'Smart Photo Enhance can improve accessible or restored photo copies using local image processing.',
              'It does not guarantee deleted-file recovery on all devices.',
              'Raw deleted-block recovery is outside normal non-root Android capabilities.',
            ]),
            _buildSection('3. Responsible Use', const [
              'Use the app only on devices you own or are authorized to access.',
              'Do not use the app for illegal access, abuse, or privacy violations.',
            ]),
            _buildSection('4. Permissions and Storage', const [
              'You must grant required storage/media permissions for scanning features.',
              'Restored copies are saved to /storage/emulated/0/MediaRescue/.',
              'Enhanced photo copies are saved to /storage/emulated/0/MediaRescue/Enhanced/ or app-specific storage when Android restricts public folder writes.',
              'You are responsible for managing restored copies and disk space.',
            ]),
            _buildSection('5. Ads', const [
              'The app is ad-supported and may show Google AdMob advertisements.',
            ]),
            _buildSection('6. Warranty Disclaimer', const [
              'The app is provided "AS IS" and "AS AVAILABLE" without warranties.',
              'Restore outcomes vary by Android version, OEM behavior, permissions, and file availability.',
            ]),
            _buildSection('7. Limitation of Liability', const [
              'To the maximum extent permitted by law, the developer is not liable for missed recovery expectations, data loss, or indirect damages.',
            ]),
            _buildSection('8. Changes', const [
              'These Terms may be updated. Continued use after changes means acceptance of updated Terms.',
            ]),
            _buildSection('9. Contact', const [
              'For terms questions: saaddkhan99@gmail.com',
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          ...paragraphs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                p,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Color(0xFF444444),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


