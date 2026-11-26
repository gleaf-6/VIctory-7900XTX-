# Starts the title with settings for a card of 8 GB and a PC of 32 GB of RAM
# (the measured machine: a Radeon RX 7600 and a Ryzen 7 5700X).
# scripts\play.ps1 is the fork's own set; this one keeps all of it and adds
# what this class of hardware needs:
#   - the display reported to the title is the one the PC has (720p unless
#     -Resolution says otherwise), not 4K: the title derives every render
#     target from it, and on 8 GB that is most of the budget;
#   - less of the card is kept for the copies of textures the title fills;
#   - the windows of title memory are cut on a finer grid, so an ask reads
#     less of the PC's memory with it;
#   - the diagnostics build's per-second statistics are left out (the memory
#     map alone takes about a second each time it is written).
#   - the title runs as the smaller console (Series S) when the FidelityFX
#     folder is given: that is the profile every number here was measured
#     with. Its two presentation planes are composed into one 1080p picture
#     (loading screens, cutscene video, HUD, subtitles and menu included),
#     the console's 720p upscale is answered by the PC FidelityFX SDK, and a
#     generated frame goes between the rendered ones. WITHOUT that folder
#     Series S has no upscaler to answer it: the world comes black, so the
#     run falls back to the bigger console (Series X), which renders alone.
#     -SeriesS and -SeriesX force either one.
#   scripts\play-rx7600.ps1 -Exe <path of your own copy's executable>
#       -FidelityFxDir <SDK>\Kits\FidelityFX\signedbin
# -Resolution   1280x720 (the default), 1600x900 or 1920x1080
# -RayTracing   the title's own ray-traced indirect light: lit interiors,
#               about a third slower
# -Stats        keep the diagnostics build's statistics (VICTORY_LOG=info)
# -Ambient      the indirect light stand-in: a constant level (0.4 default),
#               shaded in creases. -AmbientSpec 0.4 goes back to a share of
#               the estimate (follows the hour and the lamps, but keeps the
#               sky's blue indoors: white paper comes out lavender), and
#               -AmbientMost 1.5 cuts how much of that sky it keeps.
# -SeriesS      force the smaller console (the default when -FidelityFxDir or
#               VICTORY_FIDELITYFX_SDK is given)
# -SeriesX      force the bigger console (the default without the SDK: it
#               renders without the host upscaler)
# -Tune         kept for old command lines: it sets what is now the default of
#               the 8 GB class, VICTORY_CARD_BUFFERS_MIN_KB=64 with 1 GiB of
#               card copies (after fxceless/victory-fork); -CardBuffersMB
#               overrides the size, and the default follows the card.
#               VICTORY_INPLACE is NOT part of them: measured here, that one
#               made frames 1.2-2.0 s (from 0.3-1.4) and ended the process
#               after about 100 s - the title frees memory it has opened.
# -Record       write down the pipelines this run makes (VICTORY_PIPELINE_BOOK=1),
#               so that `target\diag\victory.exe warm --used` can make them all
#               ahead of the next run and no frame waits for one
# -Build        target\diag (the default) or target\release
# -More         other settings: -More @{VICTORY_AMBIENT='2'}
# Run it from a normal window, not as administrator: the driver then keeps its
# shader cache elsewhere.
param(
    [Parameter(Mandatory)][string]$Exe,
    # The package folder when the executable is not inside it
    # (VICTORY_TITLE_DIR): the dump is then only read.
    [string]$TitleDir = '',
    [ValidateSet('1280x720', '1600x900', '1920x1080', '2560x1440', '3840x2160')][string]$Resolution = '1280x720',
    [switch]$RayTracing,
    [switch]$SeriesS,
    [switch]$SeriesX,
    [switch]$Record,
    [switch]$Tune,
    [string]$PipelineDump = '',
    [ValidateRange(0, 8192)][int]$TextureBudgetMB = 0,
    [ValidateRange(0, 1024)][int]$FillsMB = 96,
    [ValidateSet(64, 256, 1024, 4096)][int]$WindowKB = 4096,
    [ValidateRange(0, 8192)][int]$TargetsRoomMB = 3072,
    [switch]$Stats,
    [double]$Ambient = 0.4,
    [string]$AmbientSpec = '',
    # The multiple of the estimate the title's own (sky) light may be kept at
    # (VICTORY_AMBIENT_MOST; 0: as is, 4). Indoors, with the rays off, that
    # sky light is what turns white paper lavender: 1.5 cuts it.
    [double]$AmbientMost = 0,
    [ValidateRange(0, 1048576)][int]$LoopLimit = 0,
    [string]$SkipPipelines = '',
# The FidelityFX SDK's `signedbin` (its `amd_fidelityfx_upscaler_dx12.dll`),
    # or the folder named in `VICTORY_FIDELITYFX_SDK`: the host upscaler and
    # frame generation need it.
    [string]$FidelityFxDir = $env:VICTORY_FIDELITYFX_SDK,
    [string]$NoDepthPipelines = '',
    [string]$Capture = '',
    [int]$CaptureAt = 80,
    [string]$ShotFolder = '',
    [string]$ShotFrames = '',
    [switch]$DumpTargets,
    # AMD's frame generation in place of a console's (VICTORY_FRAMEGEN=1):
    # presents through its swap chain, an interpolated frame between real
    # ones. It needs the FidelityFX folder, which feeds it.
    [switch]$FrameGen,
    # Submissions prepared and sent by a thread of ours (VICTORY_LATE_WAIT=3,
    # VICTORY_ASYNC_SUBMIT=1): the same frame time here, but texture copies go
    # up in the order the lists that need them were made (fewer artefacts
    # while the world streams clothes and textures in).
    [switch]$Async,
    # A timeline of a few frames (VICTORY_TIMELINE): <from s>[,<frames>,]<file>,
    # a Chrome trace and a .txt summary beside it, from that second on.
    [string]$Timeline = '',
    # Raw settings for this run: "K=V;K=V" (for the experiments above).
    [string]$Set = '',
    [double]$AmbientFloor = 0,
    [ValidateSet(0, 1)][int]$LevelsOnDemand = 0,
    [ValidateSet(0, 1)][int]$Thin = 1,
    [ValidateSet(0, 2)][int]$Relay = 2,
    [ValidateSet(0, 1, 2)][int]$Inplace = 0,
    [ValidateSet(0, 1)][int]$CardBuffers = 1,
    # The cap for card copies of title buffers, in MiB (VICTORY_CARD_BUFFERS_MB):
    # 0 lets the card's own class decide (1 GiB on the 8 GB class, 2 GiB on
    # 16 GB cards, a quarter of the budget up to 8 GiB above).
    [ValidateRange(0, 8192)][int]$CardBuffersMB = 0,
    # Windows of title memory kept in card memory the CPU writes through a
    # resizable BAR (VICTORY_WINDOWS_BAR_MB), instead of a copy in the PC's
    # memory: 'auto' (the default) sizes it by the card, none on the 8 and
    # 12 GB classes, 4096 on 16 GB cards; 0 turns it off. Needs Resizable BAR
    # (Smart Access Memory) on in the firmware; without it nothing changes.
    [string]$WindowsBarMB = 'auto',
    [int]$PipelineWaitMS = 24,
    [ValidateSet('diag', 'release')][string]$Build = 'diag',
    [hashtable]$More = @{}
)
$settings = @{
    # What scripts\play.ps1 sets: the fork's newer, faster ways.
    VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_RELAY = "$Relay"; VICTORY_WIDE_BACK = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_JOIN_COPIES = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_RELAY_COPY = '1'; VICTORY_CARD_STEPS = '2'
    VICTORY_INDIRECT_BATCH = '2'; VICTORY_MAP_THREADS = '1'; VICTORY_TITLE_PRIORITIES = '0'; VICTORY_CARD_AWAKE = '1'
    VICTORY_SHOW_AFTER = '1'; VICTORY_D3D12_DRED = 'light'; VICTORY_SKIP_PIPELINES = 'none'
    # Thin lists (calls written down, translated by other threads) have no host
    # list of their own; the FidelityFX upscaler records into the list it is
    # handed, so it needs real ones (`-Thin 0`).
    VICTORY_THIN = "$Thin"; VICTORY_JOIN_PARTS = '8'; VICTORY_UPLOAD_AHEAD = '1'
    # The display the title renders for. The fork's default is the PC's own
    # display now (crates\victory-gpu\src\dxgi.rs); this is the 8 GB choice.
    VICTORY_DISPLAY_MODE = $Resolution
    # Levels on demand and the texture budget are the two switches measured to
    # darken the picture on this machine (the title's light textures are ones
    # it fills, and both take copies of those away): off by default.
    VICTORY_LEVELS_ON_DEMAND = "$LevelsOnDemand"
    # Windows of title memory on a 256 KiB grid: every window is the PC's
    # memory in full, however little of it is read (`shadow.rs`, `window`).
    VICTORY_WINDOW_KB = "$WindowKB"
    # The card's memory kept free for the render targets a world makes in its
    # first frame (`VICTORY_CARD_ROOM_FOR_TARGETS_MB`, 3,072 by default).
    VICTORY_CARD_ROOM_FOR_TARGETS_MB = "$TargetsRoomMB"
    # A pipeline the driver is still making does not stop the frame for half
    # a second: the draws that need it are left out of the frames until it is
    # there (500 ms by default; `win 24`, README `VICTORY_PIPELINE_WAIT_MS`).
    VICTORY_PIPELINE_WAIT_MS = "$PipelineWaitMS"
    # The stand-in for the indirect light the title's rays would bring: a
    # constant level (`constant:<Ambient>`), modulated by the creases'
    # occlusion (the `open` term). Measured here, 1.6 of the estimate left the
    # night scenes black and 2.5 washed the picture into a beige veil, while
    # `constant:0.1` showed the room lit and cost nothing (255 ms either way).
    # A share of the estimate follows the hour and the lamps, but with the
    # rays off it also holds the sky's light indoors: white paper lit only
    # indirectly comes out lavender (the prison). `-AmbientSpec 0.4` goes back
    # to the estimate; `-AmbientMost 1.5` cuts the sky it keeps.
    VICTORY_AMBIENT = $(if ($AmbientSpec) { $AmbientSpec } elseif ($Ambient -le 0) { '0' } else { "constant:$Ambient" })
}
if (-not $Stats) { $settings.VICTORY_LOG = 'warn' }
if ($RayTracing) { $settings.VICTORY_BVH_BUILDER = '1' }
if ($Record) { $settings.VICTORY_PIPELINE_BOOK = '1' }
if ($TextureBudgetMB -gt 0) { $settings.VICTORY_TEXTURE_BUDGET_MB = "$TextureBudgetMB" }
# Textures the title fills itself (light, probes, the sea) are let up even
# with the budget spent: up to this many MB of them.
if ($FillsMB -gt 0) { $settings.VICTORY_TEXTURE_FILLS_MB = "$FillsMB" }
if ($Tune) {
    $settings.VICTORY_CARD_BUFFERS_MIN_KB = '64'
    $settings.VICTORY_CARD_BUFFERS_MB = '1024'
}
if ($WindowsBarMB -and $WindowsBarMB -ne '0') { $settings.VICTORY_WINDOWS_BAR_MB = $WindowsBarMB }
if ($PipelineDump) { $settings.VICTORY_PIPELINE_DUMP = $PipelineDump }
# Simulation cut: translated shader loops stop after this many iterations per
# lane (2^20 by default). It changes the shader cache's key for those programs.
if ($LoopLimit -gt 0) { $settings.VICTORY_SHADER_LOOP_LIMIT = "$LoopLimit" }
# Draws and dispatches of a named pipeline are left out (`hash,hash,...`).
if ($SkipPipelines) { $settings.VICTORY_SKIP_PIPELINES = $SkipPipelines }
# Names the render targets of the draws of these shaders, once each.
if ($NotePipelines) { $settings.VICTORY_NOTE_PIPELINES = $NotePipelines }
if ($NoteCopies) { $settings.VICTORY_NOTE_COPIES = '1' }
if ($Async) {
    $settings.VICTORY_LATE_WAIT = '3'
    $settings.VICTORY_ASYNC_SUBMIT = '1'
}
if ($Timeline) { $settings.VICTORY_TIMELINE = $Timeline }
if ($FrameGen) {
    $settings.VICTORY_FRAMEGEN = '1'
    if (-not $FidelityFxDir) { throw '-FrameGen needs the FidelityFX folder (-FidelityFxDir)' }
} elseif ($FidelityFxDir -and -not $PSBoundParameters.ContainsKey('FrameGen')) {
    # The profile's default: FSR, the two planes composed, and a generated
    # frame between real ones (the card idles most of the frame, so it is
    # nearly free here). -FrameGen:$false turns it off.
    $settings.VICTORY_FRAMEGEN = '1'
}
# The PC FidelityFX, in place of the console upscaler (`amd_fidelityfx_upscaler_dx12.dll`).
if ($FidelityFxDir) {
    $settings.VICTORY_FIDELITYFX_DIR = $FidelityFxDir
    # The upscaler records into the list it is given; a thin list has none.
    if (-not $PSBoundParameters.ContainsKey('Thin')) { $settings.VICTORY_THIN = '0' }
}
# An experiment: these pipelines get no depth test (`VICTORY_NO_DEPTH_PIPELINES`).
if ($NoDepthPipelines) { $settings.VICTORY_NO_DEPTH_PIPELINES = $NoDepthPipelines }
# Title memory opened as a heap of the card and used in place: fewer copies
# (`crates/victory-gpu/src/inplace.rs`).
if ($Inplace -gt 0) { $settings.VICTORY_INPLACE = "$Inplace" }
# Copies of title buffers in the card's memory (`VICTORY_CARD_BUFFERS=0`: none,
# which is what in-place level 2 should make unnecessary).
# The CPU's side of the buffers shaders write costs 85-90 ms a frame here
# (measured: 219.6 ms with it, 135.4 with it gone). Kept in the card's own
# memory the copying is the card's, and the frame is 131.1 ms: 1 GiB of
# them, copies from 64 KiB up. Measured beside it: 512 MiB 177.8 ms, 256 MiB
# 246.8 (worse than none), 1536 MiB 144.7 (the card is nearly full at 6.5 of
# 8 GB). -CardBuffers 0 turns it off; -CardBuffersMB forces a size.
if ($CardBuffers -eq 0) {
    $settings.VICTORY_CARD_BUFFERS = '0'
} else {
    $settings.VICTORY_CARD_BUFFERS_MIN_KB = '64'
    # auto, from the card's budget in DXGI: 1 GiB on the 8 GB class (measured
    # here: 512 MiB 177.8 ms, 256 MiB 246.8), 2 GiB on 16 GB cards, a quarter
    # of the budget (at most 8 GiB) above. -CardBuffersMB forces one instead.
    $settings.VICTORY_CARD_BUFFERS_MB = $(if ($CardBuffersMB -gt 0) { "$CardBuffersMB" } else { 'auto' })
}
# Record one frame for `victory replay` (`docs/replay.md`): the stable benchmark.
if ($Capture) {
    $settings.VICTORY_RECORD = $Capture
    $settings.VICTORY_RECORD_AT = "$CaptureAt"
    $settings.VICTORY_RECORD_FRAMES = '1'
}
# Present frames as PNG (`VICTORY_CAPTURE`), and their render targets too
# (`-DumpTargets`): what a pass writes, to look at.
if ($ShotFolder) {
    # The capture writes into the folder but does not create it.
    New-Item -ItemType Directory -Force -Path $ShotFolder | Out-Null
    $settings.VICTORY_CAPTURE = $ShotFolder
}
if ($ShotFrames) { $settings.VICTORY_CAPTURE_FRAMES = $ShotFrames }
if ($DumpTargets) { $settings.VICTORY_DUMP_TARGETS = '1' }
# A floor under the estimate, shaded by the creases: the estimate follows the
# hour and at night is nearly nothing; the floor fills the shadow.
if ($AmbientFloor -gt 0) { $settings.VICTORY_AMBIENT_FLOOR = "$AmbientFloor" }
if ($AmbientMost -gt 0) { $settings.VICTORY_AMBIENT_MOST = "$AmbientMost" }
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }
foreach ($kv in ($Set -split ';')) {
    if ($kv -and $kv.Contains('=')) {
        $k, $v = $kv -split '=', 2
        $settings[$k.Trim()] = $v.Trim()
    }
}

$victory = Join-Path $PSScriptRoot "..\target\$Build\victory.exe"
if (-not (Test-Path $victory)) { Write-Host "No $victory. Build it first (README.md)."; return }
if (-not (Test-Path $Exe)) { Write-Host "No $Exe."; return }
# (Other settings left over in this window go; where your files are stays.)
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR', 'VICTORY_TITLE_DIR'
Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
if ($TitleDir) { $env:VICTORY_TITLE_DIR = (Resolve-Path $TitleDir).Path }
$Exe = (Resolve-Path $Exe).Path
# Series S is the measured profile, but it needs the host upscaler: without the
# FidelityFX folder its world comes black, so the default falls back to Series
# X there. An explicit switch always wins.
$seriesS = if ($PSBoundParameters.ContainsKey('SeriesS') -or $PSBoundParameters.ContainsKey('SeriesX')) {
    ([bool]$SeriesS) -and (-not [bool]$SeriesX)
} else {
    [bool]$FidelityFxDir
}
$console = if ($seriesS) { @('--console', 'series-s') } else { @() }
# Say which profile this run is, and what it is missing: the measured profile
# depends on the FidelityFX folder for the upscale and for the generated frame.
$fgOn = ($settings.VICTORY_FRAMEGEN -eq '1')
Write-Host ("profile: {0} | FSR: {1} | frame generation: {2} | card buffers: {3} | windows in BAR: {7} | relay {4}, inplace {5}, ambient {6}" -f `
    $(if ($seriesS) { 'Series S' } else { 'Series X' }), `
    $(if ($FidelityFxDir) { 'on' } else { 'OFF' }), `
    $(if ($fgOn) { 'on' } else { 'off' }), `
    $(if ($CardBuffers -eq 0) { 'off' } elseif ($CardBuffersMB -gt 0) { "$CardBuffersMB MB" } else { 'auto' }), `
    $Relay, $Inplace, $settings.VICTORY_AMBIENT, $(if ($settings.VICTORY_WINDOWS_BAR_MB) { $settings.VICTORY_WINDOWS_BAR_MB } else { 'off' }))
if (-not $FidelityFxDir) {
    Write-Host 'warning: no FidelityFX folder. Series S has no upscaler to answer it and draws a black world,' -ForegroundColor Yellow
    Write-Host '         so this run falls back to Series X and is NOT the profile the numbers were measured with.' -ForegroundColor Yellow
    Write-Host '         For the measured profile (Series S + FSR + frame generation):' -ForegroundColor Yellow
    Write-Host '           $env:VICTORY_FIDELITYFX_SDK = ''<SDK>\Kits\FidelityFX\signedbin''' -ForegroundColor Yellow
    Write-Host '           scripts\play-rx7600.ps1 -Exe <path of your copy''s executable>' -ForegroundColor Yellow
}
Push-Location (Join-Path $PSScriptRoot '..')   # victory.toml is looked for here
try { & $victory run $Exe --execute @console } finally { Pop-Location }