import 'package:flutter/material.dart';
import '../main.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/common_widgets.dart';
import 'permission_screen.dart';

class ScanCategoryScreen extends StatelessWidget {
  final String fileType; // 'photo', 'video', or 'file'

  const ScanCategoryScreen({super.key, required this.fileType});

  String get _title {
    switch (fileType) {
      case 'photo':
        return 'Recover Photos';
      case 'video':
        return 'Recover Videos';
      case 'file':
        return 'Recover Files';
      default:
        return 'Recover';
    }
  }

  IconData get _pageIcon {
    switch (fileType) {
      case 'photo':
        return Icons.photo_library_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'file':
        return Icons.folder_outlined;
      default:
        return Icons.restore_outlined;
    }
  }

  List<Color> get _gradientColors {
    switch (fileType) {
      case 'photo':
        return AppColors.gradientPrimary;
      case 'video':
        return AppColors.gradientAccent;
      case 'file':
        return AppColors.gradientWarm;
      default:
        return AppColors.gradientPrimary;
    }
  }

  Color get _deepGradient1 {
    switch (fileType) {
      case 'photo':
        return const Color(0xFF8B5CF6);
      case 'video':
        return const Color(0xFFF97316);
      case 'file':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  Color get _deepGradient2 {
    switch (fileType) {
      case 'photo':
        return const Color(0xFF6366F1);
      case 'video':
        return const Color(0xFFEA580C);
      case 'file':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF6366F1);
    }
  }

  IconData get _scanAllIcon {
    switch (fileType) {
      case 'photo':
        return Icons.photo_library_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'file':
        return Icons.folder_outlined;
      default:
        return Icons.search;
    }
  }

  IconData get _scanDeletedIcon {
    return Icons.restore_outlined;
  }

  String get _scanAllTitle {
    switch (fileType) {
      case 'photo':
        return 'Scan All Photos';
      case 'video':
        return 'Scan All Videos';
      case 'file':
        return 'Scan All Files';
      default:
        return 'Scan All';
    }
  }

  String get _scanAllDescription {
    switch (fileType) {
      case 'photo':
        return 'Find all photos (existing + recoverable traces) on your device';
      case 'video':
        return 'Find all videos (existing + recoverable traces) on your device';
      case 'file':
        return 'Find documents, audio & other files (existing + recoverable traces)';
      default:
        return 'Find all files on your device';
    }
  }

  String get _scanDeletedTitle {
    switch (fileType) {
      case 'photo':
        return 'Scan Deleted Photos';
      case 'video':
        return 'Scan Deleted Videos';
      case 'file':
        return 'Scan Deleted Files';
      default:
        return 'Scan Deleted';
    }
  }

  String get _scanDeletedDescription {
    switch (fileType) {
      case 'photo':
        return 'Deep scan for deleted, hidden & trashed photos';
      case 'video':
        return 'Deep scan for deleted, hidden & trashed videos';
      case 'file':
        return 'Deep scan for deleted & hidden documents';
      default:
        return 'Deep scan for deleted & hidden files';
    }
  }

  void _navigateToScan(BuildContext context, bool scanDeleted) {
    // Keep interstitial warm before user reaches scan start.
    adService.loadInterstitialAd();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PermissionScreen(
          fileType: fileType,
          scanDeleted: scanDeleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom AppBar
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back,
                      color: AppTheme.getPrimaryTextColor(context),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _title,
                      style: TextStyle(
                        color: AppTheme.getPrimaryTextColor(context),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _gradientColors[0].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_pageIcon, color: _gradientColors[0], size: 22),
                  ),
                ],
              ),
            ),

            // Header illustration
            const SizedBox(height: 30),
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _gradientColors[0].withOpacity(0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(
                  _pageIcon,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Choose Scan Type',
                style: TextStyle(
                  color: AppTheme.getSecondaryTextColor(context),
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Scan Options
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    RecoveryTypeCard(
                      title: _scanAllTitle,
                      description: _scanAllDescription,
                      icon: _scanAllIcon,
                      gradientColors: _gradientColors,
                      badgeText: 'All',
                      onTap: () => _navigateToScan(context, false),
                    ),

                    RecoveryTypeCard(
                      title: _scanDeletedTitle,
                      description: _scanDeletedDescription,
                      icon: _scanDeletedIcon,
                      gradientColors: [_deepGradient1, _deepGradient2],
                      badgeText: 'Deep',
                      onTap: () => _navigateToScan(context, true),
                    ),

                    const SizedBox(height: 24),

                    // Info box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.getSurfaceColor(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.getDividerColor(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fileType == 'photo'
                                  ? '"Scan All" includes both normal and recoverable photo traces. "Scan Deleted" focuses only on deleted/recoverable traces.'
                                  : fileType == 'video'
                                      ? '"Scan All" includes both normal and recoverable video traces. "Scan Deleted" focuses only on deleted/recoverable traces.'
                                      : '"Scan All" includes normal and recoverable document/audio traces. "Scan Deleted" focuses only on deleted/recoverable traces.',
                              style: TextStyle(
                                color: AppTheme.getSecondaryTextColor(context),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
