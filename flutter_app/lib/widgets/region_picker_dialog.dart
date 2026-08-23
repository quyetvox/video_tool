import 'package:flutter/material.dart';

class RegionPickerDialog extends StatefulWidget {
  final String title;
  final List<double> initialRegion;

  const RegionPickerDialog({
    super.key,
    required this.title,
    required this.initialRegion,
  });

  static Future<List<double>?> show(
    BuildContext context, {
    required String title,
    List<double>? initialRegion,
  }) {
    return showDialog<List<double>>(
      context: context,
      builder: (context) => RegionPickerDialog(
        title: title,
        initialRegion: (initialRegion != null && initialRegion.length == 4)
            ? initialRegion
            : [0.75, 0.05, 0.95, 0.95],
      ),
    );
  }

  @override
  State<RegionPickerDialog> createState() => _RegionPickerDialogState();
}

class _RegionPickerDialogState extends State<RegionPickerDialog> {
  late double _top;
  late double _left;
  late double _bottom;
  late double _right;

  @override
  void initState() {
    super.initState();
    _top = widget.initialRegion[0].clamp(0.0, 1.0);
    _left = widget.initialRegion[1].clamp(0.0, 1.0);
    _bottom = widget.initialRegion[2].clamp(0.0, 1.0);
    _right = widget.initialRegion[3].clamp(0.0, 1.0);

    if (_bottom <= _top) _bottom = (_top + 0.1).clamp(0.0, 1.0);
    if (_right <= _left) _right = (_left + 0.1).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.crop, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Visual Frame Box (9:16 representation)
            Center(
              child: Container(
                width: 180,
                height: 320,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade700, width: 2),
                ),
                child: Stack(
                  children: [
                    // Grid guides
                    Positioned.fill(
                      child: Column(
                        children: List.generate(
                          3,
                          (i) => Expanded(
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.white10, width: 1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Selected Region Box
                    Positioned(
                      top: _top * 320,
                      left: _left * 180,
                      width: ((_right - _left) * 180).clamp(10.0, 180.0),
                      height: ((_bottom - _top) * 320).clamp(10.0, 320.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.3),
                          border: Border.all(color: Colors.cyanAccent, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Text(
                            'Vùng chọn',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sliders for Top, Left, Bottom, Right
            _buildSlider('Top (Lề Trên):', _top, (val) {
              setState(() {
                _top = val;
                if (_bottom <= _top) _bottom = (_top + 0.05).clamp(0.0, 1.0);
              });
            }),
            _buildSlider('Bottom (Lề Dưới):', _bottom, (val) {
              setState(() {
                _bottom = val;
                if (_top >= _bottom) _top = (_bottom - 0.05).clamp(0.0, 1.0);
              });
            }),
            _buildSlider('Left (Lề Trái):', _left, (val) {
              setState(() {
                _left = val;
                if (_right <= _left) _right = (_left + 0.05).clamp(0.0, 1.0);
              });
            }),
            _buildSlider('Right (Lề Phải):', _right, (val) {
              setState(() {
                _right = val;
                if (_left >= _right) _left = (_right - 0.05).clamp(0.0, 1.0);
              });
            }),

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Text(
                  'Giá trị: [${_top.toStringAsFixed(2)}, ${_left.toStringAsFixed(2)}, ${_bottom.toStringAsFixed(2)}, ${_right.toStringAsFixed(2)}]',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final res = [
                      double.parse(_top.toStringAsFixed(2)),
                      double.parse(_left.toStringAsFixed(2)),
                      double.parse(_bottom.toStringAsFixed(2)),
                      double.parse(_right.toStringAsFixed(2)),
                    ];
                    Navigator.of(context).pop(res);
                  },
                  child: const Text('Áp dụng'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}
