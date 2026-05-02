import 'package:flutter/material.dart';
import '../services/recovery_insights_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class RecoveryInsightsScreen extends StatefulWidget {
  const RecoveryInsightsScreen({super.key});

  @override
  State<RecoveryInsightsScreen> createState() => _RecoveryInsightsScreenState();
}

class _RecoveryInsightsScreenState extends State<RecoveryInsightsScreen> {
  final RecoveryInsightsService _insights = RecoveryInsightsService();

  // Data holders
  RecoveryInsight? _todayInsights;
  Map<DateTime, RecoveryInsight>? _weeklyInsights;
  int _totalRecoveredAllTime = 0;
  int _totalSizeRecoveredAllTime = 0;
  Map<String, int> _recoveryByType = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _insights.getTodayInsights(),
        _insights.getWeeklyInsights(),
        _insights.getTotalRecoveredAllTime(),
        _insights.getTotalSizeRecoveredAllTime(),
        _insights.getRecoveryByType(),
      ]);

      if (mounted) {
        setState(() {
          _todayInsights = results[0] as RecoveryInsight;
          _weeklyInsights = results[1] as Map<DateTime, RecoveryInsight>;
          _totalRecoveredAllTime = results[2] as int;
          _totalSizeRecoveredAllTime = results[3] as int;
          _recoveryByType = results[4] as Map<String, int>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load insights: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _dayAbbreviation(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  /// Build a full 7-day list (some days may be missing from weekly data).
  List<MapEntry<DateTime, int>> _getWeeklyBars() {
    final now = DateTime.now();
    final List<MapEntry<DateTime, int>> bars = [];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      int recovered = 0;

      // Look for this day in weekly insights (match by date key only).
      if (_weeklyInsights != null) {
        for (final entry in _weeklyInsights!.entries) {
          final key = entry.key;
          if (key.year == day.year &&
              key.month == day.month &&
              key.day == day.day) {
            recovered = entry.value.filesRecovered;
            break;
          }
        }
      }

      bars.add(MapEntry(day, recovered));
    }

    return bars;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Recovery Insights',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? _buildShimmer()
          : _hasAnyData()
              ? SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTodayStats(context),
                      const SizedBox(height: 24),
                      _buildWeeklyChart(context),
                      const SizedBox(height: 24),
                      _buildAllTimeStats(context),
                      const SizedBox(height: 24),
                      _buildRecoveryByType(context),
                      const SizedBox(height: 24),
                      _buildTipsSection(context),
                      const SizedBox(height: 32),
                      _buildPrivacyBadge(context),
                      const SizedBox(height: 24),
                    ],
                  ),
                )
              : EmptyStateWidget(
                  icon: Icons.insights,
                  title: 'No Insights Yet',
                  description:
                      'Start scanning and recovering files to see your recovery statistics here.',
                  buttonText: 'Start Scanning',
                  onButtonTap: () => Navigator.of(context).pop(),
                ),
    );
  }

  bool _hasAnyData() {
    return (_todayInsights != null &&
            (_todayInsights!.scanCount > 0 ||
                _todayInsights!.filesRecovered > 0)) ||
        _totalRecoveredAllTime > 0 ||
        _totalSizeRecoveredAllTime > 0;
  }

  // ---------------------------------------------------------------------------
  // Today's Stats
  // ---------------------------------------------------------------------------

  Widget _buildTodayStats(BuildContext context) {
    final today = _todayInsights;
    final totalFound =
        (today?.photosFound ?? 0) + (today?.videosFound ?? 0) + (today?.filesFound ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Stats",
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTodayStatCard(
                context: context,
                icon: Icons.search,
                label: 'Scans',
                value: (today?.scanCount ?? 0).toString(),
                color: const Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTodayStatCard(
                context: context,
                icon: Icons.search,
                label: 'Files Found',
                value: totalFound.toString(),
                color: const Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTodayStatCard(
                context: context,
                icon: Icons.restore,
                label: 'Recovered',
                value: (today?.filesRecovered ?? 0).toString(),
                color: const Color(0xFFF59E0B),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTodayStatCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Weekly Chart (simple bar chart with Containers)
  // ---------------------------------------------------------------------------

  Widget _buildWeeklyChart(BuildContext context) {
    final bars = _getWeeklyBars();
    final maxVal = bars.map((e) => e.value).fold<int>(0, (a, b) => a > b ? a : b);
    final chartHeight = 140.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Overview',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            children: [
              SizedBox(
                height: chartHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: bars.map((entry) {
                    final fraction = maxVal > 0 ? entry.value / maxVal : 0.0;
                    final barHeight =
                        maxVal > 0 ? (fraction * (chartHeight - 30)).clamp(4.0, chartHeight - 30) : 4.0;
                    final isToday = entry.key.day == DateTime.now().day &&
                        entry.key.month == DateTime.now().month &&
                        entry.key.year == DateTime.now().year;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Value label
                            if (entry.value > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  entry.value.toString(),
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            // Bar
                            Container(
                              height: barHeight,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? AppTheme.primaryColor
                                    : AppTheme.primaryColor.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Day label
                            Text(
                              _dayAbbreviation(entry.key),
                              style: TextStyle(
                                color: isToday
                                    ? AppTheme.primaryColor
                                    : AppTheme.textLight,
                                fontSize: 10,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Files recovered per day',
                    style: TextStyle(
                      color: AppTheme.textLight,
                      fontSize: 11,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Today',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 10,
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
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // All-Time Stats
  // ---------------------------------------------------------------------------

  Widget _buildAllTimeStats(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All-Time Stats',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildAllTimeCard(
                context: context,
                icon: Icons.inventory_2_outlined,
                label: 'Total Files Recovered',
                value: _totalRecoveredAllTime.toString(),
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAllTimeCard(
                context: context,
                icon: Icons.sd_storage_outlined,
                label: 'Total Size Recovered',
                value: _formatSize(_totalSizeRecoveredAllTime),
                color: const Color(0xFF10B981),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAllTimeCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recovery by Type (pie-chart-like display with colored circles)
  // ---------------------------------------------------------------------------

  Widget _buildRecoveryByType(BuildContext context) {
    final photos = _recoveryByType['photo'] ?? 0;
    final videos = _recoveryByType['video'] ?? 0;
    final files = _recoveryByType['file'] ?? 0;
    final total = photos + videos + files;

    if (total == 0) return const SizedBox.shrink();

    final photoPercent = total > 0 ? (photos / total * 100) : 0.0;
    final videoPercent = total > 0 ? (videos / total * 100) : 0.0;
    final filePercent = total > 0 ? (files / total * 100) : 0.0;

    const photoColor = Color(0xFF10B981);
    const videoColor = Color(0xFF6C63FF);
    const fileColor = Color(0xFFF59E0B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery by Type',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              // Pie-chart-like display
              _buildPieChartCircle(
                photoPercent: photoPercent,
                videoPercent: videoPercent,
                filePercent: filePercent,
                photoColor: photoColor,
                videoColor: videoColor,
                fileColor: fileColor,
              ),
              const SizedBox(width: 24),
              // Legend
              Expanded(
                child: Column(
                  children: [
                    _buildLegendRow(
                      context: context,
                      color: photoColor,
                      label: 'Photos',
                      count: photos,
                      percent: photoPercent,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendRow(
                      context: context,
                      color: videoColor,
                      label: 'Videos',
                      count: videos,
                      percent: videoPercent,
                    ),
                    const SizedBox(height: 12),
                    _buildLegendRow(
                      context: context,
                      color: fileColor,
                      label: 'Files',
                      count: files,
                      percent: filePercent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPieChartCircle({
    required double photoPercent,
    required double videoPercent,
    required double filePercent,
    required Color photoColor,
    required Color videoColor,
    required Color fileColor,
  }) {
    const total = 360.0;
    final photoAngle = (photoPercent / 100) * total;
    final videoAngle = (videoPercent / 100) * total;
    final fileAngle = (filePercent / 100) * total;

    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        children: [
          // Photo slice
          if (photoAngle > 0)
            _buildPieSlice(
              startAngle: -90 * 3.14159 / 180,
              sweepAngle: photoAngle * 3.14159 / 180,
              color: photoColor,
            ),
          // Video slice
          if (videoAngle > 0)
            _buildPieSlice(
              startAngle: (-90 + photoAngle) * 3.14159 / 180,
              sweepAngle: videoAngle * 3.14159 / 180,
              color: videoColor,
            ),
          // File slice
          if (fileAngle > 0)
            _buildPieSlice(
              startAngle: (-90 + photoAngle + videoAngle) * 3.14159 / 180,
              sweepAngle: fileAngle * 3.14159 / 180,
              color: fileColor,
            ),
          // Center circle (donut hole)
          Center(
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieSlice({
    required double startAngle,
    required double sweepAngle,
    required Color color,
  }) {
    return CustomPaint(
      size: const Size(120, 120),
      painter: _PieSlicePainter(
        startAngle: startAngle,
        sweepAngle: sweepAngle,
        color: color,
      ),
    );
  }

  Widget _buildLegendRow({
    required BuildContext context,
    required Color color,
    required String label,
    required int count,
    required double percent,
  }) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$count (${percent.toStringAsFixed(0)}%)',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tips Section
  // ---------------------------------------------------------------------------

  Widget _buildTipsSection(BuildContext context) {
    final tips = [
      {
        'icon': Icons.schedule,
        'text': 'Scan weekly to catch recently deleted files before they are overwritten.',
      },
      {
        'icon': Icons.folder_outlined,
        'text': 'Use Quick Scan for recent deletions and Deep Scan for older files.',
      },
      {
        'icon': Icons.save_outlined,
        'text': 'Recover important files immediately — deleted files may be overwritten over time.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pro Tips',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...tips.map((tip) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    tip['icon'] as IconData,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tip['text'] as String,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Privacy Badge
  // ---------------------------------------------------------------------------

  Widget _buildPrivacyBadge(BuildContext context) {
    return Center(
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
              'All data stored locally',
              style: TextStyle(
                color: AppTheme.successColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shimmer / Loading
  // ---------------------------------------------------------------------------

  Widget _buildShimmer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(width: 120, height: 20),
          const SizedBox(height: 12),
          Row(
            children: [
              _shimmerBox(width: 100, height: 110),
              const SizedBox(width: 12),
              _shimmerBox(width: 100, height: 110),
              const SizedBox(width: 12),
              _shimmerBox(width: 100, height: 110),
            ],
          ),
          const SizedBox(height: 24),
          _shimmerBox(width: 160, height: 20),
          const SizedBox(height: 12),
          _shimmerBox(width: double.infinity, height: 200),
          const SizedBox(height: 24),
          _shimmerBox(width: 140, height: 20),
          const SizedBox(height: 12),
          Row(
            children: [
              _shimmerBox(width: 170, height: 120),
              const SizedBox(width: 12),
              _shimmerBox(width: 170, height: 120),
            ],
          ),
          const SizedBox(height: 24),
          _shimmerBox(width: 160, height: 20),
          const SizedBox(height: 12),
          _shimmerBox(width: double.infinity, height: 140),
        ],
      ),
    );
  }

  Widget _shimmerBox({required double width, required double height}) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.dividerColor,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pie slice painter (custom)
// ---------------------------------------------------------------------------

class _PieSlicePainter extends CustomPainter {
  final double startAngle;
  final double sweepAngle;
  final Color color;

  _PieSlicePainter({
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 35;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PieSlicePainter oldDelegate) {
    return oldDelegate.startAngle != startAngle ||
        oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.color != color;
  }
}
