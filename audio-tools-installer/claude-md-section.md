
## Sound Design & Audio Workflow

Three tools, installed globally. Paths: `~/ai-audio-tools` (tools), `~/sfx-library` (all downloaded/rendered sound).

- **earshot** (MCP server `earshot` + CLI `earshot`; skills `earshot`, `real-sound`): procedural SFX synthesis
  (`make`, `make --set`, `sfx`, `kit`, `build`, `forge`), and *listening* for a model that cannot hear:
  `describe`, `match`, `rank`, `critique`, `timeline`, loudness/sync checks. Use it to verify ANY audio before saying
  how it sounds. Venv: `~/ai-audio-tools/earshot/.venv`.
- **openverse-audio** (skill; `~/ai-audio-tools/openverse-audio/openverse_sfx.py`): search + download real recorded
  CC0 / commercial-safe audio into `~/sfx-library/openverse`, logging every file in `ATTRIBUTION.md` + `metadata.json`.
- **real-sfx** (skill; `~/.claude/skills/real-sfx`): find a video's moments, place real library/uisfx sounds on exact
  frames, mix under music/voice, return MP4 + SFX WAV + cue report. `~/sfx-library` is its main library; after
  adding files run `python ~/.claude/skills/real-sfx/scripts/build_index.py`.

Default order for a video: real-sfx finds cues -> library/uisfx sounds -> gaps filled from Openverse (real) or earshot
(synthesized, only if the user allows synthesis) -> earshot listens/critiques -> real-sfx mixes. Prefer commercial-safe
licenses; put required BY/BY-SA credits from ATTRIBUTION.md in the deliverable notes. Write outputs in the project, not
in ~/.claude.
