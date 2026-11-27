#!/usr/bin/env python3
"""Listen to every file of the starter library with earshot and move the ones that do not sound like their folder's
role out of the library (to <library>/../sfx-rejected/<role>/), then rewrite ATTRIBUTION.md / metadata.json to match.

  python screen_library.py [--lib ~/sfx-library/starter] [--min-z 2.0] [--earshot earshot]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

DESCRIPTIONS = {
    "whoosh": "a fast whoosh transition", "hit": "a cinematic impact hit", "sub_drop": "a deep bass boom",
    "riser": "a rising tension riser", "pop": "a short bubble pop", "click": "a mouse or button click",
    "typing": "keyboard typing", "chime": "a bright chime or bell ding", "glitch": "a digital glitch noise",
    "paper": "paper rustling or a page turn", "camera": "a camera shutter", "water": "a water drop or splash",
    "coin": "coins or a cash register", "foley": "a footstep, door or thud", "ambience": "a background room or outdoor ambience",
}

ap = argparse.ArgumentParser()
ap.add_argument("--lib", default="~/sfx-library/starter")
ap.add_argument("--min-z", type=float, default=2.0)
ap.add_argument("--earshot", default="earshot")
a = ap.parse_args()
lib = Path(os.path.expanduser(a.lib)).resolve()
rej_root = lib.parent.parent / "sfx-rejected" if lib.parent.name == "sfx-library" else lib.parent / "sfx-rejected"

kept = rejected = 0
scores = {}
for role_dir in sorted(p for p in lib.iterdir() if p.is_dir()):
    desc = DESCRIPTIONS.get(role_dir.name)
    if not desc:
        continue
    out = subprocess.run([a.earshot, "rank", desc, str(role_dir), "--json"], capture_output=True, text=True)
    if out.returncode != 0:
        print(f"{role_dir.name}: rank failed: {out.stderr.strip()[:200]}", file=sys.stderr)
        continue
    res = json.loads(out.stdout)["results"]
    bad = [r for r in res if r.get("near_silent") or (r.get("z") or 0) < a.min_z]
    for r in res:
        scores[Path(r["path"]).resolve().relative_to(lib).as_posix()] = {"z": r.get("z"), "verdict": r.get("verdict"),
                                                                        "sounds_most_like": r.get("sounds_most_like")}
    for r in bad:
        dest = rej_root / role_dir.name
        dest.mkdir(parents=True, exist_ok=True)
        shutil.move(r["path"], dest / Path(r["path"]).name)
    kept += len(res) - len(bad)
    rejected += len(bad)
    best = res[0]["sounds_most_like"] if res else "-"
    print(f"{role_dir.name:9} kept {len(res) - len(bad):3}  rejected {len(bad):3}   best: {best}", flush=True)

# rewrite logs so they only describe files still in the library, with earshot's verdict
meta_p = lib / "metadata.json"
if meta_p.exists():
    meta = json.loads(meta_p.read_text(encoding="utf-8"))
    meta = [m for m in meta if (lib / m.get("local_file", "")).exists()]
    for m in meta:
        m["earshot"] = scores.get(m["local_file"])
        m["local_path"] = str(lib / m["local_file"])
    meta_p.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    sys.path.insert(0, str(Path.home() / "ai-audio-tools" / "openverse-audio"))
    sys.path.insert(0, str(Path(__file__).resolve().parent / "openverse-audio"))
    import openverse_sfx  # noqa: E402
    (lib / "ATTRIBUTION.md").unlink(missing_ok=True)
    meta_p.write_text("[]", encoding="utf-8")
    openverse_sfx.update_logs(lib, meta)
print(f"\nkept {kept}, rejected {rejected} (moved to {rej_root})")
