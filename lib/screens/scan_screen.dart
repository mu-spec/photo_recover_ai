import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/storage_scanner.dart';
import '../services/database_helper.dart';
import '../services/recovery_insights_service.dart';
import '../models/recoverable_file.dart';
import '../utils/app_theme.dart';
import 'scan_results_screen.dart';

class ScanScreen extends StatefulWidget {
  final String fileType;
  final bool scanDeleted;

  const ScanScreen({
    super.key,
    required this.fileType,
    this.scanDeleted = false,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  final StorageScanner _scanner = StorageScanner();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final RecoveryInsightsService _insights = RecoveryInsightsService();

  double _progress = 0.0;
  String _currentFolder = 'Preparing...';
  int _filesFound = 0;
  String _status = 'Starting scan...';
  String _phase = 'scanning';
  bool _isScanning = true;
  bool _isCancelled = false;
  bool _isPaused = false;
  List<RecoverableFile> _foundFiles = [];
  bool _isComplete = false;
  int _totalScanned = 0;
  int _elapsedSeconds = 0;
  int _signaturesMatched = 0;
  int _storageLocations = 1;

  final List<_ScanLogEntry> _logEntries = [];
  final ScrollController _logScrollController = ScrollController();

  late AnimationController _pulseController;
  late AnimationController _radarController;
  late AnimationController _checkController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _radarAnimation;
  Timer? _timerController;

  StreamSubscription<ScanProgress>? _scanSubscription;

  Color get _scanColor {
    if (widget.scanDeleted) return const Color(0xFF8B5CF6);
    switch (widget.fileType) {
      case 'photo': return AppTheme.primaryColor;
      case 'video': return const Color(0xFF00D9A6);
      default: return const Color(0xFFFF6B6B);
    }
  }

  String get _typeLabel {
    switch (widget.fileType) {
      case 'photo': return 'Photos';
      case 'video': return 'Videos';
      default: return 'Files';
    }
  }

  String get _modeLabel => widget.scanDeleted ? 'Deleted' : 'All';

  IconData get _typeIcon {
    switch (widget.fileType) {
      case 'photo': return Icons.photo_library_outlined;
      case 'video': return Icons.videocam_outlined;
      default: return Icons.folder_outlined;
    }
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200), vsync: this,
    )..repeat();

    _radarController = AnimationController(
      duration: const Duration(milliseconds: 2000), vsync: this,
    )..repeat();

    _checkController = AnimationController(
      duration: const Duration(milliseconds: 600), vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _radarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _radarController, curve: Curves.linear),
    );

    _timerController = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isScanning && !_isPaused && mounted) {
        setState(() => _elapsedSeconds++);
      }
    });

    _startScan();
  }

  void _startScan() async {
    await _db.clearScanResults(widget.fileType);

    Stream<ScanProgress> scanStream;
    if (widget.scanDeleted) {
      switch (widget.fileType) {
        case 'photo': scanStream = _scanner.scanDeletedPhotos(); break;
        case 'video': scanStream = _scanner.scanDeletedVideos(); break;
        default: scanStream = _scanner.scanDeletedFiles(); break;
      }
    } else {
      switch (widget.fileType) {
        case 'photo': scanStream = _scanner.scanAllPhotos(); break;
        case 'video': scanStream = _scanner.scanAllVideos(); break;
        default: scanStream = _scanner.scanAllFiles(); break;
      }
    }

    _scanSubscription = scanStream.listen(
      (progress) {
        if (!mounted) return;

        setState(() {
          _progress = progress.progress;
          _currentFolder = progress.currentFolder;
          _filesFound = progress.filesFound;
          _status = progress.status;
          _phase = progress.phase;
          _totalScanned = progress.totalScanned;
          _signaturesMatched = progress.signaturesMatched;
          _storageLocations = progress.storageLocations;
        });

        if (progress.phase != 'discovery' &&
            progress.phase != 'analysis' &&
            progress.phase != 'complete' &&
            progress.currentFolder != _logEntries.lastOrNull?.folder) {
          setState(() {
            _logEntries.add(_ScanLogEntry(
              folder: progress.currentFolder,
              filesInFolder: progress.filesFound,
              timestamp: _elapsedSeconds,
            ));
          });
          if (_logScrollController.hasClients) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (_logScrollController.hasClients) {
                _logScrollController.animateTo(
                  _logScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
                );
              }
            });
          }
        }

        // Detect completion directly from progress data — safety net
        // so we never get stuck even if onDone doesn't fire
        if (progress.phase == 'complete' && !_isComplete && !_isCancelled) {
          _handleScanComplete();
        }
      },
      onDone: () async {
        // This fires when the stream closes, but we also handle
        // completion in the listener above for reliability
        if (!mounted || _isComplete) return;
        _handleScanComplete();
      },
      onError: (error) {
        debugPrint('Scan error: $error');
        _timerController?.cancel();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _status = 'Scan error occurred. Please try again.';
          });
        }
      },
    );
  }

  Future<void> _handleScanComplete() async {
    if (_isComplete) return; // Prevent double-call

    var finalResults = _scanner.lastScanResults;
    _timerController?.cancel();
    _pulseController.stop();
    _radarController.stop();

    // Fallback for strict deleted filter on OEMs where true deleted traces
    // are inaccessible/over-filtered: provide likely recoverables instead of hard zero.
    final shouldRunDeletedFallback = widget.scanDeleted &&
        finalResults.isEmpty &&
        (_totalScanned >= 2000 || _signaturesMatched >= 150);

    if (shouldRunDeletedFallback) {
      if (mounted) {
        setState(() {
          _status = 'No strict deleted matches. Finding possible recoverables...';
          _currentFolder = 'Fallback analysis';
          _phase = 'analysis';
        });
      }
      final fallback = await _runDeletedFallbackCandidates();
      if (fallback.isNotEmpty) {
        finalResults = fallback;
      }
    }

    final completionStatus = finalResults.isEmpty
        ? (widget.scanDeleted
            ? 'No recoverable deleted ${_typeLabel.toLowerCase()} found on this device right now.'
            : 'Found 0 ${_typeLabel}.')
        : (shouldRunDeletedFallback
            ? 'Showing likely recoverables (${finalResults.length})'
            : 'Found ${finalResults.length} ${_typeLabel}!');

    setState(() {
      _progress = 1.0;
      _filesFound = finalResults.length;
      _isScanning = false;
      _isPaused = false;
      _isComplete = true;
      _currentFolder = 'Scan finished';
      _status = completionStatus;
      _foundFiles = finalResults;
    });

    _checkController.forward();

    // Show interstitial automatically when scan completes.
    adService.showInterstitialAd();

    try {
      // Persist results before user returns to Home stats, so counters refresh correctly.
      await _db.insertScanResults(finalResults);
    } catch (e) {
      debugPrint('DB save error: $e');
    }

    try {
      // Track scan insights for Recovery Stats / Insights screen.
      await _insights.recordScan(widget.fileType, finalResults.length);
    } catch (e) {
      debugPrint('Insights scan record error: $e');
    }
  }

  Future<List<RecoverableFile>> _runDeletedFallbackCandidates() async {
    Stream<ScanProgress> fallbackStream;
    switch (widget.fileType) {
      case 'photo':
        fallbackStream = _scanner.scanAllPhotos();
        break;
      case 'video':
        fallbackStream = _scanner.scanAllVideos();
        break;
      default:
        fallbackStream = _scanner.scanAllFiles();
        break;
    }

    await for (final _ in fallbackStream) {
      if (_isCancelled) break;
    }

    final candidates = _scanner.lastScanResults;
    if (candidates.isEmpty) return [];
    return candidates.take(300).toList();
  }

  void _cancelScan() {
    _scanner.cancelScan();
    _pulseController.stop();
    _radarController.stop();
    setState(() { _isCancelled = true; _status = 'Cancelling scan...'; });
  }

  void _pauseScan() => setState(() { _isPaused = true; _scanner.pauseScan(); });
  void _resumeScan() => setState(() { _isPaused = false; _scanner.resumeScan(); });

  String _formatTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _pulseController.dispose();
    _radarController.dispose();
    _checkController.dispose();
    _timerController?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (!_isScanning)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    )
                  else
                    Row(
                      children: [
                        IconButton(
                          onPressed: _isPaused ? _resumeScan : _pauseScan,
                          icon: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                            color: _isPaused ? AppTheme.successColor : Colors.orange[400],
                          ),
                        ),
                        IconButton(
                          onPressed: _cancelScan,
                          icon: Icon(Icons.close, color: Colors.red[400]),
                        ),
                      ],
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _isCancelled
                          ? 'Scan Cancelled'
                          : 'Scanning $_modeLabel $_typeLabel',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Mode badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _scanColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.scanDeleted ? Icons.restore : Icons.search, size: 14, color: _scanColor),
                        const SizedBox(width: 4),
                        Text(_modeLabel, style: TextStyle(color: _scanColor, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Timer
                  if (_isScanning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _scanColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: _scanColor),
                          const SizedBox(width: 4),
                          Text(_formatTime(_elapsedSeconds), style: TextStyle(color: _scanColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // Animated scan visual
                      _buildScanningVisual(),

                      const SizedBox(height: 24),

                      // Status text
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 8),

                      // Current folder
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getPhaseColor().withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getPhaseLabel(),
                              style: TextStyle(color: _getPhaseColor(), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _currentFolder,
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Privacy banner
                      if (_isScanning)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock, size: 14, color: AppTheme.successColor),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Scanning on-device only. No data uploaded.',
                                  style: TextStyle(color: AppTheme.successColor, fontSize: 12, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Stats row
                      _buildStatsRow(),

                      const SizedBox(height: 10),

                      // Extended stats row
                      _buildExtendedStatsRow(),

                      const SizedBox(height: 20),

                      // Progress bar
                      _buildProgressBar(),

                      const SizedBox(height: 24),

                      // Scan log
                      if (_logEntries.isNotEmpty) _buildScanLog(),

                      const SizedBox(height: 16),

                      // Action buttons
                      if (_isComplete || _isCancelled) _buildActionButtons(),

                      if (_isScanning) _buildScanningFooter(),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPhaseColor() {
    switch (_phase) {
      case 'discovery': return AppTheme.primaryColor;
      case 'quick_scan': return const Color(0xFF3B82F6);
      case 'scanning': return const Color(0xFF3B82F6);
      case 'deep_scan': return const Color(0xFF8B5CF6);
      case 'cache_scan': return const Color(0xFFF59E0B);
      case 'hidden_scan': return const Color(0xFFEF4444);
      case 'carving': return const Color(0xFFEC4899);
      case 'analysis': return const Color(0xFF10B981);
      case 'complete': return AppTheme.successColor;
      default: return AppTheme.primaryColor;
    }
  }

  String _getPhaseLabel() {
    switch (_phase) {
      case 'discovery': return 'Discovery';
      case 'quick_scan': return 'Quick Scan';
      case 'scanning': return 'Scanning';
      case 'deep_scan': return 'Deep Scan';
      case 'cache_scan': return 'Cache Scan';
      case 'hidden_scan': return 'Hidden Scan';
      case 'carving': return 'File Carving';
      case 'analysis': return 'Analysis';
      case 'complete': return 'Complete';
      default: return 'Scanning';
    }
  }

  Widget _buildScanningVisual() {
    return SizedBox(
      height: 180,
      width: 180,
      child: Center(
        child: AnimatedBuilder(
          animation: _isComplete ? _checkController : _isCancelled ? _pulseController : _radarController,
          builder: (context, child) {
            if (_isCancelled) {
              return Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.orange.shade300], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.cancel, color: Colors.white, size: 60),
              );
            }

            if (_isComplete) {
              return Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [const Color(0xFF10B981), const Color(0xFF34D399)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 60),
              );
            }

            // Scanning state - radar effect
            final color = _scanColor;
            return Container(
              width: 160, height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.1), width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 150 * _pulseAnimation.value,
                    height: 150 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withOpacity(0.2), width: 1),
                    ),
                  ),
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.05),
                      border: Border.all(color: color.withOpacity(0.15), width: 1),
                    ),
                  ),
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color, color.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 5))],
                    ),
                    child: Icon(_typeIcon, color: Colors.white, size: 30),
                  ),
                  Transform.rotate(
                    angle: _radarAnimation.value * 2 * 3.14159,
                    child: Container(
                      width: 2, height: 80,
                      decoration: BoxDecoration(color: color.withOpacity(0.6), borderRadius: BorderRadius.circular(1)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(icon: Icons.search, label: 'Found', value: '$_filesFound', color: _scanColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(icon: Icons.folder_open, label: 'Scanned', value: '$_totalScanned', color: const Color(0xFF3B82F6)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(icon: Icons.timer, label: 'Time', value: _formatTime(_elapsedSeconds), color: const Color(0xFF8B5CF6)),
        ),
      ],
    );
  }

  Widget _buildExtendedStatsRow() {
    return Row(
      children: [
        if (_signaturesMatched > 0)
          Expanded(
            child: _buildStatCard(icon: Icons.fingerprint, label: 'Signatures', value: '$_signaturesMatched', color: const Color(0xFFEC4899)),
          ),
        if (_signaturesMatched > 0) const SizedBox(width: 10),
        if (_storageLocations > 1)
          Expanded(
            child: _buildStatCard(icon: Icons.sd_card, label: 'Storages', value: '$_storageLocations', color: const Color(0xFFF59E0B)),
          ),
        if (_storageLocations > 1) const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.phonelink_setup,
            label: widget.scanDeleted ? 'Deleted Filter' : 'Full Scan',
            value: widget.scanDeleted ? '12+Filter' : '12 Phases',
            color: widget.scanDeleted ? const Color(0xFF8B5CF6) : const Color(0xFF10B981),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _progress.clamp(0.0, 1.0),
            minHeight: 12,
            backgroundColor: AppTheme.dividerColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              _isCancelled ? Colors.orange : _isComplete ? const Color(0xFF10B981) : _scanColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_getPhaseLabel(), style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            Text('${(_progress.clamp(0.0, 1.0) * 100).toInt()}%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildScanLog() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text('Scan Activity', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_logEntries.length} folders', style: TextStyle(color: AppTheme.textLight, fontSize: 10)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _logScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _logEntries.length,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final entry = _logEntries[index];
                final isLatest = index == _logEntries.length - 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        isLatest ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 10,
                        color: isLatest ? AppTheme.successColor : AppTheme.textLight,
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.folder, size: 12, color: AppTheme.textLight),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.folder,
                          style: TextStyle(
                            color: isLatest ? AppTheme.textPrimary : AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: isLatest ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLatest && _isScanning)
                        const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (_foundFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => ScanResultsScreen(fileType: widget.fileType, files: _foundFiles),
                    ),
                  );
                  // Show interstitial ad after navigation completes
                  Future.delayed(const Duration(milliseconds: 500), () {
                    adService.showInterstitialAd();
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.visibility, size: 20),
                    const SizedBox(width: 8),
                    Text('View ${_filesFound} ${_typeLabel}'),
                  ],
                ),
              ),
            ),
          ),
        if (_isCancelled || _foundFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _pulseController.repeat();
                  _radarController.repeat();
                  setState(() {
                    _isCancelled = false; _isComplete = false; _isPaused = false;
                    _progress = 0.0; _filesFound = 0; _foundFiles = [];
                    _isScanning = true; _logEntries.clear(); _elapsedSeconds = 0;
                  });
                  _scanner.resetCancel();
                  _startScan();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Scan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanningFooter() {
    return Column(
      children: [
        TextButton(
          onPressed: _cancelScan,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop_circle_outlined, size: 16, color: Colors.red[400]),
              const SizedBox(width: 6),
              Text('Cancel Scan', style: TextStyle(color: Colors.red[400], fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_isPaused)
          Text('Scan paused. Tap play to continue.', style: TextStyle(color: AppTheme.warningColor, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center)
        else
          Text('Please wait while scanning...\nDo not close the app.', style: TextStyle(color: AppTheme.textLight, fontSize: 12), textAlign: TextAlign.center),
      ],
    );
  }
}

class _ScanLogEntry {
  final String folder;
  final int filesInFolder;
  final int timestamp;
  _ScanLogEntry({required this.folder, required this.filesInFolder, required this.timestamp});
}
