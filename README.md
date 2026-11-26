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
- on cards of 16 GB and more, the windows of title memory kept in the card's
  memory through Resizable BAR instead of the PC's (`-WindowsBarMB auto`):
  3 GB less of the PC's memory at the same frame rate;
- buffers kept in the card's own memory: 219.6 to 131.1 ms a frame in the
  world, 6-8 real frames a second and about 15 shown with frame generation;
  the cap follows the card (1 GiB on the 8 GB class, 2 GiB on 16 GB cards,
  a quarter of the budget up to 8 GiB above);
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

### On a 16 GB card: Radeon RX 9070 XT, Ryzen 7 9800X3D, 32 GB RAM

The story's first scene (reached by scripted presses, the same scene every
run), Series S profile with FSR and frame generation, 720p display mode,
`scripts\bench.ps1` (two paired runs each, 200 s, averaged over the last
110 s):

| | before | windows in the card (`-WindowsBarMB auto`, now the default) |
|---|---|---|
| frames rendered a second | 21.9 (worst tenth 17.2) | **22.6** (worst tenth 18.0) |
| frames shown (frame generation) | 42.2 | 42.4 |
| PC memory in use (working set) | 19.7 GB | **16.6 GB** (-3.1 GB) |
| private commit | 23.4 GB | **21.2 GB** (-2.1 GB) |
| PC memory shared with the card | 7.5 GB | **4.4 GB** (-3.1 GB, -41%) |
| card memory in use | 9.7 GB | 10.9 GB |

What the numbers showed about this machine:

- **The PC's memory was the limit, not the card.** Before the change the
  process held 22-24 GB of commit on a 32 GB PC and the system had **843 MB
  left to commit** at one point; the card had 5-6 GB of its budget free. Of
  that memory, about 9 GB is the title's own (its GPU memory, write-combined,
  as on the console) and 3-3.5 GB are *windows*: host copies of title memory
  outside any buffer object (vertices, indices and constants from the title's
  own allocator), which the card read over the bus.
- **The windows now live in the card's memory, written by the CPU through
  Resizable BAR** (`D3D12_HEAP_TYPE_GPU_UPLOAD`, `VICTORY_WINDOWS_BAR_MB`).
  The path was in the tree but off: an 8 GB card has no room for it. On a
  16 GB card it moves ~3 GB from the PC's memory to the card with no copy
  left behind, and the frame rate is the same or slightly better (the reads
  are local now). `auto` sizes it from the card's budget: none up to 12 GiB,
  4 GiB on 16 GB cards, 6 GiB above.
- Measured and **not** kept: a 1 MiB window grid (`VICTORY_WINDOW_KB=1024`,
  no memory saved beyond the BAR windows) and 4 GiB of card copies of title
  buffers (`VICTORY_CARD_BUFFERS_MB=4096`: 22.7 frames a second, worst tenth
  17.1, against 22.6 with the default 2 GiB: the copies took the textures'
  room).
- The CPU is still what limits the frame (the card is idle most of it). This
  machine's Windows sees **8 logical processors**: SMT is off in the
  firmware. The layer runs its own translating and landing threads beside the
  title's, so turning SMT back on is worth trying.

### On an 8 GB card: Radeon RX 7600

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

That `scripts\play-rx7600.ps1` line is the measured profile and needs the
FidelityFX folder: with it, the script runs **Series S**, answers the console's
720p upscale with the host **FidelityFX (FSR)** and puts a **generated frame**
between the rendered ones, on top of the tuning it already sets (buffers kept
in the card's memory, `VICTORY_RELAY=2`, in-place copies off,
`VICTORY_AMBIENT=constant:0.4`).

**Without that folder there is no profile to speak of**: Series S draws a black
world, so the script falls back to Series X and says so in the window; FSR and
frame generation stay off. Pass the folder directly with
`-FidelityFxDir <signedbin>` if you prefer not to set the variable.
`-FrameGen:$false` keeps FSR without the generated frame; `-SeriesX` forces the
bigger console.

The executable may live outside the dump (renamed or not): `-TitleDir`
(`VICTORY_TITLE_DIR`) names the package folder, which is then only read, never
added to:

```powershell
scripts\play-rx7600.ps1 -Exe D:\game.exe -TitleDir D:\dump -FidelityFxDir D:\FidelityFX\signedbin
```

The FidelityFX folder is the SDK's `Kits\FidelityFX\signedbin` (the DX12
loader, upscaler and frame generation DLLs, signed by AMD), from
<https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK>.

On a 16 GB card turn **Resizable BAR / Smart Access Memory** on in the
firmware: the windows go to the card only through it (the log says
`card memory the CPU maps supported=true`). `-WindowsBarMB 0` turns it off,
`-WindowsBarMB 4096` forces a size. With 32 GB of RAM, a fixed page file of
16-32 GB keeps the commit limit away from the process.

To measure a change, `scripts\bench.ps1` runs the profile for a while, takes
the same scripted path into the story's first scene, samples the process'
memory, the card's memory and the CPU from outside, reads the frames a second
from the log, and saves a frame to look at the picture:

```powershell
scripts\bench.ps1 -Name base -Exe D:\game.exe -TitleDir D:\dump -Play @{ FidelityFxDir = 'D:\FidelityFX\signedbin'; Stats = $true; WindowsBarMB = '0' }
scripts\bench.ps1 -Name bar -Exe D:\game.exe -TitleDir D:\dump -Play @{ FidelityFxDir = 'D:\FidelityFX\signedbin'; Stats = $true }
```

Results go to `target\bench` (CSV, log, a PNG). Runs of the same settings
differ by a frame or two a second: compare pairs, run in turn.

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

## Em português (resumo)

Numa RX 9070 XT (16 GB) com Ryzen 7 9800X3D e 32 GB de RAM, o gargalo era a
**RAM do PC**: o processo chegava a 22-24 GB de commit e o Windows ficou com
menos de 1 GB de commit livre, enquanto a placa tinha 5-6 GB de VRAM sobrando.
Agora as *janelas* de memória do título (~3 GB de vértices, índices e
constantes) ficam **na VRAM, escritas pela CPU via Resizable BAR**
(`-WindowsBarMB auto`, o padrão): **-3,1 GB de RAM em uso** (19,7 → 16,6 GB),
**-41% de memória compartilhada** com a placa (7,5 → 4,4 GB), e o mesmo fps
(21,9 → 22,6 renderizados; ~42 exibidos com frame generation). Ligue o
**Resizable BAR / Smart Access Memory** na BIOS. O executável pode ficar fora
da pasta do jogo com `-TitleDir` (a pasta do jogo é só lida).
`scripts\bench.ps1` mede uma configuração do mesmo jeito sempre. Testado e
descartado: grade de janelas de 1 MiB (não economiza mais) e 4 GiB de buffers
na placa (mais lento). O limite continua sendo a CPU; este PC está com SMT
desligado (8 threads lógicas), vale testar ligado. Guia completo:
[docs/guia.pt-BR.md](docs/guia.pt-BR.md).

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
