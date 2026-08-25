use hound::WavReader;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SubtitleSegment {
    #[serde(default)]
    pub id: Option<serde_json::Value>,
    pub start: f64,
    pub end: f64,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// Voice Activity Detector & Timestamp Refiner.
/// Snaps ASR timestamps precisely to actual voice energy onset/offsets.
pub fn refine_timestamps<P: AsRef<Path>>(
    audio_path: P,
    segments: &mut [SubtitleSegment],
) -> Result<(), String> {
    if segments.is_empty() {
        return Ok(());
    }

    let mut reader = WavReader::open(audio_path.as_ref())
        .map_err(|e| format!("Failed to open WAV: {}", e))?;
    let spec = reader.spec();
    let sr = spec.sample_rate as usize;
    let channels = spec.channels as usize;

    let raw_samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => {
            let max_val = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .map(|s| s.unwrap_or(0) as f32 / max_val)
                .collect()
        }
        hound::SampleFormat::Float => reader.samples::<f32>().map(|s| s.unwrap_or(0.0)).collect(),
    };

    if raw_samples.is_empty() {
        return Ok(());
    }

    // Convert to Mono
    let total_frames = raw_samples.len() / channels;
    let mut mono_samples = vec![0.0f32; total_frames];
    for i in 0..total_frames {
        let mut sum = 0.0f32;
        for ch in 0..channels {
            sum += raw_samples[i * channels + ch];
        }
        mono_samples[i] = sum / channels as f32;
    }

    let total_duration = total_frames as f64 / sr as f64;
    let frame_ms = 20.0;
    let frame_len = (sr as f64 * (frame_ms / 1000.0)) as usize;
    if frame_len == 0 || total_frames < frame_len {
        return Ok(());
    }

    // Calculate RMS energies across 20ms windows
    let hop_step = (total_frames / (frame_len * 500)).max(1);
    let mut frame_energies = Vec::new();
    let mut i = 0;
    while i + frame_len <= total_frames {
        let chunk = &mono_samples[i..i + frame_len];
        let sum_sq: f32 = chunk.iter().map(|&x| x * x).sum();
        let rms = (sum_sq / frame_len as f32 + 1e-12).sqrt();
        frame_energies.push(rms);
        i += frame_len * hop_step;
    }

    frame_energies.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let p15_idx = (frame_energies.len() as f64 * 0.15) as usize;
    let global_noise_floor = if !frame_energies.is_empty() {
        frame_energies[p15_idx.min(frame_energies.len() - 1)]
    } else {
        0.001
    };

    let speech_threshold = (global_noise_floor * 3.5).max(0.005);
    let mut prev_end = 0.0f64;

    for seg in segments.iter_mut() {
        let orig_s = seg.start;
        let orig_e = seg.end;
        let mut s_time = orig_s;
        let mut e_time = orig_e;

        // 1. Onset Search
        let search_s_time = (prev_end + 0.05).max(s_time - 0.8);
        let start_sample = (search_s_time.max(0.0) * sr as f64) as usize;
        let end_sample = ((s_time + 3.0).min(total_duration) * sr as f64) as usize;

        if start_sample < end_sample && (end_sample - start_sample) >= frame_len {
            let mut idx = start_sample;
            while idx + frame_len <= end_sample {
                let chunk = &mono_samples[idx..idx + frame_len];
                let sum_sq: f32 = chunk.iter().map(|&x| x * x).sum();
                let rms = (sum_sq / frame_len as f32 + 1e-12).sqrt();
                if rms >= speech_threshold {
                    let detected_sec = idx as f64 / sr as f64;
                    if detected_sec < s_time - 0.05 {
                        s_time = search_s_time.max(detected_sec - 0.05);
                    } else if detected_sec > s_time + 0.15 {
                        s_time = orig_s.max(detected_sec - 0.05);
                    }
                    break;
                }
                idx += frame_len / 2;
            }
        }

        // 2. Offset Search
        let tail_start = ((s_time + 0.2).max(e_time - 2.5).max(0.0) * sr as f64) as usize;
        let tail_end = ((e_time + 0.5).min(total_duration) * sr as f64) as usize;

        if tail_start < tail_end && (tail_end - tail_start) >= frame_len {
            let mut idx = tail_end - frame_len;
            while idx >= tail_start {
                let chunk = &mono_samples[idx..idx + frame_len];
                let sum_sq: f32 = chunk.iter().map(|&x| x * x).sum();
                let rms = (sum_sq / frame_len as f32 + 1e-12).sqrt();
                if rms >= speech_threshold {
                    let detected_offset = (idx + frame_len) as f64 / sr as f64;
                    if e_time - detected_offset >= 0.3 {
                        e_time = orig_e.min((s_time + 0.3).max(detected_offset + 0.08));
                    }
                    break;
                }
                if idx < frame_len / 2 {
                    break;
                }
                idx -= frame_len / 2;
            }
        }

        seg.start = (s_time * 1000.0).round() / 1000.0;
        seg.end = ((s_time + 0.2).max(e_time) * 1000.0).round() / 1000.0;
        prev_end = seg.end;
    }

    Ok(())
}
