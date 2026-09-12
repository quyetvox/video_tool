import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/studio_state_notifier.dart';
import '../../../../models/studio_state.dart';
import '../../../../models/video_file.dart';
import 'studio_export_tab.dart';
import 'studio_subtitle_tab.dart';
import 'studio_subtitle_style_tab.dart';
import 'studio_inpaint_tab.dart';
import 'studio_info_tab.dart';

/// Right properties panel managing the 5 main tabs:
/// 'props' (Thuộc tính), 'sub' (Phụ đề), 'style' (Kiểu dáng), 'inpaint' (Inpaint & Logo), and 'info' (Info).
class StudioPropertiesPanel extends StatefulWidget {
  final StudioSnapshot state;
  final StudioStateNotifier notifier;
  final VideoFile? video;
  final StudioToolMode toolMode;
  final double duration;
  final double currentTime;
  final TextEditingController exportFilenameController;
  final String exportResolution;
  final String exportFps;
  final String exportRatio;
  final String exportBitrate;
  final ValueChanged<String> onResolutionChanged;
  final ValueChanged<String> onFpsChanged;
  final ValueChanged<String> onRatioChanged;
  final ValueChanged<String> onBitrateChanged;
  final VoidCallback onResetDefaultFilename;
  final void Function(double speed) onSpeedChanged;
  final void Function(double sec) onSeek;
  final VoidCallback? onReloadPipeline;

  const StudioPropertiesPanel({
    super.key,
    required this.state,
    required this.notifier,
    required this.video,
    required this.toolMode,
    required this.duration,
    required this.currentTime,
    required this.exportFilenameController,
    required this.exportResolution,
    required this.exportFps,
    required this.exportRatio,
    required this.exportBitrate,
    required this.onResolutionChanged,
    required this.onFpsChanged,
    required this.onRatioChanged,
    required this.onBitrateChanged,
    required this.onResetDefaultFilename,
    required this.onSpeedChanged,
    required this.onSeek,
    this.onReloadPipeline,
  });

  @override
  State<StudioPropertiesPanel> createState() => _StudioPropertiesPanelState();
}

class _StudioPropertiesPanelState extends State<StudioPropertiesPanel> {
  String _activeTab = 'props';

  @override
  void didUpdateWidget(StudioPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.selectedClipId != null &&
        widget.state.selectedClipId != oldWidget.state.selectedClipId) {
      if (_activeTab != 'props') {
        setState(() => _activeTab = 'props');
      }
    }
  }

  Widget _buildPropsTab(String tabKey, String label, AppColorTokens c) {
    final isSelected = _activeTab == tabKey;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = tabKey),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? c.primary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(color: c.surface),
      child: Column(
        children: [
          // 5 Tab Selector Header
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildPropsTab('props', 'Thuộc tính', c),
                _buildPropsTab('sub', 'Phụ đề', c),
                _buildPropsTab('style', 'Kiểu dáng', c),
                _buildPropsTab('inpaint', 'Xóa Sub Cũ', c),
                _buildPropsTab('info', 'Info', c),
              ],
            ),
          ),

          // Tab Content Scrollable Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (_activeTab == 'props')
                  StudioExportTab(
                    state: widget.state,
                    notifier: widget.notifier,
                    video: widget.video,
                    toolMode: widget.toolMode,
                    exportFilenameController: widget.exportFilenameController,
                    exportResolution: widget.exportResolution,
                    exportFps: widget.exportFps,
                    exportRatio: widget.exportRatio,
                    exportBitrate: widget.exportBitrate,
                    onResolutionChanged: widget.onResolutionChanged,
                    onFpsChanged: widget.onFpsChanged,
                    onRatioChanged: widget.onRatioChanged,
                    onBitrateChanged: widget.onBitrateChanged,
                    onResetDefaultFilename: widget.onResetDefaultFilename,
                    onSpeedChanged: widget.onSpeedChanged,
                  )
                else if (_activeTab == 'sub')
                  StudioSubtitleTab(
                    state: widget.state,
                    notifier: widget.notifier,
                    video: widget.video,
                    currentTime: widget.currentTime,
                    onSeek: widget.onSeek,
                    onReloadPipeline: widget.onReloadPipeline,
                  )
                else if (_activeTab == 'style')
                  StudioSubtitleStyleTab(
                    state: widget.state,
                    notifier: widget.notifier,
                  )
                else if (_activeTab == 'inpaint')
                  StudioInpaintTab(
                    state: widget.state,
                    notifier: widget.notifier,
                  )
                else if (_activeTab == 'info')
                  StudioInfoTab(
                    state: widget.state,
                    video: widget.video,
                    duration: widget.duration,
                    currentTime: widget.currentTime,
                    exportResolution: widget.exportResolution,
                    exportRatio: widget.exportRatio,
                    exportFps: widget.exportFps,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
