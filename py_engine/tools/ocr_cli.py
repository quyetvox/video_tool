#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

# Ensure root is in sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
if str(root_dir / "lib") not in sys.path:
    sys.path.insert(0, str(root_dir / "lib"))

from plugins.plugin_loader import PluginLoader


def main():
    parser = argparse.ArgumentParser(description="Sub-Video OCR CLI Runner")
    parser.add_argument("--video", required=True, help="Path to input video")
    parser.add_argument("--region", default="0.10,0.0,0.95,1.0", help="Crop region [ymin,xmin,ymax,xmax]")
    parser.add_argument("--output", required=True, help="Path to output JSON")
    parser.add_argument("--engine", default="apple_vision", help="OCR engine (apple_vision | paddle_ocr)")
    parser.add_argument("--diff-threshold", type=float, default=8.0, help="Frame diff threshold")
    args = parser.parse_args()

    video_path = Path(args.video)
    out_path = Path(args.output)
    region = [float(x.strip()) for x in args.region.split(",")]

    config = {
        "ocr": args.engine,
        "ocr_mode": "region",
        "diff_threshold": args.diff_threshold,
    }

    plugin_name = args.engine.replace("-", "_")
    if plugin_name == "paddleocr":
        plugin_name = "paddle_ocr"

    try:
        plugin = PluginLoader.load_plugin("ocr", plugin_name, config)
        if hasattr(plugin, "extract_text_with_diff_skip"):
            segments = plugin.extract_text_with_diff_skip(video_path, region, diff_threshold=args.diff_threshold)
        else:
            segments = plugin.extract_text(video_path, region)
    except Exception as e:
        print(f"[OCR CLI] Error running {plugin_name}: {e}", file=sys.stderr)
        segments = []

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(segments, f, ensure_ascii=False, indent=2)

    print(f"[OCR CLI] Completed: {len(segments)} segments extracted -> {out_path}")


if __name__ == "__main__":
    main()
