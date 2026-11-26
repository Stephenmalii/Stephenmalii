# Installs earshot (MCP + skills), Real SFX and the Openverse audio skill for Claude Code (Windows PowerShell).
# Usage (PowerShell, normal user):
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\install.ps1
#   .\install.ps1 -SkipModels     # skip the ~1.1 GB listening-model download
param([switch]$SkipModels)
$ErrorActionPreference = 'Stop'

$Kit    = $PSScriptRoot
$Home_  = $env:USERPROFILE
$Tools  = Join-Path $Home_ 'ai-audio-tools'
$Lib    = Join-Path $Home_ 'sfx-library'
$Claude = Join-Path $Home_ '.claude'
$Skills = Join-Path $Claude 'skills'
function Ok($m)   { Write-Host "  ok   $m" -ForegroundColor Green }
function Info($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  warn $m" -ForegroundColor Yellow }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
function Run { param([string]$Exe, [Parameter(ValueFromRemainingArguments)]$Rest)
  & $Exe @Rest; if ($LASTEXITCODE -ne 0) { throw "$Exe $($Rest -join ' ') failed ($LASTEXITCODE)" } }

# ---------------- Phase 1 ----------------
Info 'Phase 1: environment'
Ok "Windows $([Environment]::OSVersion.Version) $env:PROCESSOR_ARCHITECTURE, home $Home_"
function WinInstall($id) {
  if (Has winget) { winget install -e --id $id --accept-source-agreements --accept-package-agreements --silent; Refresh-Path }
  elseif (Has choco) { throw "winget missing: run 'choco install' for $id from an elevated shell" }
  else { throw "Neither winget nor choco found: install $id manually" } }
if (-not (Has git))    { WinInstall 'Git.Git' };       Ok (git --version)
if (-not (Has ffmpeg)) { WinInstall 'Gyan.FFmpeg' };   if (Has ffmpeg) { Ok 'ffmpeg on PATH' } else { Warn 'ffmpeg installed: open a NEW PowerShell and re-run if later steps miss it' }

$Py = $null
foreach ($v in '3.13','3.12','3.11','3.10') { if (Has py) { $p = (& py "-$v" -c 'import sys;print(sys.executable)' 2>$null); if ($LASTEXITCODE -eq 0 -and $p) { $Py = $p.Trim(); break } } }
if (-not $Py -and (Has python)) { $p = (& python -c 'import sys;print(sys.executable if sys.version_info>=(3,10) else "")' 2>$null); if ($p -and $p -notmatch 'WindowsApps') { $Py = $p.Trim() } }
if (-not $Py) { WinInstall 'Python.Python.3.12'; $Py = (& py -3.12 -c 'import sys;print(sys.executable)').Trim() }
Ok "Python $(& $Py -V) at $Py"
if (Has node) { Ok "node $(node -v)" } else { Warn 'Node.js not found (optional)' }
if (-not (Has claude)) { throw "Claude Code CLI 'claude' not on PATH: https://docs.claude.com/claude-code" }
Ok "claude $(claude --version)"
New-Item -ItemType Directory -Force -Path $Tools, (Join-Path $Lib 'openverse'), (Join-Path $Lib 'test'), $Skills | Out-Null
Ok "created $Tools and $Lib"

# ---------------- Phase 2: earshot ----------------
Info 'Phase 2: earshot'
$Ear = Join-Path $Tools 'earshot'
if (Test-Path (Join-Path $Ear '.git')) { git -C $Ear pull -q --ff-only } else { Run git clone -q https://github.com/Leonxlnx/earshot.git $Ear }
$VPy = Join-Path $Ear '.venv\Scripts\python.exe'
if (-not (Test-Path $VPy)) { Run $Py -m venv (Join-Path $Ear '.venv') }
Push-Location $Ear
Run $VPy -m pip install -q --upgrade pip
Run $VPy -m pip install -q torch --index-url https://download.pytorch.org/whl/cpu
Run $VPy -m pip install -q -e '.[mcp,listen]'
Pop-Location
Ok "earshot $(& $VPy -m earshot --version)"
if (-not $SkipModels) { & $VPy -m earshot doctor --fetch; if ($LASTEXITCODE -ne 0) { Warn "model fetch failed; re-run: $VPy -m earshot doctor --fetch" } }

foreach ($s in 'earshot','real-sound') { $d = Join-Path $Skills $s; if (Test-Path $d) { Remove-Item -Recurse -Force $d }; Copy-Item -Recurse (Join-Path $Ear "skills\$s") $d }
$Cmd = Join-Path $Claude 'commands\earshot'; New-Item -ItemType Directory -Force $Cmd | Out-Null
Copy-Item (Join-Path $Ear 'commands\*.md') $Cmd -Force
Ok 'skills earshot, real-sound + /earshot:make, /earshot:make-set'

$Scripts = Join-Path $Ear '.venv\Scripts'
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($UserPath -split ';') -notcontains $Scripts) { [Environment]::SetEnvironmentVariable('Path', "$UserPath;$Scripts", 'User'); Refresh-Path; Warn 'added earshot to your user PATH (new terminals)' }
Ok 'earshot CLI on PATH'

claude mcp remove earshot --scope user 2>$null | Out-Null
Run claude mcp add earshot --scope user -e EARSHOT_THREADS=3 -- $VPy -m earshot mcp
Ok "MCP server 'earshot' registered (user scope)"

# ---------------- Phase 3: Real SFX ----------------
Info 'Phase 3: Real SFX'
$Cw = Join-Path $Tools 'clipwing-skills'
if (Test-Path (Join-Path $Cw '.git')) { git -C $Cw pull -q --ff-only } else { Run git clone -q https://github.com/Clipwing/skills.git $Cw }
$Rs = Join-Path $Skills 'real-sfx'
if (Test-Path (Join-Path $Rs 'config.json')) { Copy-Item (Join-Path $Rs 'config.json') (Join-Path $Tools 'real-sfx-config.backup.json') -Force }
if (Test-Path $Rs) { Remove-Item -Recurse -Force $Rs }
Copy-Item -Recurse (Join-Path $Cw 'skills\real-sfx') $Rs
Push-Location $Rs
& $Py scripts\setup.py add-library sfx-library $Lib --index | Out-Null
& $Py scripts\setup.py check
Pop-Location
$n = (Get-ChildItem -Recurse -Filter *.mp3 (Join-Path $Rs 'vendor')).Count
Ok "real-sfx installed; ~/sfx-library is its main library ($n bundled uisfx files)"

# ---------------- Phase 4: Openverse ----------------
Info 'Phase 4: Openverse audio'
$Ov = Join-Path $Tools 'openverse-audio'; New-Item -ItemType Directory -Force $Ov, (Join-Path $Skills 'openverse-audio') | Out-Null
Copy-Item (Join-Path $Kit 'openverse-audio\openverse_sfx.py') $Ov -Force
(Get-Content -Raw (Join-Path $Kit 'skills\openverse-audio\SKILL.md')) -replace 'python3 ', 'python ' |
  Set-Content -Encoding UTF8 (Join-Path $Skills 'openverse-audio\SKILL.md')
Ok 'openverse_sfx.py + openverse-audio skill'

# ---------------- Phase 5 ----------------
Info 'Phase 5: CLAUDE.md + verification'
$Md = Join-Path $Claude 'CLAUDE.md'; if (-not (Test-Path $Md)) { New-Item $Md | Out-Null }
if (-not (Select-String -Path $Md -SimpleMatch 'Sound Design & Audio Workflow' -Quiet)) {
  ((Get-Content -Raw (Join-Path $Kit 'claude-md-section.md')) -replace 'python3 ', 'python ') | Add-Content -Encoding UTF8 $Md }
Ok '~/.claude/CLAUDE.md has the Sound Design section'

Push-Location (Join-Path $Lib 'test'); & $VPy -m earshot make 'a soft bright chime' -o test_chime.wav; Pop-Location
& $Py (Join-Path $Ov 'openverse_sfx.py') --query 'ui click' --license cc0 --limit 2 --download-dir (Join-Path $Lib 'openverse')
Push-Location $Rs; & $Py scripts\build_index.py | Out-Null; Pop-Location
claude mcp list | Select-String earshot
Info 'Done. Restart Claude Code to load the new skills and MCP server.'
