import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../utils/color_parser_utils.dart';
import 'interactive_color_picker_dialog.dart';

class SmartColorPickerRow extends StatefulWidget {
  final String label;
  final String currentColor;
  final List<ColorPreset> presets;
  final ValueChanged<String> onChanged;
  final bool preferAssFormat;

  const SmartColorPickerRow({
    super.key,
    required this.label,
    required this.currentColor,
    required this.presets,
    required this.onChanged,
    this.preferAssFormat = true,
  });

  @override
  State<SmartColorPickerRow> createState() => _SmartColorPickerRowState();
}

class _SmartColorPickerRowState extends State<SmartColorPickerRow> {
  late TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.currentColor);
  }

  @override
  void didUpdateWidget(covariant SmartColorPickerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentColor != widget.currentColor && _textCtrl.text != widget.currentColor) {
      _textCtrl.text = widget.currentColor;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _openInteractiveColorPicker() async {
    final result = await InteractiveColorPickerDialog.show(
      context,
      initialColor: widget.currentColor,
      title: 'Bảng Chọn Màu: ${widget.label.replaceAll(":", "")}',
      preferAssFormat: widget.preferAssFormat,
    );
    if (result != null && result.isNotEmpty) {
      _textCtrl.text = result;
      widget.onChanged(result);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsedColor = ColorParserUtils.parse(widget.currentColor);
    final isNone = widget.currentColor.trim().toLowerCase() == 'none' ||
        widget.currentColor.trim().toLowerCase() == 'transparent' ||
        widget.currentColor.trim().isEmpty;

    // Check if current color matches any preset
    final matchedPreset = widget.presets.cast<ColorPreset?>().firstWhere(
          (p) => p != null && p.code.toLowerCase() == widget.currentColor.trim().toLowerCase(),
          orElse: () => null,
        );

    final dropdownValue = matchedPreset != null ? matchedPreset.code : 'custom';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              // 1. Preset Dropdown (34px)
              Expanded(
                flex: 5,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdownValue,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceLight,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
                      items: [
                        ...widget.presets.map(
                          (p) => DropdownMenuItem(
                            value: p.code,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: p.previewColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.border, width: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Row(
                            children: [
                              Icon(Icons.palette_outlined, size: 13, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text('🎨 Bảng Màu 2D...', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == 'custom') {
                          _openInteractiveColorPicker();
                        } else if (val != null) {
                          _textCtrl.text = val;
                          widget.onChanged(val);
                        }
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 2. Code Text Field (34px, Strict Vertical Centering)
              Expanded(
                flex: 4,
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Colors.white,
                      height: 1.0,
                    ),
                    strutStyle: const StrutStyle(
                      fontSize: 11.5,
                      height: 1.0,
                      forceStrutHeight: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Mã màu...',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.0),
                    ),
                    onChanged: (val) {
                      widget.onChanged(val);
                      setState(() {});
                    },
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 3. Interactive Color Preview Square (34px)
              Tooltip(
                message: 'Nhấp để mở Bảng màu 2D kéo thả...',
                child: InkWell(
                  onTap: _openInteractiveColorPicker,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isNone ? AppColors.surfaceDark : parsedColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border, width: 0.8),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: isNone
                        ? const Icon(Icons.block, size: 14, color: AppColors.textMuted)
                        : const Icon(Icons.colorize, size: 13, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
