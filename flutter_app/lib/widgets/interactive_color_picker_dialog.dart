import 'package:flutter/material.dart';
import '../core/app_colors.dart';
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

  void _updateSaturationValue(Offset localPos, double width, double height) {
    final saturation = (localPos.dx / width).clamp(0.0, 1.0);
    final value = (1.0 - (localPos.dy / height)).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(saturation).withValue(value));
  }

  void _updateHue(Offset localPos, double width) {
    final hue = ((localPos.dx / width) * 360.0).clamp(0.0, 360.0);
    setState(() => _hsv = _hsv.withHue(hue));
  }

  @override
  Widget build(BuildContext context) {
    final initialParsed = ColorParserUtils.parse(widget.initialColor);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette, size: 18, color: AppColors.primary),
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
                  icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onPanDown: (d) => _updateSaturationValue(d.localPosition, 348, 160),
                onPanUpdate: (d) => _updateSaturationValue(d.localPosition, 348, 160),
                child: SizedBox(
                  width: 348,
                  height: 160,
                  child: CustomPaint(
                    painter: _SaturationValuePainter(hue: _hsv.hue),
                    child: Stack(
                      children: [
                        Positioned(
                          left: (_hsv.saturation * 348).clamp(0.0, 348.0) - 7,
                          top: ((1.0 - _hsv.value) * 160).clamp(0.0, 160.0) - 7,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentColor.withOpacity(1.0),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4, spreadRadius: 1),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dải Sắc Độ (Hue):',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GestureDetector(
                onPanDown: (d) => _updateHue(d.localPosition, 348),
                onPanUpdate: (d) => _updateHue(d.localPosition, 348),
                child: SizedBox(
                  width: 348,
                  height: 16,
                  child: CustomPaint(
                    painter: _HueTrackPainter(),
                    child: Stack(
                      children: [
                        Positioned(
                          left: ((_hsv.hue / 360.0) * 348).clamp(0.0, 348.0) - 5,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: Colors.black54, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Độ Đậm / Trong Suốt (Opacity):',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${(_alpha * 100).toInt()}%',
                  style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: AppColors.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
            const Text(
              'Màu Mẫu Nhanh:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
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
                        color: isCurrent ? AppColors.primary : AppColors.border,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gốc ➔ Mới:', style: TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: initialParsed,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _currentColor,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                            border: Border.all(color: AppColors.border),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mã Màu Xuất Ra:', style: TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
                          InkWell(
                            onTap: () => setState(() => _useAssFormat = !_useAssFormat),
                            child: Text(
                              _useAssFormat ? 'Đổi sang #HEX' : 'Đổi sang ASS &H',
                              style: const TextStyle(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Text(
                          _formattedColorCode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryText,
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

class _SaturationValuePainter extends CustomPainter {
  final double hue;
  _SaturationValuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      colors: [Colors.white, HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor()],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    const vGradient = LinearGradient(
      colors: [Colors.transparent, Colors.black],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    canvas.drawRect(rect, Paint()..shader = vGradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) => oldDelegate.hue != hue;
}

class _HueTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const gradient = LinearGradient(
      colors: [
        Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
        Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _HueTrackPainter oldDelegate) => false;
}
