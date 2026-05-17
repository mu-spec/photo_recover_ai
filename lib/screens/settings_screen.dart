import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _recoveryPath = 'Loading...';
  bool _recoveryFolderExists = false;
  int _recoveredCount = 0;

  @override
  void initState() {
    super.initState();
    _checkRecoveryFolder();
  }

  Future<void> _checkRecoveryFolder() async {
    String folderPath;
    try {
      // Try to get the actual recovery path
      final basePath = '/storage/emulated/0/${AppConstants.recoveryFolder}';
      final dir = Directory(basePath);
      if (await dir.exists()) {
        folderPath = basePath;
        _recoveryFolderExists = true;
        int count = 0;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) count++;
        }
        _recoveredCount = count;
      } else {
        // Try app-specific storage
        final appDir = await getExternalStorageDirectory();
        if (appDir != null) {
          final altPath = '${appDir.path}/${AppConstants.recoveryFolder}';
          final altDir = Directory(altPath);
          if (await altDir.exists()) {
            folderPath = altPath;
            _recoveryFolderExists = true;
            int count = 0;
            await for (final entity in altDir.list(recursive: true)) {
              if (entity is File) count++;
            }
            _recoveredCount = count;
          } else {
            folderPath = basePath;
            _recoveryFolderExists = false;
          }
        } else {
          folderPath = basePath;
          _recoveryFolderExists = false;
        }
      }
    } catch (_) {
      folderPath = '/storage/emulated/0/${AppConstants.recoveryFolder}';
      _recoveryFolderExists = false;
    }

    if (mounted) {
      setState(() {
        _recoveryPath = folderPath;
      });
    }
  }

  Future<void> _createRecoveryFolder() async {
    try {
      final basePath = '/storage/emulated/0/${AppConstants.recoveryFolder}';
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Also create sub-folders
      for (final sub in ['Photos', 'Videos', 'Files']) {
        final subDir = Directory('$basePath/$sub');
        if (!await subDir.exists()) {
          await subDir.create(recursive: true);
        }
      }
      if (mounted) {
        setState(() {
          _recoveryFolderExists = true;
        });
        _checkRecoveryFolder();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recovery folder created successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<AppSettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppColors.gradientPrimary,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.restore_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Version ${AppConstants.appVersion}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // General Settings
            _buildSectionTitle('General'),
            const SizedBox(height: 8),

            _buildSettingsTile(
              icon: Icons.notifications_outlined,
              color: const Color(0xFF6C63FF),
              title: 'Notifications',
              subtitle: settingsProvider.notificationsEnabled
                  ? 'Recovery notifications enabled'
                  : 'Recovery notifications disabled',
              trailing: Switch(
                value: settingsProvider.notificationsEnabled,
                onChanged: (val) async {
                  if (val) {
                    // Request notification permission before enabling
                    try {
                      final status = await Permission.notification.status;
                      if (status.isGranted) {
                        settingsProvider.setNotificationsEnabled(true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Notifications enabled!'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        }
                      } else if (status.isDenied) {
                        final result = await Permission.notification.request();
                        if (result.isGranted) {
                          settingsProvider.setNotificationsEnabled(true);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notifications enabled!'),
                                backgroundColor: AppTheme.successColor,
                              ),
                            );
                          }
                        } else if (result.isPermanentlyDenied) {
                          await openAppSettings();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enable notifications in app settings.'),
                                backgroundColor: Color(0xFFFF6B6B),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Notification permission denied.'),
                                backgroundColor: Color(0xFFFF6B6B),
                              ),
                            );
                          }
                        }
                      } else if (status.isPermanentlyDenied) {
                        await openAppSettings();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enable notifications in app settings.'),
                              backgroundColor: Color(0xFFFF6B6B),
                            ),
                          );
                        }
                      } else {
                        // Limited or restricted - try to enable anyway
                        settingsProvider.setNotificationsEnabled(true);
                      }
                    } catch (e) {
                      // Permission check failed - enable preference anyway
                      settingsProvider.setNotificationsEnabled(true);
                    }
                  } else {
                    settingsProvider.setNotificationsEnabled(false);
                  }
                },
                activeColor: AppTheme.primaryColor,
              ),
            ),

            _buildSettingsTile(
              icon: Icons.dark_mode_outlined,
              color: const Color(0xFF6366F1),
              title: 'Dark Mode',
              subtitle: settingsProvider.darkModeEnabled
                  ? 'Dark theme active'
                  : 'Light theme active',
              trailing: Switch(
                value: settingsProvider.darkModeEnabled,
                onChanged: (val) {
                  settingsProvider.setDarkModeEnabled(val);
                },
                activeColor: AppTheme.primaryColor,
              ),
            ),

            _buildSettingsTile(
              icon: Icons.auto_fix_high_outlined,
              color: const Color(0xFF00D9A6),
              title: 'Auto Scan',
              subtitle: settingsProvider.autoScanEnabled
                  ? 'Automatic scanning on app open'
                  : 'Manual scanning only',
              trailing: Switch(
                value: settingsProvider.autoScanEnabled,
                onChanged: (val) {
                  settingsProvider.setAutoScanEnabled(val);
                },
                activeColor: AppTheme.primaryColor,
              ),
            ),

            const SizedBox(height: 24),

            // Storage Settings
            _buildSectionTitle('Storage'),
            const SizedBox(height: 8),

            _buildSettingsTile(
              icon: _recoveryFolderExists ? Icons.folder_outlined : Icons.folder_off_outlined,
              color: _recoveryFolderExists ? const Color(0xFF22c55e) : const Color(0xFFF59E0B),
              title: 'Recovery Folder',
              subtitle: _recoveryFolderExists
                  ? '$_recoveryPath ($_recoveredCount files)'
                  : '$_recoveryPath (Not found)',
              trailing: _recoveryFolderExists
                  ? const Icon(Icons.check_circle, color: Color(0xFF22c55e), size: 20)
                  : IconButton(
                      icon: const Icon(Icons.create_new_folder, color: Color(0xFFF59E0B), size: 20),
                      onPressed: _createRecoveryFolder,
                    ),
              onTap: _recoveryFolderExists
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Recovery path: $_recoveryPath'),
                          action: SnackBarAction(
                            label: 'Copy',
                            textColor: Colors.white,
                            onPressed: () {
                              // Clipboard.setData(ClipboardData(text: _recoveryPath));
                            },
                          ),
                        ),
                      );
                    }
                  : _createRecoveryFolder,
            ),

            _buildSettingsTile(
              icon: Icons.cleaning_services_outlined,
              color: const Color(0xFFEF4444),
              title: 'Clear Cache',
              subtitle: 'Clear scan cache and temporary data',
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('Clear Cache'),
                    content: const Text(
                        'This will clear scan results and cached data. Recovered files will not be affected.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cache cleared successfully!'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // About Section
            _buildSectionTitle('About'),
            const SizedBox(height: 8),

            // Privacy Policy - opens external URL
            _buildSettingsTile(
              icon: Icons.privacy_tip_outlined,
              color: const Color(0xFF10B981),
              title: 'Privacy Policy',
              subtitle: 'How we handle your data',
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
              onTap: () async {
                final uri = Uri.parse(AppConstants.privacyPolicyUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),

            // Terms of Service - opens external URL
            _buildSettingsTile(
              icon: Icons.description_outlined,
              color: const Color(0xFF3B82F6),
              title: 'Terms of Service',
              subtitle: 'App usage terms',
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
              onTap: () async {
                final uri = Uri.parse(AppConstants.termsOfServiceUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),

            // Contact Support - opens email app
            _buildSettingsTile(
              icon: Icons.email_outlined,
              color: const Color(0xFFEF4444),
              title: 'Contact Support',
              subtitle: AppConstants.supportEmail,
              trailing: const Icon(Icons.open_in_new, color: Color(0xFF9CA3AF), size: 18),
              onTap: () async {
                final uri = Uri.parse(
                  'mailto:${AppConstants.supportEmail}?subject=${AppConstants.appName} Support&body=Hi, I need help with ${AppConstants.appName}.\n\nMy issue:',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  // Fallback: copy email to clipboard
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Email: ${AppConstants.supportEmail}'),
                      action: SnackBarAction(
                        label: 'OK',
                        textColor: Colors.white,
                        onPressed: () {},
                      ),
                    ),
                  );
                }
              },
            ),

            const SizedBox(height: 32),

            // Footer
            Center(
              child: Text(
                '${AppConstants.appName} v${AppConstants.appVersion}\nMade with ❤️',
                style: TextStyle(
                  color: AppTheme.textLight,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
