import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/app_colors.dart';
import '../core/file_service.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';

class DownloaderScreen extends ConsumerStatefulWidget {
  const DownloaderScreen({super.key});

  @override
  ConsumerState<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends ConsumerState<DownloaderScreen> {
  final TextEditingController _urlsController = TextEditingController();
  int _downloadLimit = 10;
  bool _isDownloading = false;
  List<String> _extractedUrls = [];

  @override
  void initState() {
    super.initState();
    _loadSavedDouyinTxt();
  }

  @override
  void dispose() {
    _urlsController.dispose();
    super.dispose();
  }

  void _loadSavedDouyinTxt() {
    final activeProj = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProj == null) return;

    final txtPath = p.join(projectsDir, activeProj, 'src', 'douyin-video-links.txt');
    if (File(txtPath).existsSync()) {
      final content = FileService.readTextFile(txtPath);
      _urlsController.text = content;
      _parseUrls(content);
    }
  }

  void _parseUrls(String text) {
    final lines = text.split('\n');
    final urls = <String>[];
    final urlRegex = RegExp(r'https?://[^\s]+');

    for (final line in lines) {
      final match = urlRegex.firstMatch(line.trim());
      if (match != null) {
        urls.add(match.group(0)!);
      }
    }

    setState(() => _extractedUrls = urls);
  }

  Future<void> _startDownload() async {
    final activeProj = ref.read(activeProjectProvider);
    final projectsDir = ref.read(projectsDirProvider);
    if (activeProj == null || _extractedUrls.isEmpty) return;

    // Save links to douyin-video-links.txt
    final txtPath = p.join(projectsDir, activeProj, 'src', 'douyin-video-links.txt');
    FileService.writeTextFile(txtPath, _extractedUrls.join('\n'));

    setState(() => _isDownloading = true);

    final jobId = 'dl_${DateTime.now().millisecondsSinceEpoch}';
    final args = [txtPath, '--limit', _downloadLimit.toString()];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📥 Đang bắt đầu tải ${_extractedUrls.length} video Douyin vào $activeProj/src/ ...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final result = await PythonBridge.runScript('download.py', args, jobId: jobId);

    setState(() => _isDownloading = false);
    ref.invalidate(projectVideosProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.success ? '🎉 Tải hoàn tất video Douyin!' : '❌ Có lỗi trong quá trình tải.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeProj = ref.watch(activeProjectProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.download_for_offline_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Tải Video Hàng Loạt từ Douyin / TikTok [Dự án: ${activeProj ?? ""}]',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Dán danh sách các đường link chia sẻ từ Douyin/TikTok (mỗi dòng 1 link hoặc nguyên đoạn văn bản copy từ app). Tệp sẽ được lưu vào assets/<project>/src/.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),

          // Action settings
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Text(
                  'Đã nhận diện: ${_extractedUrls.length} liên kết hợp lệ',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 14),
              const Text('Giới hạn tải tối đa:', style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              const SizedBox(width: 8),
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _downloadLimit,
                    dropdownColor: AppColors.surfaceLight,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    icon: const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.textSecondary),
                    items: [5, 10, 20, 50, 100].map((n) {
                      return DropdownMenuItem(value: n, child: Text('$n video'));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _downloadLimit = val);
                    },
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryText,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                icon: Icon(_isDownloading ? Icons.sync : Icons.cloud_download, size: 14),
                label: Text(_isDownloading ? 'Đang tải...' : 'Bắt đầu Tải Video', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: (_isDownloading || _extractedUrls.isEmpty) ? null : _startDownload,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // URL Text Field
          Expanded(
            child: TextField(
              controller: _urlsController,
              maxLines: null,
              expands: true,
              cursorColor: AppColors.primary,
              onChanged: _parseUrls,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Dán link Douyin tại đây...\nVí dụ:\nhttps://v.douyin.com/iABCxyz/\n7.12 复制打开抖音，看看【小明的作品】 https://v.douyin.com/xyz123/',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                filled: true,
                fillColor: AppColors.surfaceDark,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border, width: 0.8)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.primary, width: 1.0)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
