#!/usr/bin/env bash
# B-roll & motion graphics studio for Claude Code (macOS / Linux): motion-broll + HyperFrames + AE export,
# shared Playwright runtime, CLAUDE.md pipeline rules, end-to-end smoke test.
# Usage:  bash install.sh          (re-runnable; pulls clones, replaces skills and the CLAUDE.md block)
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$HOME/ai-video-tools"
RENDERS="$HOME/broll-renders"
SKILLS="$HOME/.claude/skills"
RUNTIME="$TOOLS/motion-runtime"
FIXED=()
ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
info() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '  \033[31mfail\033[0m %s\n' "$*"; exit 1; }

# ---------------- Phase 1: prerequisites ----------------
info "Phase 1: runtime & rendering prerequisites"
OS="$(uname -s)"; ARCH="$(uname -m)"
ok "OS $OS $ARCH, home $HOME, CPU cores $( (nproc || sysctl -n hw.ncpu) 2>/dev/null )"
if [ "$OS" = "Darwin" ]; then ok "GPU: $(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2; exit}')"
else ok "GPU: $( (lspci 2>/dev/null | grep -iE 'vga|3d' | head -1 | cut -d: -f3) || echo unknown)"; fi

pkg_install() {   # pkg_install <brew-name> <apt/dnf/pacman-name>
  if [ "$OS" = "Darwin" ]; then
    command -v brew >/dev/null || die "Homebrew missing: install from https://brew.sh then re-run"
    brew install "$1" || brew upgrade "$1"
  elif command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y $2
  elif command -v dnf >/dev/null; then sudo dnf install -y $2
  elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm $2
  else die "no supported package manager; install $2 manually"; fi
}
node_major() { node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/' || echo 0; }

command -v git >/dev/null || { pkg_install git git; FIXED+=("git"); }
ok "$(git --version)"

if [ "$(node_major)" -lt 18 ] 2>/dev/null || ! command -v node >/dev/null; then
  if [ "$OS" = "Darwin" ]; then pkg_install node node
  elif command -v apt-get >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs
  else pkg_install node nodejs; fi
  FIXED+=("Node.js -> $(node -v)")
fi
[ "$(node_major)" -ge 18 ] || die "Node.js 18+ required, found $(node -v 2>/dev/null || echo none)"
ok "node $(node -v), npm $(npm -v), npx $(command -v npx)"

PY=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)'; then PY="$(command -v "$c")"; break; fi
done
if [ -z "$PY" ]; then pkg_install python@3.12 "python3 python3-pip"; FIXED+=("Python 3"); PY="$(command -v python3.12 || command -v python3)"; fi
ok "Python $("$PY" -V 2>&1 | cut -d' ' -f2) at $PY"

has_prores() { local e; e="$(ffmpeg -hide_banner -encoders 2>/dev/null || true)"; grep -qE ' prores(_ks)? ' <<<"$e"; }
if ! command -v ffmpeg >/dev/null || ! has_prores; then pkg_install ffmpeg ffmpeg; FIXED+=("FFmpeg (ProRes)"); fi
has_prores || die "ffmpeg has no ProRes encoder; transparent .mov overlays will not work"
ok "ffmpeg $(ffmpeg -version | head -1 | awk '{print $3}') with $(ffmpeg -hide_banner -encoders 2>/dev/null | grep -oE 'prores_ks|prores_aw' | sort -u | tr '\n' ' ')"

mkdir -p "$TOOLS" "$RENDERS" "$SKILLS"; ok "workspace $TOOLS, renders $RENDERS"

clone() {  # clone <url> <dir>
  if [ -d "$2/.git" ]; then git -C "$2" pull -q --ff-only || warn "$(basename "$2"): pull failed, using existing clone"
  else git clone -q --depth 1 "$1" "$2"; fi
}
install_skill() {  # install_skill <src-dir> <name>  (replaces a stale copy or symlink)
  rm -rf "${SKILLS:?}/$2"; cp -R "$1" "$SKILLS/$2"
}

# ---------------- Phase 2: motion-broll ----------------
info "Phase 2: motion-broll"
clone https://github.com/Barty-Bart/motion-graphics.git "$TOOLS/motion-graphics"
npx -y skills add Barty-Bart/motion-graphics --skill motion-broll -g -y -a claude-code </dev/null >/dev/null 2>&1 || warn "npx skills add failed; copying instead"
# Always end with a real copy from the clone so engine/, scripts/, reference/ and examples/ are intact.
install_skill "$TOOLS/motion-graphics/skills/motion-broll" motion-broll
for f in engine/render.js engine/build.py engine/beats.js scripts/inspect_video.py reference/engine-api.md; do
  [ -f "$SKILLS/motion-broll/$f" ] || die "motion-broll is missing $f"; done
ok "skill motion-broll -> $SKILLS/motion-broll"

"$PY" -c 'import numpy' 2>/dev/null || "$PY" -m pip install --user -q numpy 2>/dev/null || "$PY" -m pip install --user -q --break-system-packages numpy
ok "numpy $("$PY" -c 'import numpy; print(numpy.__version__)')"

mkdir -p "$RUNTIME"; [ -f "$RUNTIME/package.json" ] || echo '{"private":true}' > "$RUNTIME/package.json"
if [ "${SKIP_BROWSER:-0}" = "1" ] && GLOBAL_PW="$(node -p 'require.resolve("playwright/package.json")' 2>/dev/null)"; then
  mkdir -p "$RUNTIME/node_modules" && ln -sfn "$(dirname "$GLOBAL_PW")" "$RUNTIME/node_modules/playwright"   # reuse a preinstalled Playwright
  ln -sfn "$(dirname "$(dirname "$GLOBAL_PW")")/playwright-core" "$RUNTIME/node_modules/playwright-core"
else
  (cd "$RUNTIME" && npm install --silent --no-fund --no-audit playwright && npx playwright install chromium)
fi
ok "shared Playwright + Chromium -> $RUNTIME (NODE_PATH=$RUNTIME/node_modules)"

# ---------------- Phase 3: HyperFrames ----------------
info "Phase 3: HyperFrames"
clone https://github.com/heygen-com/hyperframes.git "$TOOLS/hyperframes"
if ! npx -y skills add https://github.com/heygen-com/hyperframes --all -g -y -a claude-code </dev/null >/dev/null 2>&1; then
  warn "npx skills add failed; copying skills from the clone"
  for d in "$TOOLS/hyperframes/skills"/*/; do install_skill "$d" "$(basename "$d")"; done
fi
for s in hyperframes hyperframes-cli hyperframes-registry media-use; do
  [ -f "$SKILLS/$s/SKILL.md" ] || install_skill "$TOOLS/hyperframes/skills/$s" "$s"; done
ok "HyperFrames skills: $(cd "$TOOLS/hyperframes/skills" && ls | tr '\n' ' ')"

if ! npm install -g --silent --no-fund --no-audit hyperframes 2>/dev/null; then
  warn "global npm dir not writable; using ~/.npm-global"
  npm config set prefix "$HOME/.npm-global"; export PATH="$HOME/.npm-global/bin:$PATH"
  RC="$HOME/.zshrc"; [ "${SHELL##*/}" = "bash" ] && RC="$HOME/.bashrc"
  grep -q 'npm-global' "$RC" 2>/dev/null || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$RC"
  npm install -g --silent --no-fund --no-audit hyperframes
fi
ok "hyperframes $(hyperframes --version)"
hyperframes browser ensure </dev/null | tail -1; ok "HyperFrames Chrome: $(hyperframes browser path 2>/dev/null | tail -1)"

clone https://github.com/Clipwing/skills.git "$TOOLS/clipwing-skills"
install_skill "$TOOLS/clipwing-skills/skills/hyperframes-to-after-effects" hyperframes-to-after-effects
ok "skill hyperframes-to-after-effects"

# ---------------- Phase 4: audio pipeline + CLAUDE.md ----------------
info "Phase 4: audio pipeline + CLAUDE.md"
for s in earshot real-sound real-sfx openverse-audio; do
  [ -f "$SKILLS/$s/SKILL.md" ] && ok "audio skill $s present" || warn "audio skill $s missing (run audio-tools-installer/install.sh)"; done
[ -f "$HOME/ai-audio-tools/openverse-audio/openverse_sfx.py" ] && ok "openverse_sfx.py present" || warn "openverse_sfx.py missing"
CMD="$HOME/.claude/CLAUDE.md"; touch "$CMD"
grep -q "Sound Design & Audio Workflow" "$CMD" || warn "CLAUDE.md has no Sound Design section yet (the audio installer adds it)"
"$PY" - "$CMD" "$KIT/claude-md-section.md" <<'EOF'
import re, sys
cmd, sec = sys.argv[1], open(sys.argv[2]).read().strip() + "\n"
s = open(cmd).read()
pat = re.compile(r"<!-- BEGIN broll-pipeline.*?<!-- END broll-pipeline -->\n?", re.S)
s = pat.sub(lambda m: sec, s) if pat.search(s) else (s.rstrip() + "\n\n" if s.strip() else "") + sec
open(cmd, "w").write(s)
EOF
ok "~/.claude/CLAUDE.md has the B-Roll & Motion Graphics Pipeline section"

# ---------------- Phase 5: smoke test ----------------
info "Phase 5: smoke test"
ST="$RENDERS/smoke-test"; rm -rf "$ST"
(cd "$RENDERS" && hyperframes init smoke-test --example blank --non-interactive --skip-skills >/dev/null)
cp "$KIT/smoke-test/index.html" "$ST/index.html"
cd "$ST"
hyperframes check --json > .check.json 2>/dev/null || true
"$PY" -c 'import json,sys; d=json.load(open(".check.json")); print("  check ok:", d["ok"]); sys.exit(0 if d["ok"] else 1)' || die "hyperframes check failed (see $ST/.check.json)"
hyperframes render -o smoke_test.mp4 --fps 30 </dev/null >"$TOOLS/smoke-render.log" 2>&1 || die "render failed, see $TOOLS/smoke-render.log"
ok "rendered $(ffprobe -v error -show_entries stream=codec_name,width,height,nb_frames -of csv=p=0 smoke_test.mp4) -> $ST/smoke_test.mp4"

M="$ST/motion"; mkdir -p "$M"/{clips,dist,out,work}
cp "$SKILLS/motion-broll/examples/opus-aoe2/06-chapter.html" "$M/clips/"
"$PY" "$SKILLS/motion-broll/engine/build.py" "$M/dist" "$M/clips/06-chapter.html" >/dev/null
NODE_PATH="$RUNTIME/node_modules" node "$SKILLS/motion-broll/engine/render.js" "$M/dist/06-chapter.html" "$M/out/06-chapter.mp4" 30
ok "motion-broll engine rendered $(ffprobe -v error -show_entries stream=nb_frames -of csv=p=0 "$M/out/06-chapter.mp4") frames with motion blur"
rm -rf "$M" .check.json .hyperframes renders

info "Done"
if [ ${#FIXED[@]} -gt 0 ]; then echo "  Installed/upgraded: ${FIXED[*]}"; else echo "  Nothing needed installing or upgrading."; fi
echo "  Smoke test: $ST/smoke_test.mp4"
echo "  Restart Claude Code so it loads the new skills (/motion-broll, /hyperframes)."
