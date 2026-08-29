import 'dart:convert';
import 'dart:io';

class GcpTestResult {
  final bool success;
  final String message;
  final String? projectId;
  final String? clientEmail;
  final String? keyId;

  const GcpTestResult({
    required this.success,
    required this.message,
    this.projectId,
    this.clientEmail,
    this.keyId,
  });
}

class GcpConnectionTester {
  /// Validates the GCP Service Account Key JSON file and parses project credentials
  static Future<GcpTestResult> testKeyFile(String keyFilePath) async {
    final cleanPath = keyFilePath.trim();
    if (cleanPath.isEmpty) {
      return const GcpTestResult(
        success: false,
        message: 'Vui lòng chọn đường dẫn đến file gcp-key.json.',
      );
    }

    final file = File(cleanPath);
    if (!file.existsSync()) {
      return GcpTestResult(
        success: false,
        message: 'Không tìm thấy file tại đường dẫn: $cleanPath',
      );
    }

    try {
      final content = file.readAsStringSync().trim();
      if (content.isEmpty) {
        return const GcpTestResult(
          success: false,
          message: 'File key JSON trống, không có nội dung.',
        );
      }

      final data = jsonDecode(content);
      if (data is! Map<String, dynamic>) {
        return const GcpTestResult(
          success: false,
          message: 'Định dạng file không phải là JSON Object hợp lệ.',
        );
      }

      final type = data['type']?.toString();
      final projectId = data['project_id']?.toString();
      final clientEmail = data['client_email']?.toString();
      final privateKey = data['private_key']?.toString();
      final keyId = data['private_key_id']?.toString();

      if (type != 'service_account') {
        return GcpTestResult(
          success: false,
          message: 'Trường "type" trong file không phải "service_account" (phát hiện: "$type").',
          projectId: projectId,
        );
      }

      if (projectId == null || projectId.isEmpty) {
        return const GcpTestResult(
          success: false,
          message: 'Thiếu trường "project_id" trong file Service Account JSON.',
        );
      }

      if (clientEmail == null || clientEmail.isEmpty) {
        return const GcpTestResult(
          success: false,
          message: 'Thiếu trường "client_email" trong file Service Account JSON.',
        );
      }

      if (privateKey == null || !privateKey.contains('BEGIN PRIVATE KEY')) {
        return const GcpTestResult(
          success: false,
          message: 'Không tìm thấy hoặc private_key không đúng định dạng RSA/PKCS8.',
        );
      }

      return GcpTestResult(
        success: true,
        message: 'Key hợp lệ! Đã sẵn sàng kết nối Google Cloud Storage.',
        projectId: projectId,
        clientEmail: clientEmail,
        keyId: keyId != null && keyId.length > 8 ? '${keyId.substring(0, 8)}...' : keyId,
      );
    } catch (e) {
      return GcpTestResult(
        success: false,
        message: 'Lỗi khi đọc file JSON: $e',
      );
    }
  }
}
