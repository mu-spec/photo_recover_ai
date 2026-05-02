import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/recoverable_file.dart';
import '../services/storage_scanner.dart';
import '../services/database_helper.dart';
import '../services/file_analyzer.dart';
import '../services/recovery_insights_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'preview_screen.dart';
import 'recovery_summary_screen.dart';
import 'file_detail_screen.dart';

class ScanResultsScreen extends StatefulWidget {
  final String fileType;
  final List<RecoverableFile> files;

  const ScanResultsScreen({
    super.key,
    required this.fileType,
    required this.files,
  });

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen>
    with TickerProviderStateMixin {
  final RecoveryService _recoveryService = RecoveryService();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final RecoveryInsightsService _insights = RecoveryInsightsService();

  List<RecoverableFile> _displayedFiles = [];
  final Set<int> _selectedIndices = {};
  String _sortBy = 'date';
  String _filterSource = 'All';
  String _filterQuality = 'All Quality';
  bool _filterLargeFiles = false;
  bool _showDuplicates = false;
  bool _isSelectMode = false;
  bool _isRecovering = false;
  int _recoveredCount = 0;

  final List<String> _sources = [
    'All', 'DCIM', 'WhatsApp', 'Pictures', 'Downloads', 'Cache', 'Hidden',
  ];

  final List<String> _qualityOptions = [
    'All Quality', 'High', 'Low Quality', 'Thumbnail', 'Corrupted',
  ];

  static const int _largeFileThreshold = 10 * 1024 * 1024; // 10MB

  @override
  void initState() {
    super.initState();
    _displayedFiles = List.from(widget.files);
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<RecoverableFile>.from(widget.files);

    // Filter by source
    if (_filterSource != 'All') {
      filtered = filtered.where((f) => f.source == _filterSource).toList();
    }

    // Filter by quality
    if (_filterQuality != 'All Quality') {
      filtered = filtered.where((f) {
        final quality = FileAnalyzer.analyzeFileQuality(f);
        switch (_filterQuality) {
          case 'High':
            return quality == FileQualityTag.highQuality;
          case 'Low Quality':
            return quality == FileQualityTag.lowQuality;
          case 'Thumbnail':
            return quality == FileQualityTag.thumbnail;
          case 'Corrupted':
            return quality == FileQualityTag.corrupted;
          default:
            return true;
        }
      }).toList();
    }

    // Filter large files
    if (_filterLargeFiles) {
      filtered = filtered.where((f) => f.size >= _largeFileThreshold).toList();
    }

    // Filter duplicates
    if (_showDuplicates) {
      final duplicateGroups = FileAnalyzer.findDuplicates(widget.files);
      final duplicatePaths = <String>{};
      for (final group in duplicateGroups) {
        for (final file in group) {
          duplicatePaths.add(file.path);
        }
      }
      filtered = filtered.where((f) => duplicatePaths.contains(f.path)).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'size':
        filtered.sort((a, b) => b.size.compareTo(a.size));
        break;
      case 'date':
      default:
        filtered.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    }

    // Clear selection when filters/sort change to avoid stale indices
    setState(() {
      _displayedFiles = filtered;
      _selectedIndices.clear();
      _isSelectMode = false;
    });
  }

  void _applySmartFilter() {
    final suggestions = FileAnalyzer.getSmartRecoverySuggestions(widget.files);
    final suggestionPaths = suggestions.take(5).map((f) => f.path).toSet();
    setState(() {
      _displayedFiles = widget.files.where((f) => suggestionPaths.contains(f.path)).toList();
      _selectedIndices.clear();
      _isSelectMode = false;
    });
  }

  int _getDuplicateCount() {
    final duplicateGroups = FileAnalyzer.findDuplicates(widget.files);
    int count = 0;
    for (final group in duplicateGroups) {
      count += group.length;
    }
    return count;
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      if (_selectedIndices.isEmpty) {
        _isSelectMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIndices.length == _displayedFiles.length) {
        _selectedIndices.clear();
        _isSelectMode = false;
      } else {
        _selectedIndices.clear();
        for (int i = 0; i < _displayedFiles.length; i++) {
          _selectedIndices.add(i);
        }
        _isSelectMode = true;
      }
    });
  }

  Future<void> _recoverSelectedFiles() async {
    if (_selectedIndices.isEmpty) return;

    setState(() => _isRecovering = true);

    final selectedFileObjects = _selectedIndices
        .map((i) => _displayedFiles[i])
        .toList();

    final total = selectedFileObjects.length;
    int recovered = 0;
    final recoveredNames = <String>[];
    int totalSize = 0;
    final recoveryStopwatch = Stopwatch()..start();

    // Use ValueNotifier for live progress updates in the dialog
    final progressNotifier = ValueNotifier<_RecoveryProgress>(
      _RecoveryProgress(current: 0, total: total, progress: 0.0, fileName: ''),
    );

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        return ValueListenableBuilder<_RecoveryProgress>(
          valueListenable: progressNotifier,
          builder: (context, progressData, _) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Recovering Files',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recovering ${progressData.current} of ${progressData.total} files...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  if (progressData.fileName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      progressData.fileName,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progressData.progress,
                      minHeight: 10,
                      backgroundColor: AppTheme.dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${progressData.current}/${progressData.total}',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${(progressData.progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Give the dialog time to render before starting recovery
    await Future.delayed(const Duration(milliseconds: 400));

    // Recover files one by one with progress updates
    try {
      for (int i = 0; i < selectedFileObjects.length; i++) {
        final file = selectedFileObjects[i];

        progressNotifier.value = _RecoveryProgress(
          current: i + 1,
          total: total,
          progress: (i + 1) / total,
          fileName: file.name,
        );

        try {
          final newPath = await _recoveryService.recoverFile(file);
          if (newPath != null) {
            recovered++;
            totalSize += file.size;
            recoveredNames.add(file.name);
            try {
              await _db.insertRecoveryRecord(
                RecoveryRecord(
                  id: DateTime.now().millisecondsSinceEpoch.toString() + i.toString(),
                  fileName: file.name,
                  originalPath: file.path,
                  recoveredPath: newPath,
                  fileType: widget.fileType,
                  recoveredAt: DateTime.now(),
                  fileSize: file.size,
                ),
              );
            } catch (_) {
              // DB insert failed, but file was recovered - continue
            }
          }
        } catch (_) {
          // Single file recovery failed - continue with next
        }
      }
    } catch (e) {
      // Unexpected error in recovery loop
    }

    // Stop stopwatch
    recoveryStopwatch.stop();
    final elapsed = recoveryStopwatch.elapsedMilliseconds ~/ 1000;

    // Dispose the notifier
    progressNotifier.dispose();

    // Close the progress dialog
    if (mounted) {
      Navigator.of(context).pop(); // close progress dialog
    }

    // Provider is already imported via main.dart
    Provider.of<AppSettingsProvider>(context, listen: false).incrementRecoveredCount(recovered);
    try {
      await _insights.recordRecovery(widget.fileType, recovered, totalSize);
    } catch (_) {}

    // Show interstitial ad after recovery
    adService.showInterstitialAd();

    if (mounted) {
      setState(() {
        _isRecovering = false;
        _recoveredCount = recovered;
        _selectedIndices.clear();
        _isSelectMode = false;
      });

      // Navigate to RecoverySummaryScreen
      final recoveryPath = await _recoveryService.getRecoveryBasePath();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RecoverySummaryScreen(
            fileType: widget.fileType,
            recoveredCount: recovered,
            failedCount: total - recovered,
            totalSizeBytes: totalSize,
            elapsedTimeSeconds: elapsed,
            recoveryPath: recoveryPath,
            recoveredFileNames: recoveredNames,
          ),
        ),
      );
    }
  }

  String _getFileTypeLabel() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Banner ad at top of results
            adService.buildBannerContainer(),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      'Scan Results',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_isSelectMode)
                    TextButton(
                      onPressed: _selectAll,
                      child: Text(
                        _selectedIndices.length == _displayedFiles.length
                            ? 'Deselect All'
                            : 'Select All',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isSelectMode = !_isSelectMode;
                        if (!_isSelectMode) _selectedIndices.clear();
                      });
                    },
                    icon: Icon(
                      _isSelectMode ? Icons.close : Icons.checklist,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),

            // Filter Chips (Source)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = _sources[index];
                  final isSelected = _filterSource == source;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _filterSource = source);
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? null
                            : Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Center(
                        child: Text(
                          source,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Quality Filter Chips
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _qualityOptions.length + 2, // +1 for Duplicates, +1 for Large Files
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == _qualityOptions.length) {
                    // Duplicates filter option
                    final dupCount = _getDuplicateCount();
                    return GestureDetector(
                      onTap: () {
                        setState(() => _showDuplicates = !_showDuplicates);
                        _applyFilters();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _showDuplicates
                              ? const Color(0xFFFF6B6B)
                              : AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: _showDuplicates
                              ? null
                              : Border.all(color: AppTheme.dividerColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.content_copy, size: 13, color: _showDuplicates ? Colors.white : AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Duplicates',
                              style: TextStyle(
                                color: _showDuplicates ? Colors.white : AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: _showDuplicates ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            if (dupCount > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _showDuplicates ? Colors.white.withOpacity(0.3) : AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$dupCount',
                                  style: TextStyle(
                                    color: _showDuplicates ? Colors.white : AppTheme.primaryColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  if (index == _qualityOptions.length + 1) {
                    // Large Files filter
                    return GestureDetector(
                      onTap: () {
                        setState(() => _filterLargeFiles = !_filterLargeFiles);
                        _applyFilters();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _filterLargeFiles
                              ? Colors.orange
                              : AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: _filterLargeFiles
                              ? null
                              : Border.all(color: AppTheme.dividerColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sd_storage, size: 13, color: _filterLargeFiles ? Colors.white : AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Large (>10MB)',
                              style: TextStyle(
                                color: _filterLargeFiles ? Colors.white : AppTheme.textSecondary,
                                fontSize: 11,
                                fontWeight: _filterLargeFiles ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final quality = _qualityOptions[index];
                  final isSelected = _filterQuality == quality && !_showDuplicates;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _filterQuality = quality;
                        _showDuplicates = false;
                      });
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected
                            ? null
                            : Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Center(
                        child: Text(
                          quality,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Sort Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_displayedFiles.length} ${_getFileTypeLabel()} found',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      setState(() => _sortBy = value);
                      _applyFilters();
                    },
                    child: Row(
                      children: [
                        Icon(Icons.sort, color: AppTheme.textSecondary, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          'Sort by ${_sortBy}',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'date', child: Text('Date')),
                      const PopupMenuItem(value: 'name', child: Text('Name')),
                      const PopupMenuItem(value: 'size', child: Text('Size')),
                    ],
                  ),
                ],
              ),
            ),

            // Smart Suggestions banner
            if (_displayedFiles.isNotEmpty)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18, color: AppTheme.primaryColor),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI suggests: ${FileAnalyzer.getSmartRecoverySuggestions(_displayedFiles).take(5).length} files worth recovering',
                        style: TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _applySmartFilter,
                      child: Text('Apply', style: TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            const Divider(height: 1),

            // Files Grid / List
            Expanded(
              child: _displayedFiles.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.search_off,
                      title: 'No ${_getFileTypeLabel()} Found',
                      description:
                          'No ${_getFileTypeLabel().toLowerCase()} were found in the selected filter. Try a different filter.',
                    )
                  : widget.fileType == 'photo'
                      ? _buildPhotoGrid()
                      : _buildFileList(),
            ),

            // Bottom Bar
            if (_selectedIndices.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedIndices.length} selected',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _getTotalSelectedSize(),
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: ElevatedButton(
                          onPressed: _isRecovering
                              ? null
                              : _recoverSelectedFiles,
                          child: _isRecovering
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.restore, size: 20),
                                    SizedBox(width: 8),
                                    Text('Recover'),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _selectedIndices.isNotEmpty
          ? null
          : SizedBox(
              height: 60,
              child: Center(child: adService.getBannerAdWidget()),
            ),
    );
  }

  String _getTotalSelectedSize() {
    int total = 0;
    for (final index in _selectedIndices) {
      if (index < _displayedFiles.length) {
        total += _displayedFiles[index].size;
      }
    }
    return RecoverableFile.formatFileSize(total);
  }

  Widget _buildPhotoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _displayedFiles.length,
      itemBuilder: (context, index) {
        final file = _displayedFiles[index];
        final isSelected = _selectedIndices.contains(index);
        final isPhotoFile = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp']
            .contains(file.extension.toLowerCase());
        final quality = FileAnalyzer.analyzeFileQuality(file);

        return GestureDetector(
          onTap: () {
            if (_isSelectMode) {
              _toggleSelection(index);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PreviewScreen(
                    file: file,
                    fileType: widget.fileType,
                    allFiles: _displayedFiles,
                    initialIndex: index,
                  ),
                ),
              );
            }
          },
          onLongPress: () {
            setState(() {
              _isSelectMode = true;
              _toggleSelection(index);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image thumbnail
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isPhotoFile
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: File(file.path).existsSync()
                            ? Image.file(
                                File(file.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildImagePlaceholder(file),
                              )
                            : _buildImagePlaceholder(file),
                      )
                    : _buildImagePlaceholder(file),
              ),

              // Selection overlay
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primaryColor,
                      width: 3,
                    ),
                  ),
                ),

              // Selection checkbox
              if (_isSelectMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.white.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                ),

              // Quality tag
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: FileAnalyzer.getQualityColor(quality).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    FileAnalyzer.getQualityLabel(quality),
                    style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // File size label
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text(
                    file.formattedSize,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePlaceholder(RecoverableFile file) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.dividerColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FileIconHelper.getFileIcon(file.extension),
            color: FileIconHelper.getFileColor(file.extension),
            size: 30,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              file.name,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _displayedFiles.length,
      itemBuilder: (context, index) {
        final file = _displayedFiles[index];
        final isSelected = _selectedIndices.contains(index);
        final quality = FileAnalyzer.analyzeFileQuality(file);

        return GestureDetector(
          onTap: () {
            if (_isSelectMode) {
              _toggleSelection(index);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PreviewScreen(
                    file: file,
                    fileType: widget.fileType,
                  ),
                ),
              );
            }
          },
          onLongPress: () {
            setState(() {
              _isSelectMode = true;
              _toggleSelection(index);
            });
          },
          onDoubleTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FileDetailScreen(file: file),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withOpacity(0.08)
                  : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : AppTheme.dividerColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: FileIconHelper.getFileColor(file.extension)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    FileIconHelper.getFileIcon(file.extension),
                    color: FileIconHelper.getFileColor(file.extension),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              file.source,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Quality chip
                          QualityTagChip(
                            label: FileAnalyzer.getQualityLabel(quality),
                            color: FileAnalyzer.getQualityColor(quality),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            file.formattedSize,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            file.formattedDate,
                            style: TextStyle(
                              color: AppTheme.textLight,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_isSelectMode)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textLight,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Helper class to hold recovery progress data for the dialog
class _RecoveryProgress {
  final int current;
  final int total;
  final double progress;
  final String fileName;

  _RecoveryProgress({
    required this.current,
    required this.total,
    required this.progress,
    required this.fileName,
  });
}
