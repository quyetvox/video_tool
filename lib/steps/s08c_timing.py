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

        optimized = self._optimize(segments, char_rate, safety_margin, fill_gap)

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
    ) -> List[Dict]:
        import copy
        result = copy.deepcopy(segments)
        n = len(result)

        if n == 0:
            return result

        # Single-pass optimization:
        #
        # For each segment i:
        #   cap = start[i+1] - safety_margin  (desired ceiling from next segment)
        #   ideal_end = start + char_count × char_rate  (min readable duration)
        #
        # Priority order (highest to lowest):
        #   1. Never shrink original_end  (readability of existing timing)
        #   2. Fill gap up to cap         (when fill_gap=True and room available)
        #   3. Extend to ideal_end        (min-duration guarantee, within cap)
        #
        # If original_end is already >= cap (ultra-tight gap in source data),
        # we keep original_end as-is — the source data is already overlapping
        # and we cannot fix that without moving start (which we don't do).
        for i in range(n):
            cur = result[i]
            original_end = float(cur["end"])
            start = float(cur.get("start", 0.0))
            text = cur.get("text", "") or ""
            ideal_end = start + len(text) * char_rate

            # Determine ceiling
            if i < n - 1:
                next_start = float(result[i + 1].get("start", 0.0))
                cap = next_start - safety_margin
            else:
                cap = None  # last segment: no ceiling

            if cap is not None and original_end >= cap:
                # Source gap is too tight — no room to adjust, keep original
                cur["end"] = original_end
                continue

            # There is room to work with (original_end < cap or last segment)
            if fill_gap and cap is not None:
                candidate = cap          # fill all available gap
            else:
                candidate = ideal_end    # only apply min-duration

            # Apply: never shrink below original, cap at ceiling
            new_end = max(original_end, candidate)
            if cap is not None:
                new_end = min(new_end, cap)
            cur["end"] = new_end

        return result
