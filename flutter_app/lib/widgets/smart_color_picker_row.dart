import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              // 1. Preset Dropdown
              Expanded(
                flex: 5,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: dropdownValue,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      icon: const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF64748B)),
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
                                    border: Border.all(color: const Color(0xFF475569), width: 0.5),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Row(
                            children: [
                              Icon(Icons.palette_outlined, size: 12, color: Color(0xFF06B6D4)),
                              SizedBox(width: 6),
                              Text('🎨 Bảng Màu 2D...', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w600)),
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

              // 2. Code Text Field (Editable, Strict Vertical Centering)
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _textCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white,
                      height: 1.0,
                    ),
                    strutStyle: const StrutStyle(
                      fontSize: 11,
                      height: 1.0,
                      forceStrutHeight: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF06B6D4)),
                      ),
                      hintText: 'Mã màu...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                    onChanged: (val) {
                      widget.onChanged(val);
                      setState(() {});
                    },
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 3. Interactive Color Preview Square (Click to open Color Picker Dialog)
              Tooltip(
                message: 'Nhấp để mở Bảng màu 2D kéo thả...',
                child: InkWell(
                  onTap: _openInteractiveColorPicker,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isNone ? const Color(0xFF1E293B) : parsedColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF06B6D4), width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: isNone
                        ? const Icon(Icons.block, size: 13, color: Color(0xFF64748B))
                        : const Icon(Icons.colorize, size: 12, color: Colors.white70),
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
