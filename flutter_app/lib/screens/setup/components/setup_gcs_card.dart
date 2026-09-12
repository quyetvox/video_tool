import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/gcp_connection_tester.dart';
import '../../../widgets/app_kit.dart';

class SetupGcsCard extends StatelessWidget {
  final TextEditingController gcsKeyPathController;
  final TextEditingController bucketController;
  final TextEditingController prefixController;
  final List<String> availableBuckets;
  final List<String> availablePrefixes;
  final bool canListBuckets;
  final bool isTestingGcp;
  final bool isDiscoveringGcs;
  final GcpTestResult? gcpTestResult;
  final VoidCallback onPickGcsKeyFile;
  final void Function({bool showFeedback, bool showDialogResult}) onDiscoverGcs;
  final ValueChanged<String> onBucketSelected;
  final ValueChanged<String> onPrefixSelected;
  final VoidCallback onReloadSettings;
  final VoidCallback onSaveSettings;
  final bool isSaving;

  const SetupGcsCard({
    super.key,
    required this.gcsKeyPathController,
    required this.bucketController,
    required this.prefixController,
    required this.availableBuckets,
    required this.availablePrefixes,
    required this.canListBuckets,
    required this.isTestingGcp,
    required this.isDiscoveringGcs,
    required this.gcpTestResult,
    required this.onPickGcsKeyFile,
    required this.onDiscoverGcs,
    required this.onBucketSelected,
    required this.onPrefixSelected,
    required this.onReloadSettings,
    required this.onSaveSettings,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLoadingGcs = isTestingGcp || isDiscoveringGcs;

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
            // 3. Google Cloud Storage Service Account Key JSON
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, size: 15, color: c.primary),
                const SizedBox(width: 6),
                Text(
                  '3. Cấu hình Google Cloud Storage (gcp-key.json / gcs-key.json):',
                  style: TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Khi trỏ đến file Service Account JSON, hệ thống sẽ tự động quét danh sách Bucket và Base Prefix để bạn chọn nhanh.',
              style: TextStyle(fontSize: 10.5, color: c.textMuted),
            ),
            const SizedBox(height: 8),

            // Key file picker row
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: gcsKeyPathController,
                    isMonospace: true,
                    hint: 'resources/gcs-key.json',
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        onDiscoverGcs(showFeedback: true);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                AppButton.outlined(
                  label: 'Chọn file JSON',
                  icon: Icons.folder_open,
                  height: 34,
                  onPressed: onPickGcsKeyFile,
                ),
                const SizedBox(width: 8),
                AppButton.secondary(
                  label: isLoadingGcs ? 'Đang quét...' : 'Quét & Kiểm Tra GCS',
                  icon: Icons.network_check_rounded,
                  height: 34,
                  isLoading: isLoadingGcs,
                  onPressed: isLoadingGcs
                      ? null
                      : () => onDiscoverGcs(showFeedback: true, showDialogResult: true),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Row: Bucket Name & Base Prefix
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3.1 Bucket Name (Editable Combobox)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Tên GCS Bucket:',
                            style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          if (availableBuckets.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: c.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${availableBuckets.length} buckets',
                                style: TextStyle(fontSize: 9.5, color: c.primary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ] else if (!canListBuckets) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.statusProcessingBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Nhập tay bucket',
                                style: TextStyle(fontSize: 9.5, color: AppColors.statusProcessing, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: bucketController,
                              hint: 'ví dụ: my-video-bucket',
                              isMonospace: true,
                              onSubmitted: (val) {
                                if (val.trim().isNotEmpty && gcsKeyPathController.text.trim().isNotEmpty) {
                                  onDiscoverGcs(showFeedback: true);
                                }
                              },
                            ),
                          ),
                          if (availableBuckets.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              tooltip: 'Chọn từ danh sách Bucket trên GCP',
                              icon: Icon(Icons.arrow_drop_down_circle_outlined, size: 20, color: c.primary),
                              onSelected: onBucketSelected,
                              itemBuilder: (ctx) => availableBuckets
                                  .map((b) => PopupMenuItem(
                                        value: b,
                                        child: Text(b, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // 3.2 Base Prefix (Editable Combobox)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Prefix Thư Mục Gốc (Base Prefix):',
                            style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500),
                          ),
                          if (availablePrefixes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: c.statusCompleted.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${availablePrefixes.length} folders',
                                style: TextStyle(fontSize: 9.5, color: c.statusCompleted, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: prefixController,
                              hint: 'ví dụ: videos/ (để trống nếu ở thư mục gốc)',
                              isMonospace: true,
                            ),
                          ),
                          if (availablePrefixes.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              tooltip: 'Chọn từ các thư mục có sẵn trong Bucket',
                              icon: Icon(Icons.folder_shared_outlined, size: 20, color: c.statusCompleted),
                              onSelected: onPrefixSelected,
                              itemBuilder: (ctx) => availablePrefixes
                                  .map((p) => PopupMenuItem(
                                        value: p,
                                        child: Text(p, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (gcpTestResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: gcpTestResult!.success ? c.statusCompletedBg : c.statusFailedBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      gcpTestResult!.success ? Icons.check_circle : Icons.error_outline,
                      color: gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gcpTestResult!.success
                            ? '✅ Hợp lệ! Project: ${gcpTestResult!.projectId} | ${gcpTestResult!.clientEmail}'
                            : '❌ ${gcpTestResult!.message}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: gcpTestResult!.success ? c.statusCompleted : c.statusFailed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                AppButton.outlined(
                  label: 'Quét lại từ đĩa',
                  icon: Icons.refresh,
                  height: 34,
                  onPressed: onReloadSettings,
                ),
                const Spacer(),
                AppButton.primary(
                  label: isSaving ? 'Đang lưu...' : 'Lưu Cấu Hình & Áp Dụng Toàn Hệ Thống',
                  icon: isSaving ? Icons.sync : Icons.save,
                  height: 34,
                  isLoading: isSaving,
                  onPressed: isSaving ? null : onSaveSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
