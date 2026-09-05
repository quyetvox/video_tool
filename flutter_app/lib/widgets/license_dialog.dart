import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../core/app_constants.dart';
import '../core/license_service.dart';
import '../models/license_info.dart';

class LicenseDialog extends ConsumerStatefulWidget {
  const LicenseDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const LicenseDialog(),
    );
  }

  @override
  ConsumerState<LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends ConsumerState<LicenseDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(licenseInfoProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openBrowser(String url) {
    try {
      if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  Future<void> _handleActivateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập mã khóa bản quyền');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ref.read(licenseInfoProvider.notifier).activate(key);
      setState(() {
        _successMessage = 'Kích hoạt bản quyền thành công!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLoginActivate() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập đầy đủ Email và Mật khẩu');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await ref.read(licenseInfoProvider.notifier).loginAndActivate(
        email: email,
        password: pass,
      );
      setState(() {
        _successMessage = 'Đăng nhập và kích hoạt bản quyền thành công!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDeactivate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Xác nhận hủy kích hoạt', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Bạn có chắc chắn muốn hủy kích hoạt bản quyền trên máy tính này?\n\n'
          'Slot thiết bị sẽ được giải phóng ngay lập tức trên Portal để bạn có thể kích hoạt trên máy khác.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bỏ qua', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hủy kích hoạt', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await ref.read(licenseInfoProvider.notifier).deactivate();
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseInfoProvider);
    final c = AppColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: 580,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Header Dialog
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.workspace_premium, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          license.isValid ? 'Thông Tin Bản Quyền' : 'Kích Hoạt Sub-Video AI',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          license.isValid
                              ? 'Bản quyền phần mềm chính hãng đã kích hoạt trên máy này'
                              : 'Nhập Product Key hoặc đăng nhập để mở khóa đầy đủ tính năng',
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Nội dung Body
            Padding(
              padding: const EdgeInsets.all(24),
              child: license.isValid
                  ? _buildActiveLicenseView(license, c)
                  : _buildUnlicensedView(c),
            ),
          ],
        ),
      ),
    );
  }

  /// Giao diện khi máy tính ĐÃ KÍCH HOẠT bản quyền hợp lệ (Office Style)
  Widget _buildActiveLicenseView(LicenseInfo license, dynamic c) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final expireStr = license.expiresAt != null ? dateFormat.format(license.expiresAt!) : 'Không giới hạn';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thẻ Gold Card Bản Quyền
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFF59E0B).withOpacity(0.12),
                const Color(0xFFD97706).withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, color: Color(0xFFF59E0B), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        license.displayPlanName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: license.isTrial
                          ? const Color(0xFFF59E0B).withOpacity(0.2)
                          : const Color(0xFF10B981).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: license.isTrial ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      license.isTrial
                          ? 'Dùng thử (${license.daysRemaining} ngày)'
                          : 'Đang hoạt động',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: license.isTrial ? const Color(0xFFD97706) : const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Thông tin chi tiết
              _buildInfoRow('Mã khóa (Product Key):', license.maskedKey, onCopy: () {
                if (license.licenseKey != null) {
                  Clipboard.setData(ClipboardData(text: license.licenseKey!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã sao chép License Key vào clipboard')),
                  );
                }
              }),
              const SizedBox(height: 8),
              _buildInfoRow('Hạn sử dụng:', expireStr),
              const SizedBox(height: 8),
              _buildInfoRow('Thiết bị kích hoạt:', license.machineName ?? LicenseService.getMachineName()),
              if (license.userEmail != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow('Tài khoản liên kết:', license.userEmail!),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Các nút hành động
        Row(
          children: [
            // Nút Hủy kích hoạt trên máy này (Deactivate)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Hủy Kích Hoạt Máy Này', style: TextStyle(fontSize: 12.5)),
              onPressed: _isLoading ? null : _handleDeactivate,
            ),
            const Spacer(),

            // Nút Nâng cấp gói
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.rocket_launch, size: 16),
              label: const Text('Nâng Cấp Gói', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              onPressed: () => _openBrowser(AppConstants.pricingUrl),
            ),
            const SizedBox(width: 10),

            // Nút Đóng
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      ],
    );
  }

  /// Giao diện khi CHƯA KÍCH HOẠT hoặc HẾT HẠN
  Widget _buildUnlicensedView(dynamic c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab Header: Kích hoạt bằng Key vs Đăng nhập
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFD97706),
          unselectedLabelColor: c.textSecondary,
          indicatorColor: const Color(0xFFD97706),
          indicatorWeight: 2.5,
          tabs: const [
            Tab(icon: Icon(Icons.key, size: 18), text: 'Nhập Product Key'),
            Tab(icon: Icon(Icons.account_circle, size: 18), text: 'Đăng Nhập Tài Khoản'),
          ],
        ),

        const SizedBox(height: 18),

        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),

        if (_successMessage != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _successMessage!,
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),

        SizedBox(
          height: 210,
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: NHẬP PRODUCT KEY
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nhập mã bản quyền gồm 20 ký tự (ví dụ: SUBVID-XXXX-XXXX-XXXX):',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _keyController,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'SUBVID-ABCD-1234-EF56',
                      prefixIcon: const Icon(Icons.vpn_key, color: Color(0xFFD97706), size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFD97706), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle, size: 18),
                    label: Text(
                      _isLoading ? 'Đang kích hoạt...' : 'Kích Hoạt Ngay',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: _isLoading ? null : _handleActivateKey,
                  ),
                  const Spacer(),
                  Center(
                    child: TextButton(
                      onPressed: () => _openBrowser(AppConstants.registerUrl),
                      child: const Text(
                        'Chưa có mã bản quyền? Đăng ký nhận 7 ngày dùng thử miễn phí ↗',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFD97706),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // TAB 2: ĐĂNG NHẬP TÀI KHOẢN SUB-VIDEO
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Địa chỉ Email',
                      prefixIcon: const Icon(Icons.email_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login, size: 18),
                    label: Text(
                      _isLoading ? 'Đang xác thực...' : 'Đăng Nhập & Kích Hoạt Tự Động',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isLoading ? null : _handleLoginActivate,
                  ),
                  const Spacer(),
                  Center(
                    child: TextButton(
                      onPressed: () => _openBrowser(AppConstants.websiteUrl),
                      child: const Text(
                        'Quên mật khẩu hoặc quản lý tài khoản trên Web Portal ↗',
                        style: TextStyle(fontSize: 12, color: Color(0xFFD97706)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {VoidCallback? onCopy}) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Colors.white60),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 14, color: Color(0xFFF59E0B)),
            tooltip: 'Sao chép',
            onPressed: onCopy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }
}
