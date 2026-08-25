use hound::WavReader;
use rustfft::{num_complex::Complex, FftPlanner};
use std::path::Path;

/// Pitch (Fundamental Frequency F0) Gender Estimator.
/// Uses autocorrelation via FFT on audio segments.
pub fn estimate_segment_f0<P: AsRef<Path>>(
    audio_path: P,
    start_sec: f64,
    end_sec: f64,
    fmin: f64,
    fmax: f64,
    gender_threshold_hz: f64,
) -> String {
    let mut reader = match WavReader::open(audio_path.as_ref()) {
        Ok(r) => r,
        Err(_) => return "unknown".to_string(),
    };

    let spec = reader.spec();
    let sr = spec.sample_rate as f64;
    let channels = spec.channels as usize;
    let total_frames = reader.duration() as f64;

    if start_sec >= total_frames / sr || end_sec <= start_sec {
        return "unknown".to_string();
    }

    let start_frame = (start_sec.max(0.0) * sr) as usize;
    let num_frames = (((end_sec - start_sec).min(total_frames / sr - start_sec)) * sr) as usize;

    if num_frames < (sr * 0.1) as usize {
        return "unknown".to_string();
    }

    let raw_samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => {
            let max_val = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .skip(start_frame * channels)
                .take(num_frames * channels)
                .map(|s| s.unwrap_or(0) as f32 / max_val)
                .collect()
        }
        hound::SampleFormat::Float => reader
            .samples::<f32>()
            .skip(start_frame * channels)
            .take(num_frames * channels)
            .map(|s| s.unwrap_or(0.0))
            .collect(),
    };

    let actual_frames = raw_samples.len() / channels;
    if actual_frames < (sr * 0.1) as usize {
        return "unknown".to_string();
    }

    // Convert to Mono
    let mut mono = vec![0.0f32; actual_frames];
    for i in 0..actual_frames {
        let mut sum = 0.0f32;
        for ch in 0..channels {
            sum += raw_samples[i * channels + ch];
        }
        mono[i] = sum / channels as f32;
    }

    let min_tau = (sr / fmax) as usize;
    let max_tau = (sr / fmin) as usize;
    let frame_len = (sr * 0.04) as usize; // 40ms frame
    let hop = (sr * 0.02) as usize; // 20ms hop

    let mut f0_list = Vec::new();
    let mut planner = FftPlanner::new();
    let fft_size = (frame_len * 2).next_power_of_two();
    let fft_forward = planner.plan_fft_forward(fft_size);
    let fft_inverse = planner.plan_fft_inverse(fft_size);

    let mut pos = 0;
    while pos + frame_len <= actual_frames {
        let frame = &mono[pos..pos + frame_len];

        // Std dev check
        let mean: f32 = frame.iter().sum::<f32>() / frame_len as f32;
        let var: f32 = frame.iter().map(|&x| (x - mean) * (x - mean)).sum::<f32>() / frame_len as f32;
        let std_dev = var.sqrt();

        if std_dev >= 0.01 {
            // Autocorrelation via FFT
            let mut buf = vec![Complex::new(0.0f32, 0.0f32); fft_size];
            for i in 0..frame_len {
                buf[i] = Complex::new(frame[i] - mean, 0.0);
            }
            fft_forward.process(&mut buf);

            for c in buf.iter_mut() {
                *c = Complex::new(c.norm_sqr(), 0.0);
            }
            fft_inverse.process(&mut buf);

            let corr_0 = buf[0].re;
            if corr_0 > 0.0 && max_tau < fft_size {
                let mut peak_tau = min_tau;
                let mut peak_val = buf[min_tau].re;

                for tau in min_tau + 1..=max_tau.min(fft_size - 1) {
                    if buf[tau].re > peak_val {
                        peak_val = buf[tau].re;
                        peak_tau = tau;
                    }
                }

                if peak_val / corr_0 > 0.35 {
                    let f0 = sr / peak_tau as f64;
                    if f0 >= fmin && f0 <= fmax {
                        f0_list.push(f0);
                    }
                }
            }
        }

        pos += hop;
    }

    if f0_list.len() < 2 {
        return "unknown".to_string();
    }

    f0_list.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let median_f0 = f0_list[f0_list.len() / 2];

    if median_f0 < gender_threshold_hz {
        "male".to_string()
    } else {
        "female".to_string()
    }
}
