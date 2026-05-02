import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recoverable_file.dart';
import '../services/database_helper.dart';
import '../services/storage_scanner.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';
import '../widgets/common_widgets.dart';

class RecoveredFilesScreen extends StatefulWidget {
  const RecoveredFilesScreen({super.key});

  @override
  State<RecoveredFilesScreen> createState() => _RecoveredFilesScreenState();
}

class _RecoveredFilesScreenState extends State<RecoveredFilesScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final RecoveryService _recoveryService = RecoveryService();

  late TabController _tabController;
  List<RecoveryRecord> _allRecords = [];
  List<RecoveryRecord> _photos = [];
  List<RecoveryRecord> _videos = [];
  List<RecoveryRecord> _files = [];
  bool _isLoading = true;
  int _totalSize = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);

    final allRecords = await _db.getRecoveryRecords();
    final photoRecords = await _db.getRecoveryRecords(fileType: 'photo');
    final videoRecords = await _db.getRecoveryRecords(fileType: 'video');
    final fileRecords = await _db.getRecoveryRecords(fileType: 'file');
    final size = await _recoveryService.getRecoveryFolderSize();

    if (mounted) {
      setState(() {
        _allRecords = allRecords;
        _photos = photoRecords;
        _videos = videoRecords;
        _files = fileRecords;
        _totalSize = size;
        _isLoading = false;
      });
    }
  }

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _shareFile(String path, String name) {
    final file = File(path);
    if (file.existsSync()) {
      Share.shareXFiles([XFile(path)], text: 'Recovered: $name');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File not found. It may have been deleted.'),
            backgroundColor: Color(0xFFFF6B6B),
          ),
        );
      }
    }
  }

  Future<void> _deleteRecord(RecoveryRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete File'),
        content: Text('Delete "${record.fileName}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _recoveryService.deleteRecoveredFile(record.recoveredPath);
      await _db.deleteRecoveryRecord(record.id);
      _loadRecords();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All'),
        content: const Text('Delete all recovered files? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B)),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _recoveryService.clearAllRecoveredFiles();
      await _db.clearRecoveryRecords();
      _loadRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentList = _tabController.index == 0
        ? _photos
        : _tabController.index == 1
            ? _videos
            : _files;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovered Files'),
        actions: [
          if (_allRecords.isNotEmpty)
            IconButton(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: Column(
        children: [
          // Stats Banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.gradientAccent,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: 'Total Files',
                  value: _allRecords.length.toString(),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.3),
                ),
                _StatItem(
                  label: 'Total Size',
                  value: _formatSize(_totalSize),
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Photos'),
                Tab(text: 'Videos'),
                Tab(text: 'Files'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Records List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : currentList.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.folder_open_outlined,
                        title: 'No Recovered Files',
                        description:
                            'Your recovered files will appear here. Start a scan to find deleted files.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: currentList.length,
                        itemBuilder: (context, index) {
                          final record = currentList[index];
                          return _buildRecordTile(record);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(RecoveryRecord record) {
    final exists = File(record.recoveredPath).existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: exists ? AppTheme.dividerColor : const Color(0xFFFFE0E0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: FileIconHelper.getFileColor(record.recoveredPath)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              FileIconHelper.getFileIcon(record.recoveredPath),
              color: exists
                  ? FileIconHelper.getFileColor(record.recoveredPath)
                  : const Color(0xFFFF6B6B),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName,
                  style: TextStyle(
                    color: exists
                        ? AppTheme.textPrimary
                        : const Color(0xFFFF6B6B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      record.formattedSize,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      record.formattedDate,
                      style: TextStyle(
                        color: AppTheme.textLight,
                        fontSize: 11,
                      ),
                    ),
                    if (!exists) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '(Missing)',
                        style: TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'open':
                  _openFile(record.recoveredPath);
                  break;
                case 'share':
                  _shareFile(record.recoveredPath, record.fileName);
                  break;
                case 'delete':
                  _deleteRecord(record);
                  break;
              }
            },
            itemBuilder: (context) => [
              if (exists)
                const PopupMenuItem(
                  value: 'open',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 18),
                      SizedBox(width: 10),
                      Text('Open'),
                    ],
                  ),
                ),
              if (exists)
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, size: 18),
                      SizedBox(width: 10),
                      Text('Share'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Color(0xFFFF6B6B)),
                    SizedBox(width: 10),
                    Text('Delete',
                        style: TextStyle(color: Color(0xFFFF6B6B))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
