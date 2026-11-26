# VIctory-7900XTX

Runs an Xbox Series title natively on Windows from files the user supplies:
the compatibility layer [VIctory](https://github.com/Marvisak/VIctory) with
this fork's work on top.

Besides VIctory itself, this tree carries the performance work of
[codec-d/cool_fox](https://github.com/codec-d/cool_fox) (deferred descriptor
records, bindless refreshes, textures sent ahead, residency) and follows the
two-plane Series S composition of
[Linox-IDK/LNX-victory](https://github.com/Linox-IDK/LNX-victory). To take
upstream's changes:

```powershell
git remote add upstream https://github.com/Marvisak/VIctory.git
git fetch upstream
```

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## What this tree adds

- the console upscaler answered by the PC FidelityFX SDK
  (`VICTORY_FIDELITYFX_DIR`, or `VICTORY_FIDELITYFX_SDK`), with thin lists and
  the upscaler working together (a deferred host call);
- the Series S interface: the title's two present planes composed into one
  1080p picture;
- AMD frame generation through its swap chain, fed by the title's own upscale
  (depth, motion vectors, jitter, camera, frame time);
- buffers kept in the card's own memory: 219.6 to 131.1 ms a frame in the
  world, 6-8 real frames a second and about 15 shown with frame generation;
- page mappings as runs of pages, and the `codec-d/cool_fox` fork's six commits
  (deferred descriptor records, bindless refreshes scoped to their heap,
  textures sent ahead, residency and pool back-off);
- `scripts\play-rx7600.ps1`: the profile these numbers were measured with
  (Series S, the host FidelityFX upscaler and frame generation turned on by
  default when the SDK folder is given).

What was gained, and what was measured and rejected, is not part of this
repository: the working notes were kept by the maintainers while the fork was
tuned.

## Documentation

- **[English guide](docs/guide.en.md)** - the goal (a Series S experience on a
  PC), what the profile turns on, how to operate it from the command line, and
  how the host FidelityFX upscaler and frame generation work.
- **[Guia em portugues](docs/guia.pt-BR.md)** - o mesmo, em portugues.

The working notes this fork was tuned with (every measurement, what was tried
and not kept) are the maintainers' own and are not part of this repository.

Build from this checkout with the pinned Rust toolchain and the MSVC C++ build
tools with a Windows SDK:

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
scripts\play-rx7600.ps1 -Exe <path of your copy's executable>
```

## Where it stands

Measured on one machine: Windows 11, Ryzen 7 5700X (8 cores / 16 threads),
32 GB RAM, Radeon RX 7600 8 GB, 1080p display, the Series S profile.

| | |
|---|---|
| Menus, videos, loading screens | 30 fps |
| The world (on foot, the camp) | **6-8 fps** (120-185 ms a frame) |
| With frame generation | **~15 fps shown** |
| The interface, cutscenes | whole (checked by saved frames) |
| Video memory | 6.5-7.5 of 8 GB |
| Picture | lit and whole; interiors with little direct light are flat (no ray-traced indirect light) |

The upstream `codec-d/cool_fox` fork, on a Series X profile with an i9-12900K
and an RX 7900 XTX at 1440p, reports 50-165 ms a frame in the same parts of the
game (13-20 fps indoors, 6-10 in a street chase); its notes are the source of
much of the performance work this tree carries.

What is known to be wrong here:

- Interiors with little direct light are flat or blown out: the title's
  ray-traced indirect light does not run, and `VICTORY_AMBIENT` stands in.
- Frame generation ghosts on fast motion at 6-8 rendered frames a second.
- A few console pipeline variants are not created; the title goes without them.
- The first run after a driver or build change stutters while pipelines are
  made (`victory warm --used` makes them ahead).

## How to run it

You need Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader
model 6.6 and mesh shaders, Rust (the toolchain is pinned), the MSVC build
tools, and your own dump of the title.

```powershell
git clone <this repository>
cd VIctory-7900XTX
copy victory.example.toml victory.toml      # then set your paths, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
$env:VICTORY_FIDELITYFX_SDK = '<SDK>\Kits\FidelityFX\signedbin'
scripts\play-rx7600.ps1 -Exe <path of your copy's executable>
```

The last line is the measured profile and needs the FidelityFX folder: with it,
the script runs **Series S**, answers the console's 720p upscale with the host
**FidelityFX (FSR)** and puts a **generated frame** between the rendered ones,
on top of the tuning it already sets (buffers kept in the card's memory,
`VICTORY_RELAY=2`, in-place copies off, `VICTORY_AMBIENT=constant:0.4`).

**Without that folder there is no profile to speak of**: Series S draws a black
world, so the script falls back to Series X and says so in the window; FSR and
frame generation stay off. Pass the folder directly with
`-FidelityFxDir <signedbin>` if you prefer not to set the variable.
`-FrameGen:$false` keeps FSR without the generated frame; `-SeriesX` forces the
bigger console.

`-RayTracing` turns the title's ray-traced indirect light on (it is much
heavier here); `docs/guide.en.md` explains every switch, the upscaler and
frame generation.

Before the first run, ahead of time (both can be stopped and go on later):

```powershell
target\diag\victory.exe shaders <the shader archives>   # every shader translated, minutes
target\diag\victory.exe warm --used                     # pipelines earlier runs drew with, for a new driver or build
```

Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch is
described in a comment where it is read.

## What is different here

In short; the reasons and the measurements are the maintainers' own notes and
are not part of this repository.

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only after
  its upload ran, which also ended a device loss that came every 15 minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go back
  to title memory (from fxceless and Geckomacabre, on by default here).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).

## Credits

This is a tree of other people's work with more on top. The history is kept, and
commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the fork
  this one started from, and the people whose pull requests it carries.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[codec-d/cool_fox](https://github.com/codec-d/cool_fox)**: the performance
  work merged here (deferred descriptor records, bindless refreshes scoped to
  their heap, textures ahead, residency, pool back-off).
- **[Linox-IDK/LNX-victory](https://github.com/Linox-IDK/LNX-victory)**: the
  two-plane Series S composition, the model this tree's composition follows.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the same
  title behaves under another layer; no code of it is here.

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md).
