"""
In-memory visual alignment engine for Movie Review:
Matches voiceover script segments with best shots from the scene pool,
enforcing timeline flow, intent matching, and the Zero-Duplicate law.
"""

from typing import Any, Dict, List, Set


class VisualAlignmentEngine:
    """
    Bộ so khớp Visual Alignment In-Memory:
    Gán từng câu thoại của kịch bản với các shot hình đắt giá nhất từ Scene Pool.
    Hỗ trợ:
    - Timeline Match (khóa theo thứ tự thời gian cho phần story, tự do cho hook/review/outro).
    - Intent Match (direct, supporting, symbolic, montage).
    - Montage Generation (ghép 2-3 shot ngắn cho câu thoại dồn dập).
    - Anti-Repetition Penalty (phạt nặng các shot vừa dùng trong 3-5 câu gần nhất).
    """

    @staticmethod
    def align_script_with_scenes(
        script_items: List[Dict[str, Any]],
        scenes: List[Dict[str, Any]],
        video_duration_sec: float = 0.0
    ) -> List[Dict[str, Any]]:
        if not script_items or not scenes:
            return script_items

        valid_scenes = [
            s for s in scenes
            if float(s.get("end_sec", 0)) - float(s.get("start_sec", 0)) >= 0.5
        ]
        if not valid_scenes:
            valid_scenes = list(scenes)

        sorted_scenes = sorted(valid_scenes, key=lambda s: float(s.get("start_sec", 0.0)))
        max_time = max(video_duration_sec, max([float(s.get("end_sec", 0.0)) for s in sorted_scenes], default=100.0))

        story_items = [it for it in script_items if it.get("section", "story").lower() in ["story", "storytelling"]]
        total_story = max(1, len(story_items))
        story_idx = 0

        globally_used_scene_ids: Set[int] = set()

        for item in script_items:
            sec = item.get("section", "story").lower()
            intent = item.get("visual_intent", "direct").lower()
            tr = item.get("time_range")

            if sec in ["story", "storytelling"]:
                if tr and isinstance(tr, (list, tuple)) and len(tr) == 2:
                    tr_s = float(tr[0])
                    tr_e = float(tr[1])
                    target_t = (tr_s + tr_e) / 2.0
                else:
                    target_t = (story_idx / float(total_story)) * max_time
                story_idx += 1
            elif sec == "hook":
                target_t = 0.0
            elif sec in ["review", "critique"]:
                target_t = max_time * 0.65
            else:
                target_t = max_time * 0.9

            # Zero-Duplicate: Ưu tiên tuyệt đối các cảnh chưa từng xuất hiện trong toàn bộ video review
            unused_scenes = [sc for sc in sorted_scenes if sc.get("scene_id", 0) not in globally_used_scene_ids]
            candidate_pool = unused_scenes if unused_scenes else sorted_scenes

            scored_candidates = []
            for sc in candidate_pool:
                sc_id = sc.get("scene_id", 0)
                s_val = float(sc.get("start_sec", 0.0))
                e_val = float(sc.get("end_sec", s_val + 2.0))
                dur = max(0.5, e_val - s_val)

                # 1. Điểm Timeline (ưu tiên cảnh trong đúng time_range của chương)
                if sec in ["story", "storytelling"]:
                    time_diff = abs(s_val - target_t)
                    timeline_score = max(0.0, 1.0 - (time_diff / max(1.0, max_time * 0.5)))
                    if tr and isinstance(tr, (list, tuple)) and len(tr) == 2:
                        tr_s = float(tr[0])
                        tr_e = float(tr[1])
                        if tr_s <= s_val <= tr_e or tr_s <= e_val <= tr_e:
                            timeline_score += 1.5
                else:
                    timeline_score = 0.85

                # 2. Điểm Intent
                intent_score = 0.6
                if intent == "symbolic":
                    if dur >= 3.5:
                        intent_score = 1.0
                elif intent == "montage":
                    if 1.5 <= dur <= 4.5:
                        intent_score = 1.0
                elif intent == "direct":
                    intent_score = 0.85
                elif intent == "supporting":
                    intent_score = 0.75

                # 3. Phạt lặp cảnh (Zero-Duplicate Hard Penalty: phạt 100 điểm nếu đã dùng)
                repetition_penalty = 100.0 if sc_id in globally_used_scene_ids else 0.0

                total_score = (timeline_score * 0.5) + (intent_score * 0.3) - repetition_penalty
                scored_candidates.append((total_score, sc))

            scored_candidates.sort(key=lambda x: x[0], reverse=True)

            if intent == "montage" and len(scored_candidates) >= 2:
                chosen_scenes = [dict(scored_candidates[0][1]), dict(scored_candidates[1][1])]
            else:
                chosen_scenes = [dict(scored_candidates[0][1])] if scored_candidates else [dict(sorted_scenes[0])]

            for cs in chosen_scenes:
                cid = cs.get("scene_id", 0)
                globally_used_scene_ids.add(cid)

            item["scenes_to_use"] = chosen_scenes
            if "voiceover_text" not in item:
                item["voiceover_text"] = item.get("text", "")

        return script_items
