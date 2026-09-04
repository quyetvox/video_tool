import 'dart:io';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_constants.dart';
import '../core/app_update_service.dart';
import '../core/engine_update_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const UpdateDialog(),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isChecking = false;

  // Core Engine Info
  ActiveEngineInfo? _coreInfo;
  EngineUpdateInfo? _coreUpdate;
  bool _isApplyingCore = false;
  double _coreProgress = 0.0;
  String _coreStatus = '';

  // App GUI Info
  AppUpdateRelease? _appUpdate;
  bool _isDownloadingApp = false;
  double _appProgress = 0.0;
  String _appStatus = '';

  @override
  void initState() {
    super.initState();
    _checkAllUpdates();
  }

  Future<void> _checkAllUpdates() async {
    setState(() {
      _isChecking = true;
      _coreStatus = 'Đang kiểm tra bản vá lõi...';
      _appStatus = 'Đang kiểm tra bản phát hành GitHub...';
    });

    try {
      final coreInfo = await EngineUpdateService.getActiveEngineInfo();
      _coreInfo = coreInfo;

      // Check Core update
      final coreUpdate = await EngineUpdateService.checkUpdate();
      _coreUpdate = coreUpdate;
      _coreStatus = coreUpdate != null
          ? '✨ Có bản vá lõi mới: ${coreUpdate.version}'
          : '✅ Lõi xử lý đang ở phiên bản mới nhất.';
    } catch (e) {
      _coreStatus = 'Không thể kiểm tra lõi: $e';
    }

    try {
      // Check App update
      final appUpdate = await AppUpdateService.checkAppUpdate();
      _appUpdate = appUpdate;
      _appStatus = appUpdate != null
          ? '🚀 Đã có bản phát hành mới: ${appUpdate.tagName}'
          : '✅ Ứng dụng Desktop đang ở phiên bản mới nhất.';
    } catch (e) {
      _appStatus = 'Không thể kiểm tra ứng dụng: $e';
    }

    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _applyCorePatch() async {
    if (_coreUpdate == null) return;

    setState(() {
      _isApplyingCore = true;
      _coreProgress = 0.1;
      _coreStatus = 'Đang tải bản vá lõi...';
    });

    try {
      await EngineUpdateService.applyPatch(
        _coreUpdate!,
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _coreProgress = p;
              _coreStatus = s;
            });
          }
        },
      );

      final updatedInfo = await EngineUpdateService.getActiveEngineInfo();
      if (mounted) {
        setState(() {
          _coreInfo = updatedInfo;
          _isApplyingCore = false;
          _coreUpdate = null;
          _coreStatus = '🎉 Đã nâng cấp Lõi lên ${_coreInfo?.version} thành công!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApplyingCore = false;
          _coreStatus = '❌ Cập nhật lõi thất bại: $e';
        });
      }
    }
  }

  Future<void> _downloadAndInstallApp() async {
    if (_appUpdate == null) return;

    setState(() {
      _isDownloadingApp = true;
      _appProgress = 0.05;
      _appStatus = 'Bắt đầu tải bản cài đặt...';
    });

    try {
      await AppUpdateService.downloadAndInstallUpdate(
        _appUpdate!,
        onProgress: (p, s) {
          if (mounted) {
            setState(() {
              _appProgress = p;
              _appStatus = s;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloadingApp = false;
          _appStatus = Platform.isWindows
              ? '🎉 Đang khởi chạy bộ cài đặt tự động...'
              : '🎉 Đã mở tệp DMG cài đặt!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingApp = false;
          _appStatus = '❌ Lỗi tải bản cập nhật: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.system_update_alt, color: Color(0xFF60A5FA), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trung Tâm Cập Nhật Sub-Video AI',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Quản lý phiên bản Lõi Video Engine và Ứng dụng Desktop',
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: _isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    tooltip: 'Kiểm tra lại',
                    onPressed: _isChecking ? null : _checkAllUpdates,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── CARD 1: CORE ENGINE UPDATE ───────────────────────────────
              _buildSectionCard(
                context,
                icon: Icons.memory,
                iconColor: const Color(0xFF10B981),
                title: '1. Lõi Xử Lý Video (Core Engine)',
                currentLabel: 'Bản vá hiện tại:',
                currentValue: _coreInfo?.version ?? 'Đang tải...',
                hasUpdate: _coreUpdate != null,
                updateVersion: _coreUpdate?.version,
                updateSize: 'Bản vá siêu nhẹ (~1MB)',
                statusMessage: _coreStatus,
                isProcessing: _isApplyingCore,
                progress: _coreProgress,
                actionButtonText: 'Nạp Bản Vá Core Ngay',
                actionButtonColor: const Color(0xFF059669),
                onAction: _applyCorePatch,
              ),

              const SizedBox(height: 14),

              // ── CARD 2: APP GUI DESKTOP UPDATE ──────────────────────────
              _buildSectionCard(
                context,
                icon: Icons.desktop_windows,
                iconColor: const Color(0xFF3B82F6),
                title: '2. Ứng Dụng Desktop (Flutter GUI)',
                currentLabel: 'Phiên bản hiện tại:',
                currentValue: AppConstants.appVersion,
                hasUpdate: _appUpdate != null,
                updateVersion: _appUpdate?.tagName,
                updateSize: _appUpdate?.assetName != null ? '${_appUpdate!.assetName}' : null,
                statusMessage: _appStatus,
                isProcessing: _isDownloadingApp,
                progress: _appProgress,
                actionButtonText: Platform.isWindows
                    ? 'Tải & Cài Đặt Tự Động (.exe)'
                    : 'Tải Bản Cập Nhật (.dmg)',
                actionButtonColor: const Color(0xFF2563EB),
                onAction: _downloadAndInstallApp,
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng', style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String currentLabel,
    required String currentValue,
    required bool hasUpdate,
    required String? updateVersion,
    String? updateSize,
    required String statusMessage,
    required bool isProcessing,
    required double progress,
    required String actionButtonText,
    required Color actionButtonColor,
    required VoidCallback onAction,
  }) {
    final c = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasUpdate ? iconColor.withOpacity(0.5) : c.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$currentLabel $currentValue',
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            statusMessage,
            style: TextStyle(
              fontSize: 11.5,
              color: hasUpdate ? Colors.white : c.textSecondary,
              fontWeight: hasUpdate ? FontWeight.w600 : FontWeight.normal,
            ),
          ),

          if (isProcessing) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: Colors.white12,
              color: actionButtonColor,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ],

          if (hasUpdate && !isProcessing) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (updateSize != null) ...[
                  Text(
                    updateSize,
                    style: TextStyle(fontSize: 11, color: c.textMuted),
                  ),
                  const Spacer(),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionButtonColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.download, size: 14),
                  label: Text(
                    actionButtonText,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onAction,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
