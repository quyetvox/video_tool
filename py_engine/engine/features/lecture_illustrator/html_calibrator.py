"""
HTML Calibrator, Quality Evaluator & Speed Synchronizer (Sub-Video Lecture Illustrator).

Tự động chuẩn hóa, cân chỉnh tốc độ, mốc thời gian (STEP_STARTS, SCENE_DURATION),
sửa lỗi vi mô hình học (font size, lấn vạch cấm phụ đề đáy, căn giữa) và chấm điểm chất lượng
của file HTML/SVG bài giảng do AI sinh ra.
"""

try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import json
from pathlib import Path
import re
from typing import Any, Dict, List, Optional, Tuple


ASSETS_DIR = (Path(__file__).resolve().parent / "assets").resolve()
FONTS_DIR = (ASSETS_DIR / "fonts").resolve()
PATRICK_HAND_FONT_PATH = FONTS_DIR / "PatrickHand.ttf"


def ensure_handdrawn_font_in_html(html_str: str) -> str:
    """Đảm bảo trang HTML luôn nạp và áp dụng font viết tay Patrick Hand chuẩn Sub-Video."""
    if not html_str:
        return html_str

    font_link = (
        '  <link rel="preconnect" href="https://fonts.googleapis.com">\n'
        '  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
        '  <link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">'
    )
    font_style = """  <style id="sub-video-font-guarantee">
    @import url('https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap');
    @font-face {
      font-family: 'PatrickHand';
      src: local('Patrick Hand'), local('PatrickHand'),
           url('https://fonts.gstatic.com/s/patrickhand/v22/LDI1apSQOAYtSuYWp8ZhfImpWrVk.woff2') format('woff2'),
           url('assets/fonts/PatrickHand.ttf') format('truetype'),
           url('fonts/PatrickHand.ttf') format('truetype');
    }
    html, body, text, svg text {
      font-family: 'Patrick Hand', 'PatrickHand', cursive, sans-serif !important;
    }
    .text-white { fill: #ffffff !important; color: #ffffff !important; }
    .text-ink { fill: var(--ink, #0f172a) !important; color: var(--ink, #0f172a) !important; }
    .text-muted { fill: var(--ink-muted, #334155) !important; color: var(--ink-muted, #334155) !important; }
    .text-red { fill: var(--accent-red, #991b1b) !important; color: var(--accent-red, #991b1b) !important; }
    .text-green { fill: var(--accent-green, #14532d) !important; color: var(--accent-green, #14532d) !important; }
    .text-blue { fill: var(--accent-blue, #1e3a8a) !important; color: var(--accent-blue, #1e3a8a) !important; }
    .flow-pulse, [id*="dots"] { visibility: visible; }
  </style>"""

    if "sub-video-font-guarantee" not in html_str:
        if "<head>" in html_str:
            html_str = html_str.replace("<head>", f"<head>\n{font_link}\n{font_style}", 1)
        elif "<head " in html_str:
            html_str = re.sub(r"(<head[^>]*>)", rf"\1\n{font_link}\n{font_style}", html_str, count=1)
        elif "<html" in html_str:
            html_str = html_str.replace("<html>", f"<html><head>\n{font_link}\n{font_style}</head>", 1)
        elif "<body" in html_str:
            html_str = re.sub(r"(<body[^>]*>)", rf"<head>\n{font_link}\n{font_style}</head>\n\1", html_str, count=1)
    else:
        # Cập nhật lại style nếu đã tồn tại để nhận thêm các rule mới
        html_str = re.sub(
            r"<style id=\"sub-video-font-guarantee\">.*?<\/style>",
            font_style.strip(),
            html_str,
            flags=re.DOTALL
        )

    return html_str


def sanitize_latex_formulas(text: str) -> str:
    """Chuyển đổi các ký hiệu công thức toán LaTeX phổ biến sang Unicode chuẩn."""
    if not text or ("$" not in text and "\\" not in text):
        return text

    replacements = [
        (r"\$?\\leftrightarrow\$?", "⟷"),
        (r"\$?\\longleftrightarrow\$?", "⟷"),
        (r"\$?\\rightleftharpoons\$?", "⇌"),
        (r"\$?\\rightarrow\$?", "➔"),
        (r"\$?\\longrightarrow\$?", "➔"),
        (r"\$?\\to\$?", "➔"),
        (r"\$?\\leftarrow\$?", "⬅"),
        (r"\$?\\longleftarrow\$?", "⬅"),
        (r"\$?\\le(?:q)?(?![a-zA-Z])\$?", "≤"),
        (r"\$?\\ge(?:q)?(?![a-zA-Z])\$?", "≥"),
        (r"\$?\\ne(?:q)?(?![a-zA-Z])\$?", "≠"),
        (r"\$?\\approx\$?", "≈"),
        (r"\$?\\times\$?", "×"),
        (r"\$?\\cdot\$?", "·"),
        (r"\$?\\pm\$?", "±"),
        (r"\$?\\mp\$?", "∓"),
        (r"\$?\\in(?![a-zA-Z])\$?", "∈"),
        (r"\$?\\notin\$?", "∉"),
        (r"\$?\\subset(?![a-zA-Z])\$?", "⊂"),
        (r"\$?\\subseteq\$?", "⊆"),
        (r"\$?\\cup\$?", "∪"),
        (r"\$?\\cap\$?", "∩"),
        (r"\$?\\forall\$?", "∀"),
        (r"\$?\\exists\$?", "∃"),
        (r"\$?\\dots\$?", "…"),
        (r"\$?\\cdots\$?", "…"),
        (r"\$?\\infty\$?", "∞"),
        (r"\$?\\alpha(?![a-zA-Z])\$?", "α"),
        (r"\$?\\beta(?![a-zA-Z])\$?", "β"),
        (r"\$?\\gamma(?![a-zA-Z])\$?", "γ"),
        (r"\$?\\pi(?![a-zA-Z])\$?", "π"),
        (r"\$?\\theta(?![a-zA-Z])\$?", "θ"),
        (r"\$?\\lambda(?![a-zA-Z])\$?", "λ"),
        (r"\$?\\mu(?![a-zA-Z])\$?", "μ"),
        (r"\$?\\sigma(?![a-zA-Z])\$?", "σ"),
        (r"\$?\\Delta(?![a-zA-Z])\$?", "Δ"),
        (r"\$?\\Omega(?![a-zA-Z])\$?", "Ω"),
        (r"\$?\\Theta(?![a-zA-Z])\$?", "Θ"),
        (r"\$?\\mathcal\{O\}\$?", "O"),
        (r"O\(\s*n\s*[\^]\s*2\s*\)", "O(n²)"),
        (r"O\(\s*n\s*[\^]\s*3\s*\)", "O(n³)"),
        (r"O\(\s*1\s*\)", "O(1)"),
        (r"O\(\s*n\s*\)", "O(n)"),
        (r"\\log(?:_2)?", "log"),
        (r"\$([^$]+)\$", r"\1"),
    ]
    res = text
    for pat, rep in replacements:
        res = re.sub(pat, rep, res)
    return res


def calibrate_imported_html(
    raw_html: str,
    actual_duration: float,
    actual_step_starts: List[float],
) -> str:
    """Cân chỉnh mã HTML: thay thế biến thời gian, bảo đảm font viết tay và tiêm bridge đồng bộ tốc độ."""
    if not raw_html or not raw_html.strip():
        return raw_html

    cleaned = ensure_handdrawn_font_in_html(raw_html.strip())

    # Bỏ markdown code fences nếu có ```html ... ```
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:html)?\s*\n?", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\n?```\s*$", "", cleaned)

    # Loại bỏ bridge script cũ nếu có trước khi tiêm bản mới nhất
    cleaned = re.sub(r"\s*<!-- Sub-Video Auto-Calibration Bridge.*?<\/script>", "", cleaned, flags=re.DOTALL)

    dur_val = round(max(0.5, float(actual_duration)), 2)
    step_vals = [round(float(s), 2) for s in (actual_step_starts or [0.0])]
    steps_json = json.dumps(step_vals)

    # Tự động chuyển đổi các ký hiệu LaTeX toán học sang Unicode sạch
    def _sanitize_svg_text(m):
        return f"{m.group(1)}{sanitize_latex_formulas(m.group(2))}{m.group(3)}"
    cleaned = re.sub(r"(<text[^>]*>)([^<]+)(</text>)", _sanitize_svg_text, cleaned)

    # 1. Thay thế trực tiếp các khai báo biến thời lượng phổ biến nếu có trong mã
    cleaned = re.sub(
        r"((?:const|let|var)\s+(?:SCENE_)?DURATION\s*=\s*)[\d\.]+(\s*;?)",
        rf"\g<1>{dur_val}\g<2>",
        cleaned
    )
    cleaned = re.sub(
        r"((?:const|let|var)\s+STEP_STARTS\s*=\s*)\[[^\]]*\](\s*;?)",
        rf"\g<1>{steps_json}\g<2>",
        cleaned
    )

    # Đảm bảo hàm drawStroke luôn bật opacity: 1 cho phần tử khi progress p > 0
    cleaned = re.sub(
        r"(function\s+drawStroke\s*\([^)]*\)\s*\{)",
        r"\1\n      if (el && p > 0) { el.style.opacity = '1'; el.style.visibility = 'visible'; }",
        cleaned
    )

    # Loại bỏ triệt để CSS transform trên .sync-entity và các SVG group vì CSS transform trong SVG2/Chrome
    # sẽ ghi đè và XÓA SẠCH thuộc tính XML transform="translate(...)", khiến các phần tử bị dồn về góc trái (0, 0).
    cleaned = re.sub(r"(\.sync-entity[^{]*\{[^}]*?)transform\s*:[^;]+;?", r"\1", cleaned)
    cleaned = re.sub(r"(\.sync-entity[^{]*\{[^}]*?)transform-origin\s*:[^;]+;?", r"\1", cleaned)
    cleaned = re.sub(r",\s*transform\s+[\d\.]+[s|ms][^;]*", "", cleaned)

    # 2. Tạo đoạn Auto-Calibration Bridge Script
    bridge_script = f"""
  <!-- Sub-Video Auto-Calibration Bridge (Timing & Subtitle Sync) -->
  <script>
    (function() {{
      var actualDur = {dur_val};
      var actualSteps = {steps_json};
      window.__ACTUAL_SCENE_DURATION = actualDur;
      window.__ACTUAL_STEP_STARTS = actualSteps;
      try {{ if (typeof SCENE_DURATION !== 'undefined') SCENE_DURATION = actualDur; }} catch(_) {{}}
      try {{ if (typeof STEP_STARTS !== 'undefined') STEP_STARTS = actualSteps; }} catch(_) {{}}

      // Bảo vệ chống CSS style.transform ghi đè thuộc tính XML transform của SVG và loại bỏ triệt để đơn vị px cấm
      function sanitizeSvgTransforms() {{
        var svg = document.getElementById('svg') || document.querySelector('svg');
        if (!svg) return;
        var transEls = svg.querySelectorAll('[transform], [style*="transform"]');
        for (var i = 0; i < transEls.length; i++) {{
          var el = transEls[i];
          var st = el.style.transform;
          if (st) {{
            // Loại bỏ hoàn toàn đơn vị px vì thuộc tính XML transform của SVG 1.1 cấm tuyệt đối đơn vị px
            var cleanSt = st.replace(/([-\d\.]+)px/g, '$1');
            var attr = el.getAttribute('transform') || '';
            el.style.transform = '';

            // Nếu cả attr và cleanSt đều có translate, xóa translate cũ trong attr để tránh nhân đôi vị trí
            if (/translate\s*\(/.test(cleanSt) && /translate\s*\([^)]+\)/.test(attr)) {{
              attr = attr.replace(/translate\s*\([^)]+\)/g, '').trim();
            }}
            if (/scale\s*\(/.test(cleanSt) && /scale\s*\([^)]+\)/.test(attr)) {{
              attr = attr.replace(/scale\s*\([^)]+\)/g, '').trim();
            }}

            var combined = (attr ? (attr + ' ' + cleanSt) : cleanSt).trim();
            el.setAttribute('transform', combined);
          }}
        }}
      }}
      window.__sanitizeSvgTransforms = sanitizeSvgTransforms;

      // Đảm bảo window.__renderAt luôn nhận step_starts đã cân chỉnh và tự động sửa transform & sync visibility flow dots
      var origRenderAt = window.__renderAt;
      if (typeof origRenderAt === 'function') {{
        window.__renderAt = function(t, s) {{
          var effectiveSteps = (s && Array.isArray(s) && s.length) ? s : actualSteps;
          var res = origRenderAt(t, effectiveSteps);
          try {{ sanitizeSvgTransforms(); }} catch(_) {{}}
          try {{
            var flowGroups = document.querySelectorAll('.flow-pulse, [id*="dots"]');
            for (var k = 0; k < flowGroups.length; k++) {{
              var g = flowGroups[k];
              var op = parseFloat(g.style.opacity || '0');
              if (op > 0) {{
                g.style.visibility = 'visible';
                // Đảm bảo connector path liên kết với flow dots không bị ẩn tàng hình
                var gid = g.id || '';
                var pid = gid.replace('dots-', 'path-').replace('-dots', '');
                var pEl = document.getElementById(pid);
                if (pEl && pEl.style) {{
                  pEl.style.opacity = '1';
                  pEl.style.visibility = 'visible';
                }}
              }} else if (op === 0) {{
                g.style.visibility = 'hidden';
              }}
            }}
          }} catch(_) {{}}
          return res;
        }};
      }} else {{
        // Fallback tối thiểu nếu HTML ngoài chưa có __renderAt
        window.__renderAt = function(t, s) {{
          var effectiveSteps = (s && Array.isArray(s) && s.length) ? s : actualSteps;
          var svg = document.getElementById('svg') || document.querySelector('svg');
          if (svg) svg.style.opacity = Math.min(1, Math.max(0, t * 2));
        }};
      }}

      // Cung cấp hàm chuẩn hóa updateFlowDots toàn cục nếu chưa có
      if (typeof window.updateFlowDots !== 'function') {{
        window.updateFlowDots = function(dotsGroup, pathEl, t, speed, spacing, active) {{
          if (!dotsGroup || !pathEl) return;
          var isAct = (active === undefined) ? true : !!active;
          var circles = [];
          if (Array.isArray(dotsGroup) || dotsGroup instanceof NodeList) {{
            circles = Array.from(dotsGroup);
          }} else if (dotsGroup.getElementsByTagName) {{
            circles = Array.from(dotsGroup.getElementsByTagName('circle'));
          }} else if (dotsGroup.tagName && dotsGroup.tagName.toLowerCase() === 'circle') {{
            circles = [dotsGroup];
          }}
          if (!isAct) {{
            for (var j = 0; j < circles.length; j++) {{
              circles[j].style.opacity = '0';
              circles[j].style.visibility = 'hidden';
            }}
            if (dotsGroup.style) {{
              dotsGroup.style.opacity = '0';
              dotsGroup.style.visibility = 'hidden';
            }}
            return;
          }}
          if (dotsGroup.style) {{
            dotsGroup.style.opacity = '1';
            dotsGroup.style.visibility = 'visible';
          }}
          var pathElement = typeof pathEl === 'string' ? document.getElementById(pathEl) : pathEl;
          if (pathElement && pathElement.style) {{
            pathElement.style.opacity = '1';
            pathElement.style.visibility = 'visible';
          }}
          if (!pathElement || !pathElement.getTotalLength) return;
          var totalLen = pathElement.getTotalLength();
          if (!totalLen || totalLen <= 0) return;
          var spd = speed || 120;
          var spc = spacing || 60;
          for (var i = 0; i < circles.length; i++) {{
            circles[i].style.opacity = '1';
            circles[i].style.visibility = 'visible';
            var dist = ((t * spd + i * spc) % totalLen + totalLen) % totalLen;
            var pt = pathElement.getPointAtLength(dist);
            circles[i].setAttribute('cx', pt.x.toFixed(1));
            circles[i].setAttribute('cy', pt.y.toFixed(1));
          }}
        }};
      }}

      // Tự động kích hoạt sanitizeSvgTransforms trong vòng lặp autoplay
      var origRAF = window.requestAnimationFrame;
      if (typeof origRAF === 'function') {{
        window.requestAnimationFrame = function(cb) {{
          return origRAF(function(time) {{
            try {{ cb(time); }} finally {{ sanitizeSvgTransforms(); }}
          }});
        }};
      }}
    }})();
  </script>
"""

    # 3. Tiêm bridge vào HTML trước </body> hoặc </head>
    if "</body>" in cleaned:
        cleaned = cleaned.replace("</body>", f"{bridge_script}\n</body>", 1)
    elif "</head>" in cleaned:
        cleaned = cleaned.replace("</head>", f"{bridge_script}\n</head>", 1)
    else:
        cleaned = cleaned + f"\n{bridge_script}"

    return cleaned


def evaluate_and_calibrate_scene_html(
    html_str: str,
    duration: float,
    step_starts: List[float],
    aspect_ratio: str = "16:9",
) -> Tuple[str, Dict[str, Any]]:
    """
    Chạy bộ kiểm định chất lượng (Quality Gate) và tự động cân chỉnh (Auto-Calibrate)
    cho mã HTML do AI sinh ra:
    - Ép cỡ chữ tối thiểu >= 22px
    - Kéo lùi đồ họa nếu lấn vạch cấm phụ đề đáy (y <= 840 với 16:9, y <= 1620 với 9:16)
    - Tự động căn giữa nếu sơ đồ bị lệch biên
    - Kiểm tra tính hợp lệ của window.__renderAt
    - Chấm điểm chất lượng 0-100 và trả về (html_đã_nắn, quality_report)
    """
    calibrated_html = calibrate_imported_html(html_str, duration, step_starts)

    is_portrait = aspect_ratio == "9:16"
    width = 1080 if is_portrait else 1920
    height = 1920 if is_portrait else 1080
    sub_limit = height - (250 if is_portrait else 140)

    calibrations: List[str] = []
    if ("$" in html_str or "\\" in html_str) and sanitize_latex_formulas(html_str) != html_str:
        calibrations.append("sanitized_latex_math_formulas")

    eval_details: Dict[str, Any] = {
        "timing_contract": {"passed": True, "score": 25, "message": "window.__renderAt functional"},
        "subtitle_safety": {"passed": True, "score": 25, "max_y": 0, "limit_y": sub_limit},
        "boundary_safety": {"passed": True, "score": 25, "violations": []},
        "layout_occupancy": {"passed": True, "score": 25, "span_w": 0, "occupancy_ratio": 0.0},
    }

    # Thử chạy kiểm định sâu bằng Headless Playwright nếu có
    try:
        try:
            from .scene_renderer import _get_playwright, _launch
        except (ImportError, ValueError):
            try:
                from scene_renderer import _get_playwright, _launch
            except ImportError:
                from engine.features.lecture_illustrator.scene_renderer import _get_playwright, _launch
        sync_pw = _get_playwright()
        with sync_pw() as p:
            browser = _launch(p)
            try:
                page = browser.new_page(viewport={"width": width, "height": height})
                page.set_content(calibrated_html, wait_until="domcontentloaded", timeout=4000)

                # Script kiểm tra & nắn chỉnh vi mô trực tiếp trên DOM
                js_eval = f"""
                (() => {{
                    const subLimit = {sub_limit};
                    const width = {width};
                    const height = {height};
                    let calibs = [];
                    let details = {{
                        timing_contract: {{ passed: true, score: 25, message: "window.__renderAt functional" }},
                        subtitle_safety: {{ passed: true, score: 25, max_y: 0, limit_y: subLimit }},
                        boundary_safety: {{ passed: true, score: 25, violations: [] }},
                        layout_occupancy: {{ passed: true, score: 25, span_w: 0, occupancy_ratio: 0.0 }}
                    }};

                    function applyTransformTranslate(el, dx, dy) {{
                        if (!el || (dx === 0 && dy === 0)) return;
                        const cur = el.getAttribute('transform') || '';
                        const m = cur.match(/translate\\(\\s*([-\\d\\.]+)(?:[\\s,]+([-\\d\\.]+))?\\s*\\)/);
                        let curX = 0, curY = 0;
                        let rest = cur;
                        if (m) {{
                            curX = parseFloat(m[1]) || 0;
                            curY = parseFloat(m[2]) || 0;
                            rest = cur.replace(/translate\\([^)]*\\)/, '').trim();
                        }}
                        const newX = Math.round(curX + dx);
                        const newY = Math.round(curY + dy);
                        const newTrans = (`translate(${{newX}}, ${{newY}}) ` + rest).trim();
                        el.setAttribute('transform', newTrans);
                    }}

                    function isElementHidden(el) {{
                        let cur = el;
                        while (cur && cur.nodeType === 1) {{
                            const comp = window.getComputedStyle(cur);
                            if (comp.display === 'none' || comp.visibility === 'hidden' || parseFloat(comp.opacity || '1') === 0) return true;
                            if (cur.getAttribute && cur.getAttribute('opacity') === '0') return true;
                            cur = cur.parentElement;
                        }}
                        return false;
                    }}

                    function isIgnored(el) {{
                        let cur = el;
                        while (cur && cur.nodeType === 1) {{
                            if (cur.tagName && cur.tagName.toLowerCase() === 'defs') return true;
                            const comp = window.getComputedStyle(cur);
                            if (comp.display === 'none') return true;
                            cur = cur.parentElement;
                        }}
                        return false;
                    }}

                    // 1. Kiểm tra timing hook tại nhiều mốc thời gian
                    if (typeof window.__renderAt !== 'function') {{
                        details.timing_contract.passed = false;
                        details.timing_contract.score = 0;
                        details.timing_contract.message = "Thiếu hàm window.__renderAt";
                    }} else {{
                        try {{
                            const testSteps = {json.dumps(step_starts or [0.0])};
                            window.__renderAt(0, testSteps);
                            if (typeof window.__sanitizeSvgTransforms === 'function') window.__sanitizeSvgTransforms();

                            const midT = {duration:.2f} * 0.5;
                            window.__renderAt(midT, testSteps);
                            if (typeof window.__sanitizeSvgTransforms === 'function') window.__sanitizeSvgTransforms();

                            window.__renderAt({duration:.2f}, testSteps);
                            if (typeof window.__sanitizeSvgTransforms === 'function') window.__sanitizeSvgTransforms();
                        }} catch (e) {{
                            details.timing_contract.passed = false;
                            details.timing_contract.score = 12;
                            details.timing_contract.message = "Lỗi khi gọi __renderAt: " + String(e);
                        }}
                    }}

                    // 2. Chuyển đổi LaTeX và chuẩn hóa văn bản
                    const textEls = Array.from(document.querySelectorAll('text'));

                    // LaTeX Math Auto-Sanitizer trên DOM
                    let hasSanitizedLatex = false;
                    textEls.forEach(el => {{
                        const raw = el.textContent || '';
                        if (raw.includes('$') || raw.includes('\\\\')) {{
                            let s = raw
                                .replace(/\\$?\\\\leftrightarrow\\$?|\\\\leftrightarrow/g, '⟷')
                                .replace(/\\$?\\\\longleftrightarrow\\$?|\\\\longleftrightarrow/g, '⟷')
                                .replace(/\\$?\\\\rightleftharpoons\\$?|\\\\rightleftharpoons/g, '⇌')
                                .replace(/\\$?\\\\rightarrow\\$?|\\\\rightarrow/g, '➔')
                                .replace(/\\$?\\\\longrightarrow\\$?|\\\\longrightarrow/g, '➔')
                                .replace(/\\$?\\\\to\\$?|\\\\to(?![a-zA-Z])/g, '➔')
                                .replace(/\\$?\\\\leftarrow\\$?|\\\\leftarrow/g, '⬅')
                                .replace(/\\$?\\\\longleftarrow\\$?|\\\\longleftarrow/g, '⬅')
                                .replace(/\\$?\\\\le(?:q)?(?![a-zA-Z])\\$?|\\\\le(?:q)?(?![a-zA-Z])/g, '≤')
                                .replace(/\\$?\\\\ge(?:q)?(?![a-zA-Z])\\$?|\\\\ge(?:q)?(?![a-zA-Z])/g, '≥')
                                .replace(/\\$?\\\\ne(?:q)?(?![a-zA-Z])\\$?|\\\\ne(?:q)?(?![a-zA-Z])/g, '≠')
                                .replace(/\\$?\\\\approx\\$?|\\\\approx/g, '≈')
                                .replace(/\\$?\\\\times\\$?|\\\\times/g, '×')
                                .replace(/\\$?\\\\cdot\\$?|\\\\cdot/g, '·')
                                .replace(/\\$?\\\\pm\\$?|\\\\pm/g, '±')
                                .replace(/\\$?\\\\in(?![a-zA-Z])\\$?|\\\\in(?![a-zA-Z])/g, '∈')
                                .replace(/\\$?\\\\notin\\$?|\\\\notin/g, '∉')
                                .replace(/\\$?\\\\dots\\$?|\\\\dots/g, '…')
                                .replace(/\\$?\\\\infty\\$?|\\\\infty/g, '∞')
                                .replace(/O\\(\\s*n\\s*\\^\\s*2\\s*\\)/g, 'O(n²)')
                                .replace(/O\\(\\s*n\\s*\\^\\s*3\\s*\\)/g, 'O(n³)')
                                .replace(/O\\(\\s*1\\s*\\)/g, 'O(1)')
                                .replace(/O\\(\\s*n\\s*\\)/g, 'O(n)')
                                .replace(/\\\\log(?:_2)?/g, 'log')
                                .replace(/\\$([^$]+)\\$/g, '$1');
                            if (s !== raw) {{
                                el.textContent = s;
                                hasSanitizedLatex = true;
                            }}
                        }}
                    }});
                    if (hasSanitizedLatex) {{
                        calibs.push('sanitized_latex_math_formulas');
                    }}

                    // Gỡ bỏ triệt để footer-note hoặc box chú thích nguyên lý ở đáy màn hình để nhường chỗ cho phụ đề
                    const footerNote = document.getElementById('footer-note');
                    if (footerNote) {{
                        footerNote.remove();
                        calibs.push('removed_bottom_footer_note');
                    }}

                    // Tự động kiểm tra và nâng kích thước tiêu đề chính đỉnh (56-62px), giảm cỡ chữ text phụ dẫn nhập (24px) và chống đè viền
                    const headerGroup = document.getElementById('header-group') || document.querySelector('g[id*="header"], g[id*="title"]');
                    if (headerGroup) {{
                        const hTexts = Array.from(headerGroup.querySelectorAll('text'));
                        const hPaths = Array.from(headerGroup.querySelectorAll('path, line'));

                        // 1. Chuẩn hóa font-size tiêu đề chính và text phụ
                        const mainTitleEl = hTexts[0];
                        hTexts.forEach((el, idx) => {{
                            const comp = window.getComputedStyle(el);
                            const fs = parseFloat(comp.fontSize || 0);
                            const yAttr = parseFloat(el.getAttribute('y') || 0);
                            const textLen = (el.textContent || '').trim().length;
                            if ((idx === 0 || yAttr <= 30)) {{
                                if (textLen <= 35 && fs < 52) {{
                                    el.setAttribute('font-size', '58');
                                    el.style.fontSize = '58px';
                                    calibs.push('amplified_main_title_to_58px');
                                }}
                            }} else if (idx === 1 || (yAttr > 30 && yAttr <= 165)) {{
                                if (fs > 26 || fs < 22) {{
                                    el.setAttribute('font-size', '24');
                                    el.style.fontSize = '24px';
                                    calibs.push('adjusted_sub_title_to_24px');
                                }}
                            }}
                        }});

                        // Tự động kiểm tra và co cỡ chữ tiêu đề chính nếu bị tràn lề màn hình
                        if (mainTitleEl) {{
                            const tr = mainTitleEl.getBoundingClientRect();
                            const maxAllowedWidth = width - 260; // chừa lề an toàn mỗi bên >= 130px
                            if (tr.width > maxAllowedWidth || tr.left < 50 || tr.right > width - 50) {{
                                const currentFs = parseFloat(window.getComputedStyle(mainTitleEl).fontSize || 58);
                                const scaleFactor = maxAllowedWidth / Math.max(tr.width, 1);
                                const safeFs = Math.max(30, Math.floor(currentFs * Math.min(0.9, scaleFactor)));
                                mainTitleEl.setAttribute('font-size', String(safeFs));
                                mainTitleEl.style.fontSize = safeFs + 'px';
                                calibs.push('scaled_main_title_to_' + safeFs + 'px_to_fit_canvas');
                            }}
                        }}

                        // 2. Chống lỗi đường gạch chân đỏ (underline) đè lên chữ text phụ dưới tiêu đề
                        if (hTexts.length >= 2 && hPaths.length > 0) {{
                            const subEl = hTexts[1];
                            let subY = parseFloat(subEl.getAttribute('y') || 65);
                            hPaths.forEach(p => {{
                                const d = p.getAttribute('d') || '';
                                const m = d.match(/M\\s*([-\\d\\.]+)\\s+([-\\d\\.]+)/i);
                                if (m) {{
                                    const lineY = parseFloat(m[2]);
                                    if (lineY >= subY - 20 || lineY > 28) {{
                                        const newD = d.replace(/(M\\s*[-\\d\\.]+\\s+)[-\\d\\.]+/i, '$118')
                                                      .replace(/(Q\\s*[-\\d\\.]+\\s+)[-\\d\\.]+/i, '$124')
                                                      .replace(/(\\s+[-\\d\\.]+\\s+)[-\\d\\.]+(\\s*$)/i, '$118$2');
                                        p.setAttribute('d', newD);
                                        calibs.push('retracted_header_underline_to_y18');
                                    }}
                                }}
                            }});
                            if (subY < 60) {{
                                subEl.setAttribute('y', '65');
                                calibs.push('shifted_sub_title_to_y65');
                            }}
                        }}

                        // Tự động căn chỉnh độ rộng đường gạch chân đỏ ôm sát tiêu đề chính nếu có
                        if (mainTitleEl && hPaths.length > 0) {{
                            const tr = mainTitleEl.getBoundingClientRect();
                            if (tr.width > 0) {{
                                const halfW = Math.min(650, Math.max(160, Math.round(tr.width * 0.52)));
                                hPaths.forEach(p => {{
                                    const d = p.getAttribute('d') || '';
                                    if (/M\\s*[-\\d\\.]+\\s+[-\\d\\.]+\\s+Q/i.test(d)) {{
                                        p.setAttribute('d', `M -${{halfW}} 18 Q 0 24 ${{halfW}} 18`);
                                    }}
                                }});
                            }}
                        }}
                    }}

                    textEls.forEach(el => {{
                        const comp = window.getComputedStyle(el);
                        let fs = parseFloat(comp.fontSize || 0);
                        const yAttr = parseFloat(el.getAttribute('y') || 0);

                        if (!headerGroup) {{
                            const textLen = (el.textContent || '').trim().length;
                            if (yAttr > 0 && yAttr <= 95 && fs < 52 && fs >= 28 && textLen <= 35) {{
                                el.setAttribute('font-size', '58');
                                el.style.fontSize = '58px';
                                fs = 58;
                                calibs.push('amplified_main_title_to_58px');
                            }} else if (yAttr > 95 && yAttr <= 165 && (fs > 26 || fs < 22)) {{
                                el.setAttribute('font-size', '24');
                                el.style.fontSize = '24px';
                                fs = 24;
                                calibs.push('adjusted_sub_title_to_24px');
                            }}
                        }}

                        // Bảo vệ độ tương phản: nếu thẻ text có fill="#fff" nhưng bị CSS cascade ghi đè
                        const fillAttr = (el.getAttribute('fill') || '').toLowerCase();
                        if (fillAttr === '#fff' || fillAttr === '#ffffff' || fillAttr === 'white') {{
                            el.classList.add('text-white');
                            el.style.fill = '#ffffff';
                        }}
                    }});

                    // 3. Kiểm tra tràn viền & cắt cụt nội dung (Boundary Safety Check)
                    let boundaryViolations = [];
                    textEls.forEach(el => {{
                        if (isElementHidden(el)) return;
                        const r = el.getBoundingClientRect();
                        if (r.width > 0 && r.height > 0) {{
                            if (r.left < 10 || r.top < 15 || r.right > width + 15) {{
                                boundaryViolations.push({{
                                    text: el.textContent.trim(),
                                    left: Math.round(r.left),
                                    top: Math.round(r.top),
                                    right: Math.round(r.right)
                                }});
                            }}
                        }}
                    }});
                    if (boundaryViolations.length > 0) {{
                        details.boundary_safety.violations = boundaryViolations;
                        details.boundary_safety.score = Math.max(0, 25 - boundaryViolations.length * 6);
                        if (boundaryViolations.length > 1) {{
                            details.boundary_safety.passed = false;
                        }}
                    }}

                    // 4. Đo đạc Bounding Box, Chống lấn vùng phụ đề đáy & Tự động Cân giữa sơ đồ
                    const allSvgs = Array.from(document.querySelectorAll('svg'));
                    const svg = document.getElementById('svg') || allSvgs.find(s => {{
                        const vb = s.getAttribute('viewBox') || '';
                        const parts = vb.trim().split(/\\s+/).map(parseFloat);
                        return parts.length === 4 && parts[2] >= 500 && parts[3] >= 300;
                    }}) || allSvgs[0];
                    const mainCanvas = (svg ? svg.querySelector('#main-canvas') : null) || svg;
                    let maxY = 0;
                    if (svg) {{
                        const elements = Array.from(svg.querySelectorAll('g, rect, text, path, circle'));
                        elements.forEach(el => {{
                            try {{
                                if (el.tagName && el.tagName.toLowerCase() === 'rect') {{
                                    const wAttr = el.getAttribute('width') || '';
                                    if (wAttr.includes('%') || parseFloat(wAttr) >= 1800) return;
                                    const ident = ((el.id || '') + ' ' + (el.getAttribute('class') || '') + ' ' + (el.getAttribute('fill') || '')).toLowerCase();
                                    if (ident.includes('grid') || ident.includes('bg') || ident.includes('grain')) return;
                                }}
                                const bbox = el.getBBox();
                                if (bbox && (bbox.width > 0 || bbox.height > 0)) {{
                                    const bottom = bbox.y + bbox.height;
                                    if (bottom > maxY) maxY = bottom;
                                }}
                            }} catch(_) {{}}
                        }});
                    }}

                    details.subtitle_safety.max_y = Math.round(maxY);
                    if (maxY > subLimit) {{
                        const deltaY = maxY - subLimit + 25;
                        if (mainCanvas && mainCanvas !== svg) {{
                            applyTransformTranslate(mainCanvas, 0, -Math.round(deltaY));
                            calibs.push(`shifted_up_${{Math.round(deltaY)}}px_for_subtitles`);
                            details.subtitle_safety.score = 20;
                        }} else {{
                            details.subtitle_safety.passed = false;
                            details.subtitle_safety.score = 5;
                            details.subtitle_safety.warning = `Nội dung lấn vào vùng cấm phụ đề đáy (${{Math.round(maxY)}}px > ${{subLimit}}px)`;
                        }}
                    }}

                    // Kiểm tra cấm giao diện Player Controls / Scrubber
                    const forbiddenControls = document.querySelector('input[type="range"], .scrubber, .footer-bar, button');
                    if (forbiddenControls) {{
                        details.timing_contract.passed = false;
                        details.timing_contract.score = 0;
                        details.timing_contract.message = 'Phát hiện tạo giao diện player controls / scrubber cấm. Video được render tự động qua Playwright, không dùng HTML UI controls.';
                    }}

                    // Kiểm tra cấm container thu nhỏ
                    const squeezedContainer = document.querySelector('.container, .canvas-container');
                    if (squeezedContainer) {{
                        const cs = window.getComputedStyle(squeezedContainer);
                        const cw = parseFloat(cs.width || 0);
                        if (cw > 0 && cw < width - 100) {{
                            details.layout_occupancy.passed = false;
                            details.layout_occupancy.score = 0;
                            details.layout_occupancy.warning = 'Phát hiện bọc SVG vào container thu nhỏ có width cố định. Bắt buộc SVG chiếm trọn 100vw x 100vh.';
                        }}
                    }}

                    // A. CĂN GIỮA THEO HÀNG NGANG (Row-Level Subgroup Auto-Centering)
                    // Chỉ áp dụng cho các group biểu diễn danh sách/mảng phần tử nằm ngang (VD: cards-row, array-items, steps-row)
                    // Tuyệt đối không áp dụng cho các node đơn lẻ trong sơ đồ kiến trúc (server, client, db, tech, box, v.v.)
                    const sceneGroups = Array.from(svg.querySelectorAll('g[id^="scene-"], g[id^="step-"]'));
                    const isSingleNodeName = (name) => {{
                        const raw = (name && typeof name === 'object' && name.baseVal !== undefined) ? name.baseVal : name;
                        const n = String(raw || '').toLowerCase();
                        return /client|server|tech|user|database|\bdb\b|worker|balancer|\blb\b|router|gateway|hero|panel|pillar|badge|pill|item-\d|card-elem-\d/.test(n);
                    }};

                    const candidateRowGroups = Array.from(svg.querySelectorAll(
                        'g[id*="row"], g[id*="array"], g[id*="cards"], g[id*="items-group"], g[id*="items-row"], g[class*="row"], g[class*="cards"]'
                    )).filter(rg => !isSingleNodeName(rg.id) && !isSingleNodeName(rg.className && rg.className.baseVal ? rg.className.baseVal : rg.className));

                    candidateRowGroups.forEach(rg => {{
                        if (isIgnored(rg)) return;
                        if (rg.closest && rg.closest('#header-group, [id*="header"], [id*="title"]')) return;

                        const rItems = Array.from(rg.querySelectorAll('rect, circle, text')).filter(el => {{
                            if (isIgnored(el)) return false;
                            const w = parseFloat(el.getAttribute('width') || 0);
                            const h = parseFloat(el.getAttribute('height') || 0);
                            if (w >= 1800 || h >= 1000) return false;
                            return true;
                        }});

                        if (rItems.length < 2) return;

                        let rMinX = 9999, rMaxX = -9999;
                        let minCenterX = 9999, maxCenterX = -9999;
                        const s = svg.getBoundingClientRect();
                        const scaleX = (svg.viewBox.baseVal.width || 1920) / s.width;

                        rItems.forEach(el => {{
                            const r = el.getBoundingClientRect();
                            if (r.width > 5) {{
                                const left = (r.left - s.left) * scaleX;
                                const right = (r.right - s.left) * scaleX;
                                const mid = (left + right) / 2;
                                if (left < rMinX) rMinX = left;
                                if (right > rMaxX) rMaxX = right;
                                if (mid < minCenterX) minCenterX = mid;
                                if (mid > maxCenterX) maxCenterX = mid;
                            }}
                        }});

                        // Một hàng ngang (row) hợp lệ bắt buộc các phần tử con phải phân tán theo trục X ít nhất 150px
                        // (Nếu maxCenterX - minCenterX < 150px, đó chỉ là 1 thẻ/khối đơn lẻ chứa nhiều text/rect đồng tâm, không phải mảng ngang)
                        if (maxCenterX - minCenterX < 150) return;

                        if (rMinX < rMaxX) {{
                            const rSpanW = rMaxX - rMinX;
                            if (rSpanW >= 250 && rSpanW <= 1750) {{
                                const rowMidX = (rMinX + rMaxX) / 2;
                                const targetMidX = width / 2;
                                const rowOffset = rowMidX - targetMidX;

                                if (Math.abs(rowOffset) > 25) {{
                                    const shiftX = Math.round(-rowOffset);
                                    applyTransformTranslate(rg, shiftX, 0);
                                    calibs.push(`auto_centered_row_${{rg.id || 'group'}}_dx_${{shiftX}}px`);
                                }}
                            }}
                        }}
                    }});

                    // B. Đo độ phủ ngang, căn giữa diagram đối xứng & Cân bằng dọc (Vertical Auto-Balance)
                    const targetsToCenter = sceneGroups.length > 0 ? sceneGroups : (mainCanvas && mainCanvas !== svg ? [mainCanvas] : [svg]);

                    let globalSpanW = 0;
                    targetsToCenter.forEach(tg => {{
                        const entities = Array.from(tg.querySelectorAll('rect, circle, text')).filter(el => {{
                            if (isIgnored(el)) return false;
                            if (el.closest && el.closest('#header-group, [id*="header"], [id*="title"], [id*="dot"], .flow-pulse, [id*="particle"]')) return false;
                            const w = parseFloat(el.getAttribute('width') || 0);
                            const h = parseFloat(el.getAttribute('height') || 0);
                            if (w >= 1800 || h >= 1000) return false;
                            return true;
                        }});
                        let minX = 9999, maxX = -9999;
                        let minY = 9999, maxY = -9999;
                        const s = svg.getBoundingClientRect();
                        const scaleX = (svg.viewBox.baseVal.width || 1920) / s.width;
                        const scaleY = (svg.viewBox.baseVal.height || 1080) / s.height;

                        entities.forEach(el => {{
                            const r = el.getBoundingClientRect();
                            const left = (r.left - s.left) * scaleX;
                            const right = (r.right - s.left) * scaleX;
                            const top = (r.top - s.top) * scaleY;
                            const bottom = (r.bottom - s.top) * scaleY;
                            if (r.width > 15 && r.height > 15) {{
                                if (left < minX) minX = left;
                                if (right > maxX) maxX = right;
                                if (top < minY) minY = top;
                                if (bottom > maxY) maxY = bottom;
                            }}
                        }});

                        if (minX < maxX) {{
                            const spanW = maxX - minX;
                            if (spanW > globalSpanW) globalSpanW = spanW;
                            const midX = (minX + maxX) / 2;
                            const targetMidX = width / 2;
                            const offset = midX - targetMidX;
                            const leftMargin = minX;
                            const rightMargin = width - maxX;
                            const diffMargins = Math.abs(leftMargin - rightMargin);

                            // Tự động căn giữa nếu sơ đồ bị lệch biên quá 30px hoặc 2 lề lệch nhau quá 60px
                            if (spanW > 120 && (Math.abs(offset) > 30 || diffMargins > 60) && tg !== svg) {{
                                const shiftX = Math.round(-offset);
                                applyTransformTranslate(tg, shiftX, 0);
                                calibs.push(`auto_centered_${{tg.id || 'scene'}}_dx_${{shiftX}}px`);

                                const innerHeader = tg.querySelector('g[id*="header"]');
                                if (innerHeader) {{
                                    applyTransformTranslate(innerHeader, -shiftX, 0);
                                }}
                            }}
                        }}

                        // Cân bằng dọc (Vertical Auto-Balance)
                        // Tự động phát hiện khoảng trống lớn dưới tiêu đề khi nội dung bị dồn sát đáy
                        if (minY < maxY) {{
                            const cSpanH = maxY - minY;
                            const headerBottomSafe = 145;
                            const subtitleTopSafe = subLimit; // 940 (16:9)

                            const topGap = minY - headerBottomSafe;
                            const bottomGap = subtitleTopSafe - maxY;

                            if (topGap > 200 && bottomGap < 180 && cSpanH <= 720 && tg !== svg) {{
                                const contentMidY = (minY + maxY) / 2;
                                const targetMidY = (headerBottomSafe + subtitleTopSafe) / 2; // ~542.5
                                const desiredShiftY = targetMidY - contentMidY; // số âm (kéo lên)

                                const maxUpShift = -(minY - (headerBottomSafe + 30));
                                const safeShiftY = Math.max(maxUpShift, desiredShiftY);

                                if (safeShiftY < -30) {{
                                    const shiftY = Math.round(safeShiftY);
                                    applyTransformTranslate(tg, 0, shiftY);
                                    calibs.push(`auto_vertical_balance_${{tg.id || 'scene'}}_dy_${{shiftY}}px`);
                                }}
                            }}
                        }}
                    }});

                    const ratio = Math.round((globalSpanW / width) * 100) / 100;
                    details.layout_occupancy.span_w = Math.round(globalSpanW);
                    details.layout_occupancy.occupancy_ratio = ratio;

                    if (ratio < 0.50 && globalSpanW > 0) {{
                        details.layout_occupancy.score = Math.max(5, Math.round(ratio * 50));
                        details.layout_occupancy.warning = (details.layout_occupancy.warning ? details.layout_occupancy.warning + ' ' : '') + 'Độ phủ ngang chỉ đạt ' + Math.round(ratio * 100) + '%, khuyến nghị >= 65%';
                    }} else if (globalSpanW === 0 && !details.layout_occupancy.warning) {{
                        details.layout_occupancy.passed = false;
                        details.layout_occupancy.score = 0;
                        details.layout_occupancy.warning = 'Không tìm thấy các phần tử đồ họa có kích thước hợp lệ trên khung hình.';
                    }}

                    // 5. Kiểm tra & tự động rút ngắn mũi tên đâm xuyên vào thân hộp (Arrow Penetration Auto-Retract)
                    if (svg) {{
                        const arrowPaths = Array.from(svg.querySelectorAll('path[marker-end], path[id*="conn"], path[id*="arrow"], path[id^="path-"]'));
                        const contentBoxes = Array.from(svg.querySelectorAll('rect')).filter(r => {{
                            if (isIgnored(r)) return false;
                            const w = parseFloat(r.getAttribute('width') || 0);
                            const h = parseFloat(r.getAttribute('height') || 0);
                            const cls = ((r.getAttribute('class') || '') + ' ' + (r.id || '')).toLowerCase();
                            if (cls.includes('shadow') || cls.includes('grain') || cls.includes('grid')) return false;
                            return w >= 140 && h >= 80 && !r.id.includes('page-bg') && !r.id.includes('stage-bg');
                        }});

                        // Kiểm tra chống co cụm vào dải hẹp giữa màn hình
                        if (contentBoxes.length >= 3 && details.layout_occupancy.span_w > 0 && details.layout_occupancy.span_w < 1050) {{
                            details.layout_occupancy.passed = false;
                            details.layout_occupancy.score = Math.max(5, Math.round((details.layout_occupancy.span_w / 1200) * 20));
                            details.layout_occupancy.warning = `Phát hiện các khối co cụm vào dải hẹp giữa màn hình (độ phủ ngang chỉ đạt ${{details.layout_occupancy.span_w}}px). Với ${{contentBoxes.length}} khối, hãy dàn trải đều từ lề trái (X ≈ 140..200) sang lề phải (X ≈ 1400..1700), tận dụng tối đa không gian canvas.`;
                        }}

                        // Kiểm tra kích thước hộp Server/Service/Component
                        let tinyBoxes = 0;
                        contentBoxes.forEach(r => {{
                            const w = parseFloat(r.getAttribute('width') || 0);
                            if (w < 280) tinyBoxes++;
                        }});
                        if (tinyBoxes > 0) {{
                            details.layout_occupancy.warning = (details.layout_occupancy.warning || '') + ' Có ' + tinyBoxes + ' hộp kích thước nhỏ (< 280px), cần mở rộng để xem tốt trên mobile.';
                            details.layout_occupancy.score = Math.max(5, details.layout_occupancy.score - tinyBoxes * 3);
                        }}

                        // CONNECTOR ANCHOR SNAP ENGINE: Tự động gắn kết đầu và đuôi mũi tên chuẩn xác vào mép hộp (Point A -> Point B)
                        function getSvgBoxBounds(el) {{
                            const r = el.getBoundingClientRect();
                            const s = svg.getBoundingClientRect();
                            const scaleX = (svg.viewBox.baseVal.width || 1920) / s.width;
                            const scaleY = (svg.viewBox.baseVal.height || 1080) / s.height;
                            const parentG = el.closest('g');
                            const stroke = (el.getAttribute('stroke') || (parentG ? parentG.getAttribute('stroke') : '') || '').toLowerCase();
                            const textContent = (parentG ? parentG.textContent : '') || '';
                            const id = el.id || (parentG ? parentG.id : '');
                            const scene = el.closest('g[id^="scene-"], g[id^="step-"]');
                            return {{
                                el: el,
                                id: id,
                                sceneId: scene ? scene.id : null,
                                stroke: stroke,
                                text: textContent,
                                left: (r.left - s.left) * scaleX,
                                right: (r.right - s.left) * scaleX,
                                top: (r.top - s.top) * scaleY,
                                bottom: (r.bottom - s.top) * scaleY,
                                centerX: ((r.left + r.right) / 2 - s.left) * scaleX,
                                centerY: ((r.top + r.bottom) / 2 - s.top) * scaleY,
                                width: r.width * scaleX,
                                height: r.height * scaleY
                            }};
                        }}

                        const contentNodes = Array.from(svg.querySelectorAll('rect, circle')).filter(el => {{
                            if (isIgnored(el)) return false;
                            const cls = ((el.getAttribute('class') || '') + ' ' + (el.id || '')).toLowerCase();
                            if (cls.includes('shadow') || cls.includes('grain') || cls.includes('grid') || cls.includes('dot') || cls.includes('particle')) return false;
                            if (el.tagName.toLowerCase() === 'rect') {{
                                const w = parseFloat(el.getAttribute('width') || 0);
                                const h = parseFloat(el.getAttribute('height') || 0);
                                const fill = (el.getAttribute('fill') || '').toLowerCase();
                                if (fill === '#e1d8c5' || fill === '#d5ccb8' || fill === '#e8dfce' || fill.includes('shadow')) return false;
                                return w >= 120 && h >= 60 && !el.id.includes('page-bg') && !el.id.includes('stage-bg');
                            }} else if (el.tagName.toLowerCase() === 'circle') {{
                                const r = parseFloat(el.getAttribute('r') || 0);
                                const parent = el.parentElement;
                                if (parent && (parent.classList.contains('flow-pulse') || (parent.id && parent.id.includes('dot')))) return false;
                                return r >= 35;
                            }}
                            return false;
                        }});

                        const boxBoundsList = contentNodes.map(b => getSvgBoxBounds(b));
                        const assignedDstForSrc = new Map();

                        function clientToLocal(clientX, clientY, targetContainer) {{
                            const pt = svg.createSVGPoint();
                            pt.x = clientX;
                            pt.y = clientY;
                            const ctm = targetContainer && targetContainer.getScreenCTM ? targetContainer.getScreenCTM() : null;
                            if (!ctm) {{
                                const s = svg.getBoundingClientRect();
                                const scaleX = (svg.viewBox.baseVal.width || 1920) / s.width;
                                const scaleY = (svg.viewBox.baseVal.height || 1080) / s.height;
                                return {{
                                    x: (clientX - s.left) * scaleX,
                                    y: (clientY - s.top) * scaleY
                                }};
                            }}
                            const matrix = ctm.inverse();
                            return pt.matrixTransform(matrix);
                        }}

                        arrowPaths.forEach(p => {{
                            const d = (p.getAttribute('d') || '').trim();
                            const nums = d.replace(/[a-zA-Z,]/g, ' ').trim().split(/\\s+/).map(parseFloat).filter(n => !isNaN(n));
                            if (nums.length >= 4) {{
                                const startX = nums[0];
                                const startY = nums[1];
                                const endX = nums[nums.length - 2];
                                const endY = nums[nums.length - 1];

                                const pScene = p.closest('g[id^="scene-"], g[id^="step-"]');
                                const pSceneId = pScene ? pScene.id : null;

                                // 1. Phạm vi Scene: chỉ tìm box trong cùng Scene
                                const candidates = boxBoundsList.filter(b => {{
                                    if (!pSceneId) return true;
                                    return b.sceneId === pSceneId;
                                }});

                                // 2. Tìm box nguồn A (srcBox)
                                let srcBox = null;
                                let minSrcDist = 99999;
                                candidates.forEach(b => {{
                                    const dist = Math.abs(startX - b.right);
                                    if (dist < minSrcDist && startX >= b.left - 50 && startX <= b.right + 220 && Math.abs(startY - b.centerY) < b.height * 0.95) {{
                                        minSrcDist = dist;
                                        srcBox = b;
                                    }}
                                }});

                                if (!srcBox) {{
                                    candidates.forEach(b => {{
                                        const dist = Math.hypot(startX - b.centerX, startY - b.centerY);
                                        if (dist < minSrcDist && dist < 320) {{
                                            minSrcDist = dist;
                                            srcBox = b;
                                        }}
                                    }});
                                }}

                                if (!srcBox) return;

                                // 3. Tìm box đích B (dstBox)
                                const dstCandidates = candidates.filter(b => b.el !== srcBox.el);
                                if (dstCandidates.length === 0) return;

                                if (!assignedDstForSrc.has(srcBox.el)) {{
                                    assignedDstForSrc.set(srcBox.el, new Set());
                                }}
                                const assignedSet = assignedDstForSrc.get(srcBox.el);

                                const arrowStroke = (p.getAttribute('stroke') || '').toLowerCase();
                                const markerEnd = (p.getAttribute('marker-end') || '').toLowerCase();
                                const isRedArrow = arrowStroke.includes('red') || arrowStroke.includes('b5533c') || markerEnd.includes('red');
                                const isGreenArrow = arrowStroke.includes('green') || arrowStroke.includes('2e7d52') || markerEnd.includes('green');
                                const isBlueArrow = arrowStroke.includes('blue') || arrowStroke.includes('1e40af') || markerEnd.includes('blue');

                                let dstBox = null;
                                const downstreamCandidates = dstCandidates.filter(b => b.centerX > srcBox.right - 60);
                                const pool = downstreamCandidates.length > 0 ? downstreamCandidates : dstCandidates;

                                if (isRedArrow) {{
                                    dstBox = pool.find(b => !assignedSet.has(b.el) && (b.stroke.includes('red') || b.stroke.includes('b5533c') || /fail|lỗi|crash|error|sự cố/i.test(b.text)));
                                }} else if (isGreenArrow) {{
                                    dstBox = pool.find(b => !assignedSet.has(b.el) && (b.stroke.includes('green') || b.stroke.includes('2e7d52') || /backup|dự phòng|active|ha|sẵn sàng|success/i.test(b.text)));
                                }} else if (isBlueArrow) {{
                                    dstBox = pool.find(b => !assignedSet.has(b.el) && (b.stroke.includes('blue') || b.stroke.includes('1e40af') || b.stroke.includes('accent-blue')));
                                }}

                                if (!dstBox) {{
                                    let bestScore = 99999;
                                    pool.forEach(b => {{
                                        let score = Math.abs(endX - b.left) + Math.abs(endY - b.centerY);
                                        if (assignedSet.has(b.el)) score += 600;
                                        if (score < bestScore) {{
                                            bestScore = score;
                                            dstBox = b;
                                        }}
                                    }});
                                }}

                                if (!dstBox) {{
                                    let bestScore = 99999;
                                    dstCandidates.forEach(b => {{
                                        let score = Math.hypot(endX - b.centerX, endY - b.centerY);
                                        if (assignedSet.has(b.el)) score += 600;
                                        if (score < bestScore) {{
                                            bestScore = score;
                                            dstBox = b;
                                        }}
                                    }});
                                }}

                                if (srcBox && dstBox) {{
                                    assignedSet.add(dstBox.el);

                                    const rSrc = srcBox.el.getBoundingClientRect();
                                    const rDst = dstBox.el.getBoundingClientRect();
                                    const pContainer = p.parentElement || svg;

                                    let newStartX, newStartY, newEndX, newEndY;
                                    let newPathD = '';

                                    const isVertical = dstBox.top >= srcBox.bottom - 60 && Math.abs(srcBox.centerX - dstBox.centerX) < 220;
                                    const isRightToLeft = dstBox.right <= srcBox.left + 60;

                                    if (isVertical) {{
                                        const pStart = clientToLocal((rSrc.left + rSrc.right) / 2, rSrc.bottom, pContainer);
                                        const pEnd = clientToLocal((rDst.left + rDst.right) / 2, rDst.top - 6, pContainer);
                                        newStartX = Math.round(pStart.x);
                                        newStartY = Math.round(pStart.y);
                                        newEndX = Math.round(pEnd.x);
                                        newEndY = Math.round(pEnd.y);

                                        if (Math.abs(newStartX - newEndX) > 20) {{
                                            const midY = Math.round((newStartY + newEndY) / 2);
                                            newPathD = `M ${{newStartX}} ${{newStartY}} C ${{newStartX}} ${{midY}} ${{newEndX}} ${{midY}} ${{newEndX}} ${{newEndY}}`;
                                        }} else {{
                                            newPathD = `M ${{newStartX}} ${{newStartY}} L ${{newEndX}} ${{newEndY}}`;
                                        }}
                                    }} else if (isRightToLeft) {{
                                        const pStart = clientToLocal(rSrc.left, (rSrc.top + rSrc.bottom) / 2, pContainer);
                                        const pEnd = clientToLocal(rDst.right + 6, (rDst.top + rDst.bottom) / 2, pContainer);
                                        newStartX = Math.round(pStart.x);
                                        newStartY = Math.round(pStart.y);
                                        newEndX = Math.round(pEnd.x);
                                        newEndY = Math.round(pEnd.y);
                                        newPathD = `M ${{newStartX}} ${{newStartY}} L ${{newEndX}} ${{newEndY}}`;
                                    }} else {{
                                        let srcContactY = (rSrc.top + rSrc.bottom) / 2;
                                        if (rDst.top + rDst.height / 2 < rSrc.top + rSrc.height / 2 - 45) {{
                                            srcContactY = (rSrc.top + rSrc.bottom) / 2 - 35;
                                        }} else if (rDst.top + rDst.height / 2 > rSrc.top + rSrc.height / 2 + 45) {{
                                            srcContactY = (rSrc.top + rSrc.bottom) / 2 + 35;
                                        }}
                                        const pStart = clientToLocal(rSrc.right, srcContactY, pContainer);
                                        const pEnd = clientToLocal(rDst.left - 6, (rDst.top + rDst.bottom) / 2, pContainer);
                                        newStartX = Math.round(pStart.x);
                                        newStartY = Math.round(pStart.y);
                                        newEndX = Math.round(pEnd.x);
                                        newEndY = Math.round(pEnd.y);

                                        if (Math.abs(newStartY - newEndY) > 20) {{
                                            const midX = Math.round((newStartX + newEndX) / 2);
                                            newPathD = `M ${{newStartX}} ${{newStartY}} C ${{midX}} ${{newStartY}} ${{midX}} ${{newEndY}} ${{newEndX}} ${{newEndY}}`;
                                        }} else {{
                                            newPathD = `M ${{newStartX}} ${{newStartY}} L ${{newEndX}} ${{newEndY}}`;
                                        }}
                                    }}

                                    p.setAttribute('d', newPathD);
                                    p.style.opacity = '1';
                                    p.style.visibility = 'visible';

                                    if (typeof p.getTotalLength === 'function') {{
                                        const newLen = Math.round(p.getTotalLength());
                                        const sda = p.getAttribute('stroke-dasharray') || p.style.strokeDasharray;
                                        if (sda && !sda.includes(' ') && parseFloat(sda) > 50) {{
                                            p.setAttribute('stroke-dasharray', `${{newLen}}`);
                                            if (p.style.strokeDasharray) p.style.strokeDasharray = `${{newLen}}`;
                                        }}
                                    }}

                                    calibs.push('snapped_arrow_' + (p.id || 'conn') + '_to_anchor');
                                }}
                            }}
                        }});

                        // 6. Tự động nắn chỉnh Status Pill đè lên viền đáy Box lớn (Border Inset Auto-Correction)
                        contentBoxes.forEach(box => {{
                            try {{
                                const boxY = parseFloat(box.getAttribute('y') || 0);
                                const boxH = parseFloat(box.getAttribute('height') || 0);
                                const parentG = box.closest('g');
                                if (!parentG) return;

                                const pills = Array.from(parentG.querySelectorAll('rect')).filter(r => {{
                                    if (r === box) return false;
                                    const pw = parseFloat(r.getAttribute('width') || 0);
                                    const ph = parseFloat(r.getAttribute('height') || 0);
                                    const cls = ((r.getAttribute('class') || '') + ' ' + (r.id || '')).toLowerCase();
                                    if (cls.includes('shadow') || cls.includes('grain')) return false;
                                    return pw > 100 && pw <= 300 && ph >= 30 && ph <= 65;
                                }});

                                pills.forEach(pill => {{
                                    const py = parseFloat(pill.getAttribute('y') || 0);
                                    const ph = parseFloat(pill.getAttribute('height') || 0);
                                    const pillBottom = py + ph;
                                    const boxBottom = boxY + boxH;

                                    if (pillBottom > boxBottom - 18) {{
                                        const safeY = Math.round(boxBottom - ph - 20);
                                        const dy = safeY - py;
                                        pill.setAttribute('y', String(safeY));

                                        const texts = Array.from(parentG.querySelectorAll('text'));
                                        texts.forEach(tEl => {{
                                            const ty = parseFloat(tEl.getAttribute('y') || 0);
                                            if (ty >= py - 5 && ty <= pillBottom + 15) {{
                                                tEl.setAttribute('y', String(Math.round(ty + dy)));
                                            }}
                                        }});
                                        calibs.push('retracted_pill_badge_away_from_box_border');
                                    }}
                                }});
                            }} catch(_) {{}}
                        }});

                        // 7. Tự động kiểm tra và bảo vệ Text Tiêu Đề không bị icon / tia sét sự cố đè lên
                        contentBoxes.forEach(box => {{
                            try {{
                                const parentG = box.closest('g');
                                if (!parentG) return;
                                const titleText = parentG.querySelector('text.title-text') || Array.from(parentG.querySelectorAll('text')).find(t => {{
                                    const fs = parseFloat(window.getComputedStyle(t).fontSize || 0);
                                    return fs >= 28 && !t.closest('g[id*="header"]');
                                }});
                                if (!titleText) return;
                                const tr = titleText.getBoundingClientRect();
                                if (tr.width <= 0) return;

                                const warningShapes = Array.from(parentG.querySelectorAll('path, polygon, circle')).filter(el => {{
                                    const ident = ((el.id || '') + ' ' + (el.getAttribute('class') || '') + ' ' + (el.getAttribute('fill') || '') + ' ' + (el.getAttribute('stroke') || '')).toLowerCase();
                                    return ident.includes('crash') || ident.includes('lightning') || ident.includes('fault') || ident.includes('bolt') || ident.includes('warn') || ident.includes('error') || ident.includes('#b5533c');
                                }});

                                warningShapes.forEach(shape => {{
                                    const sr = shape.getBoundingClientRect();
                                    if (sr.width > 0 && sr.left < tr.right && sr.right > tr.left && sr.top < tr.bottom && sr.bottom > tr.top) {{
                                        const shiftDist = Math.round(sr.bottom - tr.top + 25);
                                        applyTransformTranslate(shape, 0, -shiftDist);
                                        calibs.push('shifted_warning_shape_away_from_title_text');
                                    }}
                                }});
                            }} catch(_) {{}}
                        }});
                    }}

                    const totalScore = details.timing_contract.score +
                                       details.subtitle_safety.score +
                                       details.boundary_safety.score +
                                       details.layout_occupancy.score;

                    return {{
                        content: document.documentElement.outerHTML,
                        calibrations: calibs,
                        quality_score: totalScore,
                        passed: totalScore >= 75 && details.timing_contract.passed && details.boundary_safety.passed && details.layout_occupancy.passed,
                        eval_details: details
                    }};
                }})()
                """
                eval_res = page.evaluate(js_eval)
                if eval_res and isinstance(eval_res, dict):
                    calibrated_html = eval_res.get("content") or calibrated_html
                    calibrations.extend(eval_res.get("calibrations") or [])
                    eval_details = eval_res.get("eval_details") or eval_details
                    playwright_success = True
            finally:
                browser.close()
    except Exception:
        playwright_success = False

    # Fallback kiểm tra tĩnh nếu Playwright không khả dụng
    if not playwright_success:
        # Tĩnh: gỡ bỏ footer-note nếu có
        if 'id="footer-note"' in calibrated_html:
            calibrated_html = re.sub(r'<g[^>]*id=["\']footer-note["\'][^>]*>.*?</g>', '', calibrated_html, flags=re.DOTALL)
            calibrations.append("static_removed_bottom_footer_note")

        # Tự động nắn chỉnh tiêu đề chính & text phụ nếu còn quá bé trong fallback tĩnh
        if re.search(r'<text[^>]*y=["\'](?:[3-8]\d|9[0-5])["\'][^>]*font-size=["\'](?:3\d|4\d|5[0-1])["\']', calibrated_html):
            calibrated_html = re.sub(
                r'(<text[^>]*y=["\'](?:[3-8]\d|9[0-5])["\'][^>]*font-size=["\'])(?:3\d|4\d|5[0-1])(["\'])',
                r'\g<1>58\g<2>',
                calibrated_html
            )
            calibrations.append("static_amplified_main_title_to_58px")
        if re.search(r'<text[^>]*y=["\'](?:9[6-9]|1[0-5]\d|16[0-5])["\'][^>]*font-size=["\'](?:2[0-7])["\']', calibrated_html):
            calibrated_html = re.sub(
                r'(<text[^>]*y=["\'](?:9[6-9]|1[0-5]\d|16[0-5])["\'][^>]*font-size=["\'])(?:2[0-7])(["\'])',
                r'\g<1>30\g<2>',
                calibrated_html
            )
            calibrations.append("static_amplified_sub_title_to_30px")

        # Kiểm tra tĩnh cấm giao diện Player Controls / Scrubber
        if re.search(r'<(?:input|button)\b|\b(?:scrubber|footer-bar)\b', calibrated_html, re.IGNORECASE):
            eval_details["timing_contract"]["passed"] = False
            eval_details["timing_contract"]["score"] = 0
            eval_details["timing_contract"]["message"] = "Phát hiện tạo giao diện player controls / scrubber cấm. Video được render tự động qua Playwright."

        # Kiểm tra tĩnh cấm container thu nhỏ
        if re.search(r'\.(?:container|canvas-container)\s*\{[^}]*width\s*:\s*(?:9\d\d|8\d\d|[1-7]\d\d)px', calibrated_html, re.IGNORECASE) or '<div class="container">' in calibrated_html:
            eval_details["layout_occupancy"]["passed"] = False
            eval_details["layout_occupancy"]["score"] = 0
            eval_details["layout_occupancy"]["warning"] = "Phát hiện bọc SVG vào container thu nhỏ có width cố định. Bắt buộc SVG chiếm trọn 100vw x 100vh."

        # Kiểm tra tĩnh viewBox của SVG chính
        viewbox_matches = re.findall(r'<svg[^>]*viewBox=["\']([^"\']+)["\']', calibrated_html, re.IGNORECASE)
        valid_vb = any("1920" in vb or "1080" in vb for vb in viewbox_matches)
        if viewbox_matches and not valid_vb:
            eval_details["layout_occupancy"]["passed"] = False
            eval_details["layout_occupancy"]["score"] = min(eval_details["layout_occupancy"]["score"], 5)
            eval_details["layout_occupancy"]["warning"] = f"ViewBox của SVG không đúng chuẩn 1080p ({viewbox_matches[0]}). Yêu cầu 0 0 1920 1080 hoặc 0 0 1080 1920."

    total_score = (
        eval_details["timing_contract"]["score"]
        + eval_details["subtitle_safety"]["score"]
        + eval_details.get("boundary_safety", {}).get("score", 25)
        + eval_details.get("layout_occupancy", {}).get("score", 25)
    )

    quality_report = {
        "quality_score": total_score,
        "passed": (
            total_score >= 75
            and eval_details["timing_contract"]["passed"]
            and eval_details.get("boundary_safety", {}).get("passed", True)
            and eval_details.get("layout_occupancy", {}).get("passed", True)
        ),
        "calibrations": list(set(calibrations)),
        "eval_details": eval_details,
    }

    return calibrated_html, quality_report


def import_and_calibrate_scene_html(
    input_html_path: Path,
    output_html_path: Path,
    actual_duration: float,
    actual_step_starts: List[float],
) -> Path:
    """Đọc file HTML ngoài, cân chỉnh tốc độ & mốc bước, ghi vào output_html_path."""
    in_path = Path(input_html_path).resolve()
    if not in_path.exists():
        raise FileNotFoundError(f"File HTML cần import không tồn tại: {in_path}")

    raw_content = in_path.read_text(encoding="utf-8", errors="ignore")
    calibrated_content, _ = evaluate_and_calibrate_scene_html(
        html_str=raw_content,
        duration=actual_duration,
        step_starts=actual_step_starts,
    )

    out_path = Path(output_html_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(calibrated_content, encoding="utf-8")
    return out_path


if __name__ == "__main__":
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(description="HTML Calibrator & Quality Evaluator cho Lecture Illustrator")
    parser.add_argument("html_path", type=Path, help="Đường dẫn đến file HTML cảnh")
    parser.add_argument("--duration", type=float, default=10.0, help="Thời lượng phân cảnh (giây)")
    parser.add_argument("--step-starts", type=str, default="[]", help="JSON mảng các mốc thời gian [t0, t1, ...]")
    parser.add_argument("--aspect-ratio", type=str, default="16:9", choices=["16:9", "9:16"], help="Tỷ lệ khung hình")
    parser.add_argument("--inplace", action="store_true", help="Ghi đè file HTML bằng phiên bản đã cân chỉnh")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Đường dẫn ghi file HTML đã cân chỉnh")

    args = parser.parse_args()

    if not args.html_path.exists():
        print(f"❌ Lỗi: File không tồn tại: {args.html_path}", file=sys.stderr)
        sys.exit(1)

    raw_html = args.html_path.read_text(encoding="utf-8", errors="ignore")

    # Tự động trích xuất duration và step_starts từ file hoặc metadata lân cận nếu không truyền qua CLI
    actual_dur = args.duration
    step_starts = []
    try:
        step_starts = json.loads(args.step_starts)
    except Exception:
        step_starts = []

    if actual_dur == 10.0:
        meta_file = args.html_path.with_suffix(".meta.json")
        if meta_file.exists():
            try:
                m_data = json.loads(meta_file.read_text(encoding="utf-8"))
                if "duration" in m_data:
                    actual_dur = float(m_data["duration"])
            except Exception:
                pass
        m_dur = re.search(r'(?:const|let|var)\s+(?:SCENE_)?DURATION\s*=\s*([\d\.]+)', raw_html)
        if m_dur:
            try:
                actual_dur = float(m_dur.group(1))
            except Exception:
                pass

    if not step_starts:
        m_steps = re.search(r'(?:const|let|var)\s+STEP_STARTS\s*=\s*(\[[^\]]+\])', raw_html)
        if m_steps:
            try:
                step_starts = json.loads(m_steps.group(1))
            except Exception:
                pass

    calibrated_html, report = evaluate_and_calibrate_scene_html(
        html_str=raw_html,
        duration=actual_dur,
        step_starts=step_starts,
        aspect_ratio=args.aspect_ratio,
    )

    score = report.get("quality_score", 0)
    passed = report.get("passed", False)
    calibs = report.get("calibrations", [])

    print("\n" + "=" * 60)
    print(f"📊 KẾT QUẢ ĐÁNH GIÁ CHẤT LƯỢNG HTML: {args.html_path.name}")
    print("=" * 60)
    print(f"Điểm chất lượng (Quality Score): {score}/100")
    print(f"Trạng thái Quality Gate:        {'✅ ĐẠT (PASSED)' if passed else '❌ CHƯA ĐẠT (FAILED)'}")
    if calibs:
        print(f"Các lỗi nhỏ đã tự cân chỉnh:    {', '.join(calibs)}")
    else:
        print("Các lỗi nhỏ đã tự cân chỉnh:    Không có (Mã chuẩn chỉnh)")

    print("\nChi tiết các tiêu chí (Evaluation Breakdown):")
    core_criteria = ["timing_contract", "subtitle_safety", "boundary_safety", "layout_occupancy"]
    for k in core_criteria:
        v = report.get("eval_details", {}).get(k)
        if isinstance(v, dict):
            status_icon = "✅" if v.get("passed", True) else "⚠️"
            item_score = v.get("score", 0)
            warning = f" - {v.get('warning')}" if v.get("warning") else ""
            print(f"  {status_icon} [{k}]: {item_score}/25đ{warning}")

    print("=" * 60 + "\n")

    if args.inplace:
        args.html_path.write_text(calibrated_html, encoding="utf-8")
        print(f"💾 Đã lưu phiên bản cân chỉnh vào: {args.html_path}")
        meta_path = args.html_path.with_suffix(".meta.json")
        if meta_path.exists():
            try:
                meta_data = json.loads(meta_path.read_text(encoding="utf-8"))
                meta_data["quality_score"] = score
                meta_data["passed"] = passed
                meta_data["calibrations"] = calibs
                meta_data["eval_details"] = report.get("eval_details", {})
                meta_path.write_text(json.dumps(meta_data, indent=2, ensure_ascii=False), encoding="utf-8")
                print(f"💾 Đã cập nhật metadata đánh giá vào: {meta_path.name}")
            except Exception as e:
                print(f"⚠️ Không thể cập nhật metadata: {e}")
    elif args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(calibrated_html, encoding="utf-8")
        print(f"💾 Đã lưu phiên bản cân chỉnh vào: {args.output}")

    sys.exit(0 if passed else 1)

