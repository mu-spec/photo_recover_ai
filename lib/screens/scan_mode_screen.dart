import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ScanModeScreen extends StatelessWidget {
  const ScanModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Select Scan Mode',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header description
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'Choose a scan mode that fits your needs. Higher thoroughness takes longer but finds more files.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),

            // Quick Scan Card
            _ScanModeCard(
              icon: Icons.flash_on,
              title: 'Quick Scan',
              description:
                  'Scans priority folders only (DCIM, Camera, Downloads, WhatsApp). Fastest scan, ~30 seconds.',
              estimatedTime: '~30 sec',
              cardColor: const Color(0xFF10B981),
              isRecommended: true,
              onTap: () => Navigator.of(context).pop('quick'),
            ),

            const SizedBox(height: 16),

            // Deep Scan Card
            _ScanModeCard(
              icon: Icons.search,
              title: 'Deep Scan',
              description:
                  'Scans all folders including hidden & thumbnails. Finds more files, ~2-3 minutes.',
              estimatedTime: '~2-3 min',
              cardColor: const Color(0xFF3B82F6),
              isRecommended: false,
              onTap: () => Navigator.of(context).pop('deep'),
            ),

            const SizedBox(height: 16),

            // Full Scan Card
            _ScanModeCard(
              icon: Icons.radar,
              title: 'Full Scan',
              description:
                  'Complete scan including cache, app data & orphan detection. Most thorough, ~5+ minutes.',
              estimatedTime: '~5+ min',
              cardColor: const Color(0xFF8B5CF6),
              isRecommended: false,
              onTap: () => Navigator.of(context).pop('full'),
            ),

            const SizedBox(height: 40),

            // Privacy badge at the bottom
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: AppTheme.successColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: AppTheme.successColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No data uploaded - 100% offline',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ScanModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String estimatedTime;
  final Color cardColor;
  final bool isRecommended;
  final VoidCallback onTap;

  const _ScanModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.estimatedTime,
    required this.cardColor,
    required this.isRecommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isRecommended
                ? cardColor.withOpacity(0.5)
                : AppTheme.dividerColor,
            width: isRecommended ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: cardColor.withOpacity(isRecommended ? 0.15 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon + title + badges
            Row(
              children: [
                // Icon container
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: cardColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Estimated time badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cardColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  color: cardColor,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  estimatedTime,
                                  style: TextStyle(
                                    color: cardColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Recommended badge
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Recommended',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Description
            Text(
              description,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            // Bottom row: tap hint
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap to select',
                  style: TextStyle(
                    color: cardColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward,
                  color: cardColor,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
