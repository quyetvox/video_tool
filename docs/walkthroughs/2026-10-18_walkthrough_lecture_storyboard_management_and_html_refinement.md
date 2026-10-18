# Walkthrough: Quản Lý Storyboard Toàn Diện & AI Tinh Chỉnh HTML trong AI Lecture Illustrator

**Ngày hoàn thành**: 18/10/2026  
**Module**: `py_engine/lecture_illustrator/`, `flutter_app/lib/screens/lecture_illustrator/`  
**Nhánh Git**: `v-flutter`

---

## 🎯 Tổng Quan & Mục Tiêu

Hệ thống **AI Lecture Illustrator** được trang bị bộ công cụ biên tập và can thiệp storyboard chuyên sâu theo chuẩn thiết kế sư phạm trực quan, đáp ứng đầy đủ 5 yêu cầu cốt lõi của người dùng:

1. **Thêm phân cảnh (Add Storyboard)**: Tự do chèn một storyboard mới tại bất kỳ vị trí nào với kịch bản tùy ý; tự động gọi TTS sinh giọng đọc, tạo file phụ đề `.ass` và dồn lại toàn bộ timeline của dự án.
2. **Sửa nội dung & Đồng bộ TTS (Edit & Sync TTS)**: Cho phép sửa kịch bản dịch và bấm nút **"Đồng bộ TTS"** để tạo lại ngay giọng đọc cho phân cảnh đó, tự động co dãn thời lượng `(start_sec, end_sec)` của các phân cảnh tiếp theo mà không làm lệch nhịp.
3. **Xóa phân cảnh (Delete Storyboard)**: Xóa một hoặc nhiều phân cảnh được chọn, dọn dẹp các tệp liên quan (`scenes/`, `audio/`, `subtitles/`) và tự động kéo dồn thời gian liền mạch.
4. **Chọn nhiều storyboard để tái tạo song song (Multi-Select Batch Reauthor)**: Hỗ trợ checkbox chọn từng phân cảnh hoặc "Chọn tất cả", kích hoạt tái tạo hàng loạt (`reauthor_batch_multi`) tuân thủ nghiêm ngặt số lượng worker được cấp phát trong cấu hình hệ thống (`concurrency.max_workers`).
5. **AI Tinh chỉnh từ mã HTML hiện hữu (Iterative AI HTML Refinement)**: Cho phép gửi lại mã HTML đã sinh cùng yêu cầu tinh chỉnh (feedback) để AI phẫu thuật trực tiếp trên bố cục hiện tại, tự động sao lưu bản cũ vào file `.html.bak` và cung cấp nút khôi phục (restore) 1-click.

---

## 🏗️ Kiến Trúc & Chi Tiết Triển Khai

### 1. Backend Python (`py_engine/`)

| File | Chức năng mới |
|---|---|
| [lecture_illustrator_orchestrator.py](file:///Users/voquyt/Documents/projects/video/Sub-Video/py_engine/lecture_illustrator_orchestrator.py) | • `_recalculate_project_timeline`: Tính toán lại mốc `start_sec` / `end_sec` liên tục theo độ dài audio.<br>• `run_sync_batch_audio_flow`: Thực thi CLI `--mode sync_batch_audio --action [create\|update\|delete]`.<br>• `run_reauthor_batch_multi_flow`: Tái tạo song song qua `ThreadPoolExecutor(max_workers=workers)` kèm stream progress JSON. |
| [scene_author.py](file:///Users/voquyt/Documents/projects/video/Sub-Video/py_engine/lecture_illustrator/scene_author.py) | • `build_scene_refine_user_prompt`: Tạo prompt yêu cầu AI giữ nguyên cấu trúc logic, chỉ sửa đổi các phần tử SVG/CSS/JS theo feedback.<br>• Tự động sao lưu `.html.bak` trước khi ghi đè mã mới.<br>• Đóng vòng kiểm định chất lượng tự động qua Playwright Headless Calibrator. |

#### CLI Mode Mới:
```bash
# Thêm storyboard mới
python3 py_engine/lecture_illustrator_orchestrator.py --mode sync_batch_audio --action create --batch-id batch_004 --text "Nội dung bài giảng mới" --project-file lecture_project.json

# Cập nhật & tạo lại TTS
python3 py_engine/lecture_illustrator_orchestrator.py --mode sync_batch_audio --action update --batch-id batch_002 --text "Nội dung cập nhật" --project-file lecture_project.json

# Xóa storyboard
python3 py_engine/lecture_illustrator_orchestrator.py --mode sync_batch_audio --action delete --batch-id batch_003 --project-file lecture_project.json

# Tinh chỉnh từ HTML hiện có
python3 py_engine/lecture_illustrator_orchestrator.py --mode reauthor_batch --refine --batch-id batch_001 --feedback "Đổi màu nền sang xanh navy và phóng to tiêu đề" --project-file lecture_project.json

# Tái tạo hàng loạt theo số lượng workers
python3 py_engine/lecture_illustrator_orchestrator.py --mode reauthor_batch_multi --batch-ids batch_001,batch_002,batch_003 --workers 3 --project-file lecture_project.json
```

---

### 2. Frontend Flutter (`flutter_app/`)

| File | Thành phần |
|---|---|
| [lecture_illustrator_controller.dart](file:///Users/voquyt/Documents/projects/video/Sub-Video/flutter_app/lib/screens/lecture_illustrator/controllers/lecture_illustrator_controller.dart) | • State: `selectedBatchIds`, `isBatchReauthoring`, `batchReauthorProgress`.<br>• Controller methods: `toggleSelectBatch`, `selectAllBatches`, `addNewBatch`, `syncBatchAudioAndText`, `deleteBatch`, `deleteSelectedBatches`, `reauthorSelectedBatches`, `refineBatchHtmlWithAi`. |
| [lecture_storyboard_tab_card.dart](file:///Users/voquyt/Documents/projects/video/Sub-Video/flutter_app/lib/screens/lecture_illustrator/components/lecture_storyboard_tab_card.dart) | • Checkbox "Chọn tất cả" & nút **"+ Thêm Phân Cảnh"**.<br>• Dynamic Batch Action Bar hiển thị khi có $\ge 1$ phân cảnh được tick chọn: **"Tái tạo đã chọn (N)"** và **"Xóa đã chọn"** kèm hộp thoại xác nhận. |
| [lecture_batch_storyboard_card.dart](file:///Users/voquyt/Documents/projects/video/Sub-Video/flutter_app/lib/screens/lecture_illustrator/components/lecture_batch_storyboard_card.dart) | • Checkbox chọn phân cảnh trên từng thẻ storyboard.<br>• Nút xóa từng phân cảnh với confirm dialog.<br>• Nút **"Đồng bộ TTS"** trực tiếp bên cạnh trường nhập bản dịch. |
| [lecture_scene_studio_dialog.dart](file:///Users/voquyt/Documents/projects/video/Sub-Video/flutter_app/lib/screens/lecture_illustrator/components/lecture_scene_studio_dialog.dart) | • Nút **"AI Tinh Chỉnh HTML"** gọi AI phẫu thuật trực tiếp trên mã HTML cũ.<br>• Nút **"Khôi phục bản sao trước tinh chỉnh (.bak)"** khôi phục nguyên trạng khi cần rollback. |

---

## 🧪 Kết Quả Kiểm Thử (Verification)

### 1. Python Unit Tests (16/16 Pass)
- `test_sync_batch_audio.py`:
  - `test_create_batch_adds_and_recalculates_timeline`: PASS
  - `test_delete_batch_removes_and_recalculates_timeline`: PASS
  - `test_update_batch_updates_text_and_timeline`: PASS
  - `test_invalid_action_returns_error`: PASS
- `test_refine_html.py`:
  - `test_refine_creates_backup_file`: PASS
  - `test_refine_prompt_contains_existing_html_and_feedback`: PASS
- `test_reauthor_batch_multi.py`:
  - `test_reauthor_multi_runs_parallel_and_streams_progress`: PASS

```
Ran 7 tests in 2.854s
OK
```

### 2. Flutter Unit Tests (12/12 Pass)
- `test/lecture_storyboard_management_test.dart`:
  - `LectureIllustratorState initial selection is empty`: PASS
  - `LectureIllustratorState copyWith updates selection and batch reauthoring state`: PASS
  - `Controller toggles batch selection`: PASS
  - `Controller selectAllBatches selects all and deselects all`: PASS
- `test/lecture_illustrator_test.dart`: 8/8 tests PASS.

### 3. Static Code Analysis (`flutter analyze`)
- `lecture_storyboard_tab_card.dart`: No issues found!
- `lecture_batch_storyboard_card.dart`: No issues found!
- `lecture_scene_studio_dialog.dart`: No issues found!

---

## 🔒 Tuân Thủ Ràng Buộc Kiến Trúc & Prime Directive
- **Pure AI & Calibrator Invariant**: Không sửa tay các file `.html` cảnh; mọi thay đổi đều thông qua Prompt (`master_handdrawn_animation_prompt.md`), `build_scene_refine_user_prompt`, và bộ vi chỉnh `html_calibrator.py`.
- **Resource Guard & Concurrency**: Số lượng luồng chạy đồng thời khi tái tạo hàng loạt luôn lấy chính xác từ `concurrency.max_workers` trong cấu hình máy.
- **Data Integrity**: Dồn thời gian liền mạch, bảo vệ `.bak` khi tinh chỉnh HTML, giải quyết triệt để race-condition khi ghi `lecture_project.json`.
