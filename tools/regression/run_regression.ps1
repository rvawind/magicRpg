# Regression runner for the magicRpg WC3 map.
#
# Flow:
#   1) Point YDWE launcher at -GameDir by temporarily switching HKCU Warcraft III InstallPath.
#   2) Launch:  YDWEConfig.exe -launchwar3 -loadfile <map>
#   3) During map loading, keep foreground on another window (Edge/Explorer/desktop) so the
#      "focus lost after load -> pause" issue does not hit.
#   4) When bootlog appears (load finished), bring WAR3 to the foreground again (unpause + the
#      screenshots need the game visible), then capture periodic PNG screenshots.
#   5) Poll <GameDir>\Save\war3regression.txt, parse Preload(...) lines into checks/summary.
#   6) On timeout, collect an anomaly bundle (process/window/file timestamps/last screenshot).
#   7) Kill war3, restore registry, write JSON. Exit 0 PASS / 1 FAIL / 3 TIMEOUT / 2 setup error.
param(
    [Parameter(Mandatory = $true)][string]$Map,
    [string]$GameDir = 'H:\Game\Warcraft3',
    [int]$TimeoutSec = 180,
    [switch]$KeepGame,
    [string]$JsonOut = ''
)

$ErrorActionPreference = 'SilentlyContinue'

$KKWE = 'C:\Users\admin\Documents\WE\KKWE_nncouVer1.5.7.1'
$YDWECONFIG = Join-Path $KKWE 'bin\YDWEConfig.exe'
$REG_KEY = 'HKCU:\Software\Blizzard Entertainment\Warcraft III'
$PROJ = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Guard: launching YDWEConfig rewrites KKWE\bin\EverConfig.cfg (editor settings).
# Back it up before every run and restore it afterwards if it changed.
$EVERCONFIG = Join-Path $KKWE 'bin\EverConfig.cfg'
$EVERCONFIG_GUARD = Join-Path $PROJ '.team\reports\EverConfig_guard.cfg'
$everCfgHashBefore = ''

if (-not (Test-Path -LiteralPath $Map)) { Write-Host "[run] map not found: $Map"; exit 2 }
if (-not (Test-Path -LiteralPath $YDWECONFIG)) { Write-Host "[run] YDWEConfig not found: $YDWECONFIG"; exit 2 }
if (-not (Test-Path -LiteralPath $GameDir)) { Write-Host "[run] game dir not found: $GameDir"; exit 2 }

$report = Join-Path $GameDir 'Save\war3regression.txt'
$bootFile = Join-Path $GameDir 'Save\war3regression_bootlog.txt'
$hbFile = Join-Path $GameDir 'Save\war3regression_hb.txt'
$logFile = Join-Path $GameDir 'Save\war3regression_log.txt'
$screensDir = Join-Path $PROJ '.team\screens'
New-Item -ItemType Directory -Force -Path $screensDir | Out-Null

$oldInstall = (Get-ItemProperty -Path $REG_KEY -Name InstallPath).InstallPath
$start = Get-Date
$result = [ordered]@{
    map        = (Resolve-Path -LiteralPath $Map).Path
    gameDir    = $GameDir
    runAt      = $start.ToString('yyyy-MM-dd HH:mm:ss')
    elapsedSec = 0
    report     = $report
    result     = 'TIMEOUT'
    summary    = ''
    checks     = @()
    fails      = @()
    lines      = @()
    screens    = @()
}

# ---------- screenshot / window helpers ----------
$script:shotReady = $false
try {
    Add-Type -AssemblyName System.Drawing
    $cs = @(
        'using System;',
        'using System.Text;',
        'using System.Runtime.InteropServices;',
        'public class W3WinApi {',
        '  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }',
        '  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);',
        '  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);',
        '  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();',
        '  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);',
        '  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);',
        '  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);',
        '  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);',
        '  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);',
        '  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);',
        '  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);',
        '  public static string ForegroundTitle() {',
        '    var sb = new StringBuilder(512);',
        '    GetWindowText(GetForegroundWindow(), sb, sb.Capacity);',
        '    return sb.ToString();',
        '  }',
        '  public static bool TitleContains(IntPtr h, string part) {',
        '    var sb = new StringBuilder(512);',
        '    GetWindowText(h, sb, sb.Capacity);',
        '    return sb.ToString().IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0;',
        '  }',
        '  public static IntPtr FindWindowByTitle(string part) {',
        '    IntPtr best = IntPtr.Zero; int bestArea = 0;',
        '    EnumWindows(delegate(IntPtr h, IntPtr l) {',
        '      if (IsWindowVisible(h) && TitleContains(h, part)) {',
        '        RECT r; if (GetWindowRect(h, out r)) {',
        '          int area = (r.Right - r.Left) * (r.Bottom - r.Top);',
        '          if (area > bestArea) { bestArea = area; best = h; }',
        '        }',
        '      }',
        '      return true;',
        '    }, IntPtr.Zero);',
        '    return best;',
        '  }',
        '  public static bool FocusWindowByTitle(string part) {',
        '    IntPtr h = FindWindowByTitle(part);',
        '    if (h == IntPtr.Zero) return false;',
        '    ShowWindow(h, 9);',
        '    SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);',
        '    SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002);',
        '    return SetForegroundWindow(h);',
        '  }',
        '  public static bool FocusProcessWindow(int targetPid) {',
        '    IntPtr best = IntPtr.Zero; int bestArea = 0;',
        '    EnumWindows(delegate(IntPtr h, IntPtr l) {',
        '      uint pid; GetWindowThreadProcessId(h, out pid);',
        '      if (pid == (uint)targetPid && IsWindowVisible(h)) {',
        '        RECT r; if (GetWindowRect(h, out r)) {',
        '          int area = (r.Right - r.Left) * (r.Bottom - r.Top);',
        '          if (area > bestArea) { bestArea = area; best = h; }',
        '        }',
        '      }',
        '      return true;',
        '    }, IntPtr.Zero);',
        '    if (best == IntPtr.Zero) return false;',
        '    ShowWindow(best, 9);',
        '    SetWindowPos(best, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);',
        '    SetWindowPos(best, new IntPtr(-2), 0, 0, 0, 0, 0x0001 | 0x0002);',
        '    return SetForegroundWindow(best);',
        '  }',
        '}'
    ) -join "`n"
    Add-Type -TypeDefinition $cs
    $script:shotReady = $true
} catch {
    Write-Host ("[run] screenshot api unavailable: {0}" -f $_.Exception.Message)
}

function Get-War3Process {
    return (Get-Process war3 -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Capture-GameShot([string]$tag) {
    if (-not $script:shotReady) { return $null }
    $h = [IntPtr]::Zero
    try { $h = [W3WinApi]::FindWindowByTitle('Warcraft III') } catch { }
    if ($h -eq [IntPtr]::Zero) {
        $p = Get-War3Process
        if (-not $p) { return $null }
        try { $p.Refresh() } catch { }
        $h = $p.MainWindowHandle
    }
    if (-not $h) { return $null }
    $r = New-Object W3WinApi+RECT
    if (-not [W3WinApi]::GetWindowRect([IntPtr]$h, [ref]$r)) { return $null }
    $w = $r.Right - $r.Left
    $ht = $r.Bottom - $r.Top
    if ($w -lt 100 -or $ht -lt 100) { return $null }
    $name = ('run_{0:yyyyMMdd_HHmmss}_{1}.png' -f (Get-Date), $tag)
    $path = Join-Path $screensDir $name
    try {
        $bmp = New-Object System.Drawing.Bitmap $w, $ht
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $ht))
        $g.Dispose()
        if ($w -gt 1100) {
            $nw = 1100
            $nh = [int]($ht * $nw / $w)
            $small = New-Object System.Drawing.Bitmap $nw, $nh
            $g2 = [System.Drawing.Graphics]::FromImage($small)
            $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g2.DrawImage($bmp, 0, 0, $nw, $nh)
            $g2.Dispose()
            $bmp.Dispose()
            $small.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
            $small.Dispose()
        } else {
            $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
        return $path
    } catch {
        return $null
    }
}

function Get-ForegroundTitle {
    if (-not $script:shotReady) { return '' }
    try { return [W3WinApi]::ForegroundTitle() } catch { return '' }
}

$exit = 1
try {
    if ($oldInstall -and ($oldInstall.TrimEnd('\') -ne $GameDir.TrimEnd('\'))) {
        Set-ItemProperty -Path $REG_KEY -Name InstallPath -Value $GameDir
    }
    Remove-Item -LiteralPath $report -Force
    Write-Host ("[run] {0:HH:mm:ss} map: {1}" -f $start, $Map)
    Write-Host ("[run] gameDir: {0}  report: {1}" -f $GameDir, $report)

    if (Test-Path -LiteralPath $EVERCONFIG) {
        Copy-Item -LiteralPath $EVERCONFIG -Destination $EVERCONFIG_GUARD -Force
        $everCfgHashBefore = (Get-FileHash -LiteralPath $EVERCONFIG).Hash
        Write-Host '[run] config guard: EverConfig.cfg backed up'
    }
    $launcher = Start-Process -FilePath $YDWECONFIG -ArgumentList @('-launchwar3', '-loadfile', (Resolve-Path -LiteralPath $Map).Path) -WorkingDirectory (Join-Path $KKWE 'bin') -PassThru
    Write-Host ("[run] launcher pid={0}" -f $launcher.Id)

    $wsh = $null
    try { $wsh = New-Object -ComObject WScript.Shell } catch { }

    function Move-FocusAway {
        if ($null -eq $wsh) { return $false }
        foreach ($title in @('Program Manager', 'Microsoft Edge', 'File Explorer')) {
            if ($wsh.AppActivate($title)) { return $true }
        }
        return $false
    }
    function Move-FocusWar3 {
        if ($script:shotReady) {
            try {
                if ([W3WinApi]::FocusWindowByTitle('Warcraft III')) { return $true }
            } catch { }
        }
        $p = Get-War3Process
        if (-not $p) { return $false }
        if ($null -eq $wsh) { return $false }
        if ($wsh.AppActivate($p.Id)) { return $true }
        try { $p.Refresh() } catch { }
        if ($p.MainWindowTitle) { return [bool]$wsh.AppActivate($p.MainWindowTitle) }
        return $false
    }

    Start-Sleep -Seconds 6
    $focusMoved = Move-FocusAway
    if (-not $focusMoved) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $env:USERPROFILE | Out-Null
            $focusMoved = $true
        } catch { }
    }
    Write-Host ("[run] loading: focus away from war3: {0}" -f $focusMoved)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $got = $false
    $war3Focused = $false
    $shots = New-Object System.Collections.ArrayList
    $lastShotAt = Get-Date
    $shotCount = 0

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $loadingDone = (Test-Path -LiteralPath $bootFile) -and ((Get-Item -LiteralPath $bootFile).LastWriteTime -gt $start)
        if (-not $loadingDone) {
            $null = Move-FocusAway
        } elseif (-not $war3Focused) {
            $war3Focused = Move-FocusWar3
            Write-Host ("[run] load done: re-focused war3: {0}" -f $war3Focused)
            if ($war3Focused) {
                Start-Sleep -Milliseconds 800
                $p = Capture-GameShot 'after_load'
                if ($p) { [void]$shots.Add($p); $lastShotAt = Get-Date }
            }
        }
        if ($loadingDone -and (((Get-Date) - $lastShotAt).TotalSeconds -ge 1.5) -and $shotCount -lt 40) {
            $fg = Get-ForegroundTitle
            if ($fg -notmatch 'Warcraft') { $null = Move-FocusWar3 }
            $shotCount = $shotCount + 1
            $p = Capture-GameShot ('t' + $shotCount)
            if ($p) { [void]$shots.Add($p) }
            $lastShotAt = Get-Date
        }
        if (Test-Path -LiteralPath $report) { $got = $true; break }
    }
    if (-not $got) {
        $grace = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $grace) {
            Start-Sleep -Milliseconds 500
            if (Test-Path -LiteralPath $report) { $got = $true; break }
        }
        if (-not $got) {
            $p = Capture-GameShot 'timeout'
            if ($p) { [void]$shots.Add($p) }
        }
    }
    $result.screens = @($shots)
    $result.elapsedSec = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)

    if (-not $got) {
        $w3 = Get-War3Process
        $anomaly = [ordered]@{
            kind                  = 'TIMEOUT'
            war3Exists            = [bool]$w3
            war3Id                = $(if ($w3) { $w3.Id } else { 0 })
            war3Responding        = $(if ($w3) { $w3.Responding } else { $false })
            war3Title             = $(if ($w3) { $w3.MainWindowTitle } else { '' })
            foregroundTitle       = (Get-ForegroundTitle)
            bootlogNewerThanStart = ((Test-Path -LiteralPath $bootFile) -and ((Get-Item -LiteralPath $bootFile).LastWriteTime -gt $start))
            bootlogTime           = $(if (Test-Path -LiteralPath $bootFile) { (Get-Item -LiteralPath $bootFile).LastWriteTime.ToString('HH:mm:ss') } else { '' })
            hbTime                = $(if (Test-Path -LiteralPath $hbFile) { (Get-Item -LiteralPath $hbFile).LastWriteTime.ToString('HH:mm:ss') } else { '' })
            logTime               = $(if (Test-Path -LiteralPath $logFile) { (Get-Item -LiteralPath $logFile).LastWriteTime.ToString('HH:mm:ss') } else { '' })
            reportExists          = (Test-Path -LiteralPath $report)
            lastScreen            = $(if ($shots.Count -gt 0) { $shots[$shots.Count - 1] } else { '' })
            screensCount          = $shots.Count
        }
        $result.anomaly = $anomaly
        Write-Host '[run] anomaly:'
        foreach ($k in $anomaly.Keys) { Write-Host ("  {0} = {1}" -f $k, $anomaly[$k]) }
        Write-Host '[run] RESULT: TIMEOUT'
        $result.result = 'TIMEOUT'
        $exit = 3
    } else {
        $bytes = $null
        $text = ''
        $readDeadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $readDeadline) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($report)
                $candidate = [System.Text.Encoding]::UTF8.GetString($bytes)
                $text = $candidate
                if ($candidate.Contains('PreloadEnd') -or $candidate.Contains('SUMMARY|')) { break }
            } catch { }
            Start-Sleep -Milliseconds 400
        }
        if (-not $bytes) { $bytes = @() }
        if ($text.Contains([string][char]0xFFFD)) {
            try { $text = [System.Text.Encoding]::GetEncoding(936).GetString($bytes) } catch { }
        }
        $lines = @()
        foreach ($m in [regex]::Matches($text, 'call\s+Preload\(\s*"((?:[^"\\]|\\.)*)"\s*\)')) {
            $lines += ($m.Groups[1].Value -replace '\\"', '"')
        }
        $result.lines = $lines
        $result.checks = @($lines | Where-Object { $_ -like 'CHECK|*' })
        $result.fails = @($lines | Where-Object { $_ -like 'CHECK|*|FAIL|*' })
        $summary = $lines | Where-Object { $_ -like 'SUMMARY|*' } | Select-Object -Last 1
        $result.summary = $summary

        Write-Host ("[run] report after {0}s, lines={1}, checks={2}, fails={3}" -f $result.elapsedSec, $lines.Count, $result.checks.Count, $result.fails.Count)
        Write-Host '--- report ---'
        $lines | ForEach-Object { Write-Host ("  " + $_) }
        Write-Host '--------------'

        if ($summary -match 'result=PASS') {
            $result.result = 'PASS'
            Write-Host ("[run] RESULT: PASS  ({0})" -f $summary)
            $exit = 0
        } else {
            $result.result = 'FAIL'
            if (-not $summary) { $result.summary = 'NO SUMMARY LINE' }
            Write-Host ("[run] RESULT: FAIL  ({0})" -f $result.summary)
            $exit = 1
        }
    }
} catch {
    $result.result = 'FAIL'
    $result | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
    Write-Host ("[run] ERROR: {0}" -f $_.Exception.Message)
    $exit = 1
} finally {
    # Close the game gracefully so YDWE's DLL-fixer can restore version.dll/YDDllFixer state.
    if (-not $KeepGame) {
        $war3 = Get-Process war3 -ErrorAction SilentlyContinue
        if ($war3) {
            foreach ($p in $war3) { try { $p.CloseMainWindow() | Out-Null } catch {} }
            $deadline = (Get-Date).AddSeconds(10)
            while ((Get-Date) -lt $deadline -and (Get-Process war3 -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 300 }
            Get-Process war3 -ErrorAction SilentlyContinue | Stop-Process -Force
        }
    }
    # Restore editor config if YDWEConfig rewrote it during this run.
    if ($everCfgHashBefore) {
        $ydcfg = Get-Process YDWEConfig -ErrorAction SilentlyContinue
        if ($ydcfg) {
            try { $ydcfg | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue } catch {}
        }
        Get-Process YDWEConfig -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 300
        $everCfgAfter = ''
        if (Test-Path -LiteralPath $EVERCONFIG) { $everCfgAfter = (Get-FileHash -LiteralPath $EVERCONFIG).Hash }
        if ($everCfgAfter -ne $everCfgHashBefore -and (Test-Path -LiteralPath $EVERCONFIG_GUARD)) {
            try {
                Copy-Item -LiteralPath $EVERCONFIG_GUARD -Destination $EVERCONFIG -Force
                Write-Host '[run] config guard: YDWEConfig changed EverConfig.cfg -> restored backup'
                $result | Add-Member -NotePropertyName configGuard -NotePropertyValue 'restored' -Force
            } catch {
                Write-Host ("[run] config guard FAILED: {0}" -f $_.Exception.Message)
                $result | Add-Member -NotePropertyName configGuard -NotePropertyValue ('restore-failed: ' + $_.Exception.Message) -Force
            }
        }
    }
    if ($oldInstall) { Set-ItemProperty -Path $REG_KEY -Name InstallPath -Value $oldInstall }
    if ($JsonOut) {
        try {
            $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
            Write-Host ("[run] json: {0}" -f $JsonOut)
        } catch { Write-Host ("[run] json write failed: {0}" -f $_.Exception.Message) }
    }
}

exit $exit
