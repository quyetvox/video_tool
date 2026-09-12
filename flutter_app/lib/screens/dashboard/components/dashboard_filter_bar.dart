import 'package:flutter/material.dart';
import '../../../widgets/app_kit.dart';

class DashboardFilterBar extends StatelessWidget {
  final String selectedCategory;
  final int allCount;
  final int srcCount;
  final int cutCount;
  final int mergeCount;
  final int outputCount;
  final String searchQuery;
  final bool isGridView;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleGridView;

  const DashboardFilterBar({
    super.key,
    required this.selectedCategory,
    required this.allCount,
    required this.srcCount,
    required this.cutCount,
    required this.mergeCount,
    required this.outputCount,
    required this.searchQuery,
    required this.isGridView,
    required this.onCategoryChanged,
    required this.onSearchChanged,
    required this.onToggleGridView,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          _buildChip('Tất cả ($allCount)', 'all'),
          const SizedBox(width: 6),
          _buildChip('Gốc src ($srcCount)', 'src'),
          const SizedBox(width: 6),
          _buildChip('Cắt cut ($cutCount)', 'cut'),
          const SizedBox(width: 6),
          _buildChip('Ghép merge ($mergeCount)', 'merge'),
          const SizedBox(width: 6),
          _buildChip('Xuất out ($outputCount)', 'output'),

          const Spacer(),

          // Search box using AppSearchField
          AppSearchField(
            width: 180,
            hint: 'Tìm video...',
            initialValue: searchQuery,
            onChanged: onSearchChanged,
          ),
          const SizedBox(width: 8),

          // View mode toggle
          IconButton(
            tooltip: isGridView ? 'Chuyển sang dạng Danh sách' : 'Chuyển sang dạng Lưới',
            icon: Icon(isGridView ? Icons.view_list : Icons.grid_view, size: 20),
            onPressed: onToggleGridView,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String category) {
    return AppFilterChip(
      label: label,
      isSelected: selectedCategory == category,
      onTap: () => onCategoryChanged(category),
    );
  }
}
