use hound::{WavReader, WavSpec, WavWriter};
use rustfft::{num_complex::Complex, FftPlanner};
use std::f32::consts::PI;
use std::path::Path;

/// Applies Spectral Noise Gating to suppress ghost vocal residues and background hiss in WAV audio.
pub fn apply_spectral_gate<P: AsRef<Path>>(
    input_path: P,
    output_path: P,
    prop_decrease: f32,
) -> Result<bool, String> {
    let mut reader = WavReader::open(input_path.as_ref())
        .map_err(|e| format!("Failed to open input WAV: {}", e))?;
    let spec = reader.spec();

    let channels = spec.channels as usize;
    let sample_rate = spec.sample_rate as usize;
    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => {
            let max_val = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .samples::<i32>()
                .map(|s| s.unwrap_or(0) as f32 / max_val)
                .collect()
        }
        hound::SampleFormat::Float => reader.samples::<f32>().map(|s| s.unwrap_or(0.0)).collect(),
    };

    if samples.is_empty() {
        return Ok(false);
    }

    let total_frames = samples.len() / channels;
    let mut processed_channels: Vec<Vec<f32>> = Vec::with_capacity(channels);

    // Process each audio channel independently
    for ch in 0..channels {
        let ch_samples: Vec<f32> = (0..total_frames)
            .map(|i| samples[i * channels + ch])
            .collect();

        let cleaned = process_channel_stft(&ch_samples, sample_rate, prop_decrease);
        processed_channels.push(cleaned);
    }

    // Interleave channels and write output WAV
    let out_spec = WavSpec {
        channels: spec.channels,
        sample_rate: spec.sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = WavWriter::create(output_path.as_ref(), out_spec)
        .map_err(|e| format!("Failed to create output WAV: {}", e))?;

    for i in 0..total_frames {
        for ch in 0..channels {
            let s = processed_channels[ch][i].clamp(-1.0, 1.0);
            let sample_i16 = (s * 32767.0).round() as i16;
            writer
                .write_sample(sample_i16)
                .map_err(|e| format!("WAV write error: {}", e))?;
        }
    }

    writer.finalize().map_err(|e| format!("WAV finalize error: {}", e))?;
    Ok(true)
}

fn process_channel_stft(samples: &[f32], sample_rate: usize, prop_decrease: f32) -> Vec<f32> {
    let fft_size = 2048;
    let hop_size = 512;
    let n_samples = samples.len();

    if n_samples < fft_size {
        return samples.to_vec();
    }

    // 1. Noise profile estimation from first 0.5s of audio
    let noise_frames = (sample_rate / 2).min(n_samples);
    let mut noise_mag_avg = vec![0.0f32; fft_size / 2 + 1];
    let mut noise_hops = 0;

    let mut planner = FftPlanner::new();
    let fft_forward = planner.plan_fft_forward(fft_size);
    let fft_inverse = planner.plan_fft_inverse(fft_size);

    let window: Vec<f32> = (0..fft_size)
        .map(|i| 0.5 * (1.0 - (2.0 * PI * i as f32 / fft_size as f32).cos()))
        .collect();

    let mut pos = 0;
    while pos + fft_size <= noise_frames {
        let mut buffer: Vec<Complex<f32>> = (0..fft_size)
            .map(|i| Complex::new(samples[pos + i] * window[i], 0.0))
            .collect();
        fft_forward.process(&mut buffer);

        for k in 0..=fft_size / 2 {
            noise_mag_avg[k] += buffer[k].norm();
        }
        noise_hops += 1;
        pos += hop_size;
    }

    if noise_hops > 0 {
        for k in 0..=fft_size / 2 {
            noise_mag_avg[k] /= noise_hops as f32;
        }
    }

    // 2. STFT processing with Spectral Gate
    let mut output = vec![0.0f32; n_samples + fft_size];
    let mut window_sum = vec![0.0f32; n_samples + fft_size];

    pos = 0;
    while pos + fft_size <= n_samples {
        let mut buffer: Vec<Complex<f32>> = (0..fft_size)
            .map(|i| Complex::new(samples[pos + i] * window[i], 0.0))
            .collect();
        fft_forward.process(&mut buffer);

        // Apply spectral subtraction / gating
        for k in 0..=fft_size / 2 {
            let mag = buffer[k].norm();
            let phase = buffer[k].arg();

            let noise_thresh = noise_mag_avg[k] * 1.5;
            let mut gain = if mag > noise_thresh {
                (1.0 - (noise_thresh / (mag + 1e-12)).powi(2)).max(0.0).sqrt()
            } else {
                1.0 - prop_decrease
            };
            gain = gain.clamp(1.0 - prop_decrease, 1.0);

            let new_mag = mag * gain;
            buffer[k] = Complex::from_polar(new_mag, phase);

            // Mirror conjugate for inverse FFT
            if k > 0 && k < fft_size / 2 {
                buffer[fft_size - k] = buffer[k].conj();
            }
        }

        fft_inverse.process(&mut buffer);

        for i in 0..fft_size {
            output[pos + i] += (buffer[i].re / fft_size as f32) * window[i];
            window_sum[pos + i] += window[i] * window[i];
        }

        pos += hop_size;
    }

    // Normalize overlap-add
    let mut result = vec![0.0f32; n_samples];
    for i in 0..n_samples {
        if window_sum[i] > 1e-6 {
            result[i] = output[i] / window_sum[i];
        } else {
            result[i] = samples[i];
        }
    }

    result
}
