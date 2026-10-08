import 'package:flutter/material.dart';

import '../../../../core/app_colors.dart';
import '../../../../widgets/app_kit.dart';
import '../models/lecture_illustrator_model.dart';

class TemplateMeta {
  final String id;
  final String nameVi;
  final String category; // 'ai', 'coding', 'structure', 'concept'
  final String categoryName;
  final String description;
  final IconData icon;
  final Color accentColor;
  final int idealSlotsMin;
  final int idealSlotsMax;
  final String visualLayoutDescription;

  const TemplateMeta({
    required this.id,
    required this.nameVi,
    required this.category,
    required this.categoryName,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.idealSlotsMin,
    required this.idealSlotsMax,
    required this.visualLayoutDescription,
  });
}

const List<TemplateMeta> allLectureTemplates = [
  // ── 🤖 NHÓM AI & TỰ TRỊ ──
  TemplateMeta(
    id: 'agent_workflow',
    nameVi: 'Chu Trình Tự Trị AI Agent',
    category: 'ai',
    categoryName: 'AI & Tự Trị',
    description: 'Vòng lặp ReAct: Nhận thức (Perception) → Lập kế hoạch (Decision) → Công cụ (Tools) → Bộ nhớ (Memory).',
    icon: Icons.smart_toy_outlined,
    accentColor: Color(0xFFE06C75),
    idealSlotsMin: 2,
    idealSlotsMax: 4,
    visualLayoutDescription: 'Lõi trung tâm Agent Brain kết nối 4 trạm vệ tinh vòng lặp với hạt năng lượng tuần hoàn.',
  ),
  TemplateMeta(
    id: 'rag_pipeline',
    nameVi: 'Kiến Trúc RAG & Tri Thức',
    category: 'ai',
    categoryName: 'AI & Tự Trị',
    description: 'Luồng 4 trạm ngang: User Query → Embedding → Vector Database → Tổng hợp LLM Response.',
    icon: Icons.storage_rounded,
    accentColor: Color(0xFF61AFEF),
    idealSlotsMin: 2,
    idealSlotsMax: 4,
    visualLayoutDescription: '4 khối trạm ngang tuần tự, Cylinder Vector DB, cầu prompt bắc ngang và hạt dữ liệu bay.',
  ),
  TemplateMeta(
    id: 'transformer_attention',
    nameVi: 'Cơ Chế Chú Ý Transformer',
    category: 'ai',
    categoryName: 'AI & Tự Trị',
    description: 'Hàng Token đầu vào, 3 nhánh véc-tơ Q-K-V và ma trận Attention Softmax Heatmap.',
    icon: Icons.grid_view_rounded,
    accentColor: Color(0xFF98C379),
    idealSlotsMin: 2,
    idealSlotsMax: 4,
    visualLayoutDescription: 'Hàng thẻ token ở trên, 3 nhánh véc-tơ Q-K-V, lưới ma trận 4x4 nhấp nháy bên dưới.',
  ),
  TemplateMeta(
    id: 'neural_net',
    nameVi: 'Mạng Nơ-ron Đa Tầng',
    category: 'ai',
    categoryName: 'AI & Tự Trị',
    description: '4 tầng nơ-ron (Input, 2 Hidden, Output) liên kết synapses với hạt xung kích thích Forward Pass.',
    icon: Icons.hub_outlined,
    accentColor: Color(0xFFD19A66),
    idealSlotsMin: 2,
    idealSlotsMax: 6,
    visualLayoutDescription: 'Lưới 4 cột nơ-ron đan xen liên kết synapses chéo, hạt năng lượng chuyển động sóng.',
  ),

  // ── 💻 NHÓM LẬP TRÌNH & HỆ THỐNG ──
  TemplateMeta(
    id: 'code_block',
    nameVi: 'Minh Họa Code & Terminal',
    category: 'coding',
    categoryName: 'Lập Trình & Hệ Thống',
    description: 'Cửa sổ soạn thảo mã nguồn phác thảo, đánh số dòng, cú pháp lập trình và terminal.',
    icon: Icons.code_rounded,
    accentColor: Color(0xFF56B6C2),
    idealSlotsMin: 2,
    idealSlotsMax: 6,
    visualLayoutDescription: 'Khung editor phác thảo 3 chấm Mac, các dòng code thụt lề thụ động và vùng chú thích.',
  ),
  TemplateMeta(
    id: 'algo_array',
    nameVi: 'Mảng DSA & Hai Con Trỏ',
    category: 'coding',
    categoryName: 'Lập Trình & Hệ Thống',
    description: 'Mảng cấu trúc dữ liệu chia ngăn, hai con trỏ Left-Right di chuyển và công thức toán học.',
    icon: Icons.view_column_rounded,
    accentColor: Color(0xFFE5C07B),
    idealSlotsMin: 2,
    idealSlotsMax: 5,
    visualLayoutDescription: 'Hàng ô nhớ DSA chia ngăn ở giữa, 2 con trỏ L và R chỉ vào phần tử, công thức bên dưới.',
  ),
  TemplateMeta(
    id: 'system_tree',
    nameVi: 'Kiến Trúc Hệ Thống & API',
    category: 'coding',
    categoryName: 'Lập Trình & Hệ Thống',
    description: 'Cây phân cấp hệ thống: Nút gốc Client kết nối xuống các microservices, API endpoints và DB.',
    icon: Icons.account_tree_outlined,
    accentColor: Color(0xFFC678DD),
    idealSlotsMin: 2,
    idealSlotsMax: 5,
    visualLayoutDescription: 'Cây phân nhánh phân cấp từ nút nguồn tỏa ra các dịch vụ con và cơ sở dữ liệu.',
  ),
  TemplateMeta(
    id: 'network_route',
    nameVi: 'Mạng Viễn Thông & Địa Lý',
    category: 'coding',
    categoryName: 'Lập Trình & Hệ Thống',
    description: 'Bản đồ kết nối điểm-điểm, radar quét tín hiệu, định tuyến các gói tin IP qua nhiều trạm.',
    icon: Icons.alt_route_rounded,
    accentColor: Color(0xFF4EC9B0),
    idealSlotsMin: 2,
    idealSlotsMax: 5,
    visualLayoutDescription: 'Các trạm nút mạng nối zíc zắc kèm vòng tròn radar mở rộng và nhãn địa lý.',
  ),

  // ── 📊 NHÓM QUY TRÌNH & PHÂN TÍCH ──
  TemplateMeta(
    id: 'process_flow',
    nameVi: 'Quy Trình Tuần Tự Mũi Tên',
    category: 'structure',
    categoryName: 'Quy Trình & Phân Tích',
    description: 'Chuỗi các thẻ quy trình một chiều nối tiếp nhau bằng mũi tên, tự động ngắt dòng chữ.',
    icon: Icons.trending_flat_rounded,
    accentColor: Color(0xFF38BDF8),
    idealSlotsMin: 2,
    idealSlotsMax: 4,
    visualLayoutDescription: 'Các thẻ hình chữ nhật xếp ngang nối tiếp nhau bằng mũi tên phác thảo đậm nét.',
  ),
  TemplateMeta(
    id: 'compare_two',
    nameVi: 'So Sánh Đối Chiếu 2 Cột',
    category: 'structure',
    categoryName: 'Quy Trình & Phân Tích',
    description: 'Hai cột song song đối lập ngăn cách bởi vách ngăn dọc, đối chiếu ưu/nhược điểm hai trường phái.',
    icon: Icons.view_agenda_outlined,
    accentColor: Color(0xFFFBBF24),
    idealSlotsMin: 2,
    idealSlotsMax: 6,
    visualLayoutDescription: 'Hai cột đối xứng Trái - Phải chia đôi màn hình bởi đường thẳng đứng phác thảo.',
  ),
  TemplateMeta(
    id: 'number_stat',
    nameVi: 'Số Liệu & Tỷ Lệ Lớn',
    category: 'structure',
    categoryName: 'Quy Trình & Phân Tích',
    description: 'Vòng tròn phác thảo hiển thị số liệu nổi bật bên trái kèm danh sách luận điểm phân tích bên phải.',
    icon: Icons.pie_chart_outline_rounded,
    accentColor: Color(0xFFFB923C),
    idealSlotsMin: 2,
    idealSlotsMax: 5,
    visualLayoutDescription: 'Vòng tròn đồ thị lớn chứa con số ở bên trái, các ý phân tích gạch đầu dòng bên phải.',
  ),

  // ── 📝 NHÓM KHÁI NIỆM & THUYẾT MINH ──
  TemplateMeta(
    id: 'definition',
    nameVi: 'Đóng Khung Khái Niệm',
    category: 'concept',
    categoryName: 'Khái Niệm & Thuyết Minh',
    description: 'Khung hộp thẻ bài học trang trọng có badge ghim "KHÁI NIỆM", giải thích thuật ngữ cốt lõi.',
    icon: Icons.bookmark_border_rounded,
    accentColor: Color(0xFF34D399),
    idealSlotsMin: 1,
    idealSlotsMax: 4,
    visualLayoutDescription: 'Khung thẻ bài học bao quanh với badge dán nhãn nổi bật ở góc trên, text định nghĩa lớn.',
  ),
  TemplateMeta(
    id: 'title_point',
    nameVi: 'Tiêu Đề Nổi Bật Lớn',
    category: 'concept',
    categoryName: 'Khái Niệm & Thuyết Minh',
    description: 'Tiêu đề lớn ở trung tâm với nét mực gạch chân nổi bật, cô đọng thông điệp quan trọng nhất.',
    icon: Icons.title_rounded,
    accentColor: Color(0xFFF43F5E),
    idealSlotsMin: 1,
    idealSlotsMax: 3,
    visualLayoutDescription: 'Dòng tiêu đề chính cực lớn ở trung tâm, nét gạch chân đỏ cam và 1-2 câu kết luận.',
  ),
  TemplateMeta(
    id: 'bullet_list',
    nameVi: 'Danh Sách Ý Gạch Đầu Dòng',
    category: 'concept',
    categoryName: 'Khái Niệm & Thuyết Minh',
    description: 'Bố cục danh sách kinh điển với các điểm nhấn bullet vẽ tay, dễ đọc và linh hoạt nhất.',
    icon: Icons.format_list_bulleted_rounded,
    accentColor: Color(0xFF94A3B8),
    idealSlotsMin: 2,
    idealSlotsMax: 6,
    visualLayoutDescription: 'Cột danh sách các ý với bullet point vẽ tay, hiển thị tuần tự theo câu thuyết minh.',
  ),
];

class LectureTemplatePickerDialog extends StatefulWidget {
  final String currentTemplate;
  final LectureBatch batch;
  final ValueChanged<String> onSelected;

  const LectureTemplatePickerDialog({
    super.key,
    required this.currentTemplate,
    required this.batch,
    required this.onSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required String currentTemplate,
    required LectureBatch batch,
    required ValueChanged<String> onSelected,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => LectureTemplatePickerDialog(
        currentTemplate: currentTemplate,
        batch: batch,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<LectureTemplatePickerDialog> createState() => _LectureTemplatePickerDialogState();
}

class _LectureTemplatePickerDialogState extends State<LectureTemplatePickerDialog> {
  late String _selectedTemplateId;
  String _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _selectedTemplateId = widget.currentTemplate;
  }

  TemplateMeta get _currentMeta {
    return allLectureTemplates.firstWhere(
      (m) => m.id == _selectedTemplateId,
      orElse: () => allLectureTemplates.first,
    );
  }

  List<TemplateMeta> get _filteredTemplates {
    if (_selectedCategory == 'all') return allLectureTemplates;
    return allLectureTemplates.where((m) => m.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final selectedMeta = _currentMeta;
    final sentenceCount = widget.batch.sentences.isNotEmpty
        ? widget.batch.sentences.length
        : (widget.batch.scene['steps'] as List?)?.length ?? 1;

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border.withOpacity(0.8), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 680),
        child: Column(
          children: [
            // ── HEADER ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: c.border.withOpacity(0.6))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: selectedMeta.accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.palette_rounded, size: 18, color: selectedMeta.accentColor),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BỘ CHỌN TEMPLATE MINH HỌA (14 MẪU CHUYÊN SÂU)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tùy biến phong cách hình ảnh bài giảng cho phân đoạn này • Vùng an toàn chuẩn y ≤ 870px',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── BỘ LỌC DANH MỤC NHANH ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: c.surfaceLight.withOpacity(0.5),
                border: Border(bottom: BorderSide(color: c.border.withOpacity(0.4))),
              ),
              child: Row(
                children: [
                  _buildCategoryFilterChip('all', 'Tất cả (14)', Icons.apps_rounded, c),
                  const SizedBox(width: 8),
                  _buildCategoryFilterChip('ai', 'AI & Agent (4)', Icons.smart_toy_outlined, c),
                  const SizedBox(width: 8),
                  _buildCategoryFilterChip('coding', 'Lập trình & Hệ thống (4)', Icons.code_rounded, c),
                  const SizedBox(width: 8),
                  _buildCategoryFilterChip('structure', 'Quy trình & Phân tích (3)', Icons.account_tree_outlined, c),
                  const SizedBox(width: 8),
                  _buildCategoryFilterChip('concept', 'Khái niệm & Thuyết minh (3)', Icons.bookmark_border_rounded, c),
                ],
              ),
            ),

            // ── THÂN DIALOG: 2 CỘT (Cột trái: Gallery Template, Cột phải: Blueprint & Slot Mapping) ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CỘT TRÁI: Danh sách các Template
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: c.border.withOpacity(0.6))),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredTemplates.length,
                        itemBuilder: (context, idx) {
                          final item = _filteredTemplates[idx];
                          final isSelected = item.id == _selectedTemplateId;
                          final isCurrent = item.id == widget.currentTemplate;

                          return InkWell(
                            onTap: () => setState(() => _selectedTemplateId = item.id),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? item.accentColor.withOpacity(0.12) : c.surfaceLight.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? item.accentColor : c.border.withOpacity(0.6),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Wireframe Mini
                                  _buildMiniWireframe(item),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              item.nameVi,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected ? item.accentColor : c.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            if (isCurrent)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: c.primary.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'HIỆN TẠI',
                                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: c.primary),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: ${item.id}',
                                          style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: c.textMuted),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.description,
                                          style: TextStyle(fontSize: 10.5, color: c.textSecondary, height: 1.3),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // CỘT PHẢI: Xem trước Bố cục Blueprint & Ánh xạ Câu thoại
                  Expanded(
                    flex: 6,
                    child: Container(
                      color: c.surfaceDark.withOpacity(0.4),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header chi tiết template được chọn
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: selectedMeta.accentColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: selectedMeta.accentColor.withOpacity(0.6)),
                                ),
                                child: Icon(selectedMeta.icon, size: 20, color: selectedMeta.accentColor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selectedMeta.nameVi,
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: selectedMeta.accentColor),
                                    ),
                                    Text(
                                      'Nhóm: ${selectedMeta.categoryName} • Khuyến nghị: ${selectedMeta.idealSlotsMin}-${selectedMeta.idealSlotsMax} câu thoại',
                                      style: TextStyle(fontSize: 11, color: c.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Sơ đồ Blueprint trực quan lớn
                          _buildLargeBlueprintCard(selectedMeta, c),
                          const SizedBox(height: 14),

                          // Header danh sách mapping câu thoại
                          Row(
                            children: [
                              Icon(Icons.alt_route_rounded, size: 14, color: c.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Ánh Xạ Câu Thoại Thực Tế Của Đoạn Này ($sentenceCount câu):',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: c.textPrimary),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (sentenceCount >= selectedMeta.idealSlotsMin && sentenceCount <= selectedMeta.idealSlotsMax)
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (sentenceCount >= selectedMeta.idealSlotsMin && sentenceCount <= selectedMeta.idealSlotsMax)
                                      ? 'Tương thích lý tưởng'
                                      : 'Độ dài khả dụng',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: (sentenceCount >= selectedMeta.idealSlotsMin && sentenceCount <= selectedMeta.idealSlotsMax)
                                        ? Colors.greenAccent
                                        : Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Bảng mapping câu thoại vào các slots của template
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border.withOpacity(0.6)),
                              ),
                              child: ListView(
                                padding: const EdgeInsets.all(8),
                                children: _buildSlotMappingRows(selectedMeta, c),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── FOOTER HÀNH ĐỘNG ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: c.surfaceDark,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: c.border.withOpacity(0.6))),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: c.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'Template được áp dụng tức thì vào Storyboard và sẵn sàng render.',
                    style: TextStyle(fontSize: 11, color: c.textMuted),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Đóng',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppButton.primary(
                    label: 'Áp Dụng Template Này',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: () {
                      widget.onSelected(_selectedTemplateId);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilterChip(String catKey, String label, IconData icon, dynamic c) {
    final isSelected = _selectedCategory == catKey;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = catKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? c.primary.withOpacity(0.2) : c.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? c.primary : c.border.withOpacity(0.6),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isSelected ? c.primary : c.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? c.primary : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniWireframe(TemplateMeta meta) {
    return Container(
      width: 56,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE3), // Nền giấy vẽ tay
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: meta.accentColor.withOpacity(0.5), width: 1),
      ),
      child: Center(
        child: Icon(meta.icon, size: 22, color: const Color(0xFF26323D)),
      ),
    );
  }

  Widget _buildLargeBlueprintCard(TemplateMeta meta, dynamic c) {
    return Container(
      height: 105,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EFE3), // Phong cách giấy vẽ tay #f4efe3
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.accentColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Graphic layout mô phỏng
          Container(
            width: 110,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF8A8372).withOpacity(0.4)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(meta.icon, size: 38, color: meta.accentColor),
                ),
                Positioned(
                  bottom: 4,
                  left: 6,
                  right: 6,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB5533C).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26323D),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'BLUEPRINT WIREFRAME',
                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Tọa độ: y ≤ 870px',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF8A8372), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  meta.visualLayoutDescription,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF26323D),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                const Text(
                  '✓ Chừa vùng trống an toàn > 120px dưới đáy cho phụ đề ASS song ngữ.',
                  style: TextStyle(fontSize: 9.5, color: Color(0xFFB5533C), fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSlotMappingRows(TemplateMeta meta, dynamic c) {
    final sentences = widget.batch.sentences;
    if (sentences.isEmpty) {
      // Dùng dữ liệu scene nếu không có câu tách rời
      final rawSteps = widget.batch.scene['steps'] as List? ?? [];
      if (rawSteps.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Toàn bộ đoạn thoại: "${widget.batch.transcriptTranslated.isNotEmpty ? widget.batch.transcriptTranslated : widget.batch.transcriptOriginal}"',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
          ),
        ];
      }
      return rawSteps.asMap().entries.map((entry) {
        final idx = entry.key;
        final step = entry.value as Map<String, dynamic>;
        return _buildSlotRow(
          slotNum: idx + 1,
          slotName: _getSlotNameForTemplate(meta.id, idx),
          content: step['label']?.toString() ?? '',
          meta: meta,
          c: c,
        );
      }).toList();
    }

    return sentences.asMap().entries.map((entry) {
      final idx = entry.key;
      final s = entry.value;
      final text = s['text']?.toString() ?? s['text_orig']?.toString() ?? '';
      return _buildSlotRow(
        slotNum: idx + 1,
        slotName: _getSlotNameForTemplate(meta.id, idx),
        content: text,
        meta: meta,
        c: c,
      );
    }).toList();
  }

  String _getSlotNameForTemplate(String templateId, int index) {
    switch (templateId) {
      case 'agent_workflow':
        const names = ['Perception (Nhận thức)', 'Decision (Suy luận)', 'Tool Use (Công cụ)', 'Memory (Bộ nhớ)'];
        return index < names.length ? names[index] : 'Trạm ${index + 1}';
      case 'rag_pipeline':
        const names = ['User Query', 'Embedding Vector', 'Vector Database', 'LLM Response'];
        return index < names.length ? names[index] : 'Trạm ${index + 1}';
      case 'transformer_attention':
        const names = ['Input Tokens', 'Vector Q-K-V', 'Attention Matrix', 'Output Weights'];
        return index < names.length ? names[index] : 'Tầng ${index + 1}';
      case 'neural_net':
        const names = ['Input Layer', 'Hidden Layer 1', 'Hidden Layer 2', 'Output Layer'];
        return index < names.length ? names[index] : 'Tầng ${index + 1}';
      case 'algo_array':
        const names = ['Khởi tạo Mảng & Pointer', 'Bước duyệt / So sánh', 'Cập nhật chỉ số', 'Điều kiện dừng'];
        return index < names.length ? names[index] : 'Bước ${index + 1}';
      case 'compare_two':
        return index % 2 == 0 ? 'Cột Trái (Ưu điểm / Phái A)' : 'Cột Phải (Nhược điểm / Phái B)';
      case 'definition':
        return index == 0 ? 'Định Nghĩa Cốt Lõi' : 'Luận Điểm Chi Tiết $index';
      default:
        return 'Bước ${index + 1}';
    }
  }

  Widget _buildSlotRow({
    required int slotNum,
    required String slotName,
    required String content,
    required TemplateMeta meta,
    required dynamic c,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.surfaceLight.withOpacity(0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: meta.accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: meta.accentColor.withOpacity(0.4)),
            ),
            child: Text(
              'SLOT $slotNum',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: meta.accentColor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slotName,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  content,
                  style: TextStyle(fontSize: 11, color: c.textSecondary, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
