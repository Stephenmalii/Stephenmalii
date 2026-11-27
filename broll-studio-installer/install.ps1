# B-roll & motion graphics studio for Claude Code (Windows PowerShell): motion-broll + HyperFrames + AE export,
# shared Playwright runtime, CLAUDE.md pipeline rules, end-to-end smoke test.
# Usage (PowerShell, normal user, not as admin):
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\install.ps1
$ErrorActionPreference = 'Stop'

$Kit     = $PSScriptRoot
$Home_   = $env:USERPROFILE
$Tools   = Join-Path $Home_ 'ai-video-tools'
$Renders = Join-Path $Home_ 'broll-renders'
$Claude  = Join-Path $Home_ '.claude'
$Skills  = Join-Path $Claude 'skills'
$Runtime = Join-Path $Tools 'motion-runtime'
$Fixed   = @()
function Ok($m)   { Write-Host "  ok   $m" -ForegroundColor Green }
function Info($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "  warn $m" -ForegroundColor Yellow }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }
# Runs a native command through cmd so its stderr chatter never trips $ErrorActionPreference; throws on a non-zero exit.
function Run([string]$CmdLine, [switch]$Quiet) {
  if ($Quiet) { cmd /c "$CmdLine >nul 2>&1" } else { cmd /c "$CmdLine 2>&1" | Out-Host }
  if ($LASTEXITCODE -ne 0) { throw "failed ($LASTEXITCODE): $CmdLine" } }
function Try-Run([string]$CmdLine) { cmd /c "$CmdLine >nul 2>&1"; return ($LASTEXITCODE -eq 0) }

# ---------------- Phase 1: prerequisites ----------------
Info 'Phase 1: runtime & rendering prerequisites'
$gpu = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name)
Ok "Windows $([Environment]::OSVersion.Version) $env:PROCESSOR_ARCHITECTURE, $env:NUMBER_OF_PROCESSORS cores, GPU $gpu, home $Home_"
function WinInstall($id, $chocoName) {
  if (Has winget) { cmd /c "winget install -e --id $id --accept-source-agreements --accept-package-agreements --silent 2>&1" | Out-Host }
  elseif (Has choco) { cmd /c "choco install -y $chocoName 2>&1" | Out-Host }
  else { throw "Neither winget nor choco found: install $id manually" }
  Refresh-Path }

if (-not (Has git)) { WinInstall 'Git.Git' 'git'; $Fixed += 'Git' }
Ok (git --version)

function NodeMajor { if (Has node) { [int]((node -v) -replace '^v(\d+).*','$1') } else { 0 } }
if ((NodeMajor) -lt 18) { WinInstall 'OpenJS.NodeJS.LTS' 'nodejs-lts'; $Fixed += 'Node.js LTS' }
if ((NodeMajor) -lt 18) { throw 'Node.js 18+ still not on PATH: open a NEW PowerShell and re-run' }
Ok "node $(node -v), npm $(npm.cmd -v)"

$Py = $null
foreach ($v in '3.13','3.12','3.11','3.10') { if (Has py) { $p = (& py "-$v" -c 'import sys;print(sys.executable)' 2>$null); if ($LASTEXITCODE -eq 0 -and $p) { $Py = $p.Trim(); break } } }
if (-not $Py -and (Has python)) { $p = (& python -c 'import sys;print(sys.executable if sys.version_info>=(3,10) else "")' 2>$null); if ($p -and $p -notmatch 'WindowsApps') { $Py = $p.Trim() } }
if (-not $Py) { WinInstall 'Python.Python.3.12' 'python312'; $Fixed += 'Python 3.12'; $Py = (& py -3.12 -c 'import sys;print(sys.executable)').Trim() }
Ok "Python $(& $Py -V) at $Py"

function HasProRes { if (-not (Has ffmpeg)) { return $false }; $e = (cmd /c 'ffmpeg -hide_banner -encoders 2>nul') -join "`n"; return ($e -match ' prores(_ks)? ') }
if (-not (HasProRes)) { WinInstall 'Gyan.FFmpeg' 'ffmpeg'; $Fixed += 'FFmpeg (ProRes)' }
if (-not (HasProRes)) { throw 'ffmpeg with ProRes not on PATH: open a NEW PowerShell and re-run' }
Ok "ffmpeg $(((cmd /c 'ffmpeg -version 2>nul') | Select-Object -First 1).Split(' ')[2]) with prores_ks"

New-Item -ItemType Directory -Force -Path $Tools, $Renders, $Skills | Out-Null
Ok "workspace $Tools, renders $Renders"

function Clone($url, $dir) {
  if (Test-Path (Join-Path $dir '.git')) { if (-not (Try-Run "git -C `"$dir`" pull -q --ff-only")) { Warn "$(Split-Path $dir -Leaf): pull failed, using existing clone" } }
  else { Run "git -c core.longpaths=true clone -q --depth 1 $url `"$dir`"" } }
function Install-Skill($src, $name) {   # real copy (replaces a stale copy or a symlink/junction from npx skills)
  $dst = Join-Path $Skills $name
  if (Test-Path $dst) { cmd /c "rmdir /s /q `"$dst`"" | Out-Null }
  Copy-Item -Recurse -Force $src $dst }

# ---------------- Phase 2: motion-broll ----------------
Info 'Phase 2: motion-broll'
Clone 'https://github.com/Barty-Bart/motion-graphics.git' (Join-Path $Tools 'motion-graphics')
if (-not (Try-Run 'npx.cmd -y skills add Barty-Bart/motion-graphics --skill motion-broll -g -y -a claude-code')) { Warn 'npx skills add failed; copying instead' }
Install-Skill (Join-Path $Tools 'motion-graphics\skills\motion-broll') 'motion-broll'
foreach ($f in 'engine\render.js','engine\build.py','engine\beats.js','scripts\inspect_video.py','reference\engine-api.md') {
  if (-not (Test-Path (Join-Path $Skills "motion-broll\$f"))) { throw "motion-broll is missing $f" } }
Ok "skill motion-broll -> $Skills\motion-broll"

if (-not (Try-Run "`"$Py`" -c `"import numpy`"")) { Run "`"$Py`" -m pip install --user -q numpy" }
Ok "numpy $(& $Py -c 'import numpy; print(numpy.__version__)')"

New-Item -ItemType Directory -Force -Path $Runtime | Out-Null
if (-not (Test-Path (Join-Path $Runtime 'package.json'))) { Set-Content -Path (Join-Path $Runtime 'package.json') -Value '{"private":true}' -Encoding ascii }
Push-Location $Runtime
Run 'npm.cmd install --silent --no-fund --no-audit playwright'
Run 'npx.cmd playwright install chromium'
Pop-Location
Ok "shared Playwright + Chromium -> $Runtime (NODE_PATH=$Runtime\node_modules)"

# ---------------- Phase 3: HyperFrames ----------------
Info 'Phase 3: HyperFrames'
$Hf = Join-Path $Tools 'hyperframes'
Clone 'https://github.com/heygen-com/hyperframes.git' $Hf
if (-not (Try-Run 'npx.cmd -y skills add https://github.com/heygen-com/hyperframes --all -g -y -a claude-code')) { Warn 'npx skills add failed; copying skills from the clone' }
# Copy from the clone too: on Windows npx may leave symlinks that need Developer Mode.
Get-ChildItem -Directory (Join-Path $Hf 'skills') | ForEach-Object { Install-Skill $_.FullName $_.Name }
Ok "HyperFrames skills: $((Get-ChildItem -Directory (Join-Path $Hf 'skills')).Name -join ' ')"

Run 'npm.cmd install -g --silent --no-fund --no-audit hyperframes'
Refresh-Path
Ok "hyperframes $((cmd /c 'hyperframes --version 2>nul') | Select-Object -Last 1)"
Run 'hyperframes browser ensure'
Ok "HyperFrames Chrome: $((cmd /c 'hyperframes browser path 2>nul') | Select-Object -Last 1)"

Clone 'https://github.com/Clipwing/skills.git' (Join-Path $Tools 'clipwing-skills')
Install-Skill (Join-Path $Tools 'clipwing-skills\skills\hyperframes-to-after-effects') 'hyperframes-to-after-effects'
Ok 'skill hyperframes-to-after-effects'

# ---------------- Phase 4: audio pipeline + CLAUDE.md ----------------
Info 'Phase 4: audio pipeline + CLAUDE.md'
foreach ($s in 'earshot','real-sound','real-sfx','openverse-audio') {
  if (Test-Path (Join-Path $Skills "$s\SKILL.md")) { Ok "audio skill $s present" } else { Warn "audio skill $s missing (run audio-tools-installer\install.ps1)" } }
if (Test-Path (Join-Path $Home_ 'ai-audio-tools\openverse-audio\openverse_sfx.py')) { Ok 'openverse_sfx.py present' } else { Warn 'openverse_sfx.py missing' }
$Cmd = Join-Path $Claude 'CLAUDE.md'
if (-not (Test-Path $Cmd)) { New-Item -ItemType File -Path $Cmd | Out-Null }
$cur = [IO.File]::ReadAllText($Cmd)
if ($cur -notmatch 'Sound Design & Audio Workflow') { Warn 'CLAUDE.md has no Sound Design section yet (the audio installer adds it)' }
$sec = ([IO.File]::ReadAllText((Join-Path $Kit 'claude-md-section.md'))).Trim() + "`n"
$rx = [regex]'(?s)<!-- BEGIN broll-pipeline.*?<!-- END broll-pipeline -->\r?\n?'
if ($rx.IsMatch($cur)) { $new = $rx.Replace($cur, { param($m) $sec }) }
elseif ($cur.Trim()) { $new = $cur.TrimEnd() + "`n`n" + $sec } else { $new = $sec }
[IO.File]::WriteAllText($Cmd, $new, (New-Object Text.UTF8Encoding $false))
Ok '~/.claude/CLAUDE.md has the B-Roll & Motion Graphics Pipeline section'

# ---------------- Phase 5: smoke test ----------------
Info 'Phase 5: smoke test'
$St = Join-Path $Renders 'smoke-test'
if (Test-Path $St) { cmd /c "rmdir /s /q `"$St`"" | Out-Null }
Push-Location $Renders; Run 'hyperframes init smoke-test --example blank --non-interactive --skip-skills' -Quiet; Pop-Location
Copy-Item -Force (Join-Path $Kit 'smoke-test\index.html') (Join-Path $St 'index.html')
Push-Location $St
cmd /c 'hyperframes check --json 2>nul' | Set-Content -Encoding utf8 .check.json
$chk = Get-Content -Raw .check.json | ConvertFrom-Json
if (-not $chk.ok) { throw "hyperframes check failed (see $St\.check.json)" }
Ok 'hyperframes check --json: ok'
$log = Join-Path $Tools 'smoke-render.log'
cmd /c "hyperframes render -o smoke_test.mp4 --fps 30 > `"$log`" 2>&1"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path smoke_test.mp4)) { throw "render failed, see $log" }
Ok "rendered $((cmd /c 'ffprobe -v error -show_entries stream=codec_name,width,height,nb_frames -of csv=p=0 smoke_test.mp4 2>nul')) -> $St\smoke_test.mp4"

$M = Join-Path $St 'motion'
foreach ($d in 'clips','dist','out','work') { New-Item -ItemType Directory -Force -Path (Join-Path $M $d) | Out-Null }
Copy-Item (Join-Path $Skills 'motion-broll\examples\opus-aoe2\06-chapter.html') (Join-Path $M 'clips')
Run "`"$Py`" `"$Skills\motion-broll\engine\build.py`" `"$M\dist`" `"$M\clips\06-chapter.html`"" -Quiet
$env:NODE_PATH = Join-Path $Runtime 'node_modules'
Run "node `"$Skills\motion-broll\engine\render.js`" `"$M\dist\06-chapter.html`" `"$M\out\06-chapter.mp4`" 30"
Ok "motion-broll engine rendered $((cmd /c "ffprobe -v error -show_entries stream=nb_frames -of csv=p=0 `"$M\out\06-chapter.mp4`" 2>nul")) frames with motion blur"
Pop-Location
foreach ($junk in 'motion','.check.json','.hyperframes','renders') { $p = Join-Path $St $junk; if (Test-Path $p) { Remove-Item -Recurse -Force $p } }

Info 'Done'
if ($Fixed.Count) { Write-Host "  Installed/upgraded: $($Fixed -join ', ')" } else { Write-Host '  Nothing needed installing or upgrading.' }
Write-Host "  Smoke test: $St\smoke_test.mp4"
Write-Host '  Restart Claude Code so it loads the new skills (/motion-broll, /hyperframes).'
