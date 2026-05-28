import 'package:flutter/material.dart';

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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.1),
                    AppTheme.primaryColor.withOpacity(0.05),
                  ],
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
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last updated: May 21, 2026',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'App: Media Rescue  |  Package: com.photoRecoverAI.photo_recover_ai',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSection('1. About the Service', const [
              'Media Rescue helps users find and restore accessible, cached, and recently deleted media (device dependent).',
              'On modern Android devices, raw deleted-block recovery is generally not possible without root access.',
            ]),
            _buildSection('2. Data Collection', const [
              'The app does not require account signup and does not collect personal profile data.',
              'Your photos, videos, and files are not uploaded to our servers.',
              'Scan metadata is processed locally on your device.',
            ]),
            _buildSection('3. Permissions', const [
              'READ_MEDIA_* / READ_EXTERNAL_STORAGE is used to scan accessible media.',
              'INTERNET / ACCESS_NETWORK_STATE is used for Google AdMob ad delivery.',
            ]),
            _buildSection('4. Local Storage', const [
              'Scan records are stored in a local on-device database.',
              'Restored copies are saved to /storage/emulated/0/MediaRescue/.',
              'Removing the app removes app data; restored copies remain until manually deleted.',
            ]),
            _buildSection('5. Third-Party Services', const [
              'This app uses Google AdMob. Ad-related processing is governed by Google policies.',
            ]),
            _buildSection('6. Contact', const [
              'For privacy questions: saaddkhan99@gmail.com',
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


