import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recoverable_file.dart';
import '../services/storage_scanner.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class PreviewScreen extends StatefulWidget {
  final RecoverableFile file;
  final String fileType;
  final List<RecoverableFile>? allFiles;
  final int? initialIndex;

  const PreviewScreen({
    super.key,
    required this.file,
    required this.fileType,
    this.allFiles,
    this.initialIndex,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showInfo = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = widget.allFiles != null && widget.allFiles!.length > 1
        ? PageController(initialPage: _currentIndex)
        : PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _recoverFile() async {
    final recoveryService = RecoveryService();
    final newPath = await recoveryService.recoverFile(widget.file);

    if (newPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File restored successfully!'),
          backgroundColor: AppTheme.successColor,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () async {
              final uri = Uri.file(newPath);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restore failed. File may not exist.'),
          backgroundColor: Color(0xFFFF6B6B),
        ),
      );
    }
  }

  void _shareFile() {
    final file = File(widget.file.path);
    if (file.existsSync()) {
      Share.shareXFiles(
        [XFile(widget.file.path)],
        text: 'Restored with Media Rescue',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File not found at source location.'),
          backgroundColor: Color(0xFFFF6B6B),
        ),
      );
    }
  }

  RecoverableFile get _currentFile {
    if (widget.allFiles != null && widget.allFiles!.isNotEmpty) {
      return widget.allFiles![_currentIndex];
    }
    return widget.file;
  }

  bool get _canNavigate =>
      widget.allFiles != null && widget.allFiles!.length > 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Preview
          Positioned.fill(
            child: _buildPreview(),
          ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 8,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentFile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_canNavigate)
                    Text(
                      '${_currentIndex + 1}/${widget.allFiles!.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() => _showInfo = !_showInfo);
                    },
                    icon: Icon(
                      _showInfo ? Icons.info : Icons.info_outline,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Navigation arrows
          if (_canNavigate) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed: _currentIndex > 0
                      ? () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      : null,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed:
                      _currentIndex < (widget.allFiles!.length - 1)
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_right, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
          ],

          // Info Panel
          if (_showInfo) _buildInfoPanel(),

          // Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                top: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    icon: Icons.restore,
                    label: 'Restore Copy',
                    color: AppTheme.primaryColor,
                    onTap: _recoverFile,
                  ),
                  _buildActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    color: const Color(0xFF00D9A6),
                    onTap: _shareFile,
                  ),
                  _buildActionButton(
                    icon: Icons.info_outline,
                    label: 'Details',
                    color: const Color(0xFFF59E0B),
                    onTap: () => setState(() => _showInfo = !_showInfo),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (!_canNavigate) {
      return _buildFileView(_currentFile);
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: widget.allFiles!.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
      },
      itemBuilder: (context, index) {
        return _buildFileView(widget.allFiles![index]);
      },
    );
  }

  Widget _buildFileView(RecoverableFile file) {
    final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic']
        .contains(file.extension.toLowerCase());

    if (isImage && File(file.path).existsSync()) {
      return Center(
        child: Image.file(
          File(file.path),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildFilePlaceholder(file),
        ),
      );
    }

    return _buildFilePlaceholder(file);
  }

  Widget _buildFilePlaceholder(RecoverableFile file) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FileIconHelper.getFileIcon(file.extension),
              color: Colors.white70,
              size: 80,
            ),
            const SizedBox(height: 16),
            Text(
              file.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${file.extension.toUpperCase()} - ${file.formattedSize}',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    final file = _currentFile;
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FileIconHelper.getFileIcon(file.extension),
                  color: FileIconHelper.getFileColor(file.extension),
                  size: 28,
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        file.extension.toUpperCase(),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showInfo = false),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.folder_outlined, 'Source', file.source),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.straighten, 'Size', file.formattedSize),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.access_time, 'Modified', file.formattedDate),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.insert_drive_file, 'Path', file.path),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.textLight, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textLight,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

