import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

// C function signatures
typedef _ApplySpectralGateC = Int32 Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  Float propDecrease,
);
typedef _ApplySpectralGateDart = int Function(
  Pointer<Utf8> inputPath,
  Pointer<Utf8> outputPath,
  double propDecrease,
);

typedef _RefineTimestampsC = Pointer<Utf8> Function(
  Pointer<Utf8> audioPath,
  Pointer<Utf8> segmentsJson,
);
typedef _RefineTimestampsDart = Pointer<Utf8> Function(
  Pointer<Utf8> audioPath,
  Pointer<Utf8> segmentsJson,
);

typedef _EstimateGenderC = Pointer<Utf8> Function(
  Pointer<Utf8> audioPath,
  Double startSec,
  Double endSec,
);
typedef _EstimateGenderDart = Pointer<Utf8> Function(
  Pointer<Utf8> audioPath,
  double startSec,
  double endSec,
);

typedef _FreeStringC = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Dart FFI Wrapper for libsub_video_audio_dsp.
class AudioDspBindings {
  static DynamicLibrary? _lib;
  static bool _isInitialized = false;

  static late final _ApplySpectralGateDart _applySpectralGate;
  static late final _RefineTimestampsDart _refineTimestamps;
  static late final _EstimateGenderDart _estimateGender;
  static late final _FreeStringDart _freeString;

  static bool get isAvailable => _isInitialized;

  static void initialize([String? customLibPath]) {
    if (_isInitialized) return;

    final libNames = <String>[];
    if (customLibPath != null) {
      libNames.add(customLibPath);
    }

    if (Platform.isMacOS) {
      libNames.addAll([
        'libsub_video_audio_dsp.dylib',
        p.join(Directory.current.path, 'rust_native', 'target', 'release', 'libsub_video_audio_dsp.dylib'),
        p.join(Directory.current.path, '..', 'rust_native', 'target', 'release', 'libsub_video_audio_dsp.dylib'),
        p.join(Directory.current.path, '..', 'dist', 'engine_patch', 'libsub_video_audio_dsp.dylib'),
        p.join(Directory.current.path, 'dist', 'engine_patch', 'libsub_video_audio_dsp.dylib'),
        p.join(Platform.environment['HOME'] ?? '', 'Library', 'Application Support', 'SubVideo', 'engine', 'libsub_video_audio_dsp.dylib'),
        p.join(File(Platform.resolvedExecutable).parent.path, 'libsub_video_audio_dsp.dylib'),
        p.join(File(Platform.resolvedExecutable).parent.path, '..', 'Frameworks', 'libsub_video_audio_dsp.dylib'),
      ]);
    } else if (Platform.isWindows) {
      libNames.addAll([
        'sub_video_audio_dsp.dll',
        p.join(Directory.current.path, 'rust_native', 'target', 'release', 'sub_video_audio_dsp.dll'),
      ]);
    } else {
      libNames.addAll([
        'libsub_video_audio_dsp.so',
        p.join(Directory.current.path, 'rust_native', 'target', 'release', 'libsub_video_audio_dsp.so'),
      ]);
    }

    for (final path in libNames) {
      try {
        if (path.contains(p.separator) && !File(path).existsSync()) {
          continue;
        }
        _lib = DynamicLibrary.open(path);
        break;
      } catch (_) {}
    }

    if (_lib == null) {
      throw StateError('Could not load native library libsub_video_audio_dsp');
    }

    _applySpectralGate = _lib!.lookupFunction<_ApplySpectralGateC, _ApplySpectralGateDart>('audio_dsp_apply_spectral_gate');
    _refineTimestamps = _lib!.lookupFunction<_RefineTimestampsC, _RefineTimestampsDart>('audio_dsp_refine_timestamps');
    _estimateGender = _lib!.lookupFunction<_EstimateGenderC, _EstimateGenderDart>('audio_dsp_estimate_gender');
    _freeString = _lib!.lookupFunction<_FreeStringC, _FreeStringDart>('audio_dsp_free_string');

    _isInitialized = true;
  }

  /// Applies spectral noise gate to suppress ghost vocal residues.
  static bool applySpectralGate({
    required String inputWav,
    required String outputWav,
    double propDecrease = 0.9,
  }) {
    initialize();
    final inPtr = inputWav.toNativeUtf8();
    final outPtr = outputWav.toNativeUtf8();

    try {
      final res = _applySpectralGate(inPtr, outPtr, propDecrease);
      return res == 1;
    } finally {
      malloc.free(inPtr);
      malloc.free(outPtr);
    }
  }

  /// Refines subtitle segment timestamps with VAD energy snapping.
  static List<Map<String, dynamic>> refineTimestamps({
    required String audioPath,
    required List<Map<String, dynamic>> segments,
  }) {
    if (segments.isEmpty) return [];
    initialize();

    final audPtr = audioPath.toNativeUtf8();
    final jsonPtr = jsonEncode(segments).toNativeUtf8();

    try {
      final outPtr = _refineTimestamps(audPtr, jsonPtr);
      if (outPtr == nullptr) {
        return segments;
      }
      try {
        final outStr = outPtr.toDartString();
        final parsed = jsonDecode(outStr);
        if (parsed is List) {
          return parsed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        return segments;
      } finally {
        _freeString(outPtr);
      }
    } finally {
      malloc.free(audPtr);
      malloc.free(jsonPtr);
    }
  }

  /// Estimates voice gender for segment ("male", "female", "unknown").
  static String estimateGender({
    required String audioPath,
    required double startSec,
    required double endSec,
  }) {
    initialize();
    final audPtr = audioPath.toNativeUtf8();

    try {
      final outPtr = _estimateGender(audPtr, startSec, endSec);
      if (outPtr == nullptr) return 'unknown';
      try {
        return outPtr.toDartString();
      } finally {
        _freeString(outPtr);
      }
    } finally {
      malloc.free(audPtr);
    }
  }
}
