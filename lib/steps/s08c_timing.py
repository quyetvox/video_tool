import json
from pathlib import Path
from typing import Any, Dict, List

from core.step_base import StepBase


class StepSubtitleTiming(StepBase):
    """
    s08c — Subtitle Timing Optimizer

    Post-processes s08_translation.json timing to improve readability:

    PASS 1 — Min-duration guarantee:
        ideal_duration = len(text) × char_read_rate
        new_end = max(original_end, start + ideal_duration)

    PASS 2 — Gap fill + hard cap:
        For each segment i (with a next segment i+1):
            cap = start[i+1] - safety_margin
            new_end[i] = min(new_end[i], cap)   # never overlap next segment
            if fill_gap is enabled and gap > 0:
                new_end[i] = cap                 # stretch into available gap

    Rules:
    - start timestamps are NEVER modified
    - end timestamps only move LATER (never earlier)
    - new_end[i] never exceeds start[i+1] - safety_margin
    - last segment: only pass 1 (min-duration guarantee, no cap)

    Config keys:
        subtitle_char_rate    (float, default 0.07): seconds per character
        subtitle_safety_margin (float, default 0.15): gap to leave before next segment
        subtitle_fill_gap     (bool, default True): fill available gap after next-start cap

    Output: s08c_timing.json (same schema as s08_translation.json)
    """

    step_id = "s08c_timing"
    depends_on = ["s08_translation"]
    STEP_CONFIG_KEYS = [
        "subtitle_char_rate",
        "subtitle_safety_margin",
        "subtitle_fill_gap",
        "subtitle_max_gap_fill",
    ]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        trans_info = job_state.get_step_output("s08_translation") or {}
        trans_file_str = trans_info.get("translation_file", "")
        if trans_file_str and Path(trans_file_str).exists():
            trans_file = Path(trans_file_str)
        else:
            # Fallback: look for s08_translation.json directly in workspace
            trans_file = workspace / "s08_translation.json"
            if not trans_file.exists():
                raise FileNotFoundError(
                    f"s08_translation.json not found in {workspace}. "
                    "Please run s08_translation step first."
                )

        with open(trans_file, "r", encoding="utf-8") as f:
            segments: List[Dict] = json.load(f)

        char_rate: float = float(config.get("subtitle_char_rate", 0.07))
        safety_margin: float = float(config.get("subtitle_safety_margin", 0.15))
        fill_gap: bool = bool(config.get("subtitle_fill_gap", True))
        max_gap_fill: float = float(config.get("subtitle_max_gap_fill", 0.8))

        optimized = self._optimize(segments, char_rate, safety_margin, fill_gap, max_gap_fill)

        out_file = workspace / "s08c_timing.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(optimized, f, ensure_ascii=False, indent=2)

        changed = sum(
            1 for orig, opt in zip(segments, optimized)
            if round(orig.get("end", 0), 3) != round(opt.get("end", 0), 3)
        )

        return {
            "timing_file": str(out_file),
            "segment_count": len(optimized),
            "segments_adjusted": changed,
            "char_rate": char_rate,
            "safety_margin": safety_margin,
            "fill_gap": fill_gap,
            "max_gap_fill": max_gap_fill,
        }

    # ------------------------------------------------------------------
    # Core algorithm
    # ------------------------------------------------------------------

    def _optimize(
        self,
        segments: List[Dict],
        char_rate: float,
        safety_margin: float,
        fill_gap: bool,
        max_gap_fill: float = 0.8,
    ) -> List[Dict]:
        import copy
        result = copy.deepcopy(segments)
        n = len(result)

        if n == 0:
            return result

        for i in range(n):
            cur = result[i]
            original_end = float(cur["end"])
            start = float(cur.get("start", 0.0))
            text = cur.get("translated_text") or cur.get("text_vi") or cur.get("text") or ""
            ideal_end = start + max(1.2, len(text) * char_rate)

            # Determine ceiling
            if i < n - 1:
                next_start = float(result[i + 1].get("start", 0.0))
                cap = next_start - safety_margin
                gap = next_start - original_end
            else:
                cap = None  # last segment: no ceiling
                gap = None

            if cap is not None and original_end >= cap:
                # Source gap is too tight — no room to adjust, keep original
                cur["end"] = original_end
                continue

            # There is room to work with (original_end < cap or last segment)
            if fill_gap and cap is not None:
                # If gap to next speech is <= max_gap_fill (e.g. 0.8s): fill the gap seamlessly
                # If gap is > max_gap_fill (pause or scene transition): only extend up to ideal read duration,
                # letting subtitle disappear naturally so it doesn't bleed into the next scene.
                if gap is not None and gap <= max_gap_fill:
                    candidate = cap
                else:
                    candidate = min(ideal_end, cap) if cap is not None else ideal_end
            else:
                candidate = ideal_end    # only apply min-duration

            # Apply: never shrink below original, cap at ceiling
            new_end = max(original_end, candidate)
            if cap is not None:
                new_end = min(new_end, cap)
            cur["end"] = round(new_end, 3)

        return result
