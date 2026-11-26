---
name: openverse-audio
description: Search and download REAL recorded, openly licensed sound effects and audio (CC0, public domain, CC BY, CC BY-SA) from the Openverse Audio API into the local SFX library (~/sfx-library/openverse), with an automatic ATTRIBUTION.md + metadata.json license log. Use whenever the user wants a real (not synthesized) sound - whoosh, footsteps, door, impact, boom, ambience, UI click, crowd, nature - for a video, app or game, asks for royalty-free / CC0 / commercial-safe / free-to-use audio, or when earshot and the real-sfx library lack a fitting recording.
---

# Openverse audio: real, licensed recordings

Script: `~/ai-audio-tools/openverse-audio/openverse_sfx.py` (standard library only, no install).
Run it with `python3` on macOS/Linux, `python` (or `py`) on Windows. Library: `~/sfx-library/openverse`.

## When to use
- A real recording is wanted ("real", "recorded", "not synthetic", "royalty free", "CC0").
- `real-sfx` has no fitting sound in its libraries, or `earshot make` says it "makes no X".
- Background ambience, foley, or a specific real thing (a train, a crowd, rain on a car).

## How
1. Search first (no download), commercial-safe by default:
   `python3 ~/ai-audio-tools/openverse-audio/openverse_sfx.py --query "whoosh" --limit 10`
2. Narrow: `--license cc0` (no attribution needed, safest), `--length shortest|short` for one-shots,
   `--extension wav`, `--category sound_effect`, `--source freesound`, `--json` for parsing.
3. Download the picks into the library:
   `python3 ~/ai-audio-tools/openverse-audio/openverse_sfx.py --query "footsteps gravel" --license cc0 --limit 5 --download-dir ~/sfx-library/openverse`
   Files land in `~/sfx-library/openverse/<query>/`; every file is appended to `ATTRIBUTION.md` and `metadata.json`.
4. Listen/check before use: `earshot describe FILE` / `earshot match FILE "a heavy door slam"` (earshot MCP tools too).
5. To make downloads available to real-sfx: `python ~/.claude/skills/real-sfx/scripts/build_index.py`
   (`~/sfx-library` is registered as a real-sfx library).

## License rules (never skip)
- Default `--license-type commercial` excludes NC licenses. Only use `--license-type all` if the user says the
  project is non-commercial, and say so.
- CC0 / PDM: no credit required. BY / BY-SA: credit is REQUIRED - copy the lines from `ATTRIBUTION.md` into the
  video description/credits and tell the user. BY-SA also requires sharing adaptations under the same license.
- Never delete or rewrite `ATTRIBUTION.md` / `metadata.json`; never strip the creator from file names.
- Freesound "previews" are 128 kbps MP3s: fine for social video; for high-end mixes note the original WAV link (`source_url`).

## Notes
- Anonymous API limits are modest; on HTTP 429 wait and retry, or set `OPENVERSE_TOKEN`.
- Results are ranked by text, not by sound: audition several and choose by ear (earshot `rank`/`match`).
