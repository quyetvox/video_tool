import 'package:flutter/material.dart';
import '../utils/color_parser_utils.dart';

class InteractiveColorPickerDialog extends StatefulWidget {
  final String initialColor;
  final String title;
  final bool preferAssFormat;

  const InteractiveColorPickerDialog({
    super.key,
    required this.initialColor,
    this.title = 'Bảng Chọn Màu Tương Tác',
    this.preferAssFormat = true,
  });

  static Future<String?> show(
    BuildContext context, {
    required String initialColor,
    String title = 'Bảng Chọn Màu Tương Tác',
    bool preferAssFormat = true,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => InteractiveColorPickerDialog(
        initialColor: initialColor,
        title: title,
        preferAssFormat: preferAssFormat,
      ),
    );
  }

  @override
  State<InteractiveColorPickerDialog> createState() => _InteractiveColorPickerDialogState();
}

class _InteractiveColorPickerDialogState extends State<InteractiveColorPickerDialog> {
  late HSVColor _hsv;
  late double _alpha;
  late bool _useAssFormat;

  // Presets
  final List<Color> _swatches = const [
    Colors.white,
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FFFF), // Cyan
    Color(0xFFFF0000), // Red
    Color(0xFF10B981), // Green
    Color(0xFF3B82F6), // Blue
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF97316), // Orange
    Color(0xFFEC4899), // Pink
    Color(0xFF94A3B8), // Slate gray
    Color(0xFF1E293B), // Dark slate
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    final parsed = ColorParserUtils.parse(widget.initialColor);
    _hsv = HSVColor.fromColor(parsed);
    _alpha = parsed.opacity;
    _useAssFormat = widget.initialColor.startsWith('&H') ||
        widget.initialColor.startsWith('&h') ||
        widget.preferAssFormat;
  }

  Color get _currentColor => _hsv.toColor().withOpacity(_alpha);

  String get _formattedColorCode {
    if (_useAssFormat) {
      return ColorParserUtils.toAssString(_currentColor, includeAlpha: _alpha < 1.0);
    } else {
      return ColorParserUtils.toHexString(_currentColor, includeAlpha: _alpha < 1.0);
    }
  }

  void _updateFromPosition(Offset localPos, Size size) {
    final saturation = (localPos.dx / size.width).clamp(0.0, 1.0);
    final value = (1.0 - (localPos.dy / size.height)).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withSaturation(saturation).withValue(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialParsed = ColorParserUtils.parse(widget.initialColor);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TITLE BAR ──
            Row(
              children: [
                const Icon(Icons.palette, size: 18, color: Color(0xFF06B6D4)),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 2D SATURATION & VALUE GRADIENT BOX ──
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final size = Size(constraints.maxWidth, constraints.maxHeight);
                    final thumbX = _hsv.saturation * size.width;
                    final thumbY = (1.0 - _hsv.value) * size.height;

                    return GestureDetector(
                      onPanDown: (d) => _updateFromPosition(d.localPosition, size),
                      onPanUpdate: (d) => _updateFromPosition(d.localPosition, size),
                      child: Stack(
                        children: [
                          // Base Hue Color
                          Container(
                            color: HSVColor.fromAHSV(1.0, _hsv.hue, 1.0, 1.0).toColor(),
                          ),
                          // White horizontal gradient (Saturation)
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Colors.white, Colors.transparent],
                              ),
                            ),
                          ),
                          // Black vertical gradient (Brightness / Value)
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black],
                              ),
                            ),
                          ),
                          // Draggable Circle Pointer
                          Positioned(
                            left: thumbX - 8,
                            top: thumbY - 8,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentColor,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── RAINBOW HUE SLIDER ──
            const Text(
              'Tông Màu Quang Phổ (Hue 0° - 360°):',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
              ),
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 14,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _hsv.hue,
                  min: 0.0,
                  max: 360.0,
                  onChanged: (val) {
                    setState(() {
                      _hsv = _hsv.withHue(val);
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── OPACITY / ALPHA SLIDER ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Độ Đậm / Trong Suốt (Opacity):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${(_alpha * 100).toInt()}%',
                  style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                activeTrackColor: const Color(0xFF06B6D4),
                inactiveTrackColor: const Color(0xFF1E293B),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: _alpha,
                min: 0.0,
                max: 1.0,
                onChanged: (val) => setState(() => _alpha = val),
              ),
            ),

            const SizedBox(height: 10),

            // ── QUICK PRESETS SWATCHES ──
            const Text(
              'Màu Mẫu Nhanh:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _swatches.map((c) {
                final isCurrent = (c.value == _currentColor.value);
                return InkWell(
                  onTap: () {
                    setState(() {
                      _hsv = HSVColor.fromColor(c);
                      _alpha = c.opacity;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isCurrent ? const Color(0xFF06B6D4) : const Color(0xFF475569),
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1E293B), height: 1),
            const SizedBox(height: 10),

            // ── PREVIEW & CODE FORMAT DISPLAY ──
            Row(
              children: [
                // Old vs New Preview
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gốc ➔ Mới:', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: initialParsed,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _currentColor,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(width: 10),

                // Formatted Output Code with Format Switcher
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mã Màu Xuất Ra:', style: TextStyle(color: Color(0xFF64748B), fontSize: 9.5)),
                          InkWell(
                            onTap: () => setState(() => _useAssFormat = !_useAssFormat),
                            child: Text(
                              _useAssFormat ? 'Đổi sang #HEX' : 'Đổi sang ASS &H',
                              style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1120),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Text(
                          _formattedColorCode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── ACTION BUTTONS ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF06B6D4),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Chọn Màu Này', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.of(context).pop(_formattedColorCode);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
