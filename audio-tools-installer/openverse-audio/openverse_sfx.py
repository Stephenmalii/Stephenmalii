#!/usr/bin/env python3
"""Search and download openly licensed audio from the Openverse Audio API.

Zero dependencies (Python 3.8+ standard library only). Works on Windows, macOS and Linux.

Examples:
  python openverse_sfx.py --query "whoosh"
  python openverse_sfx.py --query "footsteps gravel" --license cc0 --limit 5 --download-dir ~/sfx-library/openverse
  python openverse_sfx.py --query "cinematic boom" --license-type commercial --length short --json

Every download is logged to <download-dir>/metadata.json and <download-dir>/ATTRIBUTION.md
(title, creator, license, license URL, source URL, attribution line) so licensing is never lost.

Optional: set OPENVERSE_TOKEN to an Openverse API access token for higher rate limits.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://api.openverse.org/v1/audio/"
UA = "openverse-sfx-cli/1.0 (local sound-design helper)"
LICENSE_CHOICES = ["cc0", "pdm", "by", "by-sa", "by-nc", "by-nd", "by-nc-sa", "by-nc-nd", "sampling+", "nc-sampling+"]
COMMERCIAL_SAFE = {"cc0", "pdm", "by", "by-sa", "by-nd", "sampling+"}


def http_get(url, accept="application/json", timeout=30, retries=3):
    headers = {"User-Agent": UA, "Accept": accept}
    token = os.environ.get("OPENVERSE_TOKEN")
    if token and url.startswith(API):
        headers["Authorization"] = f"Bearer {token}"
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read(), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            last = e
            if e.code == 429 or e.code >= 500:
                time.sleep(2 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError as e:
            last = e
            time.sleep(2 * (attempt + 1))
    raise last


def search(args):
    params = {"q": args.query, "page_size": max(1, min(args.limit, 50)), "page": args.page}
    if args.license:
        params["license"] = args.license
    elif args.license_type != "all":
        params["license_type"] = args.license_type
    for key in ("extension", "length", "category", "source"):
        val = getattr(args, key)
        if val:
            params[key] = val
    if not args.allow_mature:
        params["mature"] = "false"
    url = API + "?" + urllib.parse.urlencode(params)
    body, _ = http_get(url)
    data = json.loads(body)
    return data, url


def safe_name(text, maxlen=60):
    text = re.sub(r"[^\w\-]+", "_", text or "untitled", flags=re.UNICODE).strip("_")
    return (text or "untitled")[:maxlen]


def record_for(item):
    return {
        "id": item.get("id"),
        "title": item.get("title"),
        "creator": item.get("creator"),
        "creator_url": item.get("creator_url"),
        "license": item.get("license"),
        "license_version": item.get("license_version"),
        "license_url": item.get("license_url"),
        "commercial_safe": (item.get("license") or "").lower() in COMMERCIAL_SAFE,
        "source_url": item.get("foreign_landing_url"),
        "audio_url": item.get("url"),
        "provider": item.get("provider"),
        "filetype": item.get("filetype"),
        "duration_ms": item.get("duration"),
        "tags": [t.get("name") for t in (item.get("tags") or []) if t.get("name")],
        "attribution": item.get("attribution"),
    }


def download(item, rec, out_dir: Path, query):
    url = item.get("url")
    if not url:
        return None, "no audio url"
    ext = (item.get("filetype") or Path(urllib.parse.urlparse(url).path).suffix.lstrip(".") or "mp3").lower()
    name = f"{safe_name(item.get('title'))}__{safe_name(item.get('creator'), 30)}__{(item.get('id') or '')[:8]}.{ext}"
    sub = out_dir / safe_name(query, 40)
    sub.mkdir(parents=True, exist_ok=True)
    path = sub / name
    if path.exists() and path.stat().st_size > 0:
        return path, "exists"
    data, _ = http_get(url, accept="*/*", timeout=120)
    path.write_bytes(data)
    return path, "downloaded"


def update_logs(out_dir: Path, new_records):
    meta_path = out_dir / "metadata.json"
    existing = []
    if meta_path.exists():
        try:
            existing = json.loads(meta_path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            existing = []
    by_id = {r.get("id"): r for r in existing}
    for r in new_records:
        by_id[r["id"]] = r
    records = sorted(by_id.values(), key=lambda r: r.get("local_file") or "")
    meta_path.write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")

    lines = ["# Attribution - Openverse audio", "",
             "Audio files in this folder were downloaded from Openverse (https://openverse.org).",
             "Keep this file with the sounds. Credit every non-CC0/PDM sound where you publish.", ""]
    for r in records:
        lines += [f"## {r.get('title') or 'Untitled'}",
                  f"- File: `{r.get('local_file')}`",
                  f"- Creator: {r.get('creator') or 'unknown'}" + (f" ({r['creator_url']})" if r.get("creator_url") else ""),
                  f"- License: {(r.get('license') or '').upper()} {r.get('license_version') or ''} - {r.get('license_url') or ''}",
                  f"- Commercial use: {'yes' if r.get('commercial_safe') else 'NO (non-commercial license)'}",
                  f"- Source: {r.get('source_url') or ''}",
                  f"- Attribution: {r.get('attribution') or ''}",
                  f"- Downloaded: {r.get('downloaded_at')}", ""]
    (out_dir / "ATTRIBUTION.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    p = argparse.ArgumentParser(description="Search/download openly licensed audio from Openverse.")
    p.add_argument("--query", "-q", required=True, help='search words, e.g. "whoosh", "footsteps gravel"')
    p.add_argument("--license-type", default="commercial", choices=["all", "commercial", "modification"],
                   help="license group filter (default: commercial). Ignored when --license is given.")
    p.add_argument("--license", choices=LICENSE_CHOICES, help="one specific license, e.g. cc0, by, by-sa")
    p.add_argument("--limit", type=int, default=10, help="number of results (1-50, default 10)")
    p.add_argument("--page", type=int, default=1, help="result page (default 1)")
    p.add_argument("--extension", help="file type filter, e.g. mp3, wav, ogg, flac")
    p.add_argument("--length", choices=["shortest", "short", "medium", "long"], help="duration bucket")
    p.add_argument("--category", help="e.g. sound_effect, music, podcast, audiobook, news")
    p.add_argument("--source", help="restrict to a source, e.g. freesound, jamendo, wikimedia_audio")
    p.add_argument("--allow-mature", action="store_true", help="include results flagged mature")
    p.add_argument("--download-dir", help="download results here and log ATTRIBUTION.md + metadata.json")
    p.add_argument("--json", action="store_true", help="print machine-readable JSON instead of a table")
    args = p.parse_args()

    try:
        data, url = search(args)
    except urllib.error.HTTPError as e:
        print(f"Openverse API error {e.code}: {e.read()[:300].decode('utf-8', 'replace')}", file=sys.stderr)
        return 2
    except Exception as e:  # network failure
        print(f"Could not reach Openverse: {e}", file=sys.stderr)
        return 2

    items = (data.get("results") or [])[: args.limit]
    records = [record_for(i) for i in items]

    if args.download_dir:
        out_dir = Path(os.path.expanduser(args.download_dir)).resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        logged = []
        for item, rec in zip(items, records):
            try:
                path, status = download(item, rec, out_dir, args.query)
            except Exception as e:
                rec["download_status"] = f"failed: {e}"
                continue
            rec["download_status"] = status
            if path:
                rec["local_file"] = str(path.relative_to(out_dir)).replace("\\", "/")
                rec["local_path"] = str(path)
                rec["downloaded_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
                rec["query"] = args.query
                logged.append(rec)
        if logged:
            update_logs(out_dir, logged)

    if args.json:
        print(json.dumps({"query": args.query, "request_url": url, "result_count": data.get("result_count"),
                          "results": records}, indent=2, ensure_ascii=False))
    else:
        print(f'Openverse audio: "{args.query}" - {data.get("result_count", 0)} matches, showing {len(records)}')
        for n, r in enumerate(records, 1):
            dur = f"{(r['duration_ms'] or 0) / 1000:.1f}s" if r.get("duration_ms") else "?s"
            lic = f"{(r['license'] or '?').upper()} {r.get('license_version') or ''}".strip()
            print(f"{n:2}. {r['title']}  [{lic}, {dur}, {r.get('filetype') or '?'}]  by {r['creator']}")
            print(f"    source: {r['source_url']}")
            if r.get("local_path"):
                print(f"    saved:  {r['local_path']} ({r['download_status']})")
            elif r.get("download_status"):
                print(f"    {r['download_status']}")
        if args.download_dir:
            print(f"Attribution log: {Path(os.path.expanduser(args.download_dir)).resolve() / 'ATTRIBUTION.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
