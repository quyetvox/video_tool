import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/studio_state_notifier.dart';

/// Compact region display row + Gizmo activator button for Studio Properties.
/// Replicates the proven design from Video Editor's Subtitle Inspector.
class StudioRegionEditRow extends ConsumerWidget {
  final String label;
  final List<double>? region;
  final StudioGizmoLayer layerType;
  final VoidCallback? onReset;
  final String nullLabel;

  const StudioRegionEditRow({
    super.key,
    required this.label,
    required this.region,
    required this.layerType,
    this.onReset,
    this.nullLabel = 'Tự động (Auto)',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final activeLayer = ref.watch(activeStudioGizmoLayerProvider);
    final isActive = activeLayer == layerType;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              // Coordinate display box (monospace)
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive ? c.primary : c.border,
                      width: isActive ? 1.2 : 0.8,
                    ),
                  ),
                  child: Text(
                    region != null && region!.length == 4
                        ? '${region!.map((e) => (e * 100).toStringAsFixed(1)).join('%, ')}%'
                        : nullLabel,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: region != null ? c.primary : c.textMuted,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 🎯 Chỉnh Trên Video (34px)
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive
                        ? c.primary
                        : c.primary.withOpacity(0.15),
                    foregroundColor: isActive ? Colors.white : c.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: c.primary, width: 0.8),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    Icons.crop_free,
                    size: 14,
                    color: isActive ? Colors.white : c.primary,
                  ),
                  label: Text(
                    isActive ? '✓ Đang Chỉnh' : '🎯 Chỉnh',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    if (isActive) {
                      ref.read(activeStudioGizmoLayerProvider.notifier).state =
                          StudioGizmoLayer.none;
                    } else {
                      ref.read(activeStudioGizmoLayerProvider.notifier).state =
                          layerType;
                    }
                  },
                ),
              ),

              // Reset / Auto Button
              if (onReset != null) ...[
                const SizedBox(width: 6),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      side: BorderSide(color: c.border, width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: onReset,
                    child: Text(
                      'Auto',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
