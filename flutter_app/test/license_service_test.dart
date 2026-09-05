import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sub_video_desktop/core/license_service.dart';
import 'package:sub_video_desktop/models/license_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('LicenseInfo Model Tests', () {
    test('Unlicensed status behaves correctly', () {
      final unlicensed = LicenseInfo.unlicensed();
      expect(unlicensed.isValid, isFalse);
      expect(unlicensed.status, equals(LicenseStatus.unlicensed));
      expect(unlicensed.daysRemaining, equals(0));
      expect(unlicensed.displayPlanName, equals('Chưa Kích Hoạt'));
    });

    test('Valid Trial 7-Days license calculation', () {
      final expires = DateTime.now().add(const Duration(days: 6, hours: 23));
      final trial = LicenseInfo(
        licenseKey: 'SUBVID-ABCD-1234-EFGH',
        planType: 'trial_7days',
        status: LicenseStatus.trial,
        expiresAt: expires,
      );

      expect(trial.isValid, isTrue);
      expect(trial.isTrial, isTrue);
      expect(trial.daysRemaining, inInclusiveRange(6, 7));
      expect(trial.displayPlanName, equals('Bản Quyền Dùng Thử 7 Ngày'));
      expect(trial.maskedKey, equals('SUBVID-****-****-EFGH'));
    });

    test('Expired license returns isValid = false', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final expired = LicenseInfo(
        licenseKey: 'SUBVID-1111-2222-3333',
        planType: 'creator',
        status: LicenseStatus.expired,
        expiresAt: past,
      );

      expect(expired.isValid, isFalse);
      expect(expired.daysRemaining, equals(0));
    });

    test('Serialization to/from JSON roundtrip preserves data', () {
      final now = DateTime.now();
      final original = LicenseInfo(
        licenseKey: 'SUBVID-9999-8888-7777',
        planType: 'pro',
        status: LicenseStatus.active,
        expiresAt: now.add(const Duration(days: 365)),
        activatedAt: now,
        lastOnlineCheck: now,
        machineId: 'fake_sha256_hwid_123456',
        machineName: 'MacBook Pro M1',
        userEmail: 'creator@example.com',
        maxDevices: 2,
      );

      final json = original.toJson();
      final restored = LicenseInfo.fromJson(json);

      expect(restored.licenseKey, equals(original.licenseKey));
      expect(restored.planType, equals(original.planType));
      expect(restored.status, equals(original.status));
      expect(restored.machineId, equals(original.machineId));
      expect(restored.machineName, equals(original.machineName));
      expect(restored.userEmail, equals(original.userEmail));
      expect(restored.maxDevices, equals(2));
      expect(restored.isValid, isTrue);
    });

    test('Feature Gating Matrix operates correctly across plan tiers', () {
      final now = DateTime.now().add(const Duration(days: 30));

      // 1. Gói Creator (69k) -> Mở GCS, Khóa Resume, Video Dài, Tải Tuần Tự
      final creator = LicenseInfo(
        licenseKey: 'SUBVID-CREA-1111-2222',
        planType: 'creator',
        status: LicenseStatus.active,
        expiresAt: now,
      );
      expect(creator.canUseGcs, isTrue, reason: 'Creator phải được mở GCS Cloud');
      expect(creator.canUseResume, isFalse, reason: 'Creator phải bị khóa Resume');
      expect(creator.canUseLongVideoChunking, isFalse, reason: 'Creator phải bị khóa phân đoạn video dài');
      expect(creator.canUseSequentialBatch, isFalse, reason: 'Creator phải bị khóa tải tuần tự hàng loạt');

      // 2. Gói Pro Studio (299k) -> Mở toàn bộ tính năng
      final pro = LicenseInfo(
        licenseKey: 'SUBVID-PROS-3333-4444',
        planType: 'pro',
        status: LicenseStatus.active,
        expiresAt: now,
      );
      expect(pro.canUseGcs, isTrue);
      expect(pro.canUseResume, isTrue);
      expect(pro.canUseLongVideoChunking, isTrue);
      expect(pro.canUseSequentialBatch, isTrue);

      // 3. Gói Dùng Thử 7 Ngày -> Mở 100% toàn bộ tính năng cao cấp
      final trial = LicenseInfo(
        licenseKey: 'SUBVID-TRIA-5555-6666',
        planType: 'trial_7days',
        status: LicenseStatus.trial,
        expiresAt: now,
      );
      expect(trial.canUseGcs, isTrue);
      expect(trial.canUseResume, isTrue);
      expect(trial.canUseLongVideoChunking, isTrue);
      expect(trial.canUseSequentialBatch, isTrue);

      // 4. Khi chưa kích hoạt hoặc hết hạn -> Toàn bộ là false
      final expired = creator.copyWith(status: LicenseStatus.expired);
      expect(expired.canUseGcs, isFalse);
      expect(expired.canUseResume, isFalse);
      expect(expired.canUseLongVideoChunking, isFalse);
      expect(expired.canUseSequentialBatch, isFalse);
    });

    test('Enterprise Studio tier is safely mapped and hidden from display', () {
      final studio = LicenseInfo(
        licenseKey: 'SUBVID-STUD-7777-8888',
        planType: 'studio',
        status: LicenseStatus.active,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );
      expect(studio.displayPlanName, equals('Gói Pro Studio'));
    });
  });

  group('LicenseService Machine HWID Tests', () {
    test('Generates valid 64-character SHA-256 fingerprint', () async {
      final hwid = await LicenseService.getMachineId();
      expect(hwid, isNotEmpty);
      expect(hwid.length, equals(64)); // SHA-256 hex string has 64 chars
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hwid), isTrue);

      // Cùng 1 máy gọi lại phải giữ nguyên fingerprint
      final hwid2 = await LicenseService.getMachineId();
      expect(hwid2, equals(hwid));
    });

    test('Identifies valid OS Platform and friendly machine name', () {
      final os = LicenseService.getOsPlatform();
      expect(os, isIn(['MACOS', 'WINDOWS', 'OTHER']));

      final name = LicenseService.getMachineName();
      expect(name, isNotEmpty);
    });
  });

  group('Auth & Email Verification Tests', () {
    test('EmailNotVerifiedException preserves email and format message correctly', () {
      final ex = EmailNotVerifiedException('user@test.com', 'Tài khoản chưa được kích hoạt email.');
      expect(ex.email, equals('user@test.com'));
      expect(ex.toString(), contains('chưa được kích hoạt'));
    });

    test('AuthToken storage operates correctly with memory/prefs', () async {
      await LicenseService.saveAuthToken('sample_jwt_token_123');
      final token = await LicenseService.getAuthToken();
      expect(token, equals('sample_jwt_token_123'));

      await LicenseService.clearAuthToken();
      final clearedToken = await LicenseService.getAuthToken();
      expect(clearedToken, isNull);
    });
  });
}
