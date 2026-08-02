import re
from typing import Any, Dict, List

KNOWN_HALLUCINATIONS = {
    # Chinese ASR hallucinations
    "为什么为什么为什么",
    "为什么为什么",
    "为什么",
    "为什么呢",
    "怎么到",
    "怎么",
    "谢谢观看",
    "请订阅",
    "点赞关注",

    # Vietnamese translations of ASR hallucinations
    "tại sao tại sao tại sao",
    "tại sao tại sao",
    "tại sao",
    "sao lại đến",
    "cảm ơn đã xem",
    "đăng ký kênh",
    "theo dõi kênh",

    # English hallucinations
    "untertitel freiwillig",
    "subtitles by",
    "thank you for watching",
    "please subscribe",
    "thanks for watching",
    "by amara.org"
}


class RepetitionCleaner:
    @staticmethod
    def collapse_phrase_repetition(text: str) -> str:
        """Collapses intra-string phrase loops e.g. 'Tại sao tại sao tại sao' -> 'Tại sao'."""
        text = text.strip()
        if not text:
            return ""

        # Specifically collapse common Chinese hallucination words
        text = re.sub(r"(为什么)+", "为什么", text)
        text = re.sub(r"(怎么)+", "怎么", text)

        # Collapse 1-4 word space-separated phrase repetitions (e.g. "Tại sao tại sao tại sao" -> "Tại sao")
        text = re.sub(r"(\b\w+(?:\s+\w+){0,3}\b)(?:\s+\1)+", r"\1", text, flags=re.IGNORECASE)

        # Collapse any repeated 2-6 character n-gram
        text = re.sub(r"(.{2,6})\1+", r"\1", text)

        return text.strip()

    @staticmethod
    def clean_segments(segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Cleans transcript & translation segments:
        - Removes empty text and zero-duration segments.
        - Collapses phrase repetitions inside single text strings.
        - Filters out known ASR hallucination words/phrases.
        - Limits consecutive identical segment repetitions to at most 1.
        """
        cleaned: List[Dict[str, Any]] = []
        prev_text_norm = ""
        consecutive_repeat = 0

        for seg in segments:
            raw_text = seg.get("text", "").strip()
            start = float(seg.get("start", 0.0))
            end = float(seg.get("end", 0.0))

            # Filter out empty text or invalid time range
            if not raw_text or end <= start:
                continue

            # Collapse repetitions in string
            clean_text = RepetitionCleaner.collapse_phrase_repetition(raw_text)
            if not clean_text:
                continue

            norm_text = clean_text.lower().rstrip(".,!?")

            # Filter known ASR hallucination phrases
            if norm_text in KNOWN_HALLUCINATIONS:
                continue

            if norm_text == prev_text_norm:
                consecutive_repeat += 1
                if consecutive_repeat >= 2:
                    continue
            else:
                prev_text_norm = norm_text
                consecutive_repeat = 1

            new_seg = dict(seg)
            new_seg["text"] = clean_text
            cleaned.append(new_seg)

        return cleaned
