# Rodar o jogo no PC — o objetivo, e como operar esta árvore

Esta árvore roda o build de Xbox Series de Grand Theft Auto VI no Windows
através da camada de compatibilidade [VIctory](https://github.com/Marvisak/VIctory).
O objetivo do trabalho nela é simples de enunciar:

> **A melhor imagem que este hardware consegue, na melhor taxa de quadros que a
> camada alcança — a experiência do Series S, no PC.**

No console o jogo oferece dois perfis: **Series X** renderiza em alta resolução
e precisa de muita memória; **Series S** renderiza o mundo em **1280×720** e
deixa o upscaler do console (FidelityFX) levar até a resolução da tela, com a
interface numa segunda superfície, de resolução maior. Uma placa de 8 GB no PC
não comporta o perfil Series X, então esta árvore é afinada para o **Series S**:
o perfil de console, o upscale do console respondido pelo **FidelityFX de PC**
da AMD, os **dois planes de apresentação** do título compostos numa imagem só,
e o **frame generation** da AMD por cima.

Medido numa RX 7600 8 GB / Ryzen 7 5700X:

| | |
|---|---|
| menus, vídeos, telas de carregamento | 30 fps |
| o mundo | **9–10 quadros por segundo** (94–104 ms por quadro) |
| quadros exibidos, com frame generation | **~19 por segundo** |
| imagem | inteira: mundo iluminado, interface, cutscenes (conferida por capturas) |

**Isso não é uma experiência de 30 fps nesse hardware, e não promete ser.** O
próprio jogo precisa de ~33 ms por quadro num console; aqui cada draw e cada
dispatch é traduzido, e a memória compartilhada do console precisa ser mantida
coerente por cópia — o gargalo é o **CPU de um PC de 8 núcleos**, não a placa,
que fica ociosa dois terços do quadro. Num CPU muito mais rápido a taxa sobe;
num port nativo do jogo seria outro mundo.

## Requisitos

- Windows 10/11 x64, CPU com AVX2, placa Direct3D 12 com shader model 6.6.
- **Sua própria cópia** dos arquivos Xbox do jogo. Este repositório não contém
  nenhum.
- A toolchain Rust fixada e as ferramentas de build MSVC C++ com Windows SDK
  (para compilar).
- Para o upscaler e o frame generation: **AMD FidelityFX SDK 2.x**, de
  <https://gpuopen.com/fidelityfx-sdk/> — a pasta `Kits\FidelityFX\signedbin`
  do SDK extraído (nela ficam `amd_fidelityfx_upscaler_dx12.dll` e
  `amd_fidelityfx_framegeneration_dx12.dll`).

## Compilar e rodar

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
$env:VICTORY_FIDELITYFX_SDK = '<SDK>\Kits\FidelityFX\signedbin'
scripts\play-rx7600.ps1 -Exe <sua cópia>\game_scarlett_master.exe
```

`scripts\play-rx7600.ps1` é o perfil com que todos os números acima foram
medidos. Ele recebe o executável do jogo (`-Exe`) e a pasta do FidelityFX
(`-FidelityFxDir`, ou a variável de ambiente `VICTORY_FIDELITYFX_SDK`). Com essa
pasta a execução é **Series S**, o upscale do 720p do console é respondido pelo
FSR no host e um quadro gerado entra entre os renderizados; sem ela o script
avisa, cai para **Series X** (o Series S desenharia um mundo preto) e deixa FSR
e frame generation desligados.

## O que o perfil liga

| o quê | como |
|---|---|
| perfil de console Series S | padrão quando a pasta do SDK é informada (`--console series-s`); `-SeriesX` para o console maior |
| o upscaler FidelityFX de PC | `VICTORY_FIDELITYFX_DIR` (o `signedbin` do SDK) |
| **frame generation** | `VICTORY_FRAMEGEN=1`, ligado por padrão quando a pasta do SDK é dada |
| os dois planes de apresentação compostos | automático (o Series S apresenta dois) |
| buffers mantidos na memória da placa | `VICTORY_CARD_BUFFERS_MIN_KB=64`, `VICTORY_CARD_BUFFERS_MB=auto` (1 GiB na classe 8 GB, 2 GiB em placas de 16 GB, um quarto do orçamento até 8 GiB acima) |
| o stand-in de luz indireta | `VICTORY_AMBIENT=constant:0.4` (um nível, sombreado nas dobras) |
| memória do título usada no lugar | `VICTORY_INPLACE=2` |
| copy-back ao lado do quadro | `VICTORY_RELAY=2` |
| o heap gráfico de 32 bits in place | `VICTORY_PORT_CONSTANTS=1`: a placa lê e escreve o buffer de 174 MB onde o título o tem, sem cópia (150-157 → 94-104 ms por quadro no mundo aberto) |

As correções de imagem portadas do RYUKI-7900XT e do Scarlett (via
[avatarmanz/VIctory-7900XTX #329](https://github.com/avatarmanz/VIctory-7900XTX/pull/329))
vêm ligadas: NaN e infinito num export de cor viram números
(`VICTORY_NAN_GUARD`), os loads d16 mantêm os bits de uma view inteira
(`VICTORY_D16_BITS`), early depth é declarado onde o contêiner pede
(`VICTORY_EARLY_DEPTH`), spills só são seguidos dentro da wave
(`VICTORY_SPILL_STRICT`) — `=0` desliga cada um — e a janela de uma root view
alcança a memória commitada ao redor da célula de 4 MiB
(`VICTORY_ROOT_WINDOW_MB`, 32; `4` volta a ser a célula sozinha).

## O upscaler (FSR)

O build de Series S pede ao console um upscale do quadro de 720p para 1080p.
Esta camada responde a esse pedido com o **FidelityFX de PC da AMD** na placa do
host: o mesmo FSR que o SDK traz (4.1.2 é escolhido quando presente), alimentado
com cor, profundidade, vetores de movimento, jitter e câmera do título.

- **Ligado**: informe a pasta do SDK — `-FidelityFxDir <signedbin>`, ou defina
  `VICTORY_FIDELITYFX_SDK`. Sem ela, as DLLs de console do próprio título rodam,
  não produzem nada aqui, e o mundo fica preto no Series S.
- **Desligado**: não é útil no Series S (o caminho de console não faz upscale no
  PC). O Series X nem usa FSR.
- Custa tempo de GPU; nesta máquina a GPU não é o limite, então é de graça.

## Frame generation

O frame generation da AMD, pela swap chain dele no lugar da da janela,
alimentado pelo dispatch de upscale do título (profundidade, vetores, jitter,
câmera, tempo de quadro): um quadro gerado entre dois renderizados, então a
imagem aparece a cerca de **duas vezes** a taxa renderizada (≈9–10 renderizados,
≈19 exibidos).

- **Ligado**: por padrão com a pasta do SDK; `-FrameGen` força,
  `-FrameGen:$false` desliga.
- **Desligue** se incomodar: a 9–10 quadros renderizados, dois quadros ficam a
  ~130 ms de distância, e bordas em movimento mostram ghosting — é inerente a
  interpolar tão pouca informação, não é bug.
- Precisa da pasta do upscaler (o upscale é quem o alimenta).

## Referência de comandos (`scripts\play-rx7600.ps1`)

| switch | o que faz |
|---|---|
| `-Exe <caminho>` | o executável do jogo (obrigatório) |
| `-Resolution 1280x720` | o modo de exibição informado ao título (padrão 720p) |
| `-SeriesS` / `-SeriesX` | força o console menor / maior (Series S é o padrão com a pasta do SDK) |
| `-FidelityFxDir <pasta>` | o `signedbin` do SDK: upscaler de host e frame generation |
| `-FrameGen` / `-FrameGen:$false` | frame generation ligado / desligado |
| `-Async` | submissões preparadas por uma thread nossa: mesmo quadro, menos artefatos de streaming |
| `-Ambient <0..1>` | o stand-in de luz indireta, um nível constante (0.4 padrão; 0.2/0 mais escuro, 0.8 mais cheio) |
| `-AmbientSpec <spec>` | `0.4` para usar uma fração da estimativa (segue a hora e as lâmpadas, mas mantém o azul do céu no interior: papel branco sai lavanda) |
| `-AmbientMost <n>` | com a estimativa, quantas vezes ela a luz de céu que o título deixou pode ficar (4 padrão; 1.5 corta) |
| `-AmbientFloor <n>` | piso para a estimativa de luz (útil à noite) |
| `-CardBuffers 0` | deixa de manter buffers na memória da placa (mais lento aqui; para teste) |
| `-TitleDir <pasta>` | a pasta do jogo quando o executável está fora dela (`VICTORY_TITLE_DIR`; a pasta é só lida) |
| `-WindowsBarMB auto/0/<n>` | janelas de memória do título na VRAM via Resizable BAR em vez da RAM (`auto`, o padrão: nada em placas de 8–12 GB, 4096 em 16 GB; na RX 9070 XT: −3 GB de RAM, mesmo fps). Precisa do Resizable BAR/SAM ligado na BIOS |
| `-CardBuffersMB <n>` | limita essas cópias em MiB (0 = pela placa: 1 GiB em 8 GB, 2 GiB em 16 GB) |
| `-TextureBudgetMB <n>` | limita a memória de textura: mais rápido, ao custo da luz da imagem (0 = imagem inteira) |
| `-FillsMB <n>` | o cofre de bytes para texturas que o título preenche (96 padrão) |
| `-Inplace 0/1/2`, `-Relay 0/2`, `-Thin 0/1` | as estratégias de memória e submissão (deixe como está, salvo em teste) |
| `-RayTracing` | a luz por ray tracing do próprio título: bem mais pesada, só para experimento |
| `-Stats` | estatísticas por segundo no log (`VICTORY_LOG=info`) |
| `-Timeline "<de s>[,<quadros>,]<arquivo>"` | um trace do Chrome e um resumo em texto de poucos quadros |
| `-ShotFolder <pasta> -ShotFrames <n,n>` | salva quadros em PNG |
| `-Set "K=V;K=V"` | qualquer switch `VICTORY_...` para uma execução |
| `-Build release` | usa `target\release\victory.exe` em vez do build de diagnóstico |

Qualquer switch `VICTORY_...` pode ser definido direto no ambiente; o script
limpa as variáveis para a execução, a menos que venham por `-Set`, `-More` ou
pelas opções dele.

## Ajustando

- **Menos pressão de memória de vídeo**: baixe o orçamento com
  `-Set "VICTORY_CARD_BUFFERS_MB=896"` (512 MB custa ~45 ms por quadro;
  256 MB é pior que não usar).
- **Mais quadros, menos luz**: `-TextureBudgetMB 640` (luz parcial) ou menos.
- **Interior estourado/escuro**: `-Ambient 0.2` ou `-Ambient 0`.
- **Engasgo enquanto o mundo carrega**: acrescente `-Async`.
- **Menos espera nos write guards**: vem ligado
  (`VICTORY_PORT_GUARD=1`); `-Set VICTORY_PORT_GUARD=0` desliga. O lock dos
  guards é compartilhado entre write faults e guards dos refreshes, com um
  claim por bloco de 64 KiB: as esperas por ele, em todas as threads, de
  36-78 para 2-6 ms por quadro aqui; as perguntas ao kernel para memória de
  view, que ele recusa, ficam de fora, e os refreshes de uma submissão são
  planejados nas threads ao lado; três A/B pareados no mesmo mundo: ~1 ms por
  quadro mais rápido (0,2-2,3 ms entre runs).
- **Artefatos do frame generation**: `-FrameGen:$false`.

## Problemas conhecidos

- Interiores com pouca luz direta ficam chapados ou estourados: a luz indireta
  por ray tracing do título não roda aqui; `VICTORY_AMBIENT` é um stand-in.
- As sombras piscam de quadro a quadro: o resolve temporal de sombra não
  assenta (são os mesmos raios que o alimentam); existe desde os primeiros
  builds e não vem das correções de imagem.
- Em drivers onde o compilador da AMD encerra o processo em `amdxc64+0x861b9f`
  (tamanho de buffer lido pelo handle uniforme), o branch `port/1213-dims`
  traz o fix do fxceless #1213; ele não está aqui porque compila errado o
  cabelo na RX 7600, onde esse crash não acontece.
- O frame generation deixa rastro em movimento rápido nesta taxa de quadros.
- O cache de pipelines pré-compilados do console (slots de device 0x1c8 e
  0x218) é recusado de propósito; o título monta os mesmos pipelines pelas
  descrições normais, então não falta nada (upstream VIctory #3163).
- A imagem é conferida por quadros salvos; a interface e as cutscenes devem
  estar inteiras no Series S, os menus a 30 fps, o mundo a 9-10.

## Mais

`docs/` guarda os documentos do projeto (arquitetura, replay, política de
ativos). As notas de trabalho deste fork — cada medição, o que funcionou, o que
não funcionou e por quê - são dos mantenedores e não fazem parte deste repositório.
