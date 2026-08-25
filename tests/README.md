# Sub-Video Global Test Suite & Fixtures

Thư mục `tests/` cấp root là nơi lưu trữ **dữ liệu fixtures dùng chung** và các **bài kiểm thử tích hợp (integration / E2E tests)** giữa các module.

---

## 📂 1. Cấu Trúc Kiểm Thử Phân Tách Theo Module

```
Sub-Video/
├── 🧪 tests/                    # Global Fixtures & Cross-Module Integration Tests
│   ├── fixtures/               # Dữ liệu mẫu (Synthetic MP4, WAV mocks, JSON mock)
│   ├── integration/            # Test tích hợp End-to-End giữa các module
│   └── README.md
│
├── ⚡ video_engine/test/        # Unit tests của Native Dart Engine (17+ test cases)
├── 🐍 py_engine/tests/          # Unit tests của Python Engine (Demucs, MLX, pipeline)
├── 🦀 rust_native/tests/        # Unit tests của Rust Audio DSP & Swift OCR
└── 📱 flutter_app/test/         # Unit & Widget tests của Flutter Desktop UI
```

---

## 📌 2. Nguyên Tắc Quản Lý Test
1. **Không lưu trữ file media/data nặng bên trong module**: Toàn bộ audio/video mock được tạo động (synthetic via ffmpeg) hoặc đặt trong `tests/fixtures/`.
2. **Module Unit Tests**: Chỉ chứa test case code logic của riêng module đó.
3. **Chạy toàn bộ kiểm thử**:
   - `cd video_engine && dart test`
   - `.venv/bin/python -m unittest discover py_engine/tests`
   - `cd flutter_app && flutter test`
