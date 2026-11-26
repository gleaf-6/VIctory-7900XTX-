# Runs the title for a while under scripts\play-rx7600.ps1 and samples what
# it costs the machine, once a second, from outside the process (no effect on
# the run): the PC's memory (private commit and working set of victory.exe),
# the card's memory it holds (dedicated and shared, from the GPU performance
# counters) and the CPU it takes. Writes a CSV and a one-line summary.
#   scripts\bench.ps1 -Name base -Seconds 180 -Exe D:\game.exe -TitleDir D:\dump `
#       -Play @{ FidelityFxDir = 'D:\FidelityFX\signedbin' } -Set 'VICTORY_WINDOWS_BAR_MB=3072'
# The log of the run (stdout and stderr) goes beside the CSV.
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Exe,
    [string]$TitleDir = '',
    [int]$Seconds = 180,
    # Seconds at the start left out of the summary (loading, first shaders).
    [int]$Skip = 60,
    [string]$Set = '',
    # Scripted presses (VICTORY_KEYS) that take a fresh profile from the start
    # screen into the story's first scene, the same scene every run; '' for none.
    [string]$Keys = '20:Enter,26:Enter,32:Enter,38:Enter,44:Enter,50:Enter',
    # A frame saved as PNG to look at the picture (0: none).
    [int]$ShotFrame = 3000,
    [hashtable]$Play = @{},
    [string]$Out = (Join-Path $PSScriptRoot '..\target\bench')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$log = Join-Path $Out "$Name.log"
$csv = Join-Path $Out "$Name.csv"

# The run, in a PowerShell of its own so that its environment stays its own.
$q = { param($s) "'" + ("$s" -replace "'", "''") + "'" }
$command = "& $(& $q (Join-Path $PSScriptRoot 'play-rx7600.ps1')) -Exe $(& $q $Exe)"
if ($TitleDir) { $command += " -TitleDir $(& $q $TitleDir)" }
$sets = @($Set) + $(if ($Keys) { "VICTORY_KEYS=$Keys" }) | Where-Object { $_ }
if ($sets) { $command += " -Set $(& $q ($sets -join ';'))" }
if ($ShotFrame -gt 0) {
    $shots = Join-Path $Out "$Name-shots"
    $command += " -ShotFolder $(& $q $shots) -ShotFrames $ShotFrame"
}
foreach ($k in $Play.Keys) {
    $v = $Play[$k]
    if ($v -is [bool]) { $command += " -${k}:`$$v" } else { $command += " -$k $(& $q $v)" }
}
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$runner = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded -PassThru -WindowStyle Minimized `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err"

$started = Get-Date
# The run's own victory.exe: started after this script, running the title.
$find = {
    Get-CimInstance Win32_Process -Filter "Name='victory.exe'" |
        Where-Object { $_.CommandLine -match ' run .*--execute' -and $_.CreationDate -ge $started.AddSeconds(-2) } |
        Sort-Object CreationDate -Descending | Select-Object -First 1
}
$proc = $null
for ($i = 0; $i -lt 60 -and -not $proc; $i++) { Start-Sleep -Seconds 1; $proc = & $find }
if (-not $proc) { Write-Host 'victory.exe did not start; see the log.'; Get-Content "$log.err" -Tail 20; return }
$id = $proc.ProcessId
$p = Get-Process -Id $id
$rows = New-Object System.Collections.Generic.List[object]
$lastCpu = $p.TotalProcessorTime.TotalSeconds
$t0 = Get-Date
$lastAt = $t0
$exited = $false
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    Start-Sleep -Seconds 1
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p) { $exited = $true; break }
    $gpu = $null
    try {
        $gpu = (Get-Counter "\GPU Process Memory(pid_${id}_*)\Dedicated Usage", "\GPU Process Memory(pid_${id}_*)\Shared Usage" -ErrorAction Stop).CounterSamples
    } catch {}
    $ded = ($gpu | Where-Object Path -match 'dedicated' | Measure-Object CookedValue -Sum).Sum
    $sha = ($gpu | Where-Object Path -match 'shared' | Measure-Object CookedValue -Sum).Sum
    $cpu = $p.TotalProcessorTime.TotalSeconds
    $now = Get-Date
    $rows.Add([pscustomobject]@{
        s          = [int]($now - $t0).TotalSeconds
        private_mb = [int]($p.PrivateMemorySize64 / 1MB)
        ws_mb      = [int]($p.WorkingSet64 / 1MB)
        vram_mb    = [int]($ded / 1MB)
        shared_mb  = [int]($sha / 1MB)
        # CPU seconds per second since the last sample: cores busy.
        cpu_cores  = [math]::Round(($cpu - $lastCpu) / [math]::Max(0.5, ($now - $lastAt).TotalSeconds), 2)
    })
    $lastCpu = $cpu
    $lastAt = $now
}
# Every victory.exe this run started goes, and the PowerShell around it.
Get-CimInstance Win32_Process -Filter "Name='victory.exe'" | Where-Object { $_.CreationDate -ge $started.AddSeconds(-2) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Stop-Process -Id $runner.Id -Force -ErrorAction SilentlyContinue
if ($rows.Count -eq 0) { Write-Host "${Name}: no sample (the title ended at once); see $log.err"; return }
$rows | Export-Csv -NoTypeInformation -Path $csv
$steady = @($rows | Where-Object { $_.s -ge $Skip })
if ($steady.Count -eq 0) { $steady = @($rows) }
$avg = { param($f) [int](($steady | Measure-Object $f -Average).Average) }
$max = { param($f) [int](($steady | Measure-Object $f -Maximum).Maximum) }
# With -Play @{Stats=$true} the log has a line a second with the frames
# rendered (and shown, with frame generation) and the diagnostics build's
# memory line: both are summed up over the same seconds.
$err = "$log.err"
if (Test-Path $err) {
    $lines = Get-Content $err
    $stamp = { param($line) if ($line -match '^(\S+?)Z') { [datetime]::Parse($Matches[1]) } }
    $first = $null
    foreach ($line in $lines) { if ($line -match 'frames rendered and frames shown') { $first = & $stamp $line; break } }
    $fps = foreach ($line in $lines) {
        if ($line -match 'frames rendered and frames shown.*real=([\d.]+)(?: presented=([\d.]+))?') {
            $real = [double]$Matches[1]; $shown = if ($Matches[2]) { [double]$Matches[2] } else { $real }
            $at = & $stamp $line
            if ($first -and ($at - $first).TotalSeconds -ge ($Skip - 15)) { [pscustomobject]@{ real = $real; shown = $shown } }
        }
    }
    if ($fps) {
        $r = @($fps.real | Sort-Object)
        Write-Host ("{0}: frames a second (from the log, {1} s): rendered avg {2:N1}, median {3:N1}, worst tenth {4:N1}; shown avg {5:N1}" -f `
            $Name, $r.Count, ($r | Measure-Object -Average).Average, $r[[int]($r.Count / 2)], $r[[int]($r.Count / 10)],
            ($fps.shown | Measure-Object -Average).Average)
    }
    $mem = $lines | Where-Object { $_ -match 'copystat: memory: (\d+) MB private' } | Select-Object -Last 1
    if ($mem) { Write-Host ("{0}: last memory line: {1}" -f $Name, (($mem -replace '^.*copystat: memory: ', '') -split ';')[0]) }
    $card = $lines | Where-Object { $_ -match 'the card: \d+ MB in use' } | Select-Object -Last 1
    if ($card -match 'the card: (.*)$') { Write-Host ("{0}: {1}" -f $Name, $Matches[1]) }
}
Write-Host ("{0}: {1} s, exited early: {2} | RAM private avg {3} MB, max {4} | working set avg {5} MB | VRAM avg {6} MB, max {7} | shared avg {8} MB | CPU {9:N1} cores" -f `
    $Name, $rows.Count, $exited, (& $avg 'private_mb'), (& $max 'private_mb'), (& $avg 'ws_mb'),
    (& $avg 'vram_mb'), (& $max 'vram_mb'), (& $avg 'shared_mb'), (($steady | Measure-Object cpu_cores -Average).Average))
