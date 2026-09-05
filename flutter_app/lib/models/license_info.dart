enum LicenseStatus {
  unlicensed,
  trial,
  active,
  expired,
  offlineGrace,
}

class LicenseInfo {
  final String? licenseKey;
  final String planType;
  final LicenseStatus status;
  final DateTime? expiresAt;
  final DateTime? activatedAt;
  final DateTime? lastOnlineCheck;
  final String? machineId;
  final String? machineName;
  final String? userEmail;
  final int maxDevices;

  const LicenseInfo({
    this.licenseKey,
    this.planType = 'unlicensed',
    this.status = LicenseStatus.unlicensed,
    this.expiresAt,
    this.activatedAt,
    this.lastOnlineCheck,
    this.machineId,
    this.machineName,
    this.userEmail,
    this.maxDevices = 1,
  });

  /// Factory cho trạng thái chưa kích hoạt
  factory LicenseInfo.unlicensed() {
    return const LicenseInfo(
      planType: 'unlicensed',
      status: LicenseStatus.unlicensed,
    );
  }

  /// Trả về true nếu bản quyền hợp lệ và còn thời hạn
  bool get isValid {
    if (status == LicenseStatus.unlicensed || status == LicenseStatus.expired) {
      return false;
    }
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) {
      return false;
    }
    return true;
  }

  /// Chuỗi định danh gói đã chuẩn hóa viết thường
  String get normalizedPlan => planType.toLowerCase().trim();

  /// Kiểm tra có phải là gói dùng thử không
  bool get isTrial => normalizedPlan == 'trial_7days';

  /// Kiểm tra các gói cụ thể
  bool get isCreator => normalizedPlan == 'creator';
  bool get isPro => normalizedPlan == 'pro';
  bool get isStudio => normalizedPlan == 'studio';

  // ── Feature Gating Matrix (Phân Quyền Theo Gói) ────────────────
  /// Quyền sử dụng Kho Lưu Trữ Đám Mây GCS (Mở cho cả Creator & Pro)
  bool get canUseGcs => isValid && (isTrial || isCreator || isPro || isStudio);

  /// Quyền sử dụng Cơ chế Resume thông minh khi gián đoạn (Chỉ Pro & Trial)
  bool get canUseResume => isValid && (isTrial || isPro || isStudio);

  /// Quyền sử dụng cơ chế phân đoạn xử lý video siêu dài 2-3 giờ (Chỉ Pro & Trial)
  bool get canUseLongVideoChunking => isValid && (isTrial || isPro || isStudio);

  /// Quyền tải & xử lý tuần tự hàng loạt danh sách video (Chỉ Pro & Trial)
  bool get canUseSequentialBatch => isValid && (isTrial || isPro || isStudio);

  /// Tính số ngày sử dụng còn lại
  int get daysRemaining {
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff + 1;
  }

  /// Tên hiển thị thân thiện của gói (Gói Doanh Nghiệp tạm ẩn)
  String get displayPlanName {
    switch (normalizedPlan) {
      case 'trial_7days':
        return 'Bản Quyền Dùng Thử 7 Ngày';
      case 'creator':
        return 'Gói Creator Hàng Tháng';
      case 'pro':
      case 'studio':
        return 'Gói Pro Studio';
      default:
        return 'Chưa Kích Hoạt';
    }
  }

  /// Chuỗi hiển thị che bớt các ký tự giữa của Key
  String get maskedKey {
    if (licenseKey == null || licenseKey!.isEmpty) return '---';
    final parts = licenseKey!.split('-');
    if (parts.length >= 4) {
      return '${parts[0]}-****-****-${parts[3]}';
    }
    return licenseKey!;
  }

  Map<String, dynamic> toJson() {
    return {
      'license_key': licenseKey,
      'plan_type': planType,
      'status': status.name,
      'expires_at': expiresAt?.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
      'last_online_check': lastOnlineCheck?.toIso8601String(),
      'machine_id': machineId,
      'machine_name': machineName,
      'user_email': userEmail,
      'max_devices': maxDevices,
    };
  }

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    LicenseStatus parseStatus(String? name) {
      if (name == null) return LicenseStatus.unlicensed;
      for (final s in LicenseStatus.values) {
        if (s.name == name) return s;
      }
      return LicenseStatus.unlicensed;
    }

    DateTime? parseDate(dynamic d) {
      if (d == null) return null;
      if (d is DateTime) return d;
      return DateTime.tryParse(d.toString());
    }

    return LicenseInfo(
      licenseKey: json['license_key'] as String?,
      planType: json['plan_type'] as String? ?? 'unlicensed',
      status: parseStatus(json['status'] as String?),
      expiresAt: parseDate(json['expires_at']),
      activatedAt: parseDate(json['activated_at']),
      lastOnlineCheck: parseDate(json['last_online_check']),
      machineId: json['machine_id'] as String?,
      machineName: json['machine_name'] as String?,
      userEmail: json['user_email'] as String?,
      maxDevices: json['max_devices'] as int? ?? 1,
    );
  }

  LicenseInfo copyWith({
    String? licenseKey,
    String? planType,
    LicenseStatus? status,
    DateTime? expiresAt,
    DateTime? activatedAt,
    DateTime? lastOnlineCheck,
    String? machineId,
    String? machineName,
    String? userEmail,
    int? maxDevices,
  }) {
    return LicenseInfo(
      licenseKey: licenseKey ?? this.licenseKey,
      planType: planType ?? this.planType,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      activatedAt: activatedAt ?? this.activatedAt,
      lastOnlineCheck: lastOnlineCheck ?? this.lastOnlineCheck,
      machineId: machineId ?? this.machineId,
      machineName: machineName ?? this.machineName,
      userEmail: userEmail ?? this.userEmail,
      maxDevices: maxDevices ?? this.maxDevices,
    );
  }
}
