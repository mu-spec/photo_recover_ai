import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/storage_scanner.dart';
import '../services/database_helper.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/common_widgets.dart';
import 'scan_category_screen.dart';
import 'recovered_files_screen.dart';
import 'smart_photo_enhance_screen.dart';
import 'settings_screen.dart';
import 'storage_analyzer_screen.dart';

import 'no_deletion_risk_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final RecoveryService _recoveryService = RecoveryService();
  int _totalRecovered = 0;
  int _totalPhotos = 0;
  int _totalVideos = 0;
  int _totalFiles = 0;
  bool _statsLoaded = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    adService.loadBannerAd(onLoaded: () {
      if (mounted) setState(() {});
    });
    _checkAutoScan();
  }

  @override
  void dispose() {
    // Do NOT dispose adService here - it's a global singleton
    // Disposing it would kill ads for the entire app
    super.dispose();
  }

  void _checkAutoScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsProvider = Provider.of<AppSettingsProvider>(context, listen: false);
      if (settingsProvider.autoScanEnabled) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _openScanCategory('photo');
        });
      }
    });
  }

  Future<void> _loadStats() async {
    final recoveryCount = await _recoveryService.getRecoveredFileCount();
    final photoResults = await _db.getScanResults(fileType: 'photo');
    final videoResults = await _db.getScanResults(fileType: 'video');
    final fileResults = await _db.getScanResults(fileType: 'file');

    if (mounted) {
      setState(() {
        _totalRecovered = recoveryCount;
        _totalPhotos = photoResults.length;
        _totalVideos = videoResults.length;
        _totalFiles = fileResults.length;
        _statsLoaded = true;
      });
    }
  }

  void _openScanCategory(String fileType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanCategoryScreen(fileType: fileType),
      ),
    ).then((_) => _loadStats());
  }

  Widget _buildHomePage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              AppConstants.appName,
                              style: TextStyle(
                                color: AppTheme.getPrimaryTextColor(context),
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find and restore accessible media safely',
                          style: TextStyle(
                            color: AppTheme.getSecondaryTextColor(context),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),

                  ],
                ),

                const SizedBox(height: 16),

                // Privacy Badge
                Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.successColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 14, color: AppTheme.successColor),
                        SizedBox(width: 6),
                        Text('100% Offline - No data uploaded', style: TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Scan Section Header
                Text(
                  'Scan & Restore',
                  style: TextStyle(
                    color: AppTheme.getPrimaryTextColor(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // === PHOTOS ===
                RecoveryTypeCard(
                  title: 'Restore Photos',
                  description: 'Scan accessible photos and possible media traces',
                  icon: Icons.photo_library_outlined,
                  gradientColors: AppColors.gradientPrimary,
                  onTap: () => _openScanCategory('photo'),
                ),

                const SizedBox(height: 8),

                // === VIDEOS ===
                RecoveryTypeCard(
                  title: 'Restore Videos',
                  description: 'Scan accessible videos and possible media traces',
                  icon: Icons.videocam_outlined,
                  gradientColors: AppColors.gradientAccent,
                  onTap: () => _openScanCategory('video'),
                ),

                const SizedBox(height: 8),

                // === FILES ===
                RecoveryTypeCard(
                  title: 'Restore Files',
                  description: 'Scan accessible files and media traces',
                  icon: Icons.folder_outlined,
                  gradientColors: AppColors.gradientWarm,
                  onTap: () => _openScanCategory('file'),
                ),

                const SizedBox(height: 32),

                // Quick Stats
                Text(
                  'Restore Stats',
                  style: TextStyle(
                    color: AppTheme.getPrimaryTextColor(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: StatsCard(
                        label: 'Restored',
                        value: _statsLoaded ? _totalRecovered.toString() : '-',
                        icon: Icons.check_circle_outline,
                        color: AppTheme.successColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatsCard(
                        label: 'Photos Found',
                        value: _statsLoaded ? _totalPhotos.toString() : '-',
                        icon: Icons.image_outlined,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatsCard(
                        label: 'Videos Found',
                        value: _statsLoaded ? _totalVideos.toString() : '-',
                        icon: Icons.videocam_outlined,
                        color: const Color(0xFF00D9A6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatsCard(
                        label: 'Files Found',
                        value: _statsLoaded ? _totalFiles.toString() : '-',
                        icon: Icons.description_outlined,
                        color: const Color(0xFFFF6B6B),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Quick Actions
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    color: AppTheme.getPrimaryTextColor(context),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                _QuickActionTile(
                  icon: Icons.auto_fix_high_outlined,
                  color: const Color(0xFF0EA5E9),
                  title: 'Smart Photo Enhance',
                  subtitle: 'Improve restored photo quality locally',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SmartPhotoEnhanceScreen(),
                      ),
                    );
                  },
                ),

                _QuickActionTile(
                  icon: Icons.restore_outlined,
                  color: AppTheme.primaryColor,
                  title: 'Restored Files',
                  subtitle: 'View all restored copies',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecoveredFilesScreen(),
                      ),
                    ).then((_) => _loadStats());
                  },
                ),

                _QuickActionTile(
                  icon: Icons.shield_outlined,
                  color: const Color(0xFF10B981),
                  title: 'How Restore Works',
                  subtitle: 'Learn how we keep your files safe',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoDeletionRiskScreen())),
                ),

                _QuickActionTile(
                  icon: Icons.star_rate_outlined,
                  color: const Color(0xFFF59E0B),
                  title: 'Rate App',
                  subtitle: 'Love this app? Give us 5 stars!',
                  onTap: () async {
                    final uri = Uri.parse('https://play.google.com/store/apps/details?id=com.photoRecoverAI.photo_recover_ai');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),

                _QuickActionTile(
                  icon: Icons.share_outlined,
                  color: const Color(0xFF10B981),
                  title: 'Share App',
                  subtitle: 'Share with friends & family',
                  onTap: () async {
                    try {
                      await Share.share(
                        'Check out ${AppConstants.appName} - Find and restore accessible media safely.\nhttps://play.google.com/store/apps/details?id=com.photoRecoverAI.photo_recover_ai',
                        subject: AppConstants.appName,
                      );
                    } catch (_) {}
                  },
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          SafeArea(child: _buildHomePage()),
          const SafeArea(child: StorageAnalyzerScreen()),
          const SafeArea(child: SettingsScreen()),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textLight,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storage),
            label: 'Storage',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.getPrimaryTextColor(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.getSecondaryTextColor(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.getLightTextColor(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
