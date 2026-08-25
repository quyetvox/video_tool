pub mod gender_detect;
pub mod spectral_gate;
pub mod vad;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// C ABI: Apply spectral noise gate to suppress ghost vocal residues.
/// Returns 1 on success, 0 on failure.
#[no_mangle]
pub extern "C" fn audio_dsp_apply_spectral_gate(
    input_path: *const c_char,
    output_path: *const c_char,
    prop_decrease: f32,
) -> i32 {
    if input_path.is_null() || output_path.is_null() {
        return 0;
    }

    let in_str = match unsafe { CStr::from_ptr(input_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let out_str = match unsafe { CStr::from_ptr(output_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    match spectral_gate::apply_spectral_gate(in_str, out_str, prop_decrease) {
        Ok(true) => 1,
        _ => 0,
    }
}

/// C ABI: Refines subtitle timestamps with VAD energy snapping.
/// Returns a pointer to a newly allocated JSON string (must be freed with audio_dsp_free_string).
#[no_mangle]
pub extern "C" fn audio_dsp_refine_timestamps(
    audio_path: *const c_char,
    segments_json: *const c_char,
) -> *mut c_char {
    if audio_path.is_null() || segments_json.is_null() {
        return std::ptr::null_mut();
    }

    let aud_str = match unsafe { CStr::from_ptr(audio_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    let json_str = match unsafe { CStr::from_ptr(segments_json) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let mut segments: Vec<vad::SubtitleSegment> = match serde_json::from_str(json_str) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    if vad::refine_timestamps(aud_str, &mut segments).is_err() {
        return std::ptr::null_mut();
    }

    let result_json = match serde_json::to_string(&segments) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    match CString::new(result_json) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// C ABI: Estimates voice gender for segment.
/// Returns "male", "female", or "unknown" (must be freed with audio_dsp_free_string).
#[no_mangle]
pub extern "C" fn audio_dsp_estimate_gender(
    audio_path: *const c_char,
    start_sec: f64,
    end_sec: f64,
) -> *mut c_char {
    if audio_path.is_null() {
        return std::ptr::null_mut();
    }

    let aud_str = match unsafe { CStr::from_ptr(audio_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let gender = gender_detect::estimate_segment_f0(aud_str, start_sec, end_sec, 70.0, 350.0, 165.0);

    match CString::new(gender) {
        Ok(c_str) => c_str.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// C ABI: Frees a string previously allocated by Rust.
#[no_mangle]
pub extern "C" fn audio_dsp_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_free_null() {
        audio_dsp_free_string(std::ptr::null_mut());
    }
}
