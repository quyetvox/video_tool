import 'dart:io';
import 'package:flutter/material.dart';
import '../core/thumbnail_service.dart';

class VideoThumbnailWidget extends StatelessWidget {
  final String videoPath;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final Color? badgeColor;
  final String? badgeText;
  final String? durationText;
  final bool showDuration;

  const VideoThumbnailWidget({
    super.key,
    required this.videoPath,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.badgeColor,
    this.badgeText,
    this.durationText,
    this.showDuration = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (videoPath.isEmpty) {
      return _buildContainer(context, isDark, null, null);
    }

    final thumbNotifier = ThumbnailService.instance.getThumbnailNotifier(videoPath);
    final durationNotifier = (showDuration && (durationText == null || durationText!.isEmpty))
        ? ThumbnailService.instance.getDurationNotifier(videoPath)
        : null;

    return ValueListenableBuilder<String?>(
      valueListenable: thumbNotifier,
      builder: (context, thumbPath, _) {
        if (durationNotifier != null) {
          return ValueListenableBuilder<double?>(
            valueListenable: durationNotifier,
            builder: (context, durationSec, _) {
              final durStr = ThumbnailService.formatDuration(durationSec);
              return _buildContainer(context, isDark, thumbPath, durStr != '--:--' ? durStr : null);
            },
          );
        }
        return _buildContainer(context, isDark, thumbPath, durationText);
      },
    );
  }

  Widget _buildContainer(BuildContext context, bool isDark, String? thumbPath, String? displayDuration) {
    final hasValidThumb = thumbPath != null && File(thumbPath).existsSync();

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: width,
        height: height,
        color: isDark ? const Color(0xFF0B1120) : const Color(0xFFE2E8F0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail Image or Fallback Placeholder
            if (hasValidThumb)
              Image.file(
                File(thumbPath),
                fit: BoxFit.cover,
                cacheWidth: 320,
                errorBuilder: (ctx, err, stack) => _buildPlaceholder(),
              )
            else
              _buildPlaceholder(),

            // Subtle Gradient Overlay for badge contrast
            if (hasValidThumb)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black54,
                    ],
                  ),
                ),
              ),

            // Top Badge if provided
            if (badgeText != null && badgeColor != null)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor!.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    badgeText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // Bottom Duration Badge if provided or auto-probed
            if (displayDuration != null && displayDuration.isNotEmpty)
              Positioned(
                bottom: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white12, width: 0.5),
                  ),
                  child: Text(
                    displayDuration,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.movie_outlined,
        size: (height != null && height! < 32) ? 14 : 24,
        color: const Color(0xFF64748B).withOpacity(0.6),
      ),
    );
  }
}
