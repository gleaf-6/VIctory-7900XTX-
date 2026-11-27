# Running the title on a PC — the goal, and how to operate this tree

This tree runs an Xbox Series build of Grand Theft Auto VI on Windows through
[VIctory](https://github.com/Marvisak/VIctory)'s compatibility layer. The goal
of the work in it is simple to state:

> **The best picture this hardware can give, at the best frame rate the layer
> can reach — the Series S experience, on a PC.**

On a console, the title offers two profiles: **Series X** renders at a high
resolution and needs a lot of memory; **Series S** renders the world at
**1280×720** and lets the console's upscaler (FidelityFX) bring it to the
display's resolution, with the interface on a second, higher-resolution
surface. An 8 GB card on a PC cannot hold the Series X profile, so this tree is
tuned around **Series S**: the console profile, the console's upscale answered
by AMD's PC FidelityFX, the title's two presentation planes composed into one
picture, and AMD's frame generation on top.

What that gives, measured on an RX 7600 8 GB / Ryzen 7 5700X:

| | |
|---|---|
| menus, videos, loading screens | 30 fps |
| the world | **9–10 frames a second** (94–104 ms a frame) |
| frames shown, with frame generation | **~19 a second** |
| picture | whole: lit world, interface, cutscenes (checked by saved frames) |

**This is not a 30 fps experience on that hardware, and it does not claim to
be.** The title itself needs about 33 ms a frame on a console; here every draw
and every dispatch is translated, and the console's shared memory has to be
kept coherent by copying — the CPU of an 8-core PC is the wall, not the card,
which idles two thirds of the frame. On a much faster CPU the frame rate goes
up; on a native PC build of the game it would be a different world.

## Requirements

- Windows 10/11 x64, an AVX2 CPU, a Direct3D 12 GPU with shader model 6.6.
- **Your own copy** of the title's Xbox files. This repository contains none.
- The pinned Rust toolchain and the MSVC C++ build tools with a Windows SDK
  (to build).
- For the upscaler and frame generation: **AMD's FidelityFX SDK 2.x**, from
  <https://gpuopen.com/fidelityfx-sdk/> — the `Kits\FidelityFX\signedbin`
  folder of the extracted SDK (it holds `amd_fidelityfx_upscaler_dx12.dll` and
  `amd_fidelityfx_framegeneration_dx12.dll`).

## Build and run

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
$env:VICTORY_FIDELITYFX_SDK = '<SDK>\Kits\FidelityFX\signedbin'
scripts\play-rx7600.ps1 -Exe <your copy>\game_scarlett_master.exe
```

`scripts\play-rx7600.ps1` is the profile every number above was measured with.
It takes the game's executable (`-Exe`) and the FidelityFX folder
(`-FidelityFxDir`, or the environment variable `VICTORY_FIDELITYFX_SDK`).
With that folder the run is **Series S**, the console's 720p upscale is answered
by the host FSR and a generated frame goes between rendered ones; without it the
script warns, falls back to **Series X** (Series S would draw a black world) and
leaves FSR and frame generation off.

## What the profile turns on

| what | how |
|---|---|
| Series S console profile | default when the SDK folder is given (`--console series-s`); `-SeriesX` for the bigger console |
| the PC FidelityFX upscaler | `VICTORY_FIDELITYFX_DIR` (the SDK's `signedbin`) |
| **frame generation** | `VICTORY_FRAMEGEN=1`, on by default when the SDK folder is given |
| the two presentation planes composed | automatic (Series S presents two) |
| buffers kept in the card's memory | `VICTORY_CARD_BUFFERS_MIN_KB=64`, `VICTORY_CARD_BUFFERS_MB=auto` (1 GiB on the 8 GB class, 2 GiB on 16 GB cards, a quarter of the budget up to 8 GiB above) |
| the indirect light stand-in | `VICTORY_AMBIENT=constant:0.4` (a level, shaded in creases) |
| title memory used in place | `VICTORY_INPLACE=2` |
| copy-back beside the frame | `VICTORY_RELAY=2` |
| the 32-bit graphics heap in place | `VICTORY_PORT_CONSTANTS=1`: the card reads and writes the title's 174 MB buffer where it has it, no copy (150-157 to 94-104 ms a frame in the open world) |

The picture fixes ported from RYUKI-7900XT and Scarlett (through
[avatarmanz/VIctory-7900XTX #329](https://github.com/avatarmanz/VIctory-7900XTX/pull/329))
are on by default: NaN and infinity in a colour export become numbers
(`VICTORY_NAN_GUARD`), d16 image loads keep an integer view's bits
(`VICTORY_D16_BITS`), early depth is declared where the container asks for it
(`VICTORY_EARLY_DEPTH`), spills are followed only inside the wave
(`VICTORY_SPILL_STRICT`) — `=0` turns each off — and a root view's window
reaches the memory committed around its 4 MiB cell (`VICTORY_ROOT_WINDOW_MB`,
32; `4` is the cell alone, as before).

## The upscaler (FSR)

The Series S build asks the console for an upscale of its 720p picture to
1080p. This layer answers that request with **AMD's PC FidelityFX** on the host
GPU: the same FSR the SDK ships (4.1.2 is chosen when present), fed the title's
colour, depth, motion vectors, jitter and camera.

- **On**: give the SDK folder — `-FidelityFxDir <signedbin>`, or set
  `VICTORY_FIDELITYFX_SDK`. Without it the title's own console DLLs run, which
  produce nothing here, and the world is black in Series S.
- **Off**: not useful in Series S (the console path cannot upscale on a PC).
  Series X does not use FSR at all.
- It costs GPU time; on this machine the GPU is not the limit, so it is free.

## Frame generation

AMD's frame generation, through its own swap chain in place of the window's,
fed by the title's upscale dispatch (depth, motion vectors, jitter, camera,
frame time): one generated frame between two rendered ones, so the picture is
shown at about **twice** the rendered rate (≈9–10 rendered, ≈19 shown).

- **On**: on by default with the SDK folder; `-FrameGen` forces it,
  `-FrameGen:$false` turns it off.
- **Off** when: you dislike its artefacts. At 9–10 rendered frames a second two
  frames are ~130 ms apart, so moving edges show ghosting; that is inherent to
  interpolating so little information, not a bug.
- It needs the upscaler's folder (the upscale is what feeds it).

## Command reference (`scripts\play-rx7600.ps1`)

| switch | what it does |
|---|---|
| `-Exe <path>` | the game's executable (required) |
| `-Resolution 1280x720` | the display mode the title is told about (default 720p) |
| `-SeriesS` / `-SeriesX` | force the smaller / bigger console (Series S is the default with the SDK folder) |
| `-FidelityFxDir <dir>` | the SDK's `signedbin`: the host upscaler and frame generation |
| `-FrameGen` / `-FrameGen:$false` | frame generation on / off |
| `-Async` | submissions prepared by a thread of ours: the same frame, fewer streaming artefacts |
| `-Ambient <0..1>` | the indirect light stand-in, a constant level (0.4 by default; 0.2/0 darker, 0.8 fuller) |
| `-AmbientSpec <spec>` | `0.4` for a share of the estimate instead (follows the hour and the lamps, but keeps the sky's blue indoors: white paper becomes lavender) |
| `-AmbientMost <n>` | with the estimate, how many times it the title's own sky light may be kept at (4 by default; 1.5 cuts it) |
| `-AmbientFloor <n>` | a floor under the light estimate (useful at night) |
| `-CardBuffers 0` | stop keeping buffers in the card's memory (slower here; useful for testing) |
| `-CardBuffersMB <n>` | cap those copies in MiB (0 = by the card: 1 GiB on 8 GB, 2 GiB on 16 GB) |
| `-TextureBudgetMB <n>` | cap the texture memory: faster, at the cost of the picture's light (0 = whole picture) |
| `-FillsMB <n>` | the byte coffer for textures the title fills (96 by default) |
| `-Inplace 0/1/2`, `-Relay 0/2`, `-Thin 0/1` | the memory and submission strategies (leave as they are unless testing) |
| `-RayTracing` | the title's own ray-traced light: much heavier, only for experiments |
| `-Stats` | per-second statistics in the log (`VICTORY_LOG=info`) |
| `-Timeline "<from s>[,<frames>,]<file>"` | a Chrome trace plus a text summary of a few frames |
| `-ShotFolder <dir> -ShotFrames <n,n>` | save frames as PNG |
| `-Set "K=V;K=V"` | any `VICTORY_...` switch for one run |
| `-Build release` | run `target\release\victory.exe` instead of the diagnostics build |

Any `VICTORY_...` switch can be set directly in the environment; the script
clears them for the run unless passed with `-Set`, `-More` or its own options.

## Tuning it

- **Less video memory pressure**: lower `-CardBuffers`' budget with
  `-Set "VICTORY_CARD_BUFFERS_MB=896"` (512 MB costs about 45 ms a frame;
  256 MB is worse than none).
- **More frames, less light**: `-TextureBudgetMB 640` (partial light) or lower.
- **Darker/blown interiors**: `-Ambient 0.2` or `-Ambient 0`.
- **Stutter while the world streams in**: add `-Async`.
- **Less waiting on the write guards**: add `-Set "VICTORY_PORT_GUARD=1"`
  (the title's write faults and the refreshes' guards take the guards' lock
  shared, a claim per 64 KiB block: the waits for it, all threads, 36-78 to
  2-6 ms a frame here; view memory's kernel askings are left out and a
  submission's refreshes are planned on the threads beside). Three paired
  A/B runs in one world (6 s phases) measured about 1 ms a frame faster
  (0.2-2.3 ms across runs).
- **Artifacts from frame generation**: `-FrameGen:$false`.

## Known issues

- Interiors with little direct light are flat or blown out: the title's
  ray-traced indirect light does not run here; `VICTORY_AMBIENT` is a stand-in.
- Shadows flicker from frame to frame: the temporal shadow resolve does not
  settle here (the same rays feed it); it has been there since the first builds
  and is not the picture fixes.
- On drivers where AMD's compiler ends the process at `amdxc64+0x861b9f` (a
  buffer's size read through the uniform handle), the branch `port/1213-dims`
  carries fxceless #1213's fix; it is not here because it miscompiles hair on
  the RX 7600, where that crash does not happen.
- Frame generation ghosts on fast motion at this frame rate.
- The console's precompiled pipeline cache (device slots 0x1c8 and 0x218) is
  declined on purpose; the title builds the same pipelines from its ordinary
  descriptions, so nothing is missing (upstream VIctory #3163).
- The picture is verified by saved frames; the interface and the cutscenes are
  expected to be whole in Series S, the menus are 30 fps, the world is 9-10.

## More

`docs/` holds the project's own documents (architecture, replay, the asset
policy). The working notes of this fork — every measurement, what worked, what
did not and why - are the maintainers' own and are not part of this repository.
