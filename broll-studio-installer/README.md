# Claude Code B-roll & motion graphics studio installer

One script that sets up a free, open-source, local B-roll studio Claude Code can drive on its own: plan, animate,
visually check, render and hand off to sound design.

| Piece | What Claude Code gets | Lives in |
|---|---|---|
| [motion-broll](https://github.com/Barty-Bart/motion-graphics) | `/motion-broll`: video + transcript -> plan table, morphing UI/chart/terminal cutaways (`.mp4`) and transparent panels (ProRes 4444 `.mov`) with motion blur, `TIMING.md`, preview + compare pages | skill `~/.claude/skills/motion-broll`, clone `~/ai-video-tools/motion-graphics` |
| Shared Playwright runtime | Chromium pre-downloaded so the first motion-broll render doesn't stall; use `NODE_PATH=~/ai-video-tools/motion-runtime/node_modules` | `~/ai-video-tools/motion-runtime` |
| [HyperFrames](https://github.com/heygen-com/hyperframes) | `/hyperframes` + 8 companion skills (cli, registry of ~450 blocks, media-use, figma, slideshow, reverse-any-video, ...) and the `hyperframes` CLI (`init`, `check --json`, `snapshot`, `render` to MP4/MOV/WebM) | `~/.claude/skills/hyperframes*`, global npm package, clone `~/ai-video-tools/hyperframes` |
| [hyperframes-to-after-effects](https://github.com/Clipwing/skills) | export a HyperFrames composition to an editable `.aep` | `~/.claude/skills/hyperframes-to-after-effects` |
| CLAUDE.md rulebook | "B-Roll & Motion Graphics Pipeline": which tool when, a required visual QA loop, sound-design handoff to real-sfx / openverse / earshot | `~/.claude/CLAUDE.md` (managed block, replaced on re-run) |

It checks and, if needed, installs Git, Node.js 18+, Python 3.10+ and FFmpeg with the ProRes encoder (winget/choco on Windows,
brew on macOS, apt/dnf/pacman on Linux), then runs a smoke test: a 3-second stat card is linted with
`hyperframes check --json`, rendered to `~/broll-renders/smoke-test/smoke_test.mp4`, and the motion-broll engine
renders one of its example clips with motion blur.

Install the audio tools first (`audio-tools-installer/`) so the sound-design handoff works; this installer only warns if they are missing.

## Run

macOS / Linux:
```bash
git clone -b claude/broll-studio-setup-gye7u7 https://github.com/Stephenmalii/Stephenmalii.git ~/broll-kit
bash ~/broll-kit/broll-studio-installer/install.sh
```

Windows (PowerShell, not as admin):
```powershell
git clone -b claude/broll-studio-setup-gye7u7 https://github.com/Stephenmalii/Stephenmalii.git $HOME\broll-kit
Set-ExecutionPolicy -Scope Process Bypass -Force
& "$HOME\broll-kit\broll-studio-installer\install.ps1"
```

Re-running is safe: clones are pulled, skills are replaced with fresh copies, and the CLAUDE.md block is replaced rather than duplicated.
If the script installed Node or FFmpeg and a later step can't find it, open a new terminal and run it again. Restart Claude Code afterwards.

Notes:
- `npx skills add` is attempted as requested, then every skill is copied from its git clone. On Windows, `npx skills` may create
  symlinks that need Developer Mode, and the copy guarantees the engine scripts are present.
- The smoke-test composition loads GSAP from jsDelivr, so the render needs internet access.
- `hyperframes doctor` lists whisper-cpp, Kokoro TTS, MusicGen and Docker as optional extras. None is needed for B-roll.
