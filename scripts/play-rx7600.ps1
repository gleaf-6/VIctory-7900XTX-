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
#   - the title runs as the bigger console (Series X). The smaller one is
#     3-4x faster on this hardware (173-370 ms a frame against 337-1,441, and
#     19 GB of the PC's memory against 22-26) but on this fork it does not
#     draw its 2D layer: the loading screen and the opening cutscene are black
#     and the world comes without HUD, subtitles or menu. The shorter frames
#     were frames without the interface. -SeriesS is there for whoever wants
#     to look into that path.
#   scripts\play-rx7600.ps1 -Exe <path of your own copy's executable>
# -Resolution   1280x720 (the default), 1600x900 or 1920x1080
# -RayTracing   the title's own ray-traced indirect light: lit interiors,
#               about a third slower
# -Stats        keep the diagnostics build's statistics (VICTORY_LOG=info)
# -SeriesS      run the title as the smaller console: 3-4x shorter frames, but
#               on this fork its 2D layer (loading screens, cutscene video,
#               HUD, subtitles, menu) is black — see above
# -Tune         experimental, for a card of 8 GB: title buffers kept in the
#               card's memory (VICTORY_CARD_BUFFERS_MIN_KB=64,
#               VICTORY_CARD_BUFFERS_MB=1024, after fxceless/victory-fork).
#               VICTORY_INPLACE is NOT part of it: measured here, that one
#               made frames 1.2-2.0 s (from 0.3-1.4) and ended the process
#               after about 100 s — the title frees memory it has opened.
# -Record       write down the pipelines this run makes (VICTORY_PIPELINE_BOOK=1),
#               so that `target\diag\victory.exe warm --used` can make them all
#               ahead of the next run and no frame waits for one
# -Build        target\diag (the default) or target\release
# -More         other settings: -More @{VICTORY_AMBIENT='2'}
# Run it from a normal window, not as administrator: the driver then keeps its
# shader cache elsewhere.
param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('1280x720', '1600x900', '1920x1080', '2560x1440', '3840x2160')][string]$Resolution = '1280x720',
    [switch]$RayTracing,
    [switch]$SeriesS,
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
    [ValidateSet(0, 2)][int]$Relay = 0,
    [ValidateSet(0, 1, 2)][int]$Inplace = 2,
    [ValidateSet(0, 1)][int]$CardBuffers = 1,
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
    # The stand-in for the indirect light the title's rays would bring. A
    # constant level, modulated by the creases' occlusion (the `open` term),
    # not a share of the estimate: measured here, 1.6 of the estimate left the
    # night scenes black and 2.5 washed the picture into a beige veil, while
    # `constant:0.1` showed the room lit and cost nothing (255 ms either way).
    # -AmbientSpec '' -Ambient 1.2 goes back to the estimate.
    VICTORY_AMBIENT = $(if ($AmbientSpec) { $AmbientSpec } elseif ($Ambient -le 0) { '0' } else { "$Ambient" })
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
# 8 GB). -CardBuffers 0 turns it off.
if ($CardBuffers -eq 0) {
    $settings.VICTORY_CARD_BUFFERS = '0'
} else {
    $settings.VICTORY_CARD_BUFFERS_MIN_KB = '64'
    $settings.VICTORY_CARD_BUFFERS_MB = '1024'
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
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR'
Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
$Exe = (Resolve-Path $Exe).Path
$console = if ($SeriesS) { @('--console', 'series-s') } else { @() }
Push-Location (Join-Path $PSScriptRoot '..')   # victory.toml is looked for here
try { & $victory run $Exe --execute @console } finally { Pop-Location }