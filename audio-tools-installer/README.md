# Claude Code audio tools installer

One script that installs and wires three sound-design tools into Claude Code globally (all projects):

| Tool | What Claude Code gets | Installed to |
|---|---|---|
| [earshot](https://github.com/Leonxlnx/earshot) | MCP server `earshot` (user scope), `earshot` CLI, skills `earshot` + `real-sound`, `/earshot:make`, `/earshot:make-set` | `~/ai-audio-tools/earshot` (+ `.venv`) |
| [Real SFX](https://github.com/Clipwing/skills/tree/main/skills/real-sfx) | skill `real-sfx` with 936 bundled CC0 uisfx files (78 cues x 12 packs); `~/sfx-library` registered as its main library | `~/.claude/skills/real-sfx` |
| Openverse Audio | `openverse_sfx.py` (no dependencies) + skill `openverse-audio`; downloads log `ATTRIBUTION.md` + `metadata.json` | `~/ai-audio-tools/openverse-audio`, `~/sfx-library/openverse` |

It also appends a "Sound Design & Audio Workflow" section to `~/.claude/CLAUDE.md` (once) and runs the verification tests.

## Run

Needs Claude Code (`claude` on PATH) and Python 3.10+ (installed for you if missing). Git and FFmpeg are installed
via winget / brew / apt when missing. About 2 GB of torch + 2.2 GB of listening models on disk.

macOS / Linux:
```bash
git clone -b ccr-577f2d7f-ysj13d https://github.com/Stephenmalii/Stephenmalii.git ~/audio-kit
bash ~/audio-kit/audio-tools-installer/install.sh
```

Windows (PowerShell, not as admin):
```powershell
git clone -b ccr-577f2d7f-ysj13d https://github.com/Stephenmalii/Stephenmalii.git $HOME\audio-kit
Set-ExecutionPolicy -Scope Process Bypass -Force
& "$HOME\audio-kit\audio-tools-installer\install.ps1"
```

`SKIP_MODELS=1` (bash) or `-SkipModels` (PowerShell) skips the 1.1 GB model download; earshot then fetches the models on
first listening call. Re-running is safe: clones are pulled, the MCP entry is replaced, CLAUDE.md is not duplicated,
and an existing real-sfx `config.json` is backed up to `~/ai-audio-tools/real-sfx-config.backup.json`.

Restart Claude Code afterwards; `claude mcp list` should show `earshot ... Connected`.
