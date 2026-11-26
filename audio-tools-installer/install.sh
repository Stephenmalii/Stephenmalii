#!/usr/bin/env bash
# Installs earshot (MCP + skills), Real SFX and the Openverse audio skill for Claude Code (macOS / Linux).
# Usage:  bash install.sh            (re-runnable; skips what is already done)
#         SKIP_MODELS=1 bash install.sh   (skip the ~1.1 GB listening-model download)
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$HOME/ai-audio-tools"
LIB="$HOME/sfx-library"
SKILLS="$HOME/.claude/skills"
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
info() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '  \033[31mfail\033[0m %s\n' "$*"; exit 1; }

# ---------------- Phase 1: prerequisites ----------------
info "Phase 1: environment"
OS="$(uname -s)"; ARCH="$(uname -m)"; ok "OS $OS $ARCH, home $HOME"

pkg_install() {   # pkg_install <brew-name> <apt-name>
  if [ "$OS" = "Darwin" ]; then
    command -v brew >/dev/null || die "Homebrew missing: install from https://brew.sh then re-run"
    brew install "$1"
  elif command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y "$2"
  elif command -v dnf >/dev/null; then sudo dnf install -y "$2"
  elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm "$2"
  else die "no supported package manager; install $2 manually"; fi
}
command -v git    >/dev/null || pkg_install git git;       ok "$(git --version)"
command -v ffmpeg >/dev/null || pkg_install ffmpeg ffmpeg; ok "ffmpeg $(ffmpeg -version | head -1 | awk '{print $3}')"

PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)'; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then pkg_install python@3.12 "python3 python3-venv"; PY="$(command -v python3.12 || command -v python3)"; fi
"$PY" -c 'import venv' 2>/dev/null || pkg_install python@3.12 python3-venv
ok "Python $("$PY" -V) at $PY"
command -v node >/dev/null && ok "node $(node -v)" || warn "Node.js not found (only needed for 'npx skills'; skills are copied instead)"
command -v claude >/dev/null || die "Claude Code CLI 'claude' not on PATH: https://docs.claude.com/claude-code"
ok "claude $(claude --version 2>/dev/null | head -1)"

mkdir -p "$TOOLS" "$LIB/openverse" "$LIB/test" "$SKILLS"; ok "created $TOOLS and $LIB"

# ---------------- Phase 2: earshot ----------------
info "Phase 2: earshot"
if [ -d "$TOOLS/earshot/.git" ]; then git -C "$TOOLS/earshot" pull -q --ff-only || warn "earshot: pull failed, using existing clone"; else git clone -q https://github.com/Leonxlnx/earshot.git "$TOOLS/earshot"; fi
cd "$TOOLS/earshot"
[ -x .venv/bin/python ] || "$PY" -m venv .venv
VPY="$TOOLS/earshot/.venv/bin/python"
"$VPY" -m pip install -q --upgrade pip
if [ "$OS" = "Darwin" ]; then "$VPY" -m pip install -q torch      # macOS wheels are CPU builds already
else "$VPY" -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu; fi
"$VPY" -m pip install -q -e ".[mcp,listen]"
ok "earshot $("$VPY" -m earshot --version 2>&1 | tail -1)"
if [ "${SKIP_MODELS:-0}" != "1" ]; then "$VPY" -m earshot doctor --fetch || warn "model fetch failed; re-run: $VPY -m earshot doctor --fetch"; fi

rm -rf "$SKILLS/earshot" "$SKILLS/real-sound"
cp -R skills/earshot skills/real-sound "$SKILLS/"
mkdir -p "$HOME/.claude/commands/earshot" && cp commands/*.md "$HOME/.claude/commands/earshot/"
ok "skills earshot, real-sound + /earshot:make, /earshot:make-set"

mkdir -p "$HOME/.local/bin" && ln -sf "$TOOLS/earshot/.venv/bin/earshot" "$HOME/.local/bin/earshot"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  RC="$HOME/.zshrc"; [ "${SHELL##*/}" = "bash" ] && RC="$HOME/.bashrc"
  grep -q 'local/bin' "$RC" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
  warn "added ~/.local/bin to PATH in $RC (open a new terminal)";; esac
ok "earshot CLI linked into ~/.local/bin"

claude mcp remove earshot --scope user >/dev/null 2>&1 || true
claude mcp add earshot --scope user -e EARSHOT_THREADS=3 -- "$VPY" -m earshot mcp
ok "MCP server 'earshot' registered (user scope)"

# ---------------- Phase 3: Real SFX ----------------
info "Phase 3: Real SFX"
if [ -d "$TOOLS/clipwing-skills/.git" ]; then git -C "$TOOLS/clipwing-skills" pull -q --ff-only || warn "clipwing: pull failed, using existing clone"; else git clone -q https://github.com/Clipwing/skills.git "$TOOLS/clipwing-skills"; fi
[ -f "$SKILLS/real-sfx/config.json" ] && cp "$SKILLS/real-sfx/config.json" "$TOOLS/real-sfx-config.backup.json"
rm -rf "$SKILLS/real-sfx" && cp -R "$TOOLS/clipwing-skills/skills/real-sfx" "$SKILLS/real-sfx"
(cd "$SKILLS/real-sfx" && "$PY" scripts/setup.py add-library sfx-library "$LIB" --index >/dev/null && "$PY" scripts/setup.py check) || warn "real-sfx check reported a problem (see above)"
ok "real-sfx installed; ~/sfx-library is its main library ($(find "$SKILLS/real-sfx/vendor" -name '*.mp3' | wc -l | tr -d ' ') bundled uisfx files)"

# ---------------- Phase 4: Openverse ----------------
info "Phase 4: Openverse audio"
mkdir -p "$TOOLS/openverse-audio" "$SKILLS/openverse-audio"
cp "$KIT/openverse-audio/openverse_sfx.py" "$TOOLS/openverse-audio/"
cp "$KIT/skills/openverse-audio/SKILL.md" "$SKILLS/openverse-audio/"
ok "openverse_sfx.py + openverse-audio skill"

# ---------------- Phase 5: CLAUDE.md + verification ----------------
info "Phase 5: CLAUDE.md + verification"
touch "$HOME/.claude/CLAUDE.md"
grep -q "Sound Design & Audio Workflow" "$HOME/.claude/CLAUDE.md" || cat "$KIT/claude-md-section.md" >> "$HOME/.claude/CLAUDE.md"
ok "~/.claude/CLAUDE.md has the Sound Design section"

(cd "$LIB/test" && "$VPY" -m earshot make "a soft bright chime" -o test_chime.wav) && ok "earshot rendered $LIB/test/test_chime.wav"
"$PY" "$TOOLS/openverse-audio/openverse_sfx.py" --query "ui click" --license cc0 --limit 2 --download-dir "$LIB/openverse" && ok "Openverse search + download"
(cd "$SKILLS/real-sfx" && "$PY" scripts/build_index.py >/dev/null 2>&1) || true
claude mcp list 2>&1 | grep -i earshot || warn "earshot not listed by 'claude mcp list'"
info "Done. Restart Claude Code to load the new skills and MCP server."
