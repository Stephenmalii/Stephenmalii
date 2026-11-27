#!/usr/bin/env python3
"""Download a starter SFX library of CC0 recordings from Openverse, one folder per real-sfx role.

  python build_starter_library.py [--out ~/sfx-library/starter] [--per-query 8]

Folders are named after real-sfx roles (whoosh, hit, riser, ...) so build_index.py gives every file the right role.
Every file is logged in <out>/ATTRIBUTION.md and <out>/metadata.json. CC0 only: no credit needed, safe for commercial use.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "openverse-audio" / "openverse_sfx.py"
if not SCRIPT.exists():
    SCRIPT = Path.home() / "ai-audio-tools" / "openverse-audio" / "openverse_sfx.py"

# role -> (queries, length bucket)
PLAN = {
    "whoosh":   (["whoosh", "swoosh transition", "fast swish", "air whoosh"], "shortest"),
    "hit":      (["cinematic hit", "impact hit", "punchy impact", "logo hit"], "shortest"),
    "sub_drop": (["sub drop", "bass drop boom", "low boom"], "shortest"),
    "riser":    (["riser", "tension riser", "uplifter sweep"], "shortest"),
    "pop":      (["pop", "bubble pop", "mouth pop"], "shortest"),
    "click":    (["mouse click", "button click", "switch click"], "shortest"),
    "typing":   (["keyboard typing", "mechanical keyboard typing"], "shortest"),
    "chime":    (["chime", "ding bell", "sparkle magic", "music box"], "shortest"),
    "glitch":   (["glitch", "digital glitch", "vhs noise"], "shortest"),
    "paper":    (["paper", "page turn", "tape peel"], "shortest"),
    "camera":   (["camera shutter", "camera flash"], "shortest"),
    "water":    (["water drop", "splash"], "shortest"),
    "coin":     (["coin", "cash register"], "shortest"),
    "foley":    (["footsteps", "door close", "cloth rustle", "thud"], "shortest"),
    "ambience": (["room tone", "city ambience", "nature ambience", "cafe ambience"], "short"),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="~/sfx-library/starter")
    ap.add_argument("--per-query", type=int, default=8)
    ap.add_argument("--roles", help="comma list, default: all")
    a = ap.parse_args()
    out = os.path.expanduser(a.out)
    roles = a.roles.split(",") if a.roles else list(PLAN)
    for role in roles:
        queries, length = PLAN[role]
        for q in queries:
            cmd = [sys.executable, str(SCRIPT), "--query", q, "--license", "cc0", "--source", "freesound",
                   "--length", length, "--limit", str(a.per_query), "--download-dir", out, "--subdir", role]
            r = subprocess.run(cmd, capture_output=True, text=True)
            got = r.stdout.count("(downloaded)") + r.stdout.count("(exists)")
            print(f"{role:9} {q!r:32} {got} files" + ("" if r.returncode == 0 else f"  ERROR {r.stderr.strip()[:120]}"),
                  flush=True)
            time.sleep(1.5)
    n = sum(1 for p in Path(out).rglob("*") if p.suffix.lower() in {".mp3", ".wav", ".ogg", ".flac"})
    print(f"\n{n} sound files in {out}")


if __name__ == "__main__":
    main()
