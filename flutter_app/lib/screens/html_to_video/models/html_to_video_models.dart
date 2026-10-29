import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chế độ nguồn âm thanh & phụ đề thông minh trong HTML to MP4 Studio
enum HtmlAudioSourceMode {
  /// Tự động tạo giọng đọc TTS & phụ đề đồng bộ từ file kịch bản (.txt / .md)
  autoScript,

  /// Ghép file Audio (.mp3 / .wav) và/hoặc Phụ đề (.ass / .srt) có sẵn
  manualAudio,

  /// Chỉ xuất hình ảnh hoạt họa HTML thuần túy (không âm thanh)
  videoOnly,
}

/// Dữ liệu nối tắt 1-Click gửi từ tab Tạo Giọng Đọc (TTS Studio) sang HTML to MP4
class HtmlToVideoPreset {
  final HtmlAudioSourceMode mode;
  final String? scriptPath;
  final String? audioPath;
  final String? assPath;
  final String? voice;
  final double? durationSec;

  const HtmlToVideoPreset({
    required this.mode,
    this.scriptPath,
    this.audioPath,
    this.assPath,
    this.voice,
    this.durationSec,
  });
}

/// Provider lưu preset chuyển giao giữa TTS Studio và HTML to MP4 Studio
final htmlToVideoPresetProvider = StateProvider<HtmlToVideoPreset?>((ref) => null);

const Map<String, List<int>> kHtmlResolutionPresets = {
  '1080p Ngang (1920x1080 - YouTube/TV)': [1920, 1080],
  '720p Ngang (1280x720 - HD Nhanh)': [1280, 720],
  '1080p Dọc (1080x1920 - TikTok/Reels/Shorts)': [1080, 1920],
  '720p Dọc (720x1280 - Shorts Nhanh)': [720, 1280],
  'Vuông (1080x1080 - Facebook/Post)': [1080, 1080],
  '2K QHD (2560x1440 - Siêu Nét)': [2560, 1440],
};

const Map<String, String> kHtmlVoicePresets = {
  '🇻🇳 Ban Mai (vi-VN-BanMai - Nữ phổ thông Google)': 'vi-VN-BanMai',
  '🇻🇳 Hoài My (vi-VN-HoaiMyNeural - Nữ truyền cảm)': 'vi-VN-HoaiMyNeural',
  '🇻🇳 Nam Minh (vi-VN-NamMinhNeural - Nam trầm ấm)': 'vi-VN-NamMinhNeural',
  '🇺🇸 Jenny (en-US-JennyNeural - Nữ Tiếng Anh Mỹ)': 'en-US-JennyNeural',
  '🇺🇸 Guy (en-US-GuyNeural - Nam Tiếng Anh Mỹ)': 'en-US-GuyNeural',
  '🇺🇸 Aria (en-US-AriaNeural - Nữ dẫn chuyện Mỹ)': 'en-US-AriaNeural',
  '🇺🇸 Christopher (en-US-ChristopherNeural - Nam trầm Mỹ)': 'en-US-ChristopherNeural',
  '🇬🇧 Sonia (en-GB-SoniaNeural - Nữ Tiếng Anh UK)': 'en-GB-SoniaNeural',
  '🇬🇧 Ryan (en-GB-RyanNeural - Nam Tiếng Anh UK)': 'en-GB-RyanNeural',
  '🇦🇺 Natasha (en-AU-NatashaNeural - Nữ Tiếng Anh Úc)': 'en-AU-NatashaNeural',
  '🇦🇺 William (en-AU-WilliamNeural - Nam Tiếng Anh Úc)': 'en-AU-WilliamNeural',
  '🇨🇳 Xiaoxiao (zh-CN-XiaoxiaoNeural - Nữ Tiếng Trung)': 'zh-CN-XiaoxiaoNeural',
  '🇨🇳 Yunxi (zh-CN-YunxiNeural - Nam Tiếng Trung)': 'zh-CN-YunxiNeural',
};

const Map<String, String> kHtmlSecondaryVoicePresets = {
  'Không dùng (Đơn giọng)': '',
  '🇻🇳 Ban Mai (vi-VN-BanMai - Nữ phổ thông Google)': 'vi-VN-BanMai',
  '🇻🇳 Nam Minh (vi-VN-NamMinhNeural - Nam)': 'vi-VN-NamMinhNeural',
  '🇻🇳 Hoài My (vi-VN-HoaiMyNeural - Nữ)': 'vi-VN-HoaiMyNeural',
  '🇺🇸 Guy (en-US-GuyNeural - Nam Tiếng Anh)': 'en-US-GuyNeural',
  '🇺🇸 Jenny (en-US-JennyNeural - Nữ Tiếng Anh)': 'en-US-JennyNeural',
};

const List<String> kHtmlFontPresets = [
  'Arial',
  'Helvetica Neue',
  'Montserrat',
  'Roboto',
  'Inter',
  'Times New Roman',
  'Georgia',
  'Courier New',
];

const Map<String, String> kHtmlWorkerPresets = {
  'Tự động (Auto theo độ dài & CPU)': '0',
  '1 luồng (Tuần tự - Ít tốn RAM)': '1',
  '2 luồng (Cân bằng - Nhanh x2)': '2',
  '4 luồng (Tốc độ cao - Nhanh x3.5)': '4',
  '6 luồng (Đa nhân M-Series/i7)': '6',
  '8 luồng (Tối đa hiệu năng)': '8',
};

