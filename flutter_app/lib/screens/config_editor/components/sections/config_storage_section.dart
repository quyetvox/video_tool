import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigStorageSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;

  const ConfigStorageSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '9. Lưu Trữ Đám Mây (Google Cloud Storage Sync)',
      icon: Icons.cloud_outlined,
      subtitle: 'Đồng bộ hai chiều và giải phóng dung lượng ổ cứng an toàn',
      children: [
        ConfigToggle(
          label: 'Kích hoạt đồng bộ Cloud Storage (storage.enabled)',
          value: cfg.storageEnabled,
          onChanged: (val) => onUpdate((c) => c.copyWith(storageEnabled: val)),
        ),
        const SizedBox(height: 10),
        ConfigRow2(
          w1: ConfigTextField(
            label: 'Đường dẫn Service Account Key JSON (key_file):',
            value: cfg.storageKeyFile,
            placeholder: 'gcp-key.json / gcs-key.json',
            onChanged: (val) => onUpdate((c) => c.copyWith(storageKeyFile: val)),
          ),
          w2: ConfigTextField(
            label: 'Tên Bucket GCS (bucket_name):',
            value: cfg.storageBucketName,
            placeholder: 'my-subvideo-storage',
            onChanged: (val) => onUpdate((c) => c.copyWith(storageBucketName: val)),
          ),
        ),
        const SizedBox(height: 12),
        ConfigTextField(
          label: 'Thư mục gốc tiền tố trên Cloud (base_prefix):',
          value: cfg.storageBasePrefix,
          placeholder: 'projects hoặc sub-video/',
          onChanged: (val) => onUpdate((c) => c.copyWith(storageBasePrefix: val)),
        ),
      ],
    );
  }
}
