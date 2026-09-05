import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../models/license_info.dart';
import 'app_constants.dart';

/// Service quản lý kích hoạt, kiểm tra và thu hồi bản quyền Sub-Video (Office & Google Style)
class LicenseService {
  static const String _prefLicenseKey = 'sub_video_license_info_v1';
  static const String _prefLastCheckKey = 'sub_video_last_online_check';
  static const int gracePeriodDays = 7;

  static String? _cachedMachineId;
  static String? _cachedMachineName;

  /// Lấy mã định danh phần cứng duy nhất (HWID Fingerprint)
  static Future<String> getMachineId() async {
    if (_cachedMachineId != null) return _cachedMachineId!;

    String? rawHwid;
    try {
      if (Platform.isMacOS) {
        final res = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
        final match = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch(res.stdout.toString());
        if (match != null && match.group(1) != null) {
          rawHwid = match.group(1);
        }
      } else if (Platform.isWindows) {
        final res = await Process.run('reg', [
          'query',
          r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ]);
        final match = RegExp(r'MachineGuid\s+REG_SZ\s+([a-zA-Z0-9\-]+)').firstMatch(res.stdout.toString());
        if (match != null && match.group(1) != null) {
          rawHwid = match.group(1);
        }
      }
    } catch (e) {
      debugPrint('[LicenseService] Không thể đọc native HWID: $e');
    }

    // Fallback an toàn nếu không đọc được registry/ioreg
    rawHwid ??= '${Platform.localHostname}_${Platform.operatingSystem}_${Platform.numberOfProcessors}';

    // Băm SHA-256 với secret salt
    final bytes = utf8.encode('sub_video_secure_hwid_v1_$rawHwid');
    _cachedMachineId = sha256.convert(bytes).toString();
    return _cachedMachineId!;
  }

  /// Lấy tên thân thiện của thiết bị hiện tại
  static String getMachineName() {
    if (_cachedMachineName != null) return _cachedMachineName!;
    String name = Platform.localHostname;
    if (Platform.isMacOS) {
      name = 'Mac ($name)';
    } else if (Platform.isWindows) {
      name = 'PC ($name)';
    }
    _cachedMachineName = name;
    return name;
  }

  /// Nền tảng hệ điều hành chuẩn Backend
  static String getOsPlatform() {
    if (Platform.isMacOS) return 'MACOS';
    if (Platform.isWindows) return 'WINDOWS';
    return 'OTHER';
  }

  /// Khởi tạo và đọc trạng thái bản quyền đã lưu
  static Future<LicenseInfo> loadSavedLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_prefLicenseKey);
      if (savedJson == null || savedJson.isEmpty) {
        return LicenseInfo.unlicensed();
      }

      final Map<String, dynamic> data = jsonDecode(savedJson);
      final info = LicenseInfo.fromJson(data);

      // Kiểm tra hạn sử dụng
      if (info.expiresAt != null && DateTime.now().isAfter(info.expiresAt!)) {
        return info.copyWith(status: LicenseStatus.expired);
      }

      // Kiểm tra Grace Period Offline
      final lastCheckStr = prefs.getString(_prefLastCheckKey);
      if (lastCheckStr != null) {
        final lastCheck = DateTime.tryParse(lastCheckStr);
        if (lastCheck != null) {
          final diffDays = DateTime.now().difference(lastCheck).inDays;
          if (diffDays > gracePeriodDays) {
            // Đã quá 7 ngày chưa heartbeat với server
            return info.copyWith(status: LicenseStatus.expired);
          }
        }
      }

      return info;
    } catch (e) {
      debugPrint('[LicenseService] Lỗi khi load cache license: $e');
      return LicenseInfo.unlicensed();
    }
  }

  /// Lưu trạng thái bản quyền vào SharedPreferences
  static Future<void> saveLicense(LicenseInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLicenseKey, jsonEncode(info.toJson()));
    if (info.lastOnlineCheck != null) {
      await prefs.setString(_prefLastCheckKey, info.lastOnlineCheck!.toIso8601String());
    }
  }

  /// Xóa bản quyền khỏi máy (khi thu hồi hoặc đăng xuất)
  static Future<void> clearLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLicenseKey);
    await prefs.remove(_prefLastCheckKey);
  }

  /// Kích hoạt bản quyền qua Product Key (Microsoft Office Style)
  static Future<LicenseInfo> activateWithKey(String key) async {
    final cleanKey = key.trim().toUpperCase();
    final machineId = await getMachineId();
    final machineName = getMachineName();
    final osPlatform = getOsPlatform();

    final uri = Uri.parse('${AppConstants.defaultApiBaseUrl}/license/activate');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'licenseKey': cleanKey,
            'machineId': machineId,
            'machineName': machineName,
            'osPlatform': osPlatform,
            'appVersion': AppConstants.appVersion,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final Map<String, dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 200) {
      final errorMsg = body['error'] ?? 'Kích hoạt không thành công';
      throw Exception(errorMsg);
    }

    final planType = body['planType']?.toString() ?? 'trial_7days';
    final expiresAt = DateTime.tryParse(body['expiresAt']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    final maxDevices = body['maxDevices'] as int? ?? 1;

    final info = LicenseInfo(
      licenseKey: cleanKey,
      planType: planType,
      status: planType == 'trial_7days' ? LicenseStatus.trial : LicenseStatus.active,
      expiresAt: expiresAt,
      activatedAt: DateTime.now(),
      lastOnlineCheck: DateTime.now(),
      machineId: machineId,
      machineName: machineName,
      maxDevices: maxDevices,
    );

    await saveLicense(info);
    return info;
  }

  /// Đăng nhập tài khoản Sub-Video và tự động kích hoạt key khả dụng
  static Future<LicenseInfo> loginAndActivate({
    required String email,
    required String password,
  }) async {
    // 1. Đăng nhập lấy JWT
    final loginUri = Uri.parse('${AppConstants.defaultApiBaseUrl}/auth/login');
    final loginRes = await http
        .post(
          loginUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    final Map<String, dynamic> loginBody = jsonDecode(utf8.decode(loginRes.bodyBytes));
    if (loginRes.statusCode != 200) {
      throw Exception(loginBody['error'] ?? 'Đăng nhập không thành công');
    }

    final token = loginBody['token'] as String;

    // 2. Lấy danh sách License Key của User
    final keysUri = Uri.parse('${AppConstants.defaultApiBaseUrl}/license/my_keys');
    final keysRes = await http.get(
      keysUri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));

    if (keysRes.statusCode != 200) {
      throw Exception('Không thể truy vấn thông tin bản quyền của tài khoản');
    }

    final dynamic decoded = jsonDecode(utf8.decode(keysRes.bodyBytes));
    final List<dynamic> keysList = decoded is Map<String, dynamic>
        ? (decoded['keys'] as List<dynamic>? ?? [])
        : (decoded is List ? decoded : []);

    if (keysList.isEmpty) {
      throw Exception('Tài khoản này chưa có License Key nào. Vui lòng truy cập trang web để nhận bản quyền.');
    }

    // Chọn key còn hạn ưu tiên PRO > CREATOR > TRIAL
    dynamic selectedKey;
    for (final k in keysList) {
      final isExpired = k['is_expired'] == true || k['status'] == 'EXPIRED';
      final status = k['status']?.toString();
      final plan = (k['planType'] ?? k['plan_type'])?.toString();
      if (!isExpired && status == 'ACTIVE') {
        selectedKey = k;
        if (plan == 'PRO' || plan == 'STUDIO') break;
      }
    }

    if (selectedKey == null) {
      throw Exception('Tất cả bản quyền của tài khoản này đã hết hạn. Vui lòng gia hạn trên Portal.');
    }

    final licenseKeyString = (selectedKey['licenseKey'] ?? selectedKey['license_key']) as String;
    final info = await activateWithKey(licenseKeyString);
    final updatedInfo = info.copyWith(userEmail: email.trim());
    await saveLicense(updatedInfo);
    return updatedInfo;
  }

  /// Thu hồi / Hủy kích hoạt trên máy này (Deactivate Device)
  static Future<void> deactivate(LicenseInfo current) async {
    if (current.licenseKey == null) return;
    final machineId = await getMachineId();

    try {
      final uri = Uri.parse('${AppConstants.defaultApiBaseUrl}/license/revoke');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'licenseKey': current.licenseKey,
              'machineId': machineId,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[LicenseService] Không thể kết nối server để báo revoke, vẫn xóa local: $e');
    }

    await clearLicense();
  }

  /// Xác thực bản quyền Online với server (Heartbeat)
  static Future<LicenseInfo> verifyOnline(LicenseInfo current) async {
    if (current.licenseKey == null) return LicenseInfo.unlicensed();
    final machineId = await getMachineId();

    try {
      final uri = Uri.parse(
        '${AppConstants.defaultApiBaseUrl}/license/verify?key=${current.licenseKey}&machineId=$machineId',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final isValid = data['isValid'] == true;
        if (!isValid) {
          debugPrint('[LicenseService] Server phản hồi thiết bị đã bị gỡ/thu hồi -> Dọn sạch cache bản quyền');
          await clearLicense();
          return LicenseInfo.unlicensed();
        }

        final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '') ?? current.expiresAt;
        final planType = data['planType']?.toString() ?? current.planType;
        final updated = current.copyWith(
          planType: planType,
          expiresAt: expiresAt,
          status: planType == 'trial_7days' ? LicenseStatus.trial : LicenseStatus.active,
          lastOnlineCheck: DateTime.now(),
        );
        await saveLicense(updated);
        return updated;
      } else if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404) {
        debugPrint('[LicenseService] Server từ chối bản quyền (${res.statusCode}) -> Dọn sạch cache bản quyền');
        await clearLicense();
        return LicenseInfo.unlicensed();
      }
    } catch (e) {
      // Khi mất mạng hoặc server bận -> Chuyển sang Grace Period Offline nếu còn hạn
      debugPrint('[LicenseService] Không thể kết nối server verify (chế độ offline): $e');
      if (current.isValid) {
        return current.copyWith(status: LicenseStatus.offlineGrace);
      }
    }
    return current;
  }
}

/// Riverpod State Notifier quản lý License State toàn cục
class LicenseNotifier extends StateNotifier<LicenseInfo> {
  LicenseNotifier() : super(LicenseInfo.unlicensed()) {
    init();
  }

  Future<void> init() async {
    final saved = await LicenseService.loadSavedLicense();
    state = saved;

    // Nếu đã kích hoạt, cố gắng heartbeat xác thực ngầm
    if (saved.isValid && saved.licenseKey != null) {
      try {
        final verified = await LicenseService.verifyOnline(saved);
        state = verified;
      } catch (_) {}
    }
  }

  Future<void> activate(String key) async {
    final info = await LicenseService.activateWithKey(key);
    state = info;
  }

  Future<void> loginAndActivate({required String email, required String password}) async {
    final info = await LicenseService.loginAndActivate(email: email, password: password);
    state = info;
  }

  Future<void> deactivate() async {
    await LicenseService.deactivate(state);
    state = LicenseInfo.unlicensed();
  }

  Future<LicenseInfo> refresh() async {
    if (state.licenseKey != null && state.licenseKey!.isNotEmpty) {
      final verified = await LicenseService.verifyOnline(state);
      state = verified;
      return verified;
    }
    return state;
  }
}

final licenseInfoProvider = StateNotifierProvider<LicenseNotifier, LicenseInfo>((ref) {
  return LicenseNotifier();
});
