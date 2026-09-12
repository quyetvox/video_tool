import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';

class SetupPathsCard extends StatelessWidget {
  final TextEditingController projectsDirController;
  final TextEditingController fontsDirController;
  final VoidCallback onPickProjectsDir;
  final VoidCallback onPickFontsDir;

  const SetupPathsCard({
    super.key,
    required this.projectsDirController,
    required this.fontsDirController,
    required this.onPickProjectsDir,
    required this.onPickFontsDir,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border, width: 0.8),
      ),
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_special_outlined, size: 17, color: c.primary),
                const SizedBox(width: 8),
                Text(
                  'Đường Dẫn Tài Nguyên & Thư Mục Dự Án',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Projects Directory
            AppInputGroup(
              label: '1. Thư mục Dự án Mặc định (projects_dir):',
              field: AppTextField(
                controller: projectsDirController,
                isMonospace: true,
                hint: '/path/to/Sub-Video/resources',
              ),
              button: AppButton.outlined(
                label: 'Chọn thư mục',
                icon: Icons.folder_open,
                height: 34,
                onPressed: onPickProjectsDir,
              ),
            ),
            const SizedBox(height: 16),

            // 2. Fonts Directory
            AppInputGroup(
              label: '2. Thư mục Chứa Font Chữ (.ttf, .otf):',
              field: AppTextField(
                controller: fontsDirController,
                isMonospace: true,
                hint: '/path/to/assets/fonts',
              ),
              button: AppButton.outlined(
                label: 'Chọn thư mục',
                icon: Icons.folder_open,
                height: 34,
                onPressed: onPickFontsDir,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
