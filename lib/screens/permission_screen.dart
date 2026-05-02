import 'package:flutter/material.dart';
import '../services/storage_scanner.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';

class PermissionScreen extends StatefulWidget {
  final String fileType;
  const PermissionScreen({super.key, this.fileType = 'photo'});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isRequesting = false;

  Future<void> _requestPermission() async {
    setState(() => _isRequesting = true);

    final scanner = StorageScanner();
    final granted = await scanner.requestPermissions();

    if (!mounted) return;
    setState(() => _isRequesting = false);

    if (granted) {
      Navigator.of(context).pop(true); // Return true to caller
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Permission is required to scan and recover files.',
          ),
          backgroundColor: AppTheme.warningColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Illustration
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: AppColors.gradientPrimary,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.folder_special_outlined,
                  color: Colors.white,
                  size: 52,
                ),
              ),

              const SizedBox(height: 28),

              // Title
              Text(
                'Storage Permission Required',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // Subtitle
              Text(
                '${AppConstants.appName} needs access to your storage to scan and recover deleted files.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Permission cards
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _PermissionCard(
                      icon: Icons.folder_outlined,
                      iconColor: AppTheme.primaryColor,
                      iconBgColor: AppTheme.primaryColor.withOpacity(0.1),
                      title: 'Storage Access',
                      description:
                          'Scan your device storage to find deleted photos, videos, and files.',
                    ),
                    const SizedBox(height: 14),
                    _PermissionCard(
                      icon: Icons.restore_outlined,
                      iconColor: const Color(0xFF00D9A6),
                      iconBgColor: const Color(0xFF00D9A6).withOpacity(0.1),
                      title: 'File Recovery',
                      description:
                          'Save recovered files to a secure folder on your device.',
                    ),
                    const SizedBox(height: 14),
                    _PermissionCard(
                      icon: Icons.photo_library_outlined,
                      iconColor: const Color(0xFFF59E0B),
                      iconBgColor: const Color(0xFFF59E0B).withOpacity(0.1),
                      title: 'Media Access',
                      description:
                          'Access photos and videos from your Camera, WhatsApp, and Gallery.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Privacy banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.successColor.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: AppTheme.successColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Your data stays on your device',
                          style: TextStyle(
                            color: AppTheme.successColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No files are uploaded. No data leaves your phone.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.primaryColor.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 20),
                            SizedBox(width: 8),
                            Text('Continue & Grant Permission'),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // Not now button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Not Now',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String description;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_outline,
            color: AppTheme.successColor,
            size: 22,
          ),
        ],
      ),
    );
  }
}
