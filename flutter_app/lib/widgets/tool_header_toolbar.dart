import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Thanh công cụ Sub-Header chuẩn mực cao 44px dành cho từng tab tool trong Sub-Video.
/// Cung cấp trải nghiệm đồng nhất:
/// - Bên trái: Icon công cụ + Tên công cụ (Breadcrumb) + Tên tệp/dự án đang thao tác + Badge trạng thái (Co giãn an toàn).
/// - Bên phải: Cụm các nút hành động cốt lõi (Action Command Bar) của riêng công cụ đó.
class ToolHeaderToolbar extends StatelessWidget {
  final Widget? icon;
  final String title;
  final String? breadcrumb;
  final Widget? badge;
  final List<Widget> actions;

  const ToolHeaderToolbar({
    super.key,
    this.icon,
    required this.title,
    this.breadcrumb,
    this.badge,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          bottom: BorderSide(color: c.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // ── CỤM TRÁI: ICON + TITLE + BREADCRUMB + BADGE (CO GIÃN AN TOÀN TRÁNH TRÀN PIXEL) ──
          Expanded(
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surfaceLight.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border.withOpacity(0.6), width: 1),
                    ),
                    child: icon!,
                  ),
                  const SizedBox(width: 8),
                ],

                // Tiêu đề & Breadcrumb bọc trong Flexible để không làm tràn hàng khi cửa sổ hẹp
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (breadcrumb != null && breadcrumb!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right, size: 14, color: c.textMuted),
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 3,
                          child: Tooltip(
                            message: breadcrumb!,
                            child: Text(
                              breadcrumb!,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Badge trạng thái
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  badge!,
                ],
              ],
            ),
          ),

          const SizedBox(width: 10),

          // ── CỤM NÚT HÀNH ĐỘNG BÊN PHẢI (ACTIONS COMMAND BAR) ──
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
        ],
      ),
    );
  }
}
