import 'dart:math';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/recoverable_file.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/common_widgets.dart';
import 'recovered_files_screen.dart';

/// A single confetti particle for the celebration animation.
class _ConfettiParticle {
  double x;
  double y;
  Color color;
  double size;
  double speed;
  double wobble;
  double opacity;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.size,
    required this.speed,
    required this.wobble,
    this.opacity = 1.0,
  });
}

class RecoverySummaryScreen extends StatefulWidget {
  final String fileType;
  final int recoveredCount;
  final int failedCount;
  final int totalSizeBytes;
  final int elapsedTimeSeconds;
  final String recoveryPath;
  final List<String> recoveredFileNames;

  const RecoverySummaryScreen({
    super.key,
    required this.fileType,
    required this.recoveredCount,
    required this.failedCount,
    required this.totalSizeBytes,
    required this.elapsedTimeSeconds,
    required this.recoveryPath,
    required this.recoveredFileNames,
  });

  @override
  State<RecoverySummaryScreen> createState() => _RecoverySummaryScreenState();
}

class _RecoverySummaryScreenState extends State<RecoverySummaryScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────
  late AnimationController _checkmarkController;
  late Animation<double> _checkmarkScaleAnimation;
  late Animation<double> _checkmarkBounceAnimation;

  late AnimationController _confettiController;
  final List<_ConfettiParticle> _confettiParticles = [];

  late AnimationController _arrowSlideController;
  late Animation<double> _arrowSlideAnimation;

  late AnimationController _fadeController;

  // ── Helpers ────────────────────────────────────────────────────────────
  String get _fileTypeLabel {
    switch (widget.fileType) {
      case 'photo':
        return 'Photos';
      case 'video':
        return 'Videos';
      case 'file':
        return 'Files';
      default:
        return 'Files';
    }
  }

  String get _fileTypeSingular {
    switch (widget.fileType) {
      case 'photo':
        return 'photo';
      case 'video':
        return 'video';
      case 'file':
        return 'file';
      default:
        return 'file';
    }
  }

  String get _formattedSize =>
      RecoverableFile.formatFileSize(widget.totalSizeBytes);

  String get _formattedTime {
    if (widget.elapsedTimeSeconds < 60) {
      return '${widget.elapsedTimeSeconds}s';
    }
    final m = widget.elapsedTimeSeconds ~/ 60;
    final s = widget.elapsedTimeSeconds % 60;
    return '${m}m ${s}s';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Checkmark scale + bounce
    _checkmarkController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _checkmarkScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _checkmarkController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _checkmarkBounceAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(
        parent: _checkmarkController,
        curve: const Interval(0.5, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // Confetti
    _confettiController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _confettiController.repeat();
        }
      });
    _initConfetti();

    // Arrow slide between before/after
    _arrowSlideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _arrowSlideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _arrowSlideController,
        curve: Curves.elasticOut,
      ),
    );

    // General fade controller for staggered sections
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Kick off staggered animations
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _checkmarkController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _confettiController.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fadeController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _arrowSlideController.forward();
    });
  }

  void _initConfetti() {
    final random = Random();
    const colors = [
      Color(0xFF6C63FF),
      Color(0xFF00D9A6),
      Color(0xFFFF6B6B),
      Color(0xFF10B981),
      Color(0xFFFFD93D),
      Color(0xFF4ECDC4),
      Color(0xFFA855F7),
      Color(0xFFFF8E53),
    ];

    for (int i = 0; i < 30; i++) {
      _confettiParticles.add(_ConfettiParticle(
        x: random.nextDouble() * 400,
        y: 200 + random.nextDouble() * 60,
        color: colors[random.nextInt(colors.length)],
        size: random.nextDouble() * 8 + 4,
        speed: random.nextDouble() * 2 + 1.5,
        wobble: random.nextDouble() * 2 - 1,
      ));
    }
  }

  @override
  void dispose() {
    _checkmarkController.dispose();
    _confettiController.dispose();
    _arrowSlideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Share helper ───────────────────────────────────────────────────────
  void _shareResults() {
    final successRate =
        (widget.recoveredCount / (widget.recoveredCount + widget.failedCount) * 100)
            .toStringAsFixed(1);
    final text =
        '${AppConstants.appName} - Restore Complete!\n\n'
        'Type: ${_fileTypeLabel}\n'
        'Files Recovered: ${widget.recoveredCount}\n'
        'Failed: ${widget.failedCount}\n'
        'Success Rate: $successRate%\n'
        'Total Size: $_formattedSize\n'
        'Time Taken: $_formattedTime\n'
        'Saved to: ${widget.recoveryPath}\n\n'
        'Try ${AppConstants.appName} today!';
    Share.share(text);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main scrollable content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // ── 1. Hero Section ─────────────────────────────────
                  _buildHeroSection(),

                  const SizedBox(height: 28),

                  // ── 2. Stats Cards Row ──────────────────────────────
                  _buildStaggeredSection(
                    delay: 300,
                    child: _buildStatsCards(),
                  ),

                  const SizedBox(height: 24),

                  // ── 3. Before vs After ─────────────────────────────
                  _buildStaggeredSection(
                    delay: 600,
                    child: _buildBeforeAfterSection(),
                  ),

                  const SizedBox(height: 24),

                  // ── 4. Recovery Details List ────────────────────────
                  _buildStaggeredSection(
                    delay: 900,
                    child: _buildRecoveryDetails(),
                  ),

                  const SizedBox(height: 24),

                  // ── 5. Action Buttons ──────────────────────────────
                  _buildStaggeredSection(
                    delay: 1100,
                    child: _buildActionButtons(),
                  ),

                  const SizedBox(height: 16),

                  // ── 6. Trust Badge ─────────────────────────────────
                  _buildStaggeredSection(
                    delay: 1300,
                    child: _buildTrustBadge(),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Confetti overlay (pointer-absorbing so it doesn't block taps)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ConfettiPainter(
                      particles: _confettiParticles,
                      progress: _confettiController.value,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1: Hero ────────────────────────────────────────────────────
  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.successColor.withOpacity(0.08),
            AppTheme.accentColor.withOpacity(0.04),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Animated checkmark icon
          AnimatedBuilder(
            animation: _checkmarkController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -_checkmarkBounceAnimation.value),
                child: Transform.scale(
                  scale: _checkmarkScaleAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.successColor,
                          AppTheme.accentColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.successColor.withOpacity(0.35),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Title
          FadeTransition(
            opacity: _fadeController,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _fadeController,
                curve: Curves.easeOutCubic,
              )),
              child: const Text(
                'Recovery Complete!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Subtitle
          FadeTransition(
            opacity: _fadeController,
            child: Text(
              '${widget.recoveredCount} ${_fileTypeLabel.toLowerCase()} recovered successfully'
              '${widget.failedCount > 0 ? ' (${widget.failedCount} failed)' : ''}',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 2: Stats Cards ─────────────────────────────────────────────
  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.check_circle_outline_rounded,
              label: 'Files Recovered',
              value: '${widget.recoveredCount}',
              color: AppTheme.successColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              icon: Icons.sd_storage_outlined,
              label: 'Total Size',
              value: _formattedSize,
              color: const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              icon: Icons.timer_outlined,
              label: 'Time Taken',
              value: _formattedTime,
              color: const Color(0xFFA855F7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          // Animated counter for numeric values
          if (int.tryParse(value) != null)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: int.parse(value)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, val, _) {
                return Text(
                  val.toString(),
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            )
          else
            Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Section 3: Before vs After ─────────────────────────────────────────
  Widget _buildBeforeAfterSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Before
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.warningColor.withOpacity(0.15),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.warningColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Before Recovery',
                    style: TextStyle(
                      color: AppTheme.warningColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.recoveredCount + widget.failedCount} ${_fileTypeLabel.toLowerCase()} at risk',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Animated arrow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedBuilder(
              animation: _arrowSlideController,
              builder: (context, _) {
                return Transform.translate(
                  offset: Offset(_arrowSlideAnimation.value * 4, 0),
                  child: Opacity(
                    opacity: _arrowSlideAnimation.value,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // After
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.successColor.withOpacity(0.15),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppTheme.successColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'After Recovery',
                    style: TextStyle(
                      color: AppTheme.successColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.recoveredCount} ${_fileTypeLabel.toLowerCase()} safely recovered',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 4: Recovery Details ────────────────────────────────────────
  Widget _buildRecoveryDetails() {
    final displayNames = widget.recoveredFileNames.take(5).toList();
    final remaining = widget.recoveredFileNames.length - 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.folder_open_outlined,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery Details',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Path row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.save_outlined,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Files saved to:',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Actual path
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                widget.recoveryPath,
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            if (displayNames.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Recovered Files',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // File names list
              ...displayNames.map((name) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          FileIconHelper.getFileIcon(name),
                          size: 16,
                          color: FileIconHelper.getFileColor(name),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: AppTheme.successColor,
                        ),
                      ],
                    ),
                  )),

              if (remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+ $remaining more ${_fileTypeLabel.toLowerCase()}',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Section 5: Action Buttons ──────────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Primary: View Recovered Files
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecoveredFilesScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.folder_special_outlined, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'View Recovered Files',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Outlined: Scan Again
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: const BorderSide(color: AppTheme.primaryColor, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.refresh_rounded, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Scan Again',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Text: Share Results
          TextButton.icon(
            onPressed: _shareResults,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text(
              'Share Results',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 6: Trust Badge ─────────────────────────────────────────────
  Widget _buildTrustBadge() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: AppTheme.textLight,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'No data uploaded \u2022 Files saved locally on your device',
                style: TextStyle(
                  color: AppTheme.textLight,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Staggered section helper ───────────────────────────────────────────
  Widget _buildStaggeredSection({
    required int delay,
    required Widget child,
  }) {
    return _StaggeredFadeIn(
      delay: Duration(milliseconds: delay),
      child: child,
    );
  }
}

// ── Staggered fade-in widget ─────────────────────────────────────────────
class _StaggeredFadeIn extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _StaggeredFadeIn({
    required this.delay,
    required this.child,
  });

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _started = true);
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return Opacity(opacity: 0.0, child: widget.child);
    }
    return FadeTransition(
      opacity: _opacityAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

// ── Confetti CustomPainter ───────────────────────────────────────────────
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final t = progress;
      // Float upward
      final y = particle.y - (t * particle.speed * 220);
      // Horizontal wobble
      final wobbleX = sin(t * 4 * particle.wobble) * 20;

      // Fade out as it goes higher
      final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.7;
      if (opacity <= 0) continue;

      final paint = Paint()
        ..color = particle.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      final xPos = particle.x + wobbleX;
      canvas.drawCircle(
        Offset(xPos.clamp(0.0, size.width), y.clamp(0.0, size.height)),
        particle.size * (1.0 - t * 0.3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
