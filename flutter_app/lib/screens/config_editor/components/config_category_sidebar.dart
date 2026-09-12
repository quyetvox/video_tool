import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class ConfigCategoryItem {
  final String id;
  final String title;
  final IconData icon;

  const ConfigCategoryItem({required this.id, required this.title, required this.icon});
}

/// Left category navigation sidebar for ConfigEditorScreen.
class ConfigCategorySidebar extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  static const categories = [
    ConfigCategoryItem(id: 'all', title: 'Tất Cả Cấu Hình', icon: Icons.grid_view_rounded),
    ConfigCategoryItem(id: 'app', title: 'Thiết Bị & Ngôn Ngữ', icon: Icons.devices_outlined),
    ConfigCategoryItem(id: 'ai', title: 'Dịch Thuật AI', icon: Icons.translate_rounded),
    ConfigCategoryItem(id: 'inpaint', title: 'Xóa Sub Cũ & Hộp Nền', icon: Icons.brush_outlined),
    ConfigCategoryItem(id: 'subtitles', title: 'Phụ Đề & Font Chữ', icon: Icons.subtitles_outlined),
    ConfigCategoryItem(id: 'voice', title: 'Giọng Đọc TTS & Âm Lượng', icon: Icons.record_voice_over_outlined),
    ConfigCategoryItem(id: 'watermark', title: 'Watermark & Logo', icon: Icons.branding_watermark_outlined),
    ConfigCategoryItem(id: 'hardware', title: 'Đa Luồng & Phần Cứng', icon: Icons.memory_outlined),
    ConfigCategoryItem(id: 'storage', title: 'Cloud Storage (GCS)', icon: Icons.cloud_outlined),
  ];

  const ConfigCategorySidebar({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              'DANH MỤC CẤU HÌNH',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 3),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final isSelected = selectedCategory == cat.id;

                return InkWell(
                  onTap: () => onCategorySelected(cat.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? c.surfaceLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? c.primary.withOpacity(0.4) : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          cat.icon,
                          size: 15,
                          color: isSelected ? c.primary : c.textSecondary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            cat.title,
                            style: TextStyle(
                              color: isSelected ? c.textPrimary : c.textSecondary,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: c.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
