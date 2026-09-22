import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';

/// Thanh công cụ điều khiển Lớp Căn Chỉnh & Khung Gizmo chuẩn hóa dùng chung
/// Cho Video Editor, Kể Chuyện Vlog, AI Review Phim và Canvas Studio.
class VideoGizmoToolbar extends ConsumerWidget {
  /// Widget phụ tùy chọn ở đầu thanh (ví dụ: Bộ chọn tỉ lệ 16:9 / 9:16)
  final Widget? leading;

  /// Khoảng đệm xung quanh thanh công cụ
  final EdgeInsetsGeometry padding;

  /// Cho phép vô hiệu hóa khi không có video
  final bool enabled;

  /// Callback khi chọn lớp căn chỉnh (hữu ích cho Canvas Studio)
  final ValueChanged<FrameLayerType>? onLayerSelected;

  /// Callback khôi phục vị trí lớp hiện tại
  final ValueChanged<FrameLayerType>? onResetLayer;

  /// Widget tùy chọn ở cuối thanh (ví dụ: nút tạo nhanh clip che mờ)
  final Widget? trailing;

  const VideoGizmoToolbar({
    super.key,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.enabled = true,
    this.onLayerSelected,
    this.onResetLayer,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final isGizmoActive = ref.watch(isGizmoActiveProvider);
    final activeLayer = ref.watch(activeGizmoLayerProvider);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surfaceLight.withOpacity(0.4),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          // ── Nhóm bên trái: Leading, Nhãn, và 4 Lớp Căn Chỉnh (Có thể cuộn ngang an toàn) ──
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 10),
                    Container(width: 1, height: 18, color: c.border),
                    const SizedBox(width: 10),
                  ],

                  // Nhãn tiêu đề
                  Text(
                    'Lớp Căn Chỉnh:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: enabled ? c.textSecondary : c.textMuted.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 1. Layer Inpaint (Xóa Sub Cũ)
                  _buildLayerPill(
                    label: '🟦 Inpaint Sub Cũ',
                    isActive: enabled && isGizmoActive && activeLayer == FrameLayerType.inpaint,
                    activeColor: const Color(0xFFEF4444),
                    enabled: enabled,
                    onTap: () {
                      ref.read(isGizmoActiveProvider.notifier).state = true;
                      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.inpaint;
                      onLayerSelected?.call(FrameLayerType.inpaint);
                    },
                  ),
                  const SizedBox(width: 5),

                  // 2. Layer Primary Sub (Sub Chính)
                  _buildLayerPill(
                    label: '🟨 Sub Chính',
                    isActive: enabled && isGizmoActive && activeLayer == FrameLayerType.primarySub,
                    activeColor: const Color(0xFFFACC15),
                    enabled: enabled,
                    onTap: () {
                      ref.read(isGizmoActiveProvider.notifier).state = true;
                      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.primarySub;
                      onLayerSelected?.call(FrameLayerType.primarySub);
                    },
                  ),
                  const SizedBox(width: 5),

                  // 3. Layer Secondary Sub (Sub Phụ)
                  _buildLayerPill(
                    label: '🔷 Sub Phụ',
                    isActive: enabled && isGizmoActive && activeLayer == FrameLayerType.secondarySub,
                    activeColor: const Color(0xFF38BDF8),
                    enabled: enabled,
                    onTap: () {
                      ref.read(isGizmoActiveProvider.notifier).state = true;
                      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.secondarySub;
                      onLayerSelected?.call(FrameLayerType.secondarySub);
                    },
                  ),
                  const SizedBox(width: 5),

                  // 4. Layer Watermark (Logo Thương Hiệu)
                  _buildLayerPill(
                    label: '🟩 Watermark',
                    isActive: enabled && isGizmoActive && activeLayer == FrameLayerType.watermark,
                    activeColor: const Color(0xFF22C55E),
                    enabled: enabled,
                    onTap: () {
                      ref.read(isGizmoActiveProvider.notifier).state = true;
                      ref.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.watermark;
                      onLayerSelected?.call(FrameLayerType.watermark);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Nhóm bên phải: Bật/Tắt Khung Gizmo & Nút Khôi Phục Vị Trí ──
          InkWell(
            onTap: enabled
                ? () {
                    ref.read(isGizmoActiveProvider.notifier).state = !isGizmoActive;
                  }
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (enabled && isGizmoActive)
                    ? AppColors.primary.withOpacity(0.15)
                    : c.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (enabled && isGizmoActive)
                      ? AppColors.primary
                      : c.border.withOpacity(0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.crop_free,
                    size: 13,
                    color: (enabled && isGizmoActive)
                        ? AppColors.primary
                        : (enabled ? c.textSecondary : c.textMuted.withOpacity(0.4)),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    (enabled && isGizmoActive) ? 'Ẩn Khung Gizmo' : 'Hiện Khung Gizmo',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: (enabled && isGizmoActive)
                          ? AppColors.primary
                          : (enabled ? c.textSecondary : c.textMuted.withOpacity(0.4)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          IconButton(
            tooltip: 'Khôi phục vị trí lớp hiện tại về mặc định',
            icon: const Icon(Icons.refresh, size: 15),
            color: enabled ? c.textMuted : c.textMuted.withOpacity(0.3),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: enabled
                ? () {
                    if (onResetLayer != null) {
                      onResetLayer!(activeLayer);
                    } else {
                      final notifier = ref.read(configProvider.notifier);
                      switch (activeLayer) {
                        case FrameLayerType.inpaint:
                          notifier.setField((s) => s.copyWith(inpaintRegion: const [0.58, 0.08, 0.64, 0.94]));
                          break;
                        case FrameLayerType.primarySub:
                          notifier.setField((s) => s.copyWith(subtitleRegion: null));
                          break;
                        case FrameLayerType.secondarySub:
                          notifier.setField((s) => s.copyWith(subtitleSecondaryRegion: null));
                          break;
                        case FrameLayerType.watermark:
                          notifier.setField((s) => s.copyWith(watermarkRegion: const [0.02, 0.85, 0.05, 0.95]));
                          break;
                      }
                    }
                  }
                : null,
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _buildLayerPill({
    required String label,
    required bool isActive,
    required Color activeColor,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? activeColor
                : (enabled ? Colors.white12 : Colors.white.withOpacity(0.04)),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive
                ? activeColor
                : (enabled ? Colors.white70 : Colors.white30),
          ),
        ),
      ),
    );
  }
}
