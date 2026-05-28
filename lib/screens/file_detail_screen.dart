import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recoverable_file.dart';
import '../services/exif_extractor.dart';
import '../services/file_repair_service.dart';
import '../services/enhanced_recovery_engine.dart';
import '../utils/app_theme.dart';

class FileDetailScreen extends StatefulWidget {
  final RecoverableFile file;
  const FileDetailScreen({super.key, required this.file});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  bool _isRecovering = false;
  bool _isRepairing = false;
  bool _recovered = false;
  String? _repairResult;
  String? _recoveryPath;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreviewSection(),
            const SizedBox(height: 16),
            _buildQualityBadge(),
            const SizedBox(height: 16),
            _buildFileBasicInfo(),
            const SizedBox(height: 12),
            _buildExifSection(),
            const SizedBox(height: 12),
            _buildCorruptionSection(),
            const SizedBox(height: 12),
            _buildSourceSection(),
            const SizedBox(height: 16),
            _buildRecoveryActions(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    final file = widget.file;
    final icon = _getFileIcon();
    final iconColor = _getFileIconColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [iconColor.withOpacity(0.08), iconColor.withOpacity(0.02)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: iconColor.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 40, color: iconColor),
          ),
          const SizedBox(height: 12),
          Text(
            file.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            file.extension.toUpperCase().replaceFirst('.', ''),
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    switch (widget.file.fileType) {
      case 'photo': return Icons.photo_library_outlined;
      case 'video': return Icons.videocam_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Color _getFileIconColor() {
    switch (widget.file.fileType) {
      case 'photo': return AppTheme.primaryColor;
      case 'video': return const Color(0xFF00D9A6);
      default: return const Color(0xFFFF6B6B);
    }
  }

  Widget _buildQualityBadge() {
    final tag = widget.file.qualityTag;
    if (tag == null) return const SizedBox.shrink();

    final color = _getQualityColor(tag);
    final label = _getQualityLabel(tag);
    final icon = _getQualityIcon(tag);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text('Quality: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          if (widget.file.isNewFile) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_new, size: 12, color: Colors.blue),
                  const SizedBox(width: 3),
                  Text('New', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getQualityColor(String tag) {
    switch (tag) {
      case 'high': return Colors.green;
      case 'thumbnail': return Colors.orange;
      case 'corrupted': return Colors.red;
      case 'partial': return Colors.orange.shade700;
      case 'recovered': return Colors.blue;
      default: return Colors.amber.shade700;
    }
  }

  String _getQualityLabel(String tag) {
    switch (tag) {
      case 'high': return 'High Quality';
      case 'thumbnail': return 'Thumbnail';
      case 'corrupted': return 'Corrupted';
      case 'partial': return 'Partial';
      case 'recovered': return 'Recovered';
      case 'low': return 'Low Quality';
      default: return tag;
    }
  }

  IconData _getQualityIcon(String tag) {
    switch (tag) {
      case 'high': return Icons.star;
      case 'thumbnail': return Icons.image_not_supported_outlined;
      case 'corrupted': return Icons.warning_amber_rounded;
      case 'partial': return Icons.broken_image_outlined;
      case 'recovered': return Icons.restore;
      default: return Icons.info_outline;
    }
  }

  Widget _buildFileBasicInfo() {
    final file = widget.file;
    final items = [
      _DetailItem(Icons.description, 'Name', file.name),
      _DetailItem(Icons.label, 'Extension', file.extension),
      _DetailItem(Icons.straighten, 'Size', file.formattedSize),
      _DetailItem(Icons.access_time, 'Modified', file.formattedDate),
      _DetailItem(Icons.folder_outlined, 'Path', file.path),
      if (file.resolution != null) _DetailItem(Icons.aspect_ratio, 'Resolution', file.resolution!),
    ];

    return _buildInfoCard('File Information', Icons.info_outline, items);
  }

  Widget _buildExifSection() {
    final file = widget.file;
    final exifItems = <_DetailItem>[];

    if (file.cameraInfo != null) exifItems.add(_DetailItem(Icons.camera_alt, 'Camera', file.cameraInfo!));
    if (file.dateTaken != null) {
      final dt = file.dateTaken!;
      final dateStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      exifItems.add(_DetailItem(Icons.calendar_today, 'Date Taken', dateStr));
    }
    if (file.gpsLocation != null) exifItems.add(_DetailItem(Icons.location_on, 'GPS', file.gpsLocation!));
    if (file.software != null) exifItems.add(_DetailItem(Icons.build_outlined, 'Software', file.software!));
    if (file.iso != null) exifItems.add(_DetailItem(Icons.camera, 'ISO', 'ISO ${file.iso}'));
    if (file.orientation != null) exifItems.add(_DetailItem(Icons.rotate_right, 'Orientation', '${file.orientation} degrees'));

    if (exifItems.isEmpty) {
      // Try reading EXIF on the fly
      if (file.fileType == 'photo' && (file.extension.toLowerCase() == '.jpg' || file.extension.toLowerCase() == '.jpeg')) {
        try {
          final exif = ExifExtractor.extractFromFile(file.path);
          if (exif.hasExif) {
            exifItems.add(_DetailItem(Icons.camera_alt, 'Camera', exif.cameraInfo));
            if (exif.dateTimeOriginal != null) {
              final dt = exif.dateTimeOriginal!;
              final dateStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
              exifItems.add(_DetailItem(Icons.calendar_today, 'Date Taken', dateStr));
            }
            if (exif.gpsLocation != null) exifItems.add(_DetailItem(Icons.location_on, 'GPS', exif.gpsLocation!));
            if (exif.software != null) exifItems.add(_DetailItem(Icons.build_outlined, 'Software', exif.software!));
            if (exif.iso != null) exifItems.add(_DetailItem(Icons.camera, 'ISO', 'ISO ${exif.iso}'));
          }
        } catch (_) {}
      }
    }

    if (exifItems.isEmpty) return const SizedBox.shrink();
    return _buildInfoCard('EXIF Metadata', Icons.photo_camera, exifItems);
  }

  Widget _buildCorruptionSection() {
    final corruption = widget.file.corruptionLevel;
    if (corruption == null) {
      // Assess on the fly
      final assessed = FileRepairService.assessCorruption(widget.file.path);
      final health = ((1.0 - assessed) * 100).toInt();
      return _buildCorruptionCard(assessed, health);
    }
    final health = ((1.0 - corruption) * 100).toInt();
    return _buildCorruptionCard(corruption, health);
  }

  Widget _buildCorruptionCard(double corruption, int health) {
    final color = health >= 80 ? Colors.green : health >= 50 ? Colors.orange : Colors.red;
    final label = health >= 80 ? 'Healthy' : health >= 50 ? 'Partial Damage' : 'Severely Corrupted';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.healing, color: color, size: 18),
              const SizedBox(width: 8),
              Text('File Health', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$health%', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: health / 100.0,
              minHeight: 10,
              backgroundColor: AppTheme.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            corruption <= 0.0 ? 'File structure is intact and fully recoverable.' :
            corruption <= 0.3 ? 'Minor issues detected. File should open normally.' :
            corruption <= 0.6 ? 'File has partial damage. Repair may help recover content.' :
            'Severe corruption detected. Restore chances are limited.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSection() {
    final source = widget.file.source;
    final sourceIcon = _getSourceIcon(source);
    final sourceColor = _getSourceColor(source);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: sourceColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(sourceIcon, color: sourceColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Source', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(source, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (widget.file.isRecovered) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Text('Recovered', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    final s = source.toLowerCase();
    if (s.contains('camera') || s.contains('dcim')) return Icons.camera_alt;
    if (s.contains('whatsapp')) return Icons.chat;
    if (s.contains('telegram')) return Icons.send;
    if (s.contains('instagram')) return Icons.camera_alt_outlined;
    if (s.contains('download')) return Icons.download;
    if (s.contains('screenshot')) return Icons.screenshot;
    if (s.contains('trash') || s.contains('deleted')) return Icons.delete_outline;
    if (s.contains('hidden')) return Icons.visibility_off;
    if (s.contains('cache')) return Icons.cached;
    return Icons.folder;
  }

  Color _getSourceColor(String source) {
    final s = source.toLowerCase();
    if (s.contains('camera') || s.contains('dcim')) return AppTheme.primaryColor;
    if (s.contains('whatsapp')) return Colors.green;
    if (s.contains('telegram')) return Colors.lightBlue;
    if (s.contains('instagram')) return Colors.purple;
    if (s.contains('download')) return Colors.teal;
    if (s.contains('trash') || s.contains('deleted')) return Colors.red;
    if (s.contains('hidden')) return Colors.orange;
    return Colors.grey;
  }

  Widget _buildRecoveryActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red, fontSize: 12))),
              ],
            ),
          ),
        if (_recoveryPath != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Restored successfully!', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(_recoveryPath!, style: TextStyle(color: Colors.green.withOpacity(0.8), fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_repairResult != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.build_circle, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_repairResult!, style: TextStyle(color: Colors.blue, fontSize: 12))),
              ],
            ),
          ),
        // Recover button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isRecovering ? null : _recoverFile,
            icon: _isRecovering
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.restore, size: 20),
            label: Text(_isRecovering ? 'Restoring...' : 'Restore This File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Repair button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isRepairing ? null : _repairFile,
            icon: _isRepairing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.build_outlined, size: 18),
            label: Text(_isRepairing ? 'Repairing...' : 'Attempt Repair'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Copy path
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.file.path));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy File Path'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _recoverFile() async {
    setState(() { _isRecovering = true; _errorMessage = null; _recoveryPath = null; });
    try {
      final engine = EnhancedRecoveryEngine();
      await for (final progress in engine.recoverSingle(widget.file)) {
        if (!mounted) return;
        if (progress.completedFiles > 0) {
          setState(() { _recoveryPath = progress.currentFile; _recovered = true; });
        }
        if (progress.failedFiles > 0) {
          setState(() { _errorMessage = progress.status; });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = 'Restore failed: ${e.toString()}'; });
    }
    if (!mounted) return;
    setState(() { _isRecovering = false; });
  }

  Future<void> _repairFile() async {
    setState(() { _isRepairing = true; _repairResult = null; _errorMessage = null; });
    try {
      final repairedPath = await FileRepairService.attemptRepair(widget.file.path);
      if (!mounted) return;
      if (repairedPath != null) {
        setState(() { _repairResult = 'Repaired file saved to: $repairedPath'; });
      } else {
        setState(() { _repairResult = 'File does not need repair or repair was not possible.'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = 'Repair failed: ${e.toString()}'; });
    }
    if (!mounted) return;
    setState(() { _isRepairing = false; });
  }

  Widget _buildInfoCard(String title, IconData icon, List<_DetailItem> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const Divider(height: 20),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.icon, size: 16, color: AppTheme.textLight),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 1),
                      Text(item.value, style: const TextStyle(fontSize: 13), maxLines: item.label == 'Path' ? 3 : 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;
  const _DetailItem(this.icon, this.label, this.value);
}
