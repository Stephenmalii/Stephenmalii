<!-- BEGIN broll-pipeline (managed by broll-studio-installer; re-running the installer replaces this block) -->
## B-Roll & Motion Graphics Pipeline

Free, local, open-source. Tools in `~/ai-video-tools`, renders in `~/broll-renders/<project>/` (or a `motion/` folder in
the user's project). Never write outputs into `~/.claude`.

### Which tool
- **`/motion-broll`** (skill `~/.claude/skills/motion-broll`): the user gives a talking-head or screen-recorded video +
  transcript (`.srt`, `.vtt` or text) and wants B-roll timed to their words. Follow the skill: inspect footage
  (`inspect_video.py` -> `video.json` + `contact.png`, find full / PiP / empty regions), estimate word times, show the
  plan table and **wait for approval**, build clips, check stills, render, then write `TIMING.md` (in/out + line per clip).
  Full-frame cutaways -> `.mp4`; panels in empty space (`bg:null`) -> ProRes 4444 `.mov` with alpha. Render at the
  source fps with motion blur; name files by timeline in-point (`04-name_0m32s40.mp4`).
  - Skip the skill's per-project Playwright download: `mkdir -p motion/{clips,dist,out,work}` and run every engine
    script with `NODE_PATH=~/ai-video-tools/motion-runtime/node_modules` (PowerShell:
    `$env:NODE_PATH="$HOME\ai-video-tools\motion-runtime\node_modules"`). Only fall back to `scripts/setup.sh` if that
    folder is missing.
- **`/hyperframes`** (skills `hyperframes`, `hyperframes-cli`, `hyperframes-registry`, `media-use`, ...; CLI `hyperframes`):
  standalone explainers, kinetic typography, stat cards / lower-thirds, charts and data viz, 3D or Lottie cards, launch
  sequences, any custom HTML/CSS/GSAP scene. `hyperframes init <name> --non-interactive --skip-skills` inside
  `~/broll-renders`, check `hyperframes-registry` before hand-building a named effect, render with
  `hyperframes render -o out.mp4` (or `--format mov` for ProRes 4444 alpha overlays; `--fps` to match the edit).
- **`hyperframes-to-after-effects`**: only when the user wants an editable `.aep` instead of a rendered clip.
- Video with a transcript and "B-roll for my video" -> motion-broll. A single designed scene or title -> HyperFrames.

### Mandatory visual QA loop (never deliver an unverified animation)
1. Lint/check: HyperFrames `hyperframes check --json` until `ok: true` with no errors; fix warnings that are real defects
   (empty first frame, overlaps, contrast, clipped text). motion-broll: `engine/beats.js` contact sheets at every
   settled state and a couple of mid-morph moments.
2. Look at the stills yourself (`hyperframes snapshot --at t1,t2,...` -> `contact-sheet.jpg`). Check for overlapping or
   clipped text, elements leaving the frame or the safe area, misaligned parts during entrances and exits, off-word
   timing, unreadable sizes, and a cursor that leaves the frame.
3. Fix, then re-check and re-inspect. Only then do the final render.
4. After rendering, `ffprobe` the file (codec, size, fps, frame count, alpha `yuva444p*` for `.mov`) and inspect
   2-4 frames extracted from the actual render before you hand it over.
5. Never invent numbers, quotes, prices or results: use relative bars or skeleton text until the user gives real figures.

### Automatic sound-design handoff
Once a clip is rendered and verified, offer (or, if the user asked for "finished" clips, run) the audio pipeline from the
"Sound Design & Audio Workflow" section: **real-sfx** finds cues on the clip's keyframes (state changes, clicks,
cursor drags, counter ends, card entrances/exits) and places subtle UI clicks, whooshes and risers frame-accurately
-> gaps filled from **openverse_sfx.py** (`~/ai-audio-tools/openverse-audio/openverse_sfx.py`, real CC0/commercial-safe
recordings) or **earshot** (synthesized, only if the user allows synthesis) -> **earshot** listens/critiques -> real-sfx
mixes. Use the keyframe times from the plan (`TIMING.md`, `plan.json`, or the GSAP timeline) as the cue list. Keep SFX
under the voice, deliver the silent clip + the SFX'd clip + a separate SFX WAV, and list any BY/BY-SA credits.
<!-- END broll-pipeline -->
