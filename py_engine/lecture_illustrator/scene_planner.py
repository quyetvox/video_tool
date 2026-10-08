"""Dịch → gom nhóm → TTS → scene plan cho Lecture Illustrator (cảnh sinh mới, không dùng hình video gốc)."""
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Dict, List, Optional

from .common import clean_json_str, emit_log, emit_progress
from .knowledge_extractor import call_llm_api, translate_text_free
from .models import LectureProjectConfig
from .scene_validator import validate_scene

LEAD_IN = 1.2         # giây đầu mỗi cảnh để tiêu đề được vẽ trước khi câu đầu tiên được đọc
TAIL = 0.6            # giây cuối mỗi cảnh sau câu cuối
SENTENCE_GAP = 0.25   # nghỉ giữa các câu trong cùng nhóm
MAX_SENTENCES = 6     # giới hạn số câu mỗi nhóm để template không chật
PAUSE_SPLIT = 1.2     # khoảng lặng (giây) trong video gốc coi là ranh giới nhóm


# ── Dịch ─────────────────────────────────────────────────────────────────────

def _chunks(items: list, size: int):
    for i in range(0, len(items), size):
        yield i, items[i:i + size]


import re

def _contains_cjk(text: str) -> bool:
    """Kiểm tra chuỗi có chứa ký tự chữ Hán (CJK) hay không."""
    return bool(re.search(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]", str(text or "")))


def translate_sentences(
    segments: List[Dict[str, Any]],
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Dịch từng câu ASR sang ngôn ngữ đích (target_lang) và ngôn ngữ phụ (secondary_lang nếu bật song ngữ)."""
    src = [s for s in segments if str(s.get("text", "")).strip()]
    texts = [str(s["text"]).strip() for s in src]
    out: List[Optional[str]] = [None] * len(texts)
    target_lang = config.target_lang or "vi"

    # 1. Dịch theo lô bằng LLM (nếu có api_key hoặc base_url)
    if api_key or base_url:
        for base, chunk in _chunks(texts, 20):
            prompt = (
                f"Dịch từng câu sau sang ngôn ngữ '{target_lang}' (xưng hô: {config.pronoun_mode}), "
                "giữ nguyên ý, tự nhiên, ngắn gọn như lời giảng. Tuyệt đối không để sót ký tự ngôn ngữ nguồn. "
                f"Trả về DUY NHẤT một JSON array gồm đúng {len(chunk)} chuỗi tiếng {target_lang} theo thứ tự.\n"
                + json.dumps(chunk, ensure_ascii=False)
            )
            try:
                raw_resp = call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""
                parsed = json.loads(clean_json_str(raw_resp))
                if isinstance(parsed, list) and len(parsed) == len(chunk):
                    for j, t in enumerate(parsed):
                        if isinstance(t, str) and t.strip() and not _contains_cjk(t):
                            out[base + j] = t.strip()
            except Exception as e:  # noqa: BLE001
                emit_log("warn", f"Dịch LLM lô {base // 20 + 1} lỗi ({e}), chuyển sang tự phục hồi...")

    # 2. Multi-tier Fallback cho các câu còn thiếu hoặc bị dính CJK
    missing_indices = [i for i, t in enumerate(out) if not t or _contains_cjk(t)]
    if missing_indices:
        emit_log("info", f"Kích hoạt Translation Guard tự phục hồi cho {len(missing_indices)} câu thoại...")

        def _safe_translate_one(idx: int) -> str:
            orig = texts[idx]
            # Thử dịch trực tiếp sang target_lang
            res = translate_text_free(orig, target_lang)
            if res and not _contains_cjk(res) and res.strip() != orig:
                return res.strip()

            # Thử bắc cầu qua tiếng Anh: CJK -> EN -> target_lang
            en_mid = translate_text_free(orig, "en")
            if en_mid and not _contains_cjk(en_mid):
                res2 = translate_text_free(en_mid, target_lang)
                if res2 and not _contains_cjk(res2):
                    return res2.strip()

            # Nếu vẫn còn ký tự CJK, làm sạch triệt để loại bỏ ký tự lạ
            clean = re.sub(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]+", " ", res or orig)
            clean = re.sub(r"\s+", " ", clean).strip()
            return clean if clean else "Khái niệm và nội dung bài học"

        with ThreadPoolExecutor(max_workers=4) as pool:
            for i, translated in zip(missing_indices, pool.map(_safe_translate_one, missing_indices)):
                out[i] = translated

    # 3. Dịch ngôn ngữ phụ secondary_lang (nếu bật song ngữ và secondary_lang khác target_lang)
    out_sec: List[str] = list(texts)
    sec_lang = (config.secondary_lang or "").strip().lower()
    if sec_lang and sec_lang != "none" and sec_lang != target_lang.lower():
        if sec_lang == (config.source_lang or "").lower():
            out_sec = list(texts)
        else:
            emit_log("info", f"Đang dịch dòng phụ sang ngôn ngữ đã chọn: '{sec_lang}'...")
            with ThreadPoolExecutor(max_workers=4) as pool:
                sec_translated = list(pool.map(lambda t: translate_text_free(t, sec_lang), texts))
                out_sec = [t if t and t.strip() and not _contains_cjk(t) else orig for t, orig in zip(sec_translated, texts)]

    return [
        {
            "start": float(s.get("start", 0.0)),
            "end": float(s.get("end", 0.0)),
            "text_orig": texts[i],
            "text": out[i] or "Nội dung bài học",
            "text_secondary": out_sec[i] if i < len(out_sec) else texts[i],
        }
        for i, s in enumerate(src)
    ]


# ── Gom nhóm ─────────────────────────────────────────────────────────────────

def group_sentences(sentences: List[Dict[str, Any]]) -> List[List[Dict[str, Any]]]:
    """Gom câu thành nhóm theo khoảng lặng của video gốc, tối đa MAX_SENTENCES câu/nhóm."""
    groups: List[List[Dict[str, Any]]] = []
    cur: List[Dict[str, Any]] = []
    for s in sentences:
        if cur and (len(cur) >= MAX_SENTENCES or s["start"] - cur[-1]["end"] >= PAUSE_SPLIT):
            groups.append(cur)
            cur = []
        cur.append(s)
    if cur:
        groups.append(cur)
    return groups


# ── Timeline theo thời lượng TTS ─────────────────────────────────────────────

def build_timeline(groups: List[List[Dict[str, Any]]], durations: List[float]) -> List[Dict[str, Any]]:
    """Gán mốc thời gian mới. `durations` là thời lượng TTS của từng câu, theo thứ tự phẳng.

    Mốc của câu k trong nhóm là nguồn thời gian duy nhất cho animation, giọng và subtitle.
    """
    timeline: List[Dict[str, Any]] = []
    t = 0.0
    n = 0
    for g in groups:
        step_starts: List[float] = []
        local = LEAD_IN
        sents = []
        for s in g:
            d = durations[n]
            audio_file = f"s_{n:04d}.mp3"
            step_starts.append(round(local, 3))
            sents.append({
                "index": n,
                "audio_file": audio_file,
                "text_orig": s["text_orig"],
                "text": s["text"],
                "text_secondary": s.get("text_secondary", s["text_orig"]),
                "duration": round(d, 3),
                "start": round(t + local, 3),
                "end": round(t + local + d, 3),
            })
            n += 1
            local += d + SENTENCE_GAP
        scene_duration = local - SENTENCE_GAP + TAIL
        timeline.append({
            "start": round(t, 3), "end": round(t + scene_duration, 3),
            "scene_duration": round(scene_duration, 3), "step_starts": step_starts, "sentences": sents,
        })
        t += scene_duration
    return timeline


# ── TTS ──────────────────────────────────────────────────────────────────────

def synthesize_sentences(sentences: List[Dict[str, Any]], config: LectureProjectConfig, workspace_dir: Path) -> List[float]:
    """Sinh TTS từng câu, trả thời lượng thật. Lưu file ở workspace/tts/s_XXXX.mp3 để bước render dùng lại."""
    from utils.movie_review_tts import MovieReviewTTS

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)

    def one(i: int) -> float:
        return MovieReviewTTS.synthesize_single(
            text=sentences[i]["text"], out_file=tts_dir / f"s_{i:04d}.mp3",
            voice=config.tts_voice or "ban_mai", speed_factor=config.tts_speed or 1.15,
        )

    from .common import resolve_hardware_config
    workers, _, _ = resolve_hardware_config()

    with ThreadPoolExecutor(max_workers=max(2, workers)) as pool:
        durations = []
        for i, d in enumerate(pool.map(one, range(len(sentences)))):
            durations.append(d if d > 0 else 1.5)  # TTS lỗi: dành tạm 1.5s để video không vỡ
            emit_progress(0.40 + 0.25 * (i + 1) / max(1, len(sentences)), f"Đã tạo giọng đọc {i + 1}/{len(sentences)}...")
    return durations


# ── Cơ chế Đánh Index Phân Loại Template (3-Tier Semantic Router) ──────────

TEMPLATE_KEYWORD_RULES = [
    # 1. Họ AI & Autonomous Agent
    ("agent_workflow", [
        r"\bagent\b", r"\btự trị\b", r"\bworkflow\b", r"\bchu trình\b", r"\bloop\b",
        r"\breasoning\b", r"\bsuy luận\b", r"\bhành động\b", r"\bquan sát\b", r"\btool\b",
        r"\bcông cụ\b", r"\bperception\b", r"\bdecision\b", r"\bmulti-agent\b", r"\bphản hồi\b"
    ]),
    ("rag_pipeline", [
        r"\brag\b", r"\bretrieval\b", r"\bvector\b", r"\bembedding\b", r"\btrích xuất\b",
        r"\btruy vấn\b", r"\bdatabase\b", r"\bkho tri thức\b", r"\bsemantic search\b",
        r"\bngữ nghĩa\b", r"\bchunk\b", r"\bcontext\b", r"\btop-k\b"
    ]),
    ("transformer_attention", [
        r"\btransformer\b", r"\battention\b", r"\btự chú ý\b", r"\bself-attention\b",
        r"\bquery\b", r"\bkey\b", r"\bvalue\b", r"\bqkv\b", r"\bsoftmax\b", r"\btoken\b",
        r"\btrọng số\b", r"\bhead\b", r"\bmulti-head\b"
    ]),
    ("neural_net", [
        r"\bnơ-ron\b", r"\bneuron\b", r"\bneural\b", r"\bhọc sâu\b", r"\bdeep learning\b",
        r"\bforward\b", r"\blan truyền\b", r"\bbackprop\b", r"\blớp ẩn\b", r"\bhidden layer\b",
        r"\btrọng số w\b", r"\bgradient\b"
    ]),

    # 2. Họ Coding & Hệ Thống
    ("algo_array", [
        r"\bmảng\b", r"\barray\b", r"\bcon trỏ\b", r"\bpointer\b", r"\btwo pointer\b",
        r"\bthuật toán\b", r"\bsắp xếp\b", r"\bsort\b", r"\bvòng lặp\b", r"\bduyệt\b",
        r"\bchỉ số\b", r"\bindex\b", r"\bbinary search\b", r"\bphần tử\b"
    ]),
    ("code_block", [
        r"\bcode\b", r"\bmã nguồn\b", r"\bcú pháp\b", r"\bsyntax\b", r"\bhàm\b",
        r"\bfunction\b", r"\blập trình\b", r"\bterminal\b", r"\blệnh\b", r"\bcommand\b",
        r"\bclass\b", r"\bvariable\b", r"\bconsole\b"
    ]),
    ("system_tree", [
        r"\bkiến trúc\b", r"\bhệ thống\b", r"\bcây\b", r"\btree\b", r"\bphân nhánh\b",
        r"\bapi\b", r"\bendpoint\b", r"\brest\b", r"\bmicroservice\b", r"\bmodule\b",
        r"\bphân cấp\b", r"\btradeoff\b"
    ]),
    ("network_route", [
        r"\bmạng\b", r"\bnetwork\b", r"\btín hiệu\b", r"\bđịa lý\b", r"\bkhoảng cách\b",
        r"\broute\b", r"\bđịnh tuyến\b", r"\bip\b", r"\bserver\b", r"\bclient\b",
        r"\bpacket\b", r"\bgói tin\b", r"\bcdn\b", r"\bradar\b"
    ]),

    # 3. Họ Phân Tích & Quy Trình
    ("compare_two", [
        r"\bso sánh\b", r"\bđối chiếu\b", r"\bkhác biệt\b", r"\bưu điểm\b", r"\bnhược điểm\b",
        r"\bvs\b", r"\btrái ngược\b", r"\bhơn kém\b", r"\bmặt khác\b", r"\bhaui lựa chọn\b"
    ]),
    ("process_flow", [
        r"\bquy trình\b", r"\btuần tự\b", r"\bbước 1\b", r"\bbước 2\b", r"\bgiai đoạn\b",
        r"\btrình tự\b", r"\bchuyển giao\b", r"\bflow\b"
    ]),
    ("number_stat", [
        r"\bphần trăm\b", r"%", r"\bthống kê\b", r"\btỷ lệ\b", r"\btăng trưởng\b",
        r"\bgấp đôi\b", r"\btriệu\b", r"\btỷ\b", r"\bcon số\b"
    ]),
    ("definition", [
        r"\bđịnh nghĩa\b", r"\bkhái niệm\b", r"\blà gì\b", r"\bđược hiểu là\b",
        r"\bthuật ngữ\b", r"\bcốt lõi\b"
    ]),
    ("title_point", [
        r"\btóm lại\b", r"\btổng kết\b", r"\blưu ý\b", r"\bquan trọng nhất\b",
        r"\bthông điệp\b", r"\bkết luận\b"
    ]),
]

TEMPLATE_FAMILIES = {
    "ai": ["agent_workflow", "rag_pipeline", "transformer_attention", "neural_net"],
    "code_sys": ["algo_array", "code_block", "system_tree", "network_route"],
    "analysis": ["process_flow", "compare_two", "number_stat"],
    "narrative": ["bullet_list", "title_point", "definition"],
}


def classify_template_by_keywords(text: str) -> Optional[str]:
    """Tier 1: Đánh giá phân loại template dựa trên mật độ từ khóa kỹ thuật."""
    lowered = text.lower()
    best_template = None
    max_score = 0
    for template_name, patterns in TEMPLATE_KEYWORD_RULES:
        score = 0
        for pat in patterns:
            if re.search(pat, lowered):
                score += 1
        if score > max_score:
            max_score = score
            best_template = template_name
    return best_template if max_score > 0 else None


def apply_anti_repetition_guard(scenes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Tier 3: Giám sát chống lặp template, không để trùng lặp quá 2 batch liên tiếp."""
    for i in range(2, len(scenes)):
        t_curr = scenes[i].get("template")
        t_prev1 = scenes[i - 1].get("template")
        t_prev2 = scenes[i - 2].get("template")

        if t_curr and t_curr == t_prev1 == t_prev2:
            # Tìm họ gia đình của template hiện tại
            target_family = None
            for fam_name, members in TEMPLATE_FAMILIES.items():
                if t_curr in members:
                    target_family = members
                    break

            if target_family:
                # Chọn một template khác trong cùng họ chưa bị lặp gần đây
                alternates = [m for m in target_family if m != t_curr]
                if alternates:
                    chosen = alternates[(i) % len(alternates)]
                    emit_log("info", f"Anti-Repetition Guard: Luân chuyển batch {i} từ '{t_curr}' sang '{chosen}' để đa dạng hóa hình ảnh.")
                    scenes[i]["template"] = chosen
            else:
                # Fallback luân chuyển linh hoạt
                scenes[i]["template"] = "title_point" if t_curr == "bullet_list" else "bullet_list"

    return scenes


# ── Scene plan ───────────────────────────────────────────────────────────────

def plan_scenes(
    groups: List[List[Dict[str, Any]]],
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Tự động phân loại ngữ cảnh và chọn template qua 3-Tier Semantic Router (Keyword -> LLM -> Anti-Repetition)."""
    raw: Dict[int, Dict[str, Any]] = {}
    if api_key or base_url:
        for base, chunk in _chunks(groups, 8):
            payload = []
            for j, g in enumerate(chunk):
                combined_txt = " ".join(s["text"] for s in g)
                suggested_kw = classify_template_by_keywords(combined_txt)
                payload.append({
                    "id": base + j,
                    "sentences": [s["text"] for s in g],
                    "suggested_template": suggested_kw or "bullet_list",
                })

            prompt = (
                "Với mỗi nhóm câu bài giảng, tự động phân tích ngữ cảnh và chọn kiểu minh họa ('template') tối ưu nhất trong 14 mẫu sau:\n"
                "1. Nhóm AI & Agent:\n"
                "   - 'agent_workflow': chu trình tự trị AI agent, ReAct loop, quan sát -> suy luận -> gọi tools -> bộ nhớ.\n"
                "   - 'rag_pipeline': kiến trúc RAG, truy vấn cơ sở dữ liệu vector, embeddings, trích xuất tri thức, ngữ cảnh.\n"
                "   - 'transformer_attention': cơ chế Attention, Self-Attention, ma trận chú ý, vector Q-K-V, softmax, token.\n"
                "   - 'neural_net': mạng nơ-ron sâu đa tầng, liên kết synapses, lan truyền thuận nghịch, ma trận trọng số.\n"
                "2. Nhóm Lập trình & Hệ thống:\n"
                "   - 'code_block': minh họa code mã nguồn, cú pháp lệnh, terminal lập trình, debug.\n"
                "   - 'algo_array': thuật toán DSA, mảng số, hai con trỏ (two pointers), duyệt vòng lặp, so sánh số.\n"
                "   - 'system_tree': kiến trúc hệ thống, API endpoint, REST/GraphQL, phân nhánh microservice, tradeoffs.\n"
                "   - 'network_route': mạng viễn thông, địa lý, ip, định tuyến, gói tin server client, tín hiệu radar.\n"
                "3. Nhóm Phân tích & Quy trình:\n"
                "   - 'compare_two': so sánh đối chiếu 2 đối tượng, ưu/nhược điểm, bảng phân tích hai chiều.\n"
                "   - 'process_flow': quy trình tuần tự các bước 1 chiều mũi tên.\n"
                "   - 'number_stat': số liệu thống kê lớn, tỷ lệ phần trăm, quy mô dữ liệu.\n"
                "4. Nhóm Khái niệm & Thuyết minh:\n"
                "   - 'definition': đóng khung định nghĩa, giải thích thuật ngữ cốt lõi.\n"
                "   - 'title_point': tiêu đề nổi bật lớn ở trung tâm kèm thông điệp cô đọng.\n"
                "   - 'bullet_list': danh sách các ý gạch đầu dòng.\n\n"
                "Trả về DUY NHẤT một JSON array, mỗi phần tử gồm: "
                '{"id": số, "template": "tên_template", "title": "tiêu đề <=30 ký tự", '
                '"steps": [{"label": "ý chính <=28 ký tự của câu", "icon": "sun|leaf|bulb|gear|check|arrow|star"}]}. '
                "Số steps phải bằng đúng số câu của nhóm.\n"
                + json.dumps(payload, ensure_ascii=False)
            )
            try:
                parsed = json.loads(clean_json_str(call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""))
                for item in parsed if isinstance(parsed, list) else []:
                    if isinstance(item, dict) and isinstance(item.get("id"), int):
                        raw[item["id"]] = item
            except Exception as e:  # noqa: BLE001
                emit_log("warn", f"Lập scene bằng LLM lỗi ({e}), chuyển sang bộ định tuyến từ khóa Heuristic.")

    # Xử lý kết quả qua validator và áp dụng Tier 1 Fallback nếu thiếu
    scenes: List[Dict[str, Any]] = []
    for i, g in enumerate(groups):
        sentences = [s["text"] for s in g]
        scene_item = raw.get(i)
        if not scene_item:
            # Kích hoạt Tier 1 Heuristic Indexing
            combined = " ".join(sentences)
            kw_tmpl = classify_template_by_keywords(combined) or "bullet_list"
            scene_item = {
                "template": kw_tmpl,
                "title": sentences[0] if sentences else "Bài giảng",
                "steps": [{"label": s[:26], "icon": "bulb"} for s in sentences],
            }
        scenes.append(validate_scene(scene_item, sentences))

    # Áp dụng Tier 3: Anti-Repetition Guard chống lặp template
    scenes = apply_anti_repetition_guard(scenes)

    return scenes

