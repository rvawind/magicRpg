$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\admin\Documents\WE\magic-core\.team\notes\2026-11-08_launch_capture.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
Set-Content -Path $log -Value '' -Encoding UTF8
function Log($msg) {
    $ts = Get-Date -Format 'HH:mm:ss.fff'
    Add-Content -Path $log -Value "[$ts] $msg" -Encoding UTF8
}
Log '=== monitor start ==='
$DURATION = 300
$deadline = (Get-Date).AddSeconds($DURATION)
$seen = @{}
$captures = @{}   # pid -> list of "due time|label"
$start = Get-Date
$targets = 'war3|Warcraft|WorldEdit|ydhost|KKWE|Platform|YDDll|YDDllFixer|worldedit'
$reportDirs = @(
    'D:\Game\Warcraft3\Warcraft3',
    'D:\Game\Warcraft3\Warcraft3\save',
    'D:\Game\Warcraft3\Warcraft3\Logs',
    'H:\Game\Warcraft3',
    'H:\Game\Warcraft3\save',
    'H:\Game\Warcraft3\Logs',
    "$env:USERPROFILE\Documents\Warcraft III",
    'C:\Users\admin\Documents\WE\magic-core\testmaps'
)
$lastReport = Get-Date
$lastHeartbeat = Get-Date

while ((Get-Date) -lt $deadline) {
    # 1) new target processes
    $procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -and ($_.Name -match $targets) }
    foreach ($p in $procs) {
        if (-not $seen.ContainsKey([int]$p.ProcessId)) {
            $seen[[int]$p.ProcessId] = Get-Date
            Log "=== NEW PROCESS pid=$($p.ProcessId) name=$($p.Name) parent=$($p.ParentProcessId) ==="
            Log "  exe = $($p.ExecutablePath)"
            Log "  cmd = $($p.CommandLine)"
            $par = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)"
            if ($par) { Log "  parent = $($par.Name) | cmd = $($par.CommandLine)" }
            $captures[[int]$p.ProcessId] = @(
                @{ due = (Get-Date).AddSeconds(0.5); label = 'modules@0.5s' },
                @{ due = (Get-Date).AddSeconds(3);   label = 'modules@3s' },
                @{ due = (Get-Date).AddSeconds(10);  label = 'modules@10s' },
                @{ due = (Get-Date).AddSeconds(25);  label = 'modules@25s' }
            )
        }
    }
    # 2) delayed module snapshots
    foreach ($pidKey in @($captures.Keys)) {
        $items = $captures[$pidKey]
        for ($i = $items.Count - 1; $i -ge 0; $i--) {
            $it = $items[$i]
            if ((Get-Date) -ge $it.due) {
                $proc = Get-Process -Id $pidKey -ErrorAction SilentlyContinue
                if (-not $proc) { Log "=== pid=$pidKey exited before $($it.label) ==="; $captures.Remove($pidKey); break }
                if ($proc.HasExited) { Log "=== pid=$pidKey exited (HasExited) before $($it.label) ==="; $captures.Remove($pidKey); break }
                $mods = @()
                try { $mods = $proc.Modules | ForEach-Object { $_.ModuleName } } catch { $mods = @('<module-enum-failed>') }
                $interesting = $mods | Where-Object { $_ -match 'yd|kkapi|jass|plugin|hook|NEP|Game|war3|Storm|mopaq|Mopaq|version|blizzard|loader|attach|inject' }
                Log "--- $($it.label) pid=$pidKey modules(total=$($mods.Count)): $($interesting -join ', ')"
                $items.RemoveAt($i)
            }
        }
        if ($items.Count -eq 0) { $captures.Remove($pidKey) }
    }
    # 3) windows snapshot every 5s
    if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 5) {
        $lastHeartbeat = Get-Date
        $titles = Get-Process | Where-Object { $_.MainWindowTitle -ne '' } | ForEach-Object { "$($_.ProcessName)[$($_.Id)]=$($_.MainWindowTitle)" }
        Log "windows: $($titles -join ' ; ')"
    }
    # 4) report file / new file scan every 2s
    if (((Get-Date) - $lastReport).TotalSeconds -ge 2) {
        $lastReport = Get-Date
        foreach ($d in $reportDirs) {
            if (Test-Path $d) {
                $hits = Get-ChildItem $d -Recurse -Depth 2 -Filter '*war3regression*' -File -ErrorAction SilentlyContinue
                foreach ($h in $hits) { if ($h.LastWriteTime -gt $start) { Log "=== REPORT FILE: $($h.FullName) size=$($h.Length) mtime=$($h.LastWriteTime) ===" } }
                $newFiles = Get-ChildItem $d -Depth 1 -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $start }
                foreach ($nf in $newFiles) { Log "new file: $($nf.FullName) size=$($nf.Length)" }
            }
        }
    }
    Start-Sleep -Milliseconds 300
}
Log '=== monitor end ==='
Log "seen pids: $(($seen.Keys | Sort-Object) -join ', ')"
