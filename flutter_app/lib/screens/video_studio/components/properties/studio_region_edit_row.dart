import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/providers.dart';
import '../../../../core/studio_state_notifier.dart';

/// Compact region display row + Gizmo activator button for Studio Properties.
/// Replicates the proven design from Video Editor's Subtitle Inspector
/// with full 2-way realtime synchronization between canvas gizmo and numerical inputs.
class StudioRegionEditRow extends ConsumerWidget {
  final String label;
  final List<double>? region;
  final StudioGizmoLayer layerType;
  final VoidCallback? onReset;
  final ValueChanged<List<double>>? onRegionChanged;
  final String nullLabel;

  const StudioRegionEditRow({
    super.key,
    required this.label,
    required this.region,
    required this.layerType,
    this.onReset,
    this.onRegionChanged,
    this.nullLabel = 'Tự động (Auto)',
  });

  FrameLayerType? _toFrameLayer(StudioGizmoLayer layer) {
    switch (layer) {
      case StudioGizmoLayer.inpaint:
        return FrameLayerType.inpaint;
      case StudioGizmoLayer.primarySub:
        return FrameLayerType.primarySub;
      case StudioGizmoLayer.secondarySub:
        return FrameLayerType.secondarySub;
      case StudioGizmoLayer.watermark:
        return FrameLayerType.watermark;
      case StudioGizmoLayer.none:
        return null;
    }
  }

  void _handleCoordChange(int index, double pctVal) {
    if (region == null || region!.length != 4 || onRegionChanged == null) return;
    final norm = (pctVal / 100.0).clamp(0.0, 1.0);
    final updated = List<double>.from(region!);
    updated[index] = double.parse(norm.toStringAsFixed(3));

    // Ensure valid bounding box constraints: top < bottom, left < right
    if (index == 0 && updated[0] >= updated[2]) {
      updated[0] = (updated[2] - 0.02).clamp(0.0, 1.0);
    } else if (index == 1 && updated[1] >= updated[3]) {
      updated[1] = (updated[3] - 0.02).clamp(0.0, 1.0);
    } else if (index == 2 && updated[2] <= updated[0]) {
      updated[2] = (updated[0] + 0.02).clamp(0.0, 1.0);
    } else if (index == 3 && updated[3] <= updated[1]) {
      updated[3] = (updated[1] + 0.02).clamp(0.0, 1.0);
    }

    onRegionChanged!(updated);
  }

  Widget _buildMiniCoordInput(
    BuildContext context,
    AppColorTokens c,
    String tag,
    double valNorm,
    ValueChanged<double> onSubmitted,
  ) {
    final pctText = (valNorm * 100.0).toStringAsFixed(1);
    return Expanded(
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: c.surfaceDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.border.withOpacity(0.7), width: 0.8),
        ),
        child: Row(
          children: [
            Text(
              tag,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextFormField(
                key: ValueKey('$tag-$pctText'),
                initialValue: pctText,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: c.textPrimary,
                  height: 1.1,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  suffixText: '%',
                  suffixStyle: TextStyle(fontSize: 9.5, color: Colors.white38),
                ),
                onFieldSubmitted: (text) {
                  final parsed = double.tryParse(text.replaceAll('%', '').trim());
                  if (parsed != null) {
                    onSubmitted(parsed);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = AppColors.of(context);
    final isGizmoActive = ref.watch(isGizmoActiveProvider);
    final activeLayer = ref.watch(activeStudioGizmoLayerProvider);
    final isActive = isGizmoActive && activeLayer == layerType;

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

              // 🎯 Chỉnh Trên Video (34px) - Bidirectional Header & Gizmo Activator
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
                      // Turn off gizmo
                      ref.read(activeStudioGizmoLayerProvider.notifier).state =
                          StudioGizmoLayer.none;
                      ref.read(isGizmoActiveProvider.notifier).state = false;
                    } else {
                      // Turn on gizmo and sync both Studio & Global Toolbar providers
                      ref.read(isGizmoActiveProvider.notifier).state = true;
                      ref.read(activeStudioGizmoLayerProvider.notifier).state =
                          layerType;
                      final frameLayer = _toFrameLayer(layerType);
                      if (frameLayer != null) {
                        ref.read(activeGizmoLayerProvider.notifier).state =
                            frameLayer;
                      }
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

          // 4 Mini Numerical Inputs (Top, Left, Bottom, Right) for granular editing
          if (region != null && region!.length == 4 && onRegionChanged != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                _buildMiniCoordInput(context, c, 'Y1', region![0], (v) => _handleCoordChange(0, v)),
                const SizedBox(width: 4),
                _buildMiniCoordInput(context, c, 'X1', region![1], (v) => _handleCoordChange(1, v)),
                const SizedBox(width: 4),
                _buildMiniCoordInput(context, c, 'Y2', region![2], (v) => _handleCoordChange(2, v)),
                const SizedBox(width: 4),
                _buildMiniCoordInput(context, c, 'X2', region![3], (v) => _handleCoordChange(3, v)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
