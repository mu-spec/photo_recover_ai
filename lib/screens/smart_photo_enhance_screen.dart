import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recoverable_file.dart';
import '../services/database_helper.dart';
import '../services/smart_photo_enhancer_service.dart';
import '../utils/app_theme.dart';
import '../widgets/common_widgets.dart';

class SmartPhotoEnhanceScreen extends StatefulWidget {
  final RecoveryRecord? initialRecord;

  const SmartPhotoEnhanceScreen({super.key, this.initialRecord});

  @override
  State<SmartPhotoEnhanceScreen> createState() =>
      _SmartPhotoEnhanceScreenState();
}

class _SmartPhotoEnhanceScreenState extends State<SmartPhotoEnhanceScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final SmartPhotoEnhancerService _enhancer = SmartPhotoEnhancerService();

  List<RecoveryRecord> _photos = [];
  bool _isLoading = true;
  String? _enhancingId;
  bool _upscale = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    final records = await _db.getRecoveryRecords(fileType: 'photo');
    final available = <RecoveryRecord>[];

    for (final record in records) {
      if (File(record.recoveredPath).existsSync() &&
          _enhancer.canEnhance(record.recoveredPath)) {
        available.add(record);
      }
    }

    if (widget.initialRecord != null &&
        File(widget.initialRecord!.recoveredPath).existsSync() &&
        _enhancer.canEnhance(widget.initialRecord!.recoveredPath) &&
        !available.any((r) => r.id == widget.initialRecord!.id)) {
      available.insert(0, widget.initialRecord!);
    }

    if (mounted) {
      setState(() {
        _photos = available;
        _isLoading = false;
      });
    }
  }

  Future<void> _enhancePhoto(RecoveryRecord record) async {
    setState(() => _enhancingId = record.id);
    final result = await _enhancer.enhancePhoto(
      record.recoveredPath,
      upscale: _upscale,
    );

    if (!mounted) return;
    setState(() => _enhancingId = null);

    if (!result.success || result.outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enhanced Photo Saved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            const SizedBox(height: 12),
            Text(
              _resolutionText(result),
              style: TextStyle(color: AppTheme.getSecondaryTextColor(context)),
            ),
            const SizedBox(height: 12),
            Text(
              result.outputPath!,
              style: TextStyle(
                color: AppTheme.getLightTextColor(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () {
              Share.shareXFiles(
                [XFile(result.outputPath!)],
                text: 'Enhanced with Media Rescue',
              );
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  String _resolutionText(SmartPhotoEnhanceResult result) {
    final original = '${result.originalWidth}x${result.originalHeight}';
    final enhanced = '${result.enhancedWidth}x${result.enhancedHeight}';
    return 'Resolution: $original to $enhanced';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Photo Enhance')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'No Photos Ready',
                  description:
                      'Restore a JPG, PNG, WEBP, BMP, GIF, or TIFF photo first. Then use Smart Photo Enhance to improve the saved copy.',
                )
              : Column(
                  children: [
                    _buildInfoCard(),
                    SwitchListTile(
                      value: _upscale,
                      onChanged: (value) => setState(() => _upscale = value),
                      title: const Text('2x smart upscale'),
                      subtitle: const Text(
                        'Creates a larger enhanced copy when safe for this device.',
                      ),
                      activeColor: AppTheme.primaryColor,
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _photos.length,
                        itemBuilder: (context, index) {
                          return _buildPhotoTile(_photos[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Local enhancement improves restored photo copies with color tuning, sharpening, and safe upscaling. No photo is uploaded.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(RecoveryRecord record) {
    final isEnhancing = _enhancingId == record.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getDividerColor(context)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(record.recoveredPath),
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 58,
                height: 58,
                color: AppTheme.primaryColor.withOpacity(0.1),
                child: const Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.getPrimaryTextColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.formattedSize}  |  ${record.formattedDate}',
                  style: TextStyle(
                    color: AppTheme.getSecondaryTextColor(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isEnhancing ? null : () => _enhancePhoto(record),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(96, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isEnhancing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enhance'),
          ),
        ],
      ),
    );
  }
}
