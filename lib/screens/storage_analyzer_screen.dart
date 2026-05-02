import 'dart:math';
import 'package:flutter/material.dart';
import '../services/storage_analyzer_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class StorageAnalyzerScreen extends StatefulWidget {
  const StorageAnalyzerScreen({super.key});

  @override
  State<StorageAnalyzerScreen> createState() => _StorageAnalyzerScreenState();
}

class _StorageAnalyzerScreenState extends State<StorageAnalyzerScreen> {
  final StorageAnalyzerService _analyzer = StorageAnalyzerService();
  late Future<_AnalysisData> _analysisFuture;

  @override
  void initState() {
    super.initState();
    _analysisFuture = _loadData();
  }

  Future<_AnalysisData> _loadData() async {
    final categories = await _analyzer.analyzeStorage();
    final totalBytes = await _analyzer.getTotalStorageBytes();
    final usedBytes = await _analyzer.getUsedStorageBytes();
    final freeBytes = await _analyzer.getFreeStorageBytes();
    final topFolders = _analyzer.getTopFolders(categories, limit: 5);

    // Generate cleanup suggestions
    final suggestions = <_CleanupSuggestion>[];
    
    final cacheCat = categories.where((c) => c.name == 'Cache').firstOrNull;
    if (cacheCat != null && cacheCat.sizeInBytes > 50 * 1024 * 1024) {
      suggestions.add(_CleanupSuggestion(
        icon: Icons.cached,
        title: 'Clear App Caches',
        description: 'Free up space by clearing temporary app cache files',
        potentialSavings: _formatBytes(cacheCat.sizeInBytes ~/ 2),
        action: 'cache',
        actionPath: cacheCat.path,
      ));
    }

    final whatsappCat = categories.where((c) => c.name == 'WhatsApp').firstOrNull;
    if (whatsappCat != null && whatsappCat.sizeInBytes > 100 * 1024 * 1024) {
      suggestions.add(_CleanupSuggestion(
        icon: Icons.chat,
        title: 'Clean WhatsApp Media',
        description: 'Remove old WhatsApp media files to free space',
        potentialSavings: _formatBytes(whatsappCat.sizeInBytes ~/ 3),
        action: 'whatsapp',
        actionPath: whatsappCat.path,
      ));
    }

    final downloadCat = categories.where((c) => c.name == 'Downloads').firstOrNull;
    if (downloadCat != null && downloadCat.sizeInBytes > 100 * 1024 * 1024) {
      suggestions.add(_CleanupSuggestion(
        icon: Icons.download,
        title: 'Review Downloads',
        description: 'Check for large files in Downloads you no longer need',
        potentialSavings: _formatBytes(downloadCat.sizeInBytes ~/ 4),
        action: 'downloads',
        actionPath: downloadCat.path,
      ));
    }

    if (suggestions.isEmpty) {
      suggestions.add(_CleanupSuggestion(
        icon: Icons.check_circle,
        title: 'Storage Looking Good',
        description: 'No immediate cleanup suggestions. Your storage is healthy!',
        potentialSavings: '0 B',
        action: 'none',
        actionPath: '',
      ));
    }

    return _AnalysisData(
      categories: categories,
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: freeBytes,
      topFolders: topFolders,
      cleanupSuggestions: suggestions,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _analysisFuture = _loadData();
    });
  }

  Future<void> _executeCleanup(_CleanupSuggestion suggestion) async {
    if (suggestion.action == 'none') return;

    int freedBytes = 0;

    try {
      switch (suggestion.action) {
        case 'cache':
          for (final p in suggestion.actionPath.split(';')) {
            freedBytes += await _analyzer.clearCacheFiles(p.trim());
          }
          break;
        case 'whatsapp':
          for (final p in suggestion.actionPath.split(';')) {
            freedBytes += await _analyzer.clearOldWhatsAppMedia(p.trim());
          }
          break;
        case 'downloads':
          // For downloads, navigate to the folder conceptually — just show info
          _showCleanupInfoDialog(
            'Review Downloads',
            'To free space, open your file manager and review files in the Downloads folder.\n\n'
            'Look for:\n'
            '• Old APK install files\n'
            '• Large videos you\'ve already watched\n'
            '• Duplicate files\n'
            '• Archived zip files',
          );
          return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleanup encountered an error: ${e.toString()}'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      return;
    }

    if (mounted) {
      final freedStr = freedBytes > 0 ? _formatBytes(freedBytes) : '0 B';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Freed $freedStr of storage space!'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 3),
        ),
      );
      _refresh();
    }
  }

  void _showCleanupInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 24),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(message, style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 22),
            SizedBox(width: 8),
            Text('Storage Analyzer'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<_AnalysisData>(
        future: _analysisFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerLoading();
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Color(0xFFFF6B6B)),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to analyze storage',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          return _buildContent(data);
        },
      ),
    );
  }

  Widget _buildContent(_AnalysisData data) {
    final usedPct = data.totalBytes > 0 ? data.usedBytes / data.totalBytes : 0.0;
    final freePct = 1.0 - usedPct;
    final totalCatSize = data.categories.fold<int>(0, (sum, c) => sum + c.sizeInBytes);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Circular storage indicator
          _buildStorageCircle(data, usedPct, freePct),

          const SizedBox(height: 28),

          // Storage breakdown
          Text(
            'Storage Breakdown',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          ...data.categories.where((c) => c.sizeInBytes > 0).map((cat) {
            final pct = totalCatSize > 0 ? (cat.sizeInBytes / totalCatSize) * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StorageCategoryTile(
                icon: cat.icon,
                label: cat.name,
                size: cat.formattedSize,
                percentage: pct,
                color: cat.color,
                fileCount: cat.fileCount,
                onTap: () => _showFolderDetails(context, cat),
              ),
            );
          }),

          const SizedBox(height: 28),

          // Top Folders
          Text(
            'Top Folders',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          if (data.topFolders.isEmpty)
            const EmptyStateWidget(
              icon: Icons.folder_off_outlined,
              title: 'No Folders Found',
              description: 'Could not detect large folders.',
            )
          else
            ...data.topFolders.asMap().entries.map((entry) {
              final idx = entry.key;
              final folder = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TopFolderTile(
                  index: idx + 1,
                  name: folder.name,
                  path: folder.path,
                  size: folder.formattedSize,
                  fileCount: folder.fileCount,
                  onTap: () => _showFolderDetails(context, folder),
                ),
              );
            }),

          const SizedBox(height: 28),

          // Cleanup Suggestions
          Text(
            'Cleanup Suggestions',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          ...data.cleanupSuggestions.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CleanupSuggestionCard(
              icon: s.icon,
              title: s.title,
              description: s.description,
              potentialSavings: s.potentialSavings,
              onTap: s.action != 'none' ? () => _executeCleanup(s) : null,
            ),
          )),

          const SizedBox(height: 20),

          // On-device footer badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 14, color: AppTheme.successColor),
                  const SizedBox(width: 6),
                  Text(
                    'All analysis happens on-device',
                    style: TextStyle(
                      color: AppTheme.successColor,
                      fontSize: 12,
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
    );
  }

  Widget _buildStorageCircle(_AnalysisData data, double usedPct, double freePct) {
    return Center(
      child: Container(
        width: 200,
        height: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _StorageCirclePainter(
            usedPercentage: usedPct,
            freePercentage: freePct,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatBytes(data.usedBytes),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'of ${_formatBytes(data.totalBytes)} used',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(usedPct * 100).toStringAsFixed(1)}% Used',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFolderDetails(BuildContext context, StorageCategory folder) {
    // Split paths for multi-path categories
    final paths = folder.path.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(folder.icon, color: folder.color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (paths.length == 1) ...[
              Text('Path:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SelectableText(paths[0], style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ] else ...[
              Text('Paths:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final p in paths)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText(p, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.storage, color: folder.color, size: 18),
                const SizedBox(width: 8),
                Text('Size: ${folder.formattedSize}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.insert_drive_file, color: folder.color, size: 18),
                const SizedBox(width: 8),
                Text('Files: ${folder.fileCount}', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _shimmerBox(width: 200, height: 200, borderRadius: 24),
          const SizedBox(height: 28),
          _shimmerBox(width: 160, height: 22),
          const SizedBox(height: 14),
          for (int i = 0; i < 5; i++) ...[
            _shimmerBox(height: 72, borderRadius: 16),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 20),
          _shimmerBox(width: 120, height: 22),
          const SizedBox(height: 14),
          for (int i = 0; i < 4; i++) ...[
            _shimmerBox(height: 56, borderRadius: 14),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _shimmerBox({double? width, required double height, double borderRadius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.dividerColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}

// ─── Data holder ──────────────────────────────────────────────────────────────

class _AnalysisData {
  final List<StorageCategory> categories;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final List<StorageCategory> topFolders;
  final List<_CleanupSuggestion> cleanupSuggestions;

  _AnalysisData({
    required this.categories,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.topFolders,
    required this.cleanupSuggestions,
  });
}

class _CleanupSuggestion {
  final IconData icon;
  final String title;
  final String description;
  final String potentialSavings;
  final String action;       // 'cache', 'whatsapp', 'downloads', 'none'
  final String actionPath;   // filesystem path(s)

  _CleanupSuggestion({
    required this.icon,
    required this.title,
    required this.description,
    required this.potentialSavings,
    required this.action,
    required this.actionPath,
  });
}

// ─── Custom painter for circular storage indicator ──────────────────────────

class _StorageCirclePainter extends CustomPainter {
  final double usedPercentage;
  final double freePercentage;

  _StorageCirclePainter({required this.usedPercentage, required this.freePercentage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 14.0;
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final bgPaint = Paint()
      ..color = AppTheme.dividerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Used space arc
    if (usedPercentage > 0) {
      final usedPaint = Paint()
        ..color = AppTheme.primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * usedPercentage,
        false,
        usedPaint,
      );
    }

    // Free space arc
    if (freePercentage > 0) {
      final freePaint = Paint()
        ..color = AppTheme.successColor.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + 2 * pi * usedPercentage,
        2 * pi * freePercentage,
        false,
        freePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StorageCirclePainter oldDelegate) {
    return oldDelegate.usedPercentage != usedPercentage || oldDelegate.freePercentage != freePercentage;
  }
}

// ─── Tile widgets ────────────────────────────────────────────────────────────

class _StorageCategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String size;
  final double percentage;
  final Color color;
  final int fileCount;
  final VoidCallback? onTap;

  const _StorageCategoryTile({
    required this.icon,
    required this.label,
    required this.size,
    required this.percentage,
    required this.color,
    required this.fileCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('$size \u2022 $fileCount files', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: AppTheme.textLight, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percentage.clamp(0.0, 100.0) / 100.0,
                minHeight: 6,
                backgroundColor: AppTheme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopFolderTile extends StatelessWidget {
  final int index;
  final String name;
  final String path;
  final String size;
  final int fileCount;
  final VoidCallback onTap;

  const _TopFolderTile({
    required this.index,
    required this.name,
    required this.path,
    required this.size,
    required this.fileCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('$index', style: TextStyle(color: AppTheme.primaryColor, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(path, style: TextStyle(color: AppTheme.textLight, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(size, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('$fileCount files', style: TextStyle(color: AppTheme.textLight, fontSize: 10)),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppTheme.textLight, size: 20),
          ],
        ),
      ),
    );
  }
}

class _CleanupSuggestionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String potentialSavings;
  final VoidCallback? onTap;

  const _CleanupSuggestionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.potentialSavings,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFFF6B6B), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (onTap != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cleaning_services, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Clean',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      potentialSavings,
                      style: TextStyle(color: AppTheme.successColor, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
