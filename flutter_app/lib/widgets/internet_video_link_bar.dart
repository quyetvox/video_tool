import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/media_link_service.dart';
import '../models/media_link_info.dart';
import 'app_kit.dart';

enum LinkBarStatus {
  idle,
  probing,
  probed,
  downloading,
  downloaded,
  error,
}

class InternetVideoLinkBar extends StatefulWidget {
  final String targetDir;
  final void Function(MediaLinkInfo info)? onStreamPreviewReady;
  final void Function(String localFilePath, String videoName)? onVideoDownloaded;
  final VoidCallback? onCleared;
  final Future<MediaLinkInfo> Function(String url)? customProber;

  const InternetVideoLinkBar({
    super.key,
    required this.targetDir,
    this.onStreamPreviewReady,
    this.onVideoDownloaded,
    this.onCleared,
    this.customProber,
  });

  @override
  State<InternetVideoLinkBar> createState() => InternetVideoLinkBarState();
}

class InternetVideoLinkBarState extends State<InternetVideoLinkBar> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  LinkBarStatus _status = LinkBarStatus.idle;
  MediaLinkInfo? _linkInfo;
  String _errorMessage = '';
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';
  int _probeId = 0;

  MediaLinkInfo? get currentLinkInfo => _linkInfo;
  bool get isPreviewing => _status == LinkBarStatus.probed && _linkInfo?.streamUrl.isNotEmpty == true;
  bool get isDownloading => _status == LinkBarStatus.downloading;

  @override
  void dispose() {
    _probeId++;
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// External reset method: clear text and restore idle state
  void reset() {
    _probeId++;
    if (_status == LinkBarStatus.downloading) {
      MediaLinkService.cancelDownload();
    }
    _textController.clear();
    setState(() {
      _status = LinkBarStatus.idle;
      _linkInfo = null;
      _errorMessage = '';
      _downloadProgress = 0.0;
      _downloadStatusText = '';
    });
    widget.onCleared?.call();
  }

  /// Extract clean HTTP/HTTPS URL from any raw text (e.g. shared text or copy with caption)
  static String? extractUrl(String text) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(text.trim());
    return match?.group(0);
  }

  /// Start probing the URL
  Future<void> probeUrl(String rawUrl) async {
    final url = extractUrl(rawUrl);
    if (url == null || url.isEmpty) return;

    final currentProbe = ++_probeId;
    setState(() {
      _status = LinkBarStatus.probing;
      _errorMessage = '';
      _linkInfo = null;
    });

    final info = widget.customProber != null
        ? await widget.customProber!(url)
        : await MediaLinkService.probeUrl(url);

    if (!mounted || currentProbe != _probeId) return;

    if (info.success) {
      setState(() {
        _status = LinkBarStatus.probed;
        _linkInfo = info;
      });
      widget.onStreamPreviewReady?.call(info);
    } else {
      setState(() {
        _status = LinkBarStatus.error;
        _errorMessage = info.error ?? 'Không thể nhận diện link video';
      });
    }
  }

  /// Trigger download of currently probed video
  Future<void> startDownload({VoidCallback? onFinish}) async {
    if (_linkInfo == null || widget.targetDir.isEmpty) return;

    setState(() {
      _status = LinkBarStatus.downloading;
      _downloadProgress = 0.05;
      _downloadStatusText = 'Bắt đầu tải...';
    });

    await MediaLinkService.downloadVideo(
      url: _linkInfo!.rawUrl,
      targetDir: widget.targetDir,
      customFilename: _linkInfo!.title.isNotEmpty ? _linkInfo!.title : null,
      onProgress: (progress, statusText) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress;
          _downloadStatusText = statusText;
        });
      },
      onCompleted: (savedFilePath) {
        if (!mounted) return;
        setState(() {
          _status = LinkBarStatus.downloaded;
          _downloadProgress = 1.0;
        });
        final fileName = savedFilePath.split(RegExp(r'[\\/]')).last;
        widget.onVideoDownloaded?.call(savedFilePath, fileName);
        onFinish?.call();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _status = LinkBarStatus.error;
          _errorMessage = error;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      height: 38,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.surfaceInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _status == LinkBarStatus.error
              ? c.statusFailed.withOpacity(0.6)
              : (_status == LinkBarStatus.probed
                  ? c.statusCompleted.withOpacity(0.4)
                  : c.border),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // 1. Icon Prefix
          Icon(
            Icons.link_rounded,
            size: 16,
            color: _status == LinkBarStatus.probed
                ? c.statusCompleted
                : (_status == LinkBarStatus.error ? c.statusFailed : c.primary),
          ),
          const SizedBox(width: 8),

          // 2. Input TextField
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 12,
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Dán link video Internet (YouTube, TikTok, Douyin, direct link)...',
                hintStyle: TextStyle(
                  fontSize: 11.5,
                  color: c.textMuted,
                  fontWeight: FontWeight.normal,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (val) {
                final clean = extractUrl(val);
                if (clean != null) {
                  probeUrl(clean);
                }
              },
              onChanged: (val) {
                // Auto probe if a full URL is pasted
                final clean = extractUrl(val);
                if (clean != null &&
                    clean != _linkInfo?.rawUrl &&
                    _status != LinkBarStatus.probing) {
                  probeUrl(clean);
                } else if (val.trim().isEmpty && _status != LinkBarStatus.idle) {
                  reset();
                }
              },
            ),
          ),

          // 3. Status Info / Badge
          if (_status == LinkBarStatus.probing) ...[
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Đang kiểm tra link...',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ] else if (_status == LinkBarStatus.probed && _linkInfo != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.statusCompleted.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.statusCompleted.withOpacity(0.3), width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 12, color: AppColors.statusCompleted),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _linkInfo!.title.isNotEmpty ? _linkInfo!.title : 'Video đã sẵn sàng',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.statusCompleted,
                      ),
                    ),
                  ),
                  if (_linkInfo!.formattedDuration.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      '• ${_linkInfo!.formattedDuration}',
                      style: TextStyle(fontSize: 10.5, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_status == LinkBarStatus.error) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: _errorMessage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: c.statusFailed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: c.statusFailed.withOpacity(0.3), width: 0.6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 13, color: c.statusFailed),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        _errorMessage.isNotEmpty ? _errorMessage : 'Lỗi tải video',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: c.statusFailed, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 4. Clear Button (X)
          if (_textController.text.isNotEmpty) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: reset,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 15, color: c.textMuted),
              ),
            ),
          ],

          // 5. Download Action Button (Mép phải)
          if (_status == LinkBarStatus.probed) ...[
            const SizedBox(width: 8),
            AppButton.primary(
              label: 'Tải xuống',
              icon: Icons.download_rounded,
              height: 26,
              fontSize: 11,
              onPressed: () => startDownload(),
            ),
          ] else if (_status == LinkBarStatus.error && _linkInfo != null) ...[
            const SizedBox(width: 8),
            AppButton.danger(
              label: 'Thử lại',
              icon: Icons.refresh_rounded,
              height: 26,
              fontSize: 11,
              onPressed: () => startDownload(),
            ),
          ] else if (_status == LinkBarStatus.downloading) ...[
            const SizedBox(width: 8),
            AppButton.primary(
              label: _downloadStatusText.isNotEmpty ? _downloadStatusText : 'Đang tải (${(_downloadProgress * 100).toInt()}%)',
              progress: _downloadProgress,
              height: 26,
              fontSize: 11,
              onPressed: null,
            ),
          ] else if (_status == LinkBarStatus.downloaded) ...[
            const SizedBox(width: 8),
            const AppButton.success(
              label: 'Đã lưu',
              icon: Icons.check_rounded,
              height: 26,
              fontSize: 11,
              onPressed: null,
            ),
          ],
        ],
      ),
    );
  }
}
