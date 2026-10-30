#requires -Version 5.1
# =============================================================================
# 小黑桌寵 V1.0.1 - 小黑, a black Taiwanese dog desktop pet
#   小黑 is a shy, sleepy and cuddly black Taiwanese mixed-breed dog who lives on the desktop.
#   PowerShell 5.1 + Windows Forms, all in this one file; START_Black.cmd starts it.
#   Safety:
#   * Offline. The only network code is 關於 → 檢查更新 / 自動檢查更新 (once a day, can be switched off):
#     a hidden helper compares this folder with github.com/chienan822454/Black_Desktop_pet (branch main)
#     and downloads only new or changed files of 小黑, each one checked. It never uploads anything, never
#     deletes a file of this folder, and copies the new files in only after 小黑 has closed.
#   * Writes only its own files: error logs in this folder when something goes wrong
#     (BlackPet_Error_*.txt, at most 5 per run) and its settings in %APPDATA%\BlackPet
#     (settings.txt, mood.txt, and update\ while an update is downloaded).
#   * In a OneDrive folder it asks OneDrive to keep this folder on this PC (attrib +P, this folder only).
#   * Changes no Windows settings, installs nothing, needs no admin rights and never works around
#     PowerShell security (START_Black.cmd only reads the policy and starts with RemoteSigned).
#   * Plays no sounds. (Later versions: one SoundPlayer at a time; looping sounds share one channel
#     with a priority order.)
# =============================================================================
param([string]$UpdateMode = '', [string]$UpdateDir = '', [int]$WaitPid = 0)
$ErrorActionPreference = 'Stop'
$script:appVersion = 'V1.0.1'
$script:appTitle = '小黑桌寵 ' + $script:appVersion

# =============================================================================
# Update helper. 關於 → 檢查更新 starts this same file again as a hidden PowerShell with -UpdateMode:
#   check    = compares every file of 小黑's folder with GitHub (chienan822454/Black_Desktop_pet, main),
#   download = also downloads the new or changed files into %APPDATA%\BlackPet\update\files (checked one by one),
#   apply    = waits until 小黑 has closed, copies the downloaded files into 小黑's folder and starts
#              START_Black.cmd again.
# It only reads from GitHub, only writes 小黑's own files, never deletes a file of 小黑's folder and never
# changes any Windows setting. Progress and the result go to status.txt in the update folder.
# =============================================================================
$script:updRepo = 'chienan822454/Black_Desktop_pet'
$script:updBranch = 'main'

function Write-UpdStatus([hashtable]$h) {
    $lines = @()
    foreach ($k in $h.Keys) { $lines += ([string]$k + '=' + [string]$h[$k]) }
    $tmp = Join-Path $UpdateDir 'status.tmp'
    [System.IO.File]::WriteAllLines($tmp, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $UpdateDir 'status.txt') -Force
}

function Get-GitBlobSha([string]$path) {
    # The same fingerprint GitHub keeps for every file (SHA-1 of "blob <size>\0" + the bytes).
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $head = [System.Text.Encoding]::ASCII.GetBytes(('blob ' + $fs.Length) + [char]0)
        [void]$sha.TransformBlock($head, 0, $head.Length, $null, 0)
        $buf = New-Object byte[] 1048576
        while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) { [void]$sha.TransformBlock($buf, 0, $n, $null, 0) }
        [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $fs.Dispose()
        $sha.Dispose()
    }
}

function New-UpdClient {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    try {
        $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    } catch { }
    return $wc
}

function Get-UpdRawUrl([string]$rel) {
    $parts = @()
    foreach ($q in ($rel -split '/')) { $parts += [Uri]::EscapeDataString($q) }
    return ('https://raw.githubusercontent.com/' + $script:updRepo + '/' + $script:updBranch + '/' + ($parts -join '/'))
}

function Get-UpdPlan {
    # Which files on GitHub are missing here or different: @(path, fingerprint, size) each, and the version on GitHub.
    $wc = New-UpdClient
    $treeUrl = 'https://api.github.com/repos/' + $script:updRepo + '/git/trees/' + $script:updBranch + '?recursive=1'
    $wc.Headers['User-Agent'] = 'XiaoheiDesktopPet'
    $json = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData($treeUrl))
    $tree = ConvertFrom-Json $json
    if ($tree.truncated) { throw 'GitHub 的檔案清單太長，沒有拿到完整清單' }
    $need = @()
    $bytes = [long]0
    foreach ($entry in $tree.tree) {
        if ([string]$entry.type -ne 'blob') { continue }
        $rel = [string]$entry.path
        if ($rel.StartsWith('.github/')) { continue }
        $local = Join-Path $PSScriptRoot ($rel -replace '/', '\')
        $same = $false
        if (Test-Path -LiteralPath $local) {
            if ((Get-Item -LiteralPath $local).Length -eq [long]$entry.size) { $same = ((Get-GitBlobSha $local) -eq [string]$entry.sha) }
        }
        if (-not $same) {
            $need += , @($rel, [string]$entry.sha, [long]$entry.size)
            $bytes += [long]$entry.size
        }
    }
    $wc.Headers['User-Agent'] = 'XiaoheiDesktopPet'
    $remote = [System.Text.Encoding]::UTF8.GetString($wc.DownloadData((Get-UpdRawUrl 'BlackPet.ps1')))
    $ver = ''
    $vm = [regex]::Match($remote, "appVersion = '(V[0-9.]+)'")
    if ($vm.Success) { $ver = $vm.Groups[1].Value }
    $wc.Dispose()
    return @{ Need = $need; Bytes = $bytes; Version = $ver }
}

if (-not [string]::IsNullOrEmpty($UpdateMode)) {
    try {
        if (-not (Test-Path -LiteralPath $UpdateDir)) { [void](New-Item -ItemType Directory -Path $UpdateDir -Force) }
        $updStage = Join-Path $UpdateDir 'files'
        $listPath = Join-Path $UpdateDir 'list.txt'
        if ($UpdateMode -eq 'check' -or $UpdateMode -eq 'download') {
            Write-UpdStatus @{ state = 'checking' }
            $plan = Get-UpdPlan
            $lines = @()
            foreach ($f in $plan.Need) { $lines += ($f[0] + "`t" + $f[1]) }
            [System.IO.File]::WriteAllLines($listPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
            if ($plan.Need.Count -eq 0) {
                Write-UpdStatus @{ state = 'uptodate'; version = $plan.Version }
                exit 0
            }
            if ($UpdateMode -eq 'check') {
                Write-UpdStatus @{ state = 'available'; version = $plan.Version; count = $plan.Need.Count; bytes = $plan.Bytes }
                exit 0
            }
            $wc = New-UpdClient
            $done = 0
            $doneBytes = [long]0
            foreach ($f in $plan.Need) {
                $dst = Join-Path $updStage ($f[0] -replace '/', '\')
                $ok = $false
                if (Test-Path -LiteralPath $dst) { $ok = ((Get-GitBlobSha $dst) -eq $f[1]) }
                if (-not $ok) {
                    $dir = Split-Path -Parent $dst
                    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
                    $got = $false
                    for ($attempt = 0; $attempt -lt 3 -and -not $got; $attempt++) {
                        $wc.Headers['User-Agent'] = 'XiaoheiDesktopPet'
                        $wc.DownloadFile((Get-UpdRawUrl $f[0]), $dst)
                        $got = ((Get-GitBlobSha $dst) -eq $f[1])
                        if (-not $got) { Start-Sleep -Seconds 5 }
                    }
                    if (-not $got) { throw ('下載的檔案跟 GitHub 上的不一樣：' + $f[0] + '（GitHub 剛更新時可能要等幾分鐘）') }
                }
                $done++
                $doneBytes += $f[2]
                Write-UpdStatus @{ state = 'downloading'; version = $plan.Version; count = $plan.Need.Count; done = $done; bytes = $plan.Bytes; donebytes = $doneBytes }
            }
            $wc.Dispose()
            Write-UpdStatus @{ state = 'ready'; version = $plan.Version; count = $plan.Need.Count; bytes = $plan.Bytes }
            exit 0
        }
        if ($UpdateMode -eq 'apply') {
            if ($WaitPid -gt 0) {
                for ($w = 0; $w -lt 120; $w++) {
                    if ($null -eq (Get-Process -Id $WaitPid -ErrorAction SilentlyContinue)) { break }
                    Start-Sleep -Milliseconds 500
                }
            }
            Start-Sleep -Milliseconds 800
            $copied = 0
            $failed = @()
            foreach ($ln in [System.IO.File]::ReadAllLines($listPath)) {
                $rel = ($ln -split "`t")[0]
                if ([string]::IsNullOrEmpty($rel)) { continue }
                $src = Join-Path $updStage ($rel -replace '/', '\')
                $dst = Join-Path $PSScriptRoot ($rel -replace '/', '\')
                if (-not (Test-Path -LiteralPath $src)) {
                    $failed += $rel
                    continue
                }
                try {
                    $dir = Split-Path -Parent $dst
                    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                    $copied++
                } catch {
                    $failed += $rel
                }
            }
            if ($failed.Count -eq 0) {
                # Only the downloaded copies in the update folder are cleared away, never a file of 小黑's folder.
                try { Remove-Item -LiteralPath $updStage -Recurse -Force } catch { }
            } else {
                [System.IO.File]::WriteAllLines((Join-Path $UpdateDir 'failed.txt'), [string[]]$failed, [System.Text.UTF8Encoding]::new($false))
            }
            Write-UpdStatus @{ state = 'applied'; copied = $copied; failed = $failed.Count }
            Start-Process -FilePath (Join-Path $PSScriptRoot 'START_Black.cmd') -WorkingDirectory $PSScriptRoot -WindowStyle Minimized
            exit 0
        }
        Write-UpdStatus @{ state = 'error'; msg = ('unknown mode ' + $UpdateMode) }
    } catch {
        try { Write-UpdStatus @{ state = 'error'; msg = (([string]$_ + ' @ line ' + $_.InvocationInfo.ScriptLineNumber) -replace "[`r`n]+", ' ') } } catch { }
        exit 1
    }
    exit 0
}

try { $Host.UI.RawUI.WindowTitle = '小黑桌寵 - 關閉這個視窗會結束小黑' } catch { }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Three read-only Windows calls, compiled in memory by Windows' own .NET compiler: sharp pictures on
# high-resolution screens (this program draws at the real screen size; only this program is affected),
# and which window is under the mouse pointer (so 小黑 is not petted through a window that covers him).
# Without them 小黑 still works (a little blurry at 125 % / 150 %).
$script:nativeOk = $false
try {
    $nativeCode = @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(long point);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
'@
    Add-Type -Namespace XiaoheiPet -Name Native -MemberDefinition $nativeCode -ErrorAction Stop
    [void][XiaoheiPet.Native]::SetProcessDPIAware()
    $script:nativeOk = $true
} catch {
    $script:nativeOk = $false
}
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

# Screen scale (1.0 = 100 %, 1.5 = 150 % ...): sizes and movements are multiplied by it.
$script:dpiScale = 1.0
try {
    $dpiG = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    try { $script:dpiScale = [Math]::Min(3.0, [Math]::Max(1.0, ($dpiG.DpiX / 96.0))) } finally { $dpiG.Dispose() }
} catch {
    $script:dpiScale = 1.0
}

function Get-Scaled([double]$value) {
    return [int][Math]::Round($value * $script:dpiScale)
}

# -----------------------------------------------------------------------------
# Error log: <小黑's folder>\BlackPet_Error_<date>_<time>_<process>.txt, at most 5 files per run and each
# message only once, so a repeating problem can never flood the folder (or OneDrive) with files.
# -----------------------------------------------------------------------------
$script:errorLogCount = 0
$script:errorSeen = @{}

function Write-ErrorLog([string]$text, [switch]$Force) {
    try {
        $sig = if ($text.Length -gt 300) { $text.Substring(0, 300) } else { $text }
        if (-not $Force) {
            if ($script:errorLogCount -ge 5) { return $null }
            if ($script:errorSeen.ContainsKey($sig)) { return $null }
        }
        $script:errorSeen[$sig] = $true
        $script:errorLogCount++
        $name = 'BlackPet_Error_{0}_{1}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID
        $path = Join-Path $PSScriptRoot $name
        [System.IO.File]::WriteAllText($path, ($script:appTitle + "`r`n" + $text), [System.Text.Encoding]::UTF8)
        return $path
    } catch {
        return $null
    }
}

function Write-PetError([string]$where, $err) {
    # Something went wrong in a timer tick or an event handler: written down with the line number, 小黑 carries on.
    try {
        $line = 0
        $trace = ''
        if ($err -is [System.Management.Automation.ErrorRecord]) {
            $line = [int]$err.InvocationInfo.ScriptLineNumber
            $trace = [string]$err.ScriptStackTrace
        }
        $null = Write-ErrorLog ($where + '：' + [string]$err + "`r`n" + 'line ' + $line + "`r`n" + $trace)
    } catch { }
}

# -----------------------------------------------------------------------------
# Timing. One animation tick = 60 ms (240 ms while fast asleep, which then counts as 4 ticks).
# -----------------------------------------------------------------------------
$script:tickMs = 60
$script:breathTicks = 10          # breathing: stand_00 and breath_00 0.6 s each (1.2 s per breath)
$script:blinkLen = 3              # a blink lasts 3 ticks (about 0.18 s); one every 3 to 6 seconds
$script:idleActMin = 100          # standing idle: the next random action after 6 to 15 seconds
$script:idleActMax = 250
$script:hoverCuddleTicks = 13     # pointer resting on 小黑 for 0.8 s: 撒嬌
$script:hoverRubTicks = 67        # petted 4 seconds more: rolls over for a belly rub
$script:hoverLeaveTicks = 17      # pointer gone for 1 s: gets up again
$script:idleSleepTicks = 10000    # 10 minutes without any attention: falls asleep (沒人理會自己睡)
$script:nightAwakeTicks = 2000    # at night: 2 minutes without attention and he goes (back) to sleep
$script:moodDecayTicks = 15000    # mood: a little lower for every 15 minutes without attention
# Speeds in pixels per tick for a 250 px window at 100 % (multiplied by Get-PetUnit for other sizes and DPI).
$script:walkSpeed = 4.6
$script:runSpeed = 10.0
$script:summonSpeed = 12.0
$script:flingMinSpeed = 20.0      # let go faster than this: thrown
$script:flingMaxSpeed = 80.0
$script:flingSlideSpeed = 6.0     # slower than this: skidding to a stop (slide_00)
$script:flingStopSpeed = 1.2
$script:flingFriction = 0.88      # part of the speed kept per tick while flying
$script:flingBounce = 0.55        # part of the speed kept when bouncing off the edge of the screen

# Where 小黑's body is in every 768 x 768 picture, as parts of the window (paws on y = 674).
$script:footLine = 674.0 / 768.0
$script:bodyLeft = 0.16
$script:bodyRight = 0.84
$script:bodyTop = 0.23
# The head in pics\stand_00.png (x, y, width, height in the 768 picture): the icon when xiaohei.ico is missing.
$script:headBox = @(440, 160, 250, 250)
# 迷你 / 小 / 一般 / 大 / 巨大 (window size in pixels at 100 %).
$script:sizeChoices = @(130, 180, 250, 320, 410)

# -----------------------------------------------------------------------------
# Pictures: pics\<name>.png, 768 x 768, alpha 0 or 255, facing right (mirrored when he faces left).
# A missing picture is shown as the first one of its list that is there (checked again every 30 s while
# pictures are missing, for example while OneDrive is still syncing them).
# Walking (8 pictures) and running (4 pictures) are used only when all pictures of the cycle are there.
# -----------------------------------------------------------------------------
$script:frameChainBase = [ordered]@{
    'stand_00'     = @('stand_00')
    'stand_01'     = @('stand_01', 'stand_00')
    'stand_02'     = @('stand_02', 'stand_00')
    'breath_00'    = @('breath_00', 'stand_00')
    'blink_00'     = @('blink_00', 'stand_00')
    'blink_01'     = @('blink_01', 'blink_00', 'stand_00')
    'blink_02'     = @('blink_02', 'blink_00', 'stand_00')
    'walk_00'      = @('walk_00', 'stand_00')
    'walk_01'      = @('walk_01', 'stand_00')
    'walk_02'      = @('walk_02', 'stand_00')
    'walk_03'      = @('walk_03', 'stand_00')
    'walk_04'      = @('walk_04', 'stand_00')
    'walk_05'      = @('walk_05', 'stand_00')
    'walk_06'      = @('walk_06', 'stand_00')
    'walk_07'      = @('walk_07', 'stand_00')
    'run_00'       = @('run_00', 'walk_00', 'stand_00')
    'run_01'       = @('run_01', 'walk_01', 'stand_00')
    'run_02'       = @('run_02', 'walk_02', 'stand_00')
    'run_03'       = @('run_03', 'walk_03', 'stand_00')
    'sit_00'       = @('sit_00', 'stand_00')
    'lie_00'       = @('lie_00', 'stand_00')
    'sleep_00'     = @('sleep_00', 'lie_00', 'stand_00')
    'curl_00'      = @('curl_00', 'sleep_00', 'lie_00', 'stand_00')
    'sidesleep_00' = @('sidesleep_00', 'sleep_00', 'lie_00', 'stand_00')
    'belly_00'     = @('belly_00', 'sleep_00', 'lie_00', 'stand_00')
    'yawn_00'      = @('yawn_00', 'stand_00')
    'tilt_00'      = @('tilt_00', 'stand_00')
    'sniff_00'     = @('sniff_00', 'stand_00')
    'sniff_01'     = @('sniff_01', 'sniff_00', 'stand_00')
    'happy_00'     = @('happy_00', 'stand_00')
    'happy_01'     = @('happy_01', 'stand_01', 'stand_00')
    'happy_02'     = @('happy_02', 'stand_02', 'stand_00')
    'cuddle_00'    = @('cuddle_00', 'blink_00', 'stand_00')
    'cuddle_01'    = @('cuddle_01', 'cuddle_00', 'blink_00', 'stand_00')
    'rub_00'       = @('rub_00', 'belly_00', 'sleep_00', 'lie_00', 'stand_00')
    'drag_00'      = @('drag_00', 'walk_00', 'stand_00')
    'drag_01'      = @('drag_01', 'drag_00', 'walk_01', 'stand_00')
    'drag_02'      = @('drag_02', 'drag_00', 'walk_02', 'stand_00')
    'slide_00'     = @('slide_00', 'stand_00')
}

# -----------------------------------------------------------------------------
# Settings: %APPDATA%\BlackPet\settings.txt (key=value lines) and mood.txt (0-100).
# -----------------------------------------------------------------------------
function Import-PetSettings {
    $script:baseSize = 250
    $script:topMostWanted = $true
    $script:roamEnabled = $true
    $script:chaseEnabled = $false
    $script:nightSleepEnabled = $true
    $script:idleSleepEnabled = $true
    $script:updAuto = $true
    $script:updLast = [datetime]::MinValue
    if ([string]::IsNullOrEmpty($script:settingsFile)) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:settingsFile)) { return }
        foreach ($ln in [System.IO.File]::ReadAllLines($script:settingsFile)) {
            $i = $ln.IndexOf('=')
            if ($i -le 0) { continue }
            $key = $ln.Substring(0, $i).Trim().ToLowerInvariant()
            $val = $ln.Substring($i + 1).Trim()
            $on = ($val -ne '0')
            switch ($key) {
                'size' {
                    $n = 0
                    if ([int]::TryParse($val, [ref]$n) -and ($script:sizeChoices -contains $n)) { $script:baseSize = $n }
                }
                'topmost' { $script:topMostWanted = $on }
                'roam' { $script:roamEnabled = $on }
                'chase' { $script:chaseEnabled = $on }
                'nightsleep' { $script:nightSleepEnabled = $on }
                'idlesleep' { $script:idleSleepEnabled = $on }
                'autoupdate' { $script:updAuto = $on }
                'lastupdatecheck' {
                    $d = [datetime]::MinValue
                    if ([datetime]::TryParse($val, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $script:updLast = $d }
                }
            }
        }
    } catch {
        Write-PetError '設定無法讀取' $_
    }
}

function Save-PetSettings {
    if ([string]::IsNullOrEmpty($script:settingsFile)) { return }
    try {
        $dir = Split-Path -Parent $script:settingsFile
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        $lines = @(
            ('size=' + $script:baseSize),
            ('topmost=' + [int]$script:topMostWanted),
            ('roam=' + [int]$script:roamEnabled),
            ('chase=' + [int]$script:chaseEnabled),
            ('nightsleep=' + [int]$script:nightSleepEnabled),
            ('idlesleep=' + [int]$script:idleSleepEnabled),
            ('autoupdate=' + [int]$script:updAuto),
            ('lastupdatecheck=' + $script:updLast.ToString('s', [System.Globalization.CultureInfo]::InvariantCulture))
        )
        [System.IO.File]::WriteAllLines($script:settingsFile, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-PetError '設定無法儲存' $_
    }
}

# 心情: how much attention 小黑 gets (0-100). Petting and playing raise it; being left alone lowers it slowly.
function Import-DogMood {
    $script:affection = 60
    if ([string]::IsNullOrEmpty($script:moodFile)) { return }
    try {
        if (Test-Path -LiteralPath $script:moodFile) {
            $v = 0
            if ([int]::TryParse(([System.IO.File]::ReadAllText($script:moodFile)).Trim(), [ref]$v)) { $script:affection = [Math]::Max(0, [Math]::Min(100, $v)) }
        }
    } catch {
        Write-PetError '心情無法讀取' $_
    }
}

function Save-DogMood {
    if ([string]::IsNullOrEmpty($script:moodFile)) { return }
    try {
        $dir = Split-Path -Parent $script:moodFile
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
        [System.IO.File]::WriteAllText($script:moodFile, [string]$script:affection, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-PetError '心情無法儲存' $_
    }
}

function Add-DogMood([int]$n) {
    $script:affection = [Math]::Max(0, [Math]::Min(100, ($script:affection + $n)))
    if ($n -gt 0) { $script:moodDecayAt = (Get-Date).AddMinutes(15) }
    Save-DogMood
}

function Get-DogMoodHearts {
    $hearts = [int][Math]::Round($script:affection / 20.0)
    return (('♥' * $hearts) + ('♡' * (5 - $hearts)))
}

function Get-DogMoodText {
    $word = '還不錯，有點想睡…'
    if ($script:affection -ge 80) { $word = '超黏你的！想一直跟著你～' }
    elseif ($script:affection -ge 60) { $word = '很開心，尾巴搖不停！' }
    elseif ($script:affection -lt 20) { $word = '好寂寞…都沒人理小黑…' }
    elseif ($script:affection -lt 40) { $word = '有點寂寞…摸摸我好嗎？' }
    return ('小黑的心情 ' + (Get-DogMoodHearts) + "`r`n" + $word)
}

function Update-DogMood {
    # Every 3 seconds: a little lower for every 15 minutes without attention (not while he sleeps).
    if ($script:dogAct -eq 'sleep') { return }
    $now = Get-Date
    if ($now -lt $script:moodDecayAt) { return }
    $script:moodDecayAt = $now.AddMinutes(15)
    if (($script:clockTick - $script:lastInteractTick) -gt $script:moodDecayTicks) { Add-DogMood (-3) }
}

function Test-NightTime {
    # Night = 23:00 to 05:59 (this PC's clock).
    $h = (Get-Date).Hour
    return ($h -ge 23 -or $h -lt 6)
}

# -----------------------------------------------------------------------------
# Pictures on the screen. Every picture is resized once to the window size and cut hard (alpha 0 or 255),
# because the window's magenta see-through colour would show through half see-through edge pixels as a pink halo.
# -----------------------------------------------------------------------------
function Convert-AlphaCut([System.Drawing.Bitmap]$source) {
    $w = $source.Width
    $h = $source.Height
    $out = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $ia = [System.Drawing.Imaging.ImageAttributes]::new()
    try {
        # Opacity 48 or more becomes solid, anything lower becomes clear.
        $cm = [System.Drawing.Imaging.ColorMatrix]::new()
        $cm.Matrix33 = 255
        $cm.Matrix43 = -47
        $ia.SetColorMatrix($cm)
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $g.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $w, $h), 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    } finally {
        $ia.Dispose()
        $g.Dispose()
    }
    return $out
}

function Test-AlphaCut([System.Drawing.Bitmap]$before, [System.Drawing.Bitmap]$after) {
    # Self-test on a grid of points: almost no half see-through pixels left, and the solid area as expected.
    $soft = 0
    $expected = 0
    $solid = 0
    for ($y = 3; $y -lt $after.Height; $y += 10) {
        for ($x = 3; $x -lt $after.Width; $x += 10) {
            $a = $after.GetPixel($x, $y).A
            if ($a -gt 8 -and $a -lt 247) { $soft++ }
            if ($a -ge 128) { $solid++ }
            if ($before.GetPixel($x, $y).A -ge 48) { $expected++ }
        }
    }
    if ($expected -eq 0) { return ($solid -eq 0) }
    $ratio = $solid / $expected
    return ($soft -le 3 -and $ratio -ge 0.9 -and $ratio -le 1.1)
}

function Convert-ToDisplayBitmap([byte[]]$bytes, [int]$size) {
    $ms = [System.IO.MemoryStream]::new($bytes)
    $src = $null
    $scaled = $null
    try {
        $src = [System.Drawing.Image]::FromStream($ms)
        $scaled = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($scaled)
        try {
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $ratio = [Math]::Min(([double]$size / $src.Width), ([double]$size / $src.Height))
            $w = [int][Math]::Round($src.Width * $ratio)
            $h = [int][Math]::Round($src.Height * $ratio)
            $x = [int][Math]::Floor(($size - $w) / 2.0)
            $y = [int][Math]::Floor(($size - $h) / 2.0)
            $g.DrawImage($src, [System.Drawing.Rectangle]::new($x, $y, $w, $h))
        } finally {
            $g.Dispose()
        }
    } finally {
        if ($null -ne $src) { $src.Dispose() }
        $ms.Dispose()
    }
    if (-not $script:alphaCutOk) { return $scaled }
    try {
        $cut = Convert-AlphaCut $scaled
    } catch {
        $script:alphaCutOk = $false
        $null = Write-ErrorLog ('邊緣處理無法使用，改用一般圖片：' + [string]$_)
        return $scaled
    }
    if (-not $script:alphaCutTested) {
        $script:alphaCutTested = $true
        $passed = $false
        try { $passed = Test-AlphaCut $scaled $cut } catch { $passed = $false }
        if (-not $passed) {
            $script:alphaCutOk = $false
            $null = Write-ErrorLog '邊緣處理自我檢查沒有通過，改用一般圖片（只影響邊緣外觀，不影響功能）。'
            $cut.Dispose()
            return $scaled
        }
    }
    $scaled.Dispose()
    return $cut
}

function Get-ContentKey([byte[]]$bytes, [string]$fallback) {
    # Identical picture files share one copy in memory.
    try {
        $sha = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()
        try {
            return [System.BitConverter]::ToString($sha.ComputeHash($bytes))
        } finally {
            $sha.Dispose()
        }
    } catch {
        return $fallback
    }
}

function Get-DisplayBitmap([string]$path, [bool]$flip) {
    $side = if ($flip) { '|L' } else { '|R' }
    if ($script:pathKey.ContainsKey($path)) {
        $cached = $script:bmpCache[$script:pathKey[$path] + $side]
        if ($null -ne $cached) { return $cached }
    }
    if ($flip) {
        # A mirrored copy, so 小黑 faces the way he goes.
        $right = Get-DisplayBitmap $path $false
        $left = [System.Drawing.Bitmap]$right.Clone()
        $left.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
        $script:bmpCache[$script:pathKey[$path] + '|L'] = $left
        return $left
    }
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $ms = [System.IO.MemoryStream]::new()
        try {
            $fs.CopyTo($ms)
            $bytes = $ms.ToArray()
        } finally {
            $ms.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
    $key = Get-ContentKey $bytes $path
    $script:pathKey[$path] = $key
    $rightKey = $key + '|R'
    if (-not $script:bmpCache.ContainsKey($rightKey)) {
        $script:bmpCache[$rightKey] = (Convert-ToDisplayBitmap $bytes $script:displaySize)
    }
    return $script:bmpCache[$rightKey]
}

function Reset-ImageCache([int]$size) {
    $script:pic.Image = $null
    $script:dogBitmap = $null
    foreach ($b in @($script:bmpCache.Values)) {
        try { $b.Dispose() } catch { }
    }
    $script:bmpCache = @{}
    $script:displaySize = $size
    $script:currentImagePath = $null
    $script:warmIndex = 0
}

function Set-BadPicture([string]$path, [string]$err) {
    # A picture that could not be read. A OneDrive file that is only in the cloud (not downloaded to this PC yet),
    # or one that is being replaced right now, is tried again a few seconds later; anything else (a broken file)
    # is skipped from now on and the next picture of its list is shown instead.
    $script:badPaths[$path] = $true
    if ($err -match 'cloud|雲端|0x8007016A|0x80070185|offline|離線|being used|另一個處理程序|0x80070020') { $script:badRetry[$path] = $script:clockTick + 60 }
    if (-not $script:badLogged.ContainsKey($path)) {
        $script:badLogged[$path] = $true
        $null = Write-ErrorLog ('圖片無法載入：' + $path + "`r`n" + $err)
    }
}

function Update-BadPictures {
    # Every few seconds: pictures that were only in the cloud get another try.
    if ($script:badRetry.Count -eq 0) { return }
    foreach ($bp in @($script:badRetry.Keys)) {
        if ($script:clockTick -ge [int]$script:badRetry[$bp]) {
            [void]$script:badRetry.Remove($bp)
            [void]$script:badPaths.Remove($bp)
        }
    }
}

function Import-DogPictures([bool]$first) {
    # Which pictures are there, and what is shown for the missing ones.
    $missing = @()
    foreach ($name in @($script:frameChainBase.Keys)) {
        $p = Join-Path $script:picsDir ([string]$name + '.png')
        if (Test-Path -LiteralPath $p) {
            $script:frameFile[[string]$name] = $p
        } else {
            [void]$script:frameFile.Remove([string]$name)
            $missing += [string]$name
        }
    }
    if ($first -and -not $script:frameFile.ContainsKey('stand_00')) { throw ('找不到小黑的圖片：' + (Join-Path $script:picsDir 'stand_00.png')) }
    $chains = @{}
    foreach ($name in @($script:frameChainBase.Keys)) { $chains[[string]$name] = @($script:frameChainBase[$name]) }
    # A walking or running cycle with a picture missing would stutter: then the whole cycle uses the fallback.
    $walkAll = $true
    $runAll = $true
    foreach ($k in 0..7) {
        if (-not $script:frameFile.ContainsKey('walk_0' + $k)) { $walkAll = $false }
    }
    foreach ($k in 0..3) {
        if (-not $script:frameFile.ContainsKey('run_0' + $k)) { $runAll = $false }
    }
    foreach ($k in 0..7) {
        if (-not $walkAll) { $chains['walk_0' + $k] = @('stand_00') }
    }
    foreach ($k in 0..3) {
        if (-not $runAll) { $chains['run_0' + $k] = @($chains['walk_0' + $k]) }
    }
    $script:frameChain = $chains
    $script:breathByFrame = $script:frameFile.ContainsKey('breath_00')
    if ($first -and $missing.Count -gt 0) {
        $null = Write-ErrorLog ('缺少這些圖片（先用替代的圖片顯示）：' + ($missing -join ', ') + "`r`n" + $script:picsDir)
    }
    $script:missingCount = $missing.Count
}

function Get-FramePath([string]$name) {
    # The file to show for this picture: the first one of its list that is there and can be read.
    $chain = $script:frameChain[$name]
    if ($null -eq $chain) { $chain = @('stand_00') }
    foreach ($n in $chain) {
        $p = $script:frameFile[[string]$n]
        if ($null -eq $p) { continue }
        # A broken picture is skipped; one that OneDrive is still downloading is kept, and Set-DisplayImage then
        # keeps the picture that is on the screen now until it can be read.
        if ($script:badPaths.ContainsKey($p) -and -not $script:badRetry.ContainsKey($p)) { continue }
        return $p
    }
    return $script:frameFile['stand_00']
}

function Update-WarmList {
    # Pictures to prepare in the background (one per tick), so the first time an action shows one it does not stutter.
    $script:warmList.Clear()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($name in @($script:frameChainBase.Keys)) {
        $p = Get-FramePath ([string]$name)
        if ($null -ne $p -and $seen.Add([string]$p)) { [void]$script:warmList.Add([string]$p) }
    }
    $script:warmIndex = 0
}

function Update-WarmPictures {
    if ($script:isDragging -or $script:warmIndex -ge $script:warmList.Count) { return }
    $wp = $script:warmList[$script:warmIndex]
    $script:warmIndex++
    if ($script:badPaths.ContainsKey($wp)) { return }
    try {
        $null = Get-DisplayBitmap $wp $false
    } catch {
        Set-BadPicture $wp ([string]$_)
        # Only in the cloud: back on the list, so it is prepared once OneDrive has downloaded it.
        if ($script:badRetry.ContainsKey($wp)) { [void]$script:warmList.Add($wp) }
    }
}

function Set-DisplayImage([string]$path) {
    if ([string]::IsNullOrEmpty($path)) { return }
    if ($script:badPaths.ContainsKey($path)) { return }
    $flip = [bool]$script:facingLeft
    $key = if ($flip) { $path + '|L' } else { $path + '|R' }
    if ($script:currentImagePath -eq $key) { return }
    try {
        $img = Get-DisplayBitmap $path $flip
    } catch {
        Set-BadPicture $path ([string]$_)
        return
    }
    $script:pic.Image = $img
    $script:dogBitmap = $img
    $script:currentImagePath = $key
}

# -----------------------------------------------------------------------------
# Mouse pointer on 小黑 and his icon
# -----------------------------------------------------------------------------
function Get-PetCursor {
    # pics\pet_hand.png as the mouse pointer on 小黑; the normal hand when that picture is missing.
    if ($null -ne $script:petCursor) { return $script:petCursor }
    $script:petCursor = [System.Windows.Forms.Cursors]::Hand
    $png = Join-Path $script:picsDir 'pet_hand.png'
    if (-not (Test-Path -LiteralPath $png)) { return $script:petCursor }
    $src = $null
    $bmp = $null
    try {
        $src = [System.Drawing.Image]::FromFile($png)
        $side = Get-Scaled 40
        $bmp = [System.Drawing.Bitmap]::new($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($src, [System.Drawing.Rectangle]::new(0, 0, $side, $side))
        } finally {
            $g.Dispose()
        }
        # An icon made into a pointer: the middle of the hand is the spot that touches 小黑.
        $script:petCursor = [System.Windows.Forms.Cursor]::new($bmp.GetHicon())
    } catch {
        $script:petCursor = [System.Windows.Forms.Cursors]::Hand
        Write-PetError '撫摸的手游標無法使用，改用一般的手' $_
    } finally {
        if ($null -ne $bmp) { $bmp.Dispose() }
        if ($null -ne $src) { $src.Dispose() }
    }
    return $script:petCursor
}

function New-HeadBitmap([int]$side) {
    # 小黑's head (the $script:headBox part of pics\stand_00.png) on a light round badge, so the black dog
    # also shows on a dark taskbar.
    $bytes = [System.IO.File]::ReadAllBytes([string]$script:frameFile['stand_00'])
    $ms = [System.IO.MemoryStream]::new($bytes)
    try {
        $src = [System.Drawing.Image]::FromStream($ms)
        try {
            $bmp = [System.Drawing.Bitmap]::new($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $badge = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 246, 236, 214))
            $round = [System.Drawing.Drawing2D.GraphicsPath]::new()
            try {
                $g.Clear([System.Drawing.Color]::Transparent)
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $round.AddEllipse(0, 0, ($side - 1), ($side - 1))
                $g.FillPath($badge, $round)
                $g.SetClip($round)
                $hb = $script:headBox
                $from = [System.Drawing.Rectangle]::new([int]$hb[0], [int]$hb[1], [int]$hb[2], [int]$hb[3])
                $g.DrawImage($src, [System.Drawing.Rectangle]::new(0, 0, $side, $side), $from, [System.Drawing.GraphicsUnit]::Pixel)
            } finally {
                $round.Dispose()
                $badge.Dispose()
                $g.Dispose()
            }
            return $bmp
        } finally {
            $src.Dispose()
        }
    } finally {
        $ms.Dispose()
    }
}

function Get-PetIcon {
    # xiaohei.ico; when it is missing, an icon made from the head in pics\stand_00.png.
    if ($null -ne $script:petIcon) { return $script:petIcon }
    $icoPath = Join-Path $PSScriptRoot 'xiaohei.ico'
    if (Test-Path -LiteralPath $icoPath) {
        try {
            $script:petIcon = [System.Drawing.Icon]::new($icoPath, [System.Windows.Forms.SystemInformation]::SmallIconSize)
        } catch {
            $script:petIcon = $null
            Write-PetError 'xiaohei.ico 無法使用，改用小黑的頭像' $_
        }
    }
    if ($null -eq $script:petIcon) {
        try {
            $head = New-HeadBitmap ([Math]::Max(32, (Get-Scaled 32)))
            try { $script:petIcon = [System.Drawing.Icon]::FromHandle($head.GetHicon()) } finally { $head.Dispose() }
        } catch {
            $script:petIcon = $null
            Write-PetError '小黑的圖示無法製作' $_
        }
    }
    if ($null -eq $script:petIcon) { $script:petIcon = [System.Drawing.SystemIcons]::Application }
    return $script:petIcon
}

# -----------------------------------------------------------------------------
# Speech bubble
# -----------------------------------------------------------------------------
function Set-Bubble([string]$message, [int]$ticks = 45) {
    # A speech bubble above 小黑's head for about 2.7 seconds (or $ticks).
    $script:bubbleTicks = $ticks
    $script:bubble.Text = $message
    $script:bubble.Visible = $true
    $script:bubble.BringToFront()
    Update-BubblePlace
}

function Update-BubblePlace {
    # Above his head: on the right when he faces right, on the left when he faces left.
    $m = Get-Scaled 4
    $x = $m
    if (-not $script:facingLeft) { $x = [Math]::Max($m, ($script:form.ClientSize.Width - $script:bubble.Width - $m)) }
    if ($script:bubble.Left -ne $x) { $script:bubble.Left = $x }
}

function Update-BubbleFont {
    # The bubble text follows the size of 小黑 (kept readable: 8 to 13 pt).
    $pt = [Math]::Max(8.0, [Math]::Min(13.0, (9.0 * $script:sizeRatio)))
    $old = $script:bubbleFont
    $script:bubbleFont = [System.Drawing.Font]::new('Microsoft JhengHei UI', [single]$pt, [System.Drawing.FontStyle]::Bold)
    $script:bubble.Font = $script:bubbleFont
    if ($null -ne $old) { $old.Dispose() }
    $script:bubble.MaximumSize = [System.Drawing.Size]::new([Math]::Max(40, ($script:form.ClientSize.Width - (Get-Scaled 8))), 0)
}

# -----------------------------------------------------------------------------
# Where 小黑 is: screens, work areas, spots to go to. $script:baseLocation is the window's top-left corner
# without the hop; $script:posX / $script:posY the same with fractions while he moves.
# -----------------------------------------------------------------------------
function Get-PetUnit {
    # Window pixels per design pixel (a 250 px window at 100 % = 1.0): speeds and hops follow the size and the DPI.
    return ([double]$script:form.Width / 250.0)
}

function Get-DogScreen {
    $x = [int]($script:baseLocation.X + ($script:form.Width * 0.5))
    $y = [int]($script:baseLocation.Y + ($script:form.Height * 0.6))
    return [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new($x, $y))
}

function Get-RoamBounds([bool]$body) {
    # @(minX, maxX, minY, maxY) for the window's corner on 小黑's screen (its work area: never under the taskbar).
    # $body = $false: the whole window stays inside (walking; the bubble stays visible).
    # $body = $true: only his body has to stay inside (thrown, put down); the empty margins may stick out.
    $wa = (Get-DogScreen).WorkingArea
    $w = [double]$script:form.Width
    $h = [double]$script:form.Height
    $minX = [double]$wa.Left
    $maxX = [double]$wa.Right - $w
    $minY = [double]$wa.Top
    if ($body) {
        $minX = [double]$wa.Left - ($w * $script:bodyLeft)
        $maxX = [double]$wa.Right - ($w * $script:bodyRight)
        $minY = [double]$wa.Top - ($h * $script:bodyTop)
    }
    $maxY = [double]$wa.Bottom - ($h * $script:footLine)
    if ($maxX -lt $minX) { $maxX = $minX }
    if ($maxY -lt $minY) { $maxY = $minY }
    return , @($minX, $maxX, $minY, $maxY)
}

function Get-ClampedSpot([double]$x, [double]$y, [bool]$body) {
    $b = Get-RoamBounds $body
    $cx = [Math]::Min([Math]::Max($x, [double]$b[0]), [double]$b[1])
    $cy = [Math]::Min([Math]::Max($y, [double]$b[2]), [double]$b[3])
    return [System.Drawing.Point]::new([int][Math]::Round($cx), [int][Math]::Round($cy))
}

function Get-CursorSpot {
    # Where the window goes so that 小黑 stands right beside the mouse pointer, nose towards it, on his own screen.
    $cur = [System.Windows.Forms.Cursor]::Position
    $w = [double]$script:form.Width
    $h = [double]$script:form.Height
    $tx = [double]$cur.X - ($w * 0.08)
    if (([double]$script:baseLocation.X + ($w * 0.5)) -le [double]$cur.X) { $tx = [double]$cur.X - ($w * 0.92) }
    return (Get-ClampedSpot $tx ([double]$cur.Y - ($h * 0.42)) $false)
}

function Get-RandomSpot([bool]$far) {
    # A spot to walk to (a few steps away) or to run to (further), on 小黑's own screen.
    if ($script:affection -ge 80 -and $script:rng.Next(0, 100) -lt 30) { return (Get-CursorSpot) }
    $w = [double]$script:form.Width
    $b = Get-RoamBounds $false
    $minD = 0.8
    $maxD = 3.0
    if ($far) {
        $minD = 2.5
        $maxD = 6.0
    }
    $dist = $w * ($minD + ($script:rng.NextDouble() * ($maxD - $minD)))
    $dir = 1.0
    if ($script:rng.Next(0, 2) -eq 0) { $dir = -1.0 }
    $x0 = [double]$script:baseLocation.X
    $tx = $x0 + ($dir * $dist)
    if ($tx -lt [double]$b[0] -or $tx -gt [double]$b[1]) { $tx = $x0 - ($dir * $dist) }
    $ty = [double]$script:baseLocation.Y + (($script:rng.NextDouble() - 0.5) * $w * 0.9)
    return (Get-ClampedSpot $tx $ty $false)
}

function Set-DogFacingCursor {
    $cur = [System.Windows.Forms.Cursor]::Position
    $script:facingLeft = ([double]$cur.X -lt ([double]$script:baseLocation.X + ($script:form.Width * 0.5)))
}

function Assert-OnScreen {
    # Brings 小黑 back when he is on no screen any more (for example a second monitor was unplugged).
    $rect = [System.Drawing.Rectangle]::new($script:baseLocation.X, $script:baseLocation.Y, $script:form.Width, $script:form.Height)
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
        $inter = [System.Drawing.Rectangle]::Intersect($scr.WorkingArea, $rect)
        if ($inter.Width -ge 40 -and $inter.Height -ge 40) { return }
    }
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:baseLocation = [System.Drawing.Point]::new(($wa.Right - $script:form.Width - (Get-Scaled 120)), [int]($wa.Bottom - ($script:form.Height * $script:footLine)))
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    $script:moveTarget = $null
    if (@('walk', 'run', 'summon', 'fling') -contains $script:dogAct) { Stop-DogAction }
}

function Set-PetSize([int]$base) {
    # 迷你 130 / 小 180 / 一般 250 / 大 320 / 巨大 410 px at 100 % (never taller than 60 % of the screen);
    # his paws and his middle stay where they were.
    $script:baseSize = $base
    foreach ($item in $script:sizeMenuItems) { $item.Checked = ([int]$item.Tag -eq $base) }
    $size = Get-Scaled $base
    $fit = [Math]::Max(60, [int]((Get-DogScreen).WorkingArea.Height * 0.6))
    $script:sizeCapped = ($size -gt $fit)
    if ($script:sizeCapped) { $size = $fit }
    $script:sizeRatio = [double]$size / [double](Get-Scaled 250)
    $old = [double]$script:form.Width
    if ($size -ne $script:form.Width) {
        $centerX = [double]$script:baseLocation.X + ($old * 0.5)
        $feetY = [double]$script:baseLocation.Y + ($old * $script:footLine)
        $script:form.Size = [System.Drawing.Size]::new($size, $size)
        $script:pic.Size = $script:form.ClientSize
        $script:baseLocation = Get-ClampedSpot ($centerX - ($size * 0.5)) ($feetY - ($size * $script:footLine)) $true
        $script:posX = [double]$script:baseLocation.X
        $script:posY = [double]$script:baseLocation.Y
        $script:form.Location = $script:baseLocation
        Reset-ImageCache $size
    }
    Update-BubbleFont
    Show-PetFrame
    Save-PetSettings
}

# -----------------------------------------------------------------------------
# What 小黑 does: one state machine (see NOTES.md). $script:dogAct is the action ('' = standing idle),
# $script:dogActTick counts its ticks and $script:dogActLen ends it (0 = it ends inside its own branch).
# Every action starts with Start-DogAction, which sets the count back to 0, and $script:actSerial tells
# Update-DogAction that a new action started during this tick, so the old action's count can never end it.
# -----------------------------------------------------------------------------
function Start-DogAction([string]$name, [int]$len, [string]$say) {
    $script:dogAct = $name
    $script:dogActTick = 0
    $script:dogActLen = $len
    $script:actSerial++
    if (-not [string]::IsNullOrEmpty($say)) { Set-Bubble $say }
}

function Stop-DogAction {
    # Back to standing; the next idle action comes 6 to 15 seconds later.
    Start-DogAction '' 0 ''
    $script:nextIdleTick = $script:clockTick + $script:rng.Next($script:idleActMin, ($script:idleActMax + 1))
}

function Get-RandomLine([string[]]$lines) {
    return [string]$lines[$script:rng.Next(0, $lines.Count)]
}

function Get-MoveStep([string]$kind) {
    $speed = $script:walkSpeed
    if ($kind -eq 'run') { $speed = $script:runSpeed }
    if ($kind -eq 'summon') { $speed = $script:summonSpeed }
    return ($speed * (Get-PetUnit))
}

function Start-DogMove([string]$act, [System.Drawing.Point]$target, [string]$say) {
    # 'walk', 'run' or 'summon': step by step until the window's corner is at $target (or the time is up).
    $script:moveTarget = $target
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    $dx = [double]$target.X - $script:posX
    $dy = [double]$target.Y - $script:posY
    if ([Math]::Abs($dx) -gt 2) { $script:facingLeft = ($dx -lt 0) }
    $dist = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
    $len = [int]($dist / (Get-MoveStep $act)) + 60
    Start-DogAction $act $len $say
}

function Step-DogMove([double]$step) {
    # One step towards $script:moveTarget; $true when he is there.
    if ($null -eq $script:moveTarget) { return $true }
    if ([Math]::Abs($script:posX - $script:baseLocation.X) -gt 1.5 -or [Math]::Abs($script:posY - $script:baseLocation.Y) -gt 1.5) {
        # Moved by something else (dragged, resized): carries on from where he is now.
        $script:posX = [double]$script:baseLocation.X
        $script:posY = [double]$script:baseLocation.Y
    }
    $dx = [double]$script:moveTarget.X - $script:posX
    $dy = [double]$script:moveTarget.Y - $script:posY
    $dist = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
    if ($dist -le $step) {
        $script:posX = [double]$script:moveTarget.X
        $script:posY = [double]$script:moveTarget.Y
        $script:baseLocation = $script:moveTarget
        return $true
    }
    if ([Math]::Abs($dx) -gt 2) { $script:facingLeft = ($dx -lt 0) }
    $script:posX += ($dx / $dist) * $step
    $script:posY += ($dy / $dist) * $step
    $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($script:posX), [int][Math]::Round($script:posY))
    return $false
}

function Start-RandomDogAction {
    # Standing idle for a while: a weighted pick. Shy and sleepy, so sitting, lying down and yawning come up
    # more often than running; walking and running only with 自由走動.
    $pool = @(@('sit', 18), @('lie', 16), @('yawn', 12), @('sniff', 10), @('tilt', 8), @('face', 10))
    if ($script:roamEnabled) {
        $pool += , @('walk', 28)
        $pool += , @('run', 5)
    }
    $total = 0
    foreach ($entry in $pool) { $total += [int]$entry[1] }
    $roll = $script:rng.Next(0, $total)
    $pick = 'sit'
    foreach ($entry in $pool) {
        $roll -= [int]$entry[1]
        if ($roll -lt 0) {
            $pick = [string]$entry[0]
            break
        }
    }
    # A shy dog: says something only now and then.
    $talk = ($script:rng.Next(0, 100) -lt 35)
    $say = ''
    switch ($pick) {
        'walk' { Start-DogMove 'walk' (Get-RandomSpot $false) '' }
        'run' { Start-DogMove 'run' (Get-RandomSpot $true) '' }
        'sit' {
            if ($talk) { $say = Get-RandomLine @('坐一下～', '乖乖坐好～') }
            Start-DogAction 'sit' ($script:rng.Next(70, 170)) $say
        }
        'lie' {
            if ($talk) { $say = Get-RandomLine @('趴一下…', '好舒服～') }
            Start-DogAction 'lie' ($script:rng.Next(100, 250)) $say
        }
        'yawn' {
            if ($talk) { $say = Get-RandomLine @('哈～啊…', '好睏喔…') }
            Start-DogAction 'yawn' 24 $say
        }
        'sniff' {
            if ($talk) { $say = '嗅嗅…' }
            Start-DogAction 'sniff' 50 $say
        }
        'tilt' { Start-DogAction 'tilt' 26 '？' }
        'face' {
            # Turns towards you (the mouse pointer) and keeps standing.
            Set-DogFacingCursor
            $script:nextIdleTick = $script:clockTick + $script:rng.Next(60, 140)
        }
    }
}

function Start-MenuAction([string]$act) {
    # 動作 menu: does it now (an asleep 小黑 just gets up and does it).
    $script:lastInteractTick = $script:clockTick
    $script:moveTarget = $null
    switch ($act) {
        'sit' { Start-DogAction 'sit' 220 (Get-RandomLine @('坐好了！', '乖乖坐下～')) }
        'lie' { Start-DogAction 'lie' 280 (Get-RandomLine @('趴一下～', '好舒服～')) }
        'yawn' { Start-DogAction 'yawn' 26 '哈～啊～' }
        'tilt' { Start-DogAction 'tilt' 30 '？' }
        'sniff' { Start-DogAction 'sniff' 60 '嗅嗅…' }
        'run' { Start-DogMove 'run' (Get-RandomSpot $true) '跑一跑～' }
        'cuddle' { Start-DogCuddle $false '嗚～摸摸我嘛～' }
    }
}

function Start-DogChase {
    # 追滑鼠: follows the pointer for as long as it is switched on.
    $script:chaseSitting = $false
    $script:chaseRun = $false
    $script:chaseSitTick = 0
    Start-DogAction 'chase' 0 ''
}

function Invoke-DogSummon {
    # 叫小黑過來 (menu, the tray icon, a second START_Black.cmd): runs to the mouse pointer on his own screen;
    # on another screen he appears right next to it.
    if ($script:isDragging) { return }
    $script:lastInteractTick = $script:clockTick
    # Back in front of the other windows (switched off and on again, so Windows puts him on top once more).
    $script:form.TopMost = -not $script:topMostWanted
    $script:form.TopMost = $true
    $script:form.TopMost = $script:topMostWanted
    $cur = [System.Windows.Forms.Cursor]::Position
    $curScreen = [System.Windows.Forms.Screen]::FromPoint($cur)
    if ((Get-DogScreen).DeviceName -ne $curScreen.DeviceName) {
        $script:baseLocation = [System.Drawing.Point]::new([int]($cur.X - ($script:form.Width * 0.5)), [int]($cur.Y - ($script:form.Height * 0.5)))
        $script:baseLocation = Get-CursorSpot
        $script:posX = [double]$script:baseLocation.X
        $script:posY = [double]$script:baseLocation.Y
        $script:form.Location = $script:baseLocation
        Set-DogFacingCursor
        Start-DogAction 'happy' 30 (Get-RandomLine @('汪！我在這裡～', '找我嗎？汪！'))
        return
    }
    $say = Get-RandomLine @('來了來了！', '汪！馬上到～')
    if ($script:dogAct -eq 'sleep') { $say = '汪…？來了來了！' }
    Start-DogMove 'summon' (Get-CursorSpot) $say
}

function Start-DogSleep([string]$kind, [string]$say) {
    # $kind: 'menu' = until woken, 'idle' = nobody around (a nap of 20 to 40 minutes), 'night' = until 06:00.
    # First a yawn and sitting down, then lying down, then one of the four sleeping poses.
    $poses = @('sleep_00', 'curl_00', 'sidesleep_00', 'belly_00')
    $script:sleepPose = [string]$poses[$script:rng.Next(0, $poses.Count)]
    $script:sleepKind = $kind
    $script:sleepUntil = 0
    if ($kind -eq 'idle') { $script:sleepUntil = $script:clockTick + $script:rng.Next(20000, 40001) }
    # Already lying down: no yawn and no sitting first.
    $script:sleepYawn = 20
    $sitTicks = 4
    if ($script:dogAct -eq 'lie' -or $script:dogAct -eq 'rub') {
        $script:sleepYawn = 0
        $sitTicks = 0
    }
    $script:sleepSettle = $script:sleepYawn + $sitTicks + 20
    $script:zzzCountdown = 90
    $script:moveTarget = $null
    Start-DogAction 'sleep' 0 $say
}

function Stop-DogSleep([string]$say) {
    # Woken up by you: lifts his head, gets up with a big yawn, then he is happy to see you.
    if ($script:dogAct -ne 'sleep') { return }
    $script:wakeHappy = $true
    Start-DogAction 'wake' 46 $say
}

function Start-DogCuddle([bool]$byHover, [string]$say) {
    # 撒嬌: ears back, eyes squinting, head low, the tail swaying slowly. Keep petting and he rolls over.
    $script:cuddleHoverTicks = 0
    $script:cuddleMinTicks = 70
    if ($byHover) { $script:cuddleMinTicks = 0 }
    $script:moveTarget = $null
    Add-DogMood 1
    Start-DogAction 'cuddle' 0 $say
}

function Test-PointerOnDog([bool]$lenient) {
    # Is the mouse pointer on 小黑? Strict: on a solid pixel of his picture and not behind another window.
    # Lenient (while he cuddles or lies on his back): anywhere on his body area, because his pose changes.
    $cur = [System.Windows.Forms.Cursor]::Position
    $p = $script:form.PointToClient($cur)
    $w = $script:form.ClientSize.Width
    $h = $script:form.ClientSize.Height
    if ($p.X -lt 0 -or $p.Y -lt 0 -or $p.X -ge $w -or $p.Y -ge $h) { return $false }
    if ($lenient) {
        $fx = [double]$p.X / [double]$w
        $fy = [double]$p.Y / [double]$h
        return ($fx -ge 0.1 -and $fx -le 0.9 -and $fy -ge $script:bodyTop -and $fy -le 0.94)
    }
    $bmp = $script:dogBitmap
    if ($null -eq $bmp) { return $false }
    if ($p.X -ge $bmp.Width -or $p.Y -ge $bmp.Height) { return $false }
    if ($bmp.GetPixel($p.X, $p.Y).A -eq 0) { return $false }
    if ($script:nativeOk) {
        $packed = ([long]$cur.Y -shl 32) -bor ([long]$cur.X -band 0xFFFFFFFFL)
        $under = [XiaoheiPet.Native]::WindowFromPoint($packed)
        if ([XiaoheiPet.Native]::GetAncestor($under, 2) -ne $script:form.Handle) { return $false }
    }
    return $true
}

function Update-DogHover([int]$step) {
    # The pointer resting on 小黑: 撒嬌 after 0.8 s. It counts as attention.
    $lenient = ($script:dogAct -eq 'cuddle' -or $script:dogAct -eq 'rub')
    $script:hoverOn = Test-PointerOnDog $lenient
    if (-not $script:hoverOn) {
        $script:hoverTicks = 0
        $script:hoverOffTicks += $step
        return
    }
    $script:hoverTicks += $step
    $script:hoverOffTicks = 0
    $script:lastInteractTick = $script:clockTick
    if ($script:hoverTicks -lt $script:hoverCuddleTicks) { return }
    if ($script:dogAct -eq 'sleep') {
        if (($script:clockTick - $script:sleepHintTick) -ge 170) {
            $script:sleepHintTick = $script:clockTick
            Set-Bubble 'Zzz…（點一下叫醒小黑）'
        }
        return
    }
    if ($script:cuddleFrom -contains $script:dogAct) {
        Start-DogCuddle $true (Get-RandomLine @('♥', '嗚～再摸一下', '嗯～好舒服…'))
    }
}

function Invoke-DogClick {
    # A click (pressed and let go without moving): a pat.
    switch ($script:dogAct) {
        'sleep' {
            Add-DogMood 1
            Stop-DogSleep (Get-RandomLine @('汪…？小黑醒來了…', '嗯…？是你啊～'))
            return
        }
        'wake' { return }
        'cuddle' {
            Add-DogMood 1
            Set-Bubble '♥'
            return
        }
        'rub' {
            $script:wriggleTicks = 14
            Add-DogMood 1
            Set-Bubble (Get-RandomLine @('嘿嘿～好癢喔！', '再摸摸肚肚～♥'))
            return
        }
    }
    Add-DogMood 2
    Start-DogAction 'happy' 26 (Get-RandomLine @('汪！', '汪汪！', '嘿嘿～', '小黑最喜歡你了！', '再摸一下～'))
}

# -----------------------------------------------------------------------------
# Carrying and throwing (the left mouse button on 小黑)
# -----------------------------------------------------------------------------
function Start-DogPress {
    # Left button pressed on 小黑: a click, or the start of carrying him.
    $cur = [System.Windows.Forms.Cursor]::Position
    $script:isDragging = $true
    $script:dragMoved = $false
    $script:dragStart = $cur
    $script:dragGrab = [System.Drawing.Point]::new(($cur.X - $script:form.Left), ($cur.Y - $script:form.Top))
    $script:dragTrail.Clear()
    $script:hoverTicks = 0
    $script:lastInteractTick = $script:clockTick
}

function Update-DogPress {
    # The mouse moves with the button held: past a few pixels 小黑 is lifted and follows the pointer.
    $cur = [System.Windows.Forms.Cursor]::Position
    if (-not $script:dragMoved) {
        $moved = [Math]::Abs($cur.X - $script:dragStart.X) + [Math]::Abs($cur.Y - $script:dragStart.Y)
        if ($moved -lt $script:dragThreshold) { return }
        $script:dragMoved = $true
        $script:moveTarget = $null
        Start-DogAction 'drag' 0 (Get-RandomLine @('放我下來啦…', '哇…好高…', '放、放我下來…'))
    }
    $ms = $script:clock.ElapsedMilliseconds
    [void]$script:dragTrail.Add(@($ms, $cur.X, $cur.Y))
    while ($script:dragTrail.Count -gt 2 -and ($ms - [long]$script:dragTrail[0][0]) -gt 250) { $script:dragTrail.RemoveAt(0) }
    $script:baseLocation = [System.Drawing.Point]::new(($cur.X - $script:dragGrab.X), ($cur.Y - $script:dragGrab.Y))
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    $script:form.Location = $script:baseLocation
    $script:lastInteractTick = $script:clockTick
}

function Get-DragVelocity {
    # Speed of the pointer (pixels per 60 ms tick) over the last ~80 ms before letting go; 0 when it was held still.
    $n = $script:dragTrail.Count
    if ($n -lt 2) { return , @(0.0, 0.0) }
    $last = $script:dragTrail[$n - 1]
    if (($script:clock.ElapsedMilliseconds - [long]$last[0]) -gt 100) { return , @(0.0, 0.0) }
    $first = $script:dragTrail[$n - 2]
    for ($i = $n - 2; $i -ge 0; $i--) {
        $first = $script:dragTrail[$i]
        if (([long]$last[0] - [long]$first[0]) -ge 80) { break }
    }
    $spanMs = [double]([long]$last[0] - [long]$first[0])
    if ($spanMs -lt 15) { return , @(0.0, 0.0) }
    $vx = (([double]$last[1] - [double]$first[1]) / $spanMs) * $script:tickMs
    $vy = (([double]$last[2] - [double]$first[2]) / $spanMs) * $script:tickMs
    return , @($vx, $vy)
}

function Complete-DogDrag {
    # The left button let go: a click, a gentle put-down, or a throw.
    $wasDown = $script:isDragging
    $moved = $script:dragMoved
    $script:isDragging = $false
    $script:dragMoved = $false
    if (-not $wasDown) { return }
    $script:lastInteractTick = $script:clockTick
    if (-not $moved) {
        Invoke-DogClick
        return
    }
    $v = Get-DragVelocity
    $vx = [double]$v[0]
    $vy = [double]$v[1]
    if ([Math]::Sqrt(($vx * $vx) + ($vy * $vy)) -gt ($script:flingMinSpeed * (Get-PetUnit))) {
        Start-DogFling $vx $vy
        return
    }
    # Put down gently: a short skid, then he stands (pulled back in when most of him is off the screen).
    $script:baseLocation = Get-ClampedSpot ([double]$script:baseLocation.X) ([double]$script:baseLocation.Y) $true
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    Start-DogAction 'land' 6 ''
}

function Start-DogFling([double]$vx, [double]$vy) {
    # Thrown: flies on with the speed of the pointer, slows down, bounces off the edges of the screen.
    $max = $script:flingMaxSpeed * (Get-PetUnit)
    $speed = [Math]::Sqrt(($vx * $vx) + ($vy * $vy))
    if ($speed -gt $max) {
        $vx = $vx * $max / $speed
        $vy = $vy * $max / $speed
    }
    $script:flingVX = $vx
    $script:flingVY = $vy
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    if ([Math]::Abs($vx) -gt 1) { $script:facingLeft = ($vx -lt 0) }
    Start-DogAction 'fling' 200 (Get-RandomLine @('哇啊啊～', '咿～～！', '不要丟我～'))
}

function Stop-DogFling {
    # Stopped after being thrown: stands up and says how scary that was.
    $script:flingVX = 0.0
    $script:flingVY = 0.0
    Stop-DogAction
    $script:nextIdleTick = $script:clockTick + $script:rng.Next(120, 221)
    Set-Bubble (Get-RandomLine @('嚇死小黑了…', '好可怕…不要再丟我了啦…', '頭好暈…', '嗚…小黑腿軟了…')) 60
}

# -----------------------------------------------------------------------------
# One tick of the current action
# -----------------------------------------------------------------------------
function Update-DogAction([int]$step, [bool]$menuOpen) {
    # Advances the current action and sets $script:offX / $script:offY (hop and sway, in design pixels).
    if ($menuOpen -and (@('walk', 'run', 'summon', 'chase', 'fling') -contains $script:dogAct)) {
        # The menu is open: he waits where he is, and so does his count.
        $script:offX = 0.0
        $script:offY = 0.0
        return
    }
    $script:dogActTick += $step
    $t = $script:dogActTick
    $serial = $script:actSerial
    $script:offX = 0.0
    $script:offY = 0.0
    if ($script:dogAct -eq '' -and -not $script:breathByFrame) {
        # No breath_00 picture: breathing as a tiny rise and fall of the window.
        $script:offY = [Math]::Sin(($script:idleTick * [Math]::PI) / $script:breathTicks) * 1.0
    }
    switch ($script:dogAct) {
        'walk' {
            if (Step-DogMove ((Get-MoveStep 'walk') * $step)) {
                Stop-DogAction
                $t = 0
                break
            }
        }
        'run' {
            if (Step-DogMove ((Get-MoveStep 'run') * $step)) {
                Stop-DogAction
                $t = 0
                break
            }
            $script:offY = @(-3.0, 0.0, -3.0, 0.0)[$t % 4]
        }
        'summon' {
            if (($t % 8) -eq 0) { $script:moveTarget = Get-CursorSpot }
            if (Step-DogMove ((Get-MoveStep 'summon') * $step)) {
                # There: a happy hop next to you.
                Set-DogFacingCursor
                Add-DogMood 1
                Start-DogAction 'happy' 30 (Get-RandomLine @('汪！找我嗎？', '來了！小黑在這裡～', '汪汪！跑過來了～'))
                $t = 0
                break
            }
            $script:offY = @(-3.0, 0.0, -3.0, 0.0)[$t % 4]
        }
        'chase' {
            if (-not $script:chaseEnabled) {
                Stop-DogAction
                $t = 0
                break
            }
            $spot = Get-CursorSpot
            $w = [double]$script:form.Width
            $dx = [double]$spot.X - [double]$script:baseLocation.X
            $dy = [double]$spot.Y - [double]$script:baseLocation.Y
            $dist = [Math]::Sqrt(($dx * $dx) + ($dy * $dy))
            if ($script:chaseSitting -and $dist -gt ($w * 0.6)) { $script:chaseSitting = $false }
            if ($script:chaseSitting) { break }
            if ($dist -le ($w * 0.1)) {
                # Caught up: sits down next to the pointer and wags.
                $script:chaseSitting = $true
                $script:chaseSitTick = $t
                Set-DogFacingCursor
                break
            }
            # Runs when the pointer is far away, walks when it is near.
            if ($dist -gt ($w * 2.5)) { $script:chaseRun = $true } elseif ($dist -lt ($w * 1.2)) { $script:chaseRun = $false }
            $kind = 'walk'
            if ($script:chaseRun) { $kind = 'run' }
            $script:moveTarget = $spot
            $script:lastChaseMoveTick = $script:clockTick
            [void](Step-DogMove ((Get-MoveStep $kind) * $step))
            if ($script:chaseRun) { $script:offY = @(-3.0, 0.0, -3.0, 0.0)[$t % 4] }
        }
        'sit' { $script:offY = [Math]::Sin($script:clockTick / 12.0) * 0.8 }
        'lie' { $script:offY = [Math]::Sin($script:clockTick / 12.0) * 0.8 }
        'happy' {
            if ($t -lt 16) { $script:offY = [Math]::Abs([Math]::Sin($t / 1.3)) * -10.0 }
        }
        'cuddle' {
            $script:offY = [Math]::Sin($t / 6.0) * 1.0
            if ($menuOpen) { break }
            if ($script:hoverOn) {
                $script:cuddleHoverTicks += $step
                if ($script:cuddleHoverTicks -ge $script:hoverRubTicks) {
                    # Still being petted: rolls over onto his back for a belly rub.
                    Add-DogMood 1
                    Start-DogAction 'rub' 0 (Get-RandomLine @('嘿嘿～摸肚肚～', '翻肚肚給你摸～♥'))
                    $t = 0
                }
            } elseif ($script:hoverOffTicks -ge $script:hoverLeaveTicks -and $t -ge $script:cuddleMinTicks) {
                # The hand is gone: stands up again (sometimes still happy).
                if ($script:affection -ge 50 -and $script:rng.Next(0, 2) -eq 0) { Start-DogAction 'happy' 22 '' } else { Stop-DogAction }
                $t = 0
            }
        }
        'rub' {
            if ($script:wriggleTicks -gt 0) {
                $script:wriggleTicks -= $step
                $script:offX = [Math]::Sin($script:wriggleTicks / 1.4) * 3.0
            }
            if (-not $menuOpen -and -not $script:hoverOn -and $script:hoverOffTicks -ge $script:hoverLeaveTicks) {
                # The hand is gone: rolls back and gets up (happy when he likes you).
                $script:getupHappy = ($script:affection -ge 40)
                Start-DogAction 'getup' 28 ''
                $t = 0
            }
        }
        'getup' {
            if ($script:getupHappy -and $t -ge 9 -and $t -lt 23) { $script:offY = [Math]::Abs([Math]::Sin(($t - 9) / 1.3)) * -8.0 }
        }
        'sleep' {
            $pre = $t - $script:sleepSettle
            if ($pre -lt 0) { break }
            $script:offY = [Math]::Sin($script:clockTick / 14.0) * 1.2
            $script:zzzCountdown -= $step
            if ($script:zzzCountdown -le 0) {
                $script:zzzCountdown = $script:rng.Next(180, 330)
                if (-not $script:bubble.Visible) { Set-Bubble (Get-RandomLine @('Zzz…', 'Zzz… Zzz…', '呼…呼…')) }
            }
            if ($script:sleepKind -eq 'idle' -and $script:sleepUntil -gt 0 -and $script:clockTick -ge $script:sleepUntil) {
                # The nap is over: wakes up by himself (a yawn, no hop: nobody is there).
                $script:napAllowedAt = $script:clockTick + $script:rng.Next(6000, 12001)
                $script:wakeHappy = $false
                Start-DogAction 'wake' 32 ''
                $t = 0
            }
        }
        'wake' {
            if ($script:wakeHappy -and $t -ge 26 -and $t -lt 40) { $script:offY = [Math]::Abs([Math]::Sin(($t - 26) / 1.3)) * -9.0 }
        }
        'fling' {
            $b = Get-RoamBounds $true
            $nx = $script:posX + ($script:flingVX * $step)
            $ny = $script:posY + ($script:flingVY * $step)
            # Bounces off the edges of the work area, losing some speed.
            if ($nx -lt [double]$b[0]) {
                $nx = [double]$b[0]
                $script:flingVX = [Math]::Abs($script:flingVX) * $script:flingBounce
            }
            if ($nx -gt [double]$b[1]) {
                $nx = [double]$b[1]
                $script:flingVX = (0.0 - [Math]::Abs($script:flingVX)) * $script:flingBounce
            }
            if ($ny -lt [double]$b[2]) {
                $ny = [double]$b[2]
                $script:flingVY = [Math]::Abs($script:flingVY) * $script:flingBounce
            }
            if ($ny -gt [double]$b[3]) {
                $ny = [double]$b[3]
                $script:flingVY = (0.0 - [Math]::Abs($script:flingVY)) * $script:flingBounce
            }
            $script:posX = $nx
            $script:posY = $ny
            $script:baseLocation = [System.Drawing.Point]::new([int][Math]::Round($nx), [int][Math]::Round($ny))
            $keep = [Math]::Pow($script:flingFriction, $step)
            $script:flingVX = $script:flingVX * $keep
            $script:flingVY = $script:flingVY * $keep
            if ([Math]::Abs($script:flingVX) -gt 1.0) { $script:facingLeft = ($script:flingVX -lt 0) }
            $speed = [Math]::Sqrt(($script:flingVX * $script:flingVX) + ($script:flingVY * $script:flingVY))
            if ($speed -lt ($script:flingStopSpeed * (Get-PetUnit))) {
                Stop-DogFling
                $t = 0
            }
        }
    }
    # The end of an action by its length (never when a new action has just started in this tick).
    if ($serial -eq $script:actSerial -and $script:dogActLen -gt 0 -and $script:dogActTick -ge $script:dogActLen) {
        if ($script:dogAct -eq 'fling') { Stop-DogFling } else { Stop-DogAction }
    }
}

function Update-IdleAnimation([int]$step) {
    # Blinks every 3 to 6 seconds; the tail wags now and then (more often the happier he is).
    if ($script:blinkTicks -gt 0) {
        $script:blinkTicks -= $step
    } else {
        $script:blinkCountdown -= $step
        if ($script:blinkCountdown -le 0) {
            $script:blinkTicks = $script:blinkLen
            $script:blinkCountdown = $script:rng.Next(50, 101)
        }
    }
    if ($script:wagTicks -gt 0) {
        $script:wagTicks -= $step
        $script:wagPhase += $step
        return
    }
    $script:wagCountdown -= $step
    if ($script:wagCountdown -gt 0) { return }
    $script:wagTicks = 16
    $script:wagPhase = 0
    if ($script:affection -ge 80) { $script:wagCountdown = $script:rng.Next(40, 90) }
    elseif ($script:affection -ge 50) { $script:wagCountdown = $script:rng.Next(70, 140) }
    else { $script:wagCountdown = $script:rng.Next(110, 220) }
}

function Update-DogIdle([bool]$menuOpen) {
    # Standing idle (or sitting next to the pointer while chasing it): time to sleep, to chase or to do something?
    if ($menuOpen -or $script:isDragging) { return }
    $idleFor = $script:clockTick - [Math]::Max($script:lastInteractTick, $script:lastChaseMoveTick)
    if ($script:nightSleepEnabled -and $script:isNight -and $idleFor -gt $script:nightAwakeTicks) {
        Start-DogSleep 'night' (Get-RandomLine @('好睏喔…小黑要睡覺了，晚安～', '哈～啊…晚安…'))
        return
    }
    if ($script:idleSleepEnabled -and $idleFor -gt $script:idleSleepTicks -and $script:clockTick -ge $script:napAllowedAt) {
        Start-DogSleep 'idle' (Get-RandomLine @('都沒人理小黑…好睏喔…', '哈～啊…小黑睡一下…'))
        return
    }
    if ($script:dogAct -ne '') { return }
    if ($script:chaseEnabled) {
        Start-DogChase
        return
    }
    if ($script:clockTick -ge $script:nextIdleTick) { Start-RandomDogAction }
}

function Get-IdleFrameName {
    # Standing: breathing (stand_00 / breath_00), a tail wag now and then, and blinks that match the tail.
    $tail = 0
    if ($script:wagTicks -gt 0) { $tail = @(0, 1, 0, 2)[([int][Math]::Floor($script:wagPhase / 2)) % 4] }
    if ($script:blinkTicks -gt 0) { return ('blink_0' + $tail) }
    if ($tail -gt 0) { return ('stand_0' + $tail) }
    if ($script:breathByFrame -and ($script:idleTick % (2 * $script:breathTicks)) -ge $script:breathTicks) { return 'breath_00' }
    return 'stand_00'
}

function Get-DogFrameName {
    # The picture for this tick (a name of $script:frameChainBase; Get-FramePath finds the file).
    $t = $script:dogActTick
    $wag = @(0, 1, 0, 2)
    $paddle = @(0, 1, 2, 1)
    switch ($script:dogAct) {
        'walk' { return ('walk_0' + (([int][Math]::Floor($t / 2)) % 8)) }
        'run' { return ('run_0' + ($t % 4)) }
        'summon' { return ('run_0' + ($t % 4)) }
        'chase' {
            if (-not $script:chaseSitting) {
                if ($script:chaseRun) { return ('run_0' + ($t % 4)) }
                return ('walk_0' + (([int][Math]::Floor($t / 2)) % 8))
            }
            $since = $t - $script:chaseSitTick
            if ($since -lt 18) { return ('stand_0' + $wag[$since % 4]) }
            return 'sit_00'
        }
        'sit' { return 'sit_00' }
        'lie' {
            if ($t -lt 4 -or $t -ge ($script:dogActLen - 4)) { return 'sit_00' }
            return 'lie_00'
        }
        'yawn' {
            if ($t -ge 2 -and $t -lt ($script:dogActLen - 2)) { return 'yawn_00' }
            return 'stand_00'
        }
        'tilt' {
            if ($t -ge 2 -and $t -lt ($script:dogActLen - 2)) { return 'tilt_00' }
            return 'stand_00'
        }
        'sniff' {
            if ($t -lt 3 -or $t -ge ($script:dogActLen - 3)) { return 'sniff_00' }
            return ('sniff_0' + ((([int][Math]::Floor($t / 4)) + 1) % 2))
        }
        'happy' { return ('happy_0' + $wag[$t % 4]) }
        'cuddle' { return ('cuddle_0' + (([int][Math]::Floor($t / 8)) % 2)) }
        'rub' { return 'rub_00' }
        'getup' {
            if ($t -lt 6) { return 'lie_00' }
            if ($t -lt 9) { return 'sit_00' }
            if ($script:getupHappy) { return ('happy_0' + $wag[$t % 4]) }
            return 'stand_00'
        }
        'sleep' {
            if ($t -lt $script:sleepYawn) {
                if ($t -ge 2 -and $t -lt ($script:sleepYawn - 2)) { return 'yawn_00' }
                return 'stand_00'
            }
            if ($script:sleepYawn -gt 0 -and $t -lt ($script:sleepYawn + 4)) { return 'sit_00' }
            $pre = $t - $script:sleepSettle
            if ($pre -lt 0) { return 'lie_00' }
            # Belly up: rolls over his side first.
            if ($script:sleepPose -eq 'belly_00' -and $pre -lt 6) { return 'sidesleep_00' }
            return $script:sleepPose
        }
        'wake' {
            if ($t -lt 6) { return 'lie_00' }
            if ($t -lt 10) { return 'sit_00' }
            if ($t -lt 26) { return 'yawn_00' }
            if ($script:wakeHappy) { return ('happy_0' + $wag[$t % 4]) }
            return 'stand_00'
        }
        'drag' { return ('drag_0' + $paddle[([int][Math]::Floor($script:clockTick / 2)) % 4]) }
        'fling' {
            $speed = [Math]::Sqrt(($script:flingVX * $script:flingVX) + ($script:flingVY * $script:flingVY))
            if ($speed -gt ($script:flingSlideSpeed * (Get-PetUnit))) { return ('drag_0' + $paddle[([int][Math]::Floor($script:clockTick / 2)) % 4]) }
            return 'slide_00'
        }
        'land' { return 'slide_00' }
    }
    return (Get-IdleFrameName)
}

function Show-PetFrame {
    # The window's place (with the hop) and the picture for this tick.
    $u = Get-PetUnit
    $x = $script:baseLocation.X + [int][Math]::Round($script:offX * $u)
    $y = $script:baseLocation.Y + [int][Math]::Round($script:offY * $u)
    $loc = [System.Drawing.Point]::new($x, $y)
    if ($script:form.Location -ne $loc) { $script:form.Location = $loc }
    Set-DisplayImage (Get-FramePath (Get-DogFrameName))
    if ($script:bubble.Visible) { Update-BubblePlace }
}

function Update-SlowChecks {
    # Every 3 seconds: night or day, mood, pictures OneDrive was still downloading, still on a screen,
    # missing pictures that may have arrived (every 30 s), and the daily check for a new version.
    $script:isNight = Test-NightTime
    if ($script:dogAct -eq 'sleep') {
        if ($script:sleepKind -eq 'night' -and -not $script:isNight) {
            Stop-DogSleep '早安！小黑睡飽了～'
        } elseif ($script:sleepKind -eq 'idle' -and $script:isNight -and $script:nightSleepEnabled) {
            # A nap that runs into the night becomes the night's sleep.
            $script:sleepKind = 'night'
            $script:sleepUntil = 0
        }
    }
    try { Update-DogMood } catch { Write-PetError '心情' $_ }
    Update-BadPictures
    if (-not $script:isDragging) { Assert-OnScreen }
    if ($script:missingCount -gt 0 -and $script:clockTick -ge $script:nextFrameScan) {
        $script:nextFrameScan = $script:clockTick + 500
        $before = $script:missingCount
        try {
            Import-DogPictures $false
            if ($script:missingCount -lt $before) { Update-WarmList }
        } catch { Write-PetError '圖片清單' $_ }
    }
    if ($script:updAuto -and $null -eq $script:updProc -and $script:clockTick -ge 500 -and ((Get-Date) - $script:updLast).TotalHours -ge 24) {
        try {
            Start-UpdWorker 'check' $false
        } catch {
            $script:updLast = Get-Date
            Write-PetError '自動檢查更新' $_
        }
    }
}

function Update-PetTick {
    # One animation tick: 60 ms (240 ms while fast asleep; then it counts as 4 ticks).
    $script:tickAcc += [double]$script:timer.Interval / [double]$script:tickMs
    $step = [int][Math]::Floor($script:tickAcc + 0.0001)
    if ($step -lt 1) { return }
    $script:tickAcc -= $step
    $script:clockTick += $step
    $script:idleTick += $step
    $menuOpen = [bool]$script:cms.Visible
    if ($script:bubbleTicks -gt 0) {
        $script:bubbleTicks -= $step
        if ($script:bubbleTicks -le 0) { $script:bubble.Visible = $false }
    }
    # A second START_Black.cmd asked 小黑 to come over.
    if ($null -ne $script:summonEvent -and $script:summonEvent.WaitOne(0)) { Invoke-DogSummon }
    # The left button was let go where this window did not hear it (another window took the mouse).
    if ($script:isDragging -and [System.Windows.Forms.Control]::MouseButtons -eq [System.Windows.Forms.MouseButtons]::None) { Complete-DogDrag }
    if ($script:clockTick -ge $script:nextSlowCheck) {
        $script:nextSlowCheck = $script:clockTick + 50
        Update-SlowChecks
    }
    Update-IdleAnimation $step
    if (-not $script:isDragging -and -not $menuOpen) { Update-DogHover $step }
    Update-DogAction $step $menuOpen
    if ($script:dogAct -eq '' -or ($script:dogAct -eq 'chase' -and $script:chaseSitting)) { Update-DogIdle $menuOpen }
    Show-PetFrame
    Update-WarmPictures
    # Power saving: fast asleep and nobody near him = 4 updates a second instead of 16.
    $calm = ($script:dogAct -eq 'sleep' -and ($script:dogActTick - $script:sleepSettle) -ge 30 -and -not $script:isDragging -and -not $script:hoverOn -and -not $menuOpen)
    $want = $script:tickMs
    if ($calm) { $want = 4 * $script:tickMs }
    if ($script:timer.Interval -ne $want) { $script:timer.Interval = $want }
    # The update helper's result comes last, because it may ask a question.
    if ($null -ne $script:updProc -and $script:clockTick -ge $script:nextUpdWatch) {
        $script:nextUpdWatch = $script:clockTick + 16
        Update-UpdWatch
    }
}

# -----------------------------------------------------------------------------
# Menus
# -----------------------------------------------------------------------------
function New-MenuIcon([int]$code, [int]$cr, [int]$cg, [int]$cb, [double]$scale) {
    # A small picture in front of a menu name: one symbol of the Windows emoji font, in one colour.
    try {
        $sz = [Math]::Max(16, [int](Get-Scaled 16))
        $bmp = [System.Drawing.Bitmap]::new($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gr = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $gr.Clear([System.Drawing.Color]::Transparent)
            $gr.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
            $font = [System.Drawing.Font]::new('Segoe UI Emoji', [float]($sz * $scale), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
            $br = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, $cr, $cg, $cb))
            $sf = [System.Drawing.StringFormat]::new()
            try {
                $sf.Alignment = [System.Drawing.StringAlignment]::Center
                $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
                $gr.DrawString([char]::ConvertFromUtf32($code), $font, $br, [System.Drawing.RectangleF]::new(0, 0, [float]$sz, [float]$sz), $sf)
            } finally {
                $sf.Dispose()
                $br.Dispose()
                $font.Dispose()
            }
        } finally {
            $gr.Dispose()
        }
        return $bmp
    } catch {
        return $null
    }
}

function New-PetMenuItem([string]$text, [string]$tip, [int]$code, [int]$cr, [int]$cg, [int]$cb, [double]$scale = 0.7) {
    # A menu entry: a short name, the explanation as a tip when the mouse rests on it, and a small picture.
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    if (-not [string]::IsNullOrEmpty($tip)) { $item.ToolTipText = $tip }
    $img = New-MenuIcon $code $cr $cg $cb $scale
    if ($null -ne $img) { $item.Image = $img }
    return $item
}

function Show-AboutWindow {
    # 小黑介紹: name, version, one line about him, how to play with him, and 檢查更新.
    $nl = "`r`n"
    $f = New-Object System.Windows.Forms.Form
    $f.Text = '關於小黑'
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.ShowInTaskbar = $false
    $f.TopMost = $true
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.AutoSize = $true
    $f.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $f.BackColor = [System.Drawing.Color]::White
    $f.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 10)
    $f.Padding = [System.Windows.Forms.Padding]::new((Get-Scaled 14))
    $f.Icon = Get-PetIcon
    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true
    $row.WrapContents = $false
    $row.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $head = $null
    try { $head = New-HeadBitmap (Get-Scaled 96) } catch { $head = $null }
    if ($null -ne $head) {
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Image = $head
        $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::AutoSize
        $pb.Margin = [System.Windows.Forms.Padding]::new(0, 0, (Get-Scaled 14), 0)
        [void]$row.Controls.Add($pb)
    }
    $col = New-Object System.Windows.Forms.FlowLayoutPanel
    $col.AutoSize = $true
    $col.WrapContents = $false
    $col.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $title = New-Object System.Windows.Forms.Label
    $title.AutoSize = $true
    $title.Font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 16, [System.Drawing.FontStyle]::Bold)
    $title.Text = '小黑  ' + $script:appVersion
    [void]$col.Controls.Add($title)
    $info = New-Object System.Windows.Forms.Label
    $info.AutoSize = $true
    $info.MaximumSize = [System.Drawing.Size]::new((Get-Scaled 340), 0)
    $info.Margin = [System.Windows.Forms.Padding]::new(0, (Get-Scaled 6), 0, (Get-Scaled 12))
    $info.Text = '一隻害羞、愛睏又愛撒嬌的台灣黑狗，住在你的桌面上。' + $nl + $nl +
        '‧左鍵點一下：摸摸小黑（睡著時會叫醒他）' + $nl +
        '‧左鍵拖曳：把小黑抱起來；快速放開會把他甩出去' + $nl +
        '‧滑鼠停在小黑身上：他會撒嬌，一直摸會翻肚肚' + $nl +
        '‧右鍵：選單（動作、走動、設定）' + $nl +
        '‧左鍵點右下角的小黑圖示：叫小黑過來' + $nl + $nl +
        '不安裝任何東西、不改 Windows 設定；只有「檢查更新」時會連到 GitHub 下載小黑自己的檔案。'
    [void]$col.Controls.Add($info)
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.AutoSize = $true
    $buttons.WrapContents = $false
    $upd = New-Object System.Windows.Forms.Button
    $upd.AutoSize = $true
    $upd.Text = '檢查更新'
    $upd.Add_Click({
        param($sender, $e)
        try {
            $sender.FindForm().Close()
            Start-UpdCheckByHand
        } catch { Write-PetError '關於視窗：檢查更新' $_ }
    })
    [void]$buttons.Controls.Add($upd)
    $ok = New-Object System.Windows.Forms.Button
    $ok.AutoSize = $true
    $ok.Text = '關閉'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    [void]$buttons.Controls.Add($ok)
    [void]$col.Controls.Add($buttons)
    [void]$row.Controls.Add($col)
    [void]$f.Controls.Add($row)
    $f.AcceptButton = $ok
    $f.CancelButton = $ok
    try {
        [void]$f.ShowDialog([System.Windows.Forms.IWin32Window]$script:form)
    } finally {
        $f.Dispose()
        if ($null -ne $head) { $head.Dispose() }
    }
}

# -----------------------------------------------------------------------------
# 關於 → 檢查更新 / 自動檢查更新 (the pet side; the work itself is done by the update helper at the top of
# this file). The setting and the time of the last check are kept in settings.txt (autoupdate, lastupdatecheck).
# -----------------------------------------------------------------------------
function Get-UpdDir {
    if ([string]::IsNullOrEmpty($script:dataDir)) { return (Join-Path $env:TEMP 'BlackPet_update') }
    return (Join-Path $script:dataDir 'update')
}

function Start-UpdWorker([string]$mode, [bool]$manual) {
    # Starts this file again as a hidden helper with -UpdateMode check / download / apply.
    if ($null -ne $script:updProc -and -not $script:updProc.HasExited) {
        if ($manual) { Set-Bubble '我正在看有沒有新版本，等一下下～' }
        return
    }
    $dir = Get-UpdDir
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $updStatus = Join-Path (Get-UpdDir) 'status.txt'
    if (Test-Path -LiteralPath $updStatus) { Remove-Item -LiteralPath $updStatus -Force }
    $ps1 = Join-Path $PSScriptRoot 'BlackPet.ps1'
    $argLine = '-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "' + $ps1 + '" -UpdateMode ' + $mode + ' -UpdateDir "' + $dir + '"'
    if ($mode -eq 'apply') { $argLine += ' -WaitPid ' + $PID }
    $script:updProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WindowStyle Hidden -PassThru
    $script:updMode = $mode
    $script:updManual = $manual
    $script:nextUpdWatch = $script:clockTick + 16
}

function Start-UpdCheckByHand {
    Set-Bubble '我去 GitHub 看看有沒有新版本～'
    Start-UpdWorker 'check' $true
}

function Read-UpdStatus {
    $h = @{}
    $st = Join-Path (Get-UpdDir) 'status.txt'
    if (-not (Test-Path -LiteralPath $st)) { return $h }
    foreach ($ln in [System.IO.File]::ReadAllLines($st)) {
        $i = $ln.IndexOf('=')
        if ($i -gt 0) { $h[$ln.Substring(0, $i)] = $ln.Substring($i + 1) }
    }
    return $h
}

function Format-UpdSize([long]$b) {
    if ($b -ge 1048576) { return ('{0:0.0} MB' -f ($b / 1048576.0)) }
    return ('{0:0} KB' -f [Math]::Max(1.0, ($b / 1024.0)))
}

function Show-UpdQuestion([string]$text) {
    $r = [System.Windows.Forms.MessageBox]::Show([System.Windows.Forms.IWin32Window]$script:form, $text, '小黑檢查更新',
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Update-UpdWatch {
    # Called from the clock: progress while downloading, and what to do when the helper has finished.
    if ($null -eq $script:updProc) { return }
    $nl = "`r`n"
    if (-not $script:updProc.HasExited) {
        if ($script:updMode -eq 'download') {
            $h = Read-UpdStatus
            if ([string]$h['state'] -eq 'downloading') {
                try { $script:trayIcon.Text = ('小黑下載新版中 ' + [string]$h['done'] + '/' + [string]$h['count']) } catch { }
            }
        }
        return
    }
    $script:updProc = $null
    try { $script:trayIcon.Text = $script:trayText } catch { }
    $h = Read-UpdStatus
    $state = [string]$h['state']
    $ver = [string]$h['version']
    if ($script:updMode -eq 'check' -or $script:updMode -eq 'download') {
        $script:updLast = Get-Date
        Save-PetSettings
    }
    if ($state -eq 'uptodate') {
        if ($script:updManual) { Set-Bubble ('已經是最新版了（' + $script:appVersion + '）！汪～') 60 }
        return
    }
    if ($state -eq 'available') {
        $size = Format-UpdSize ([long]$h['bytes'])
        if (-not $script:updManual) {
            Set-Bubble ('小黑有新版本 ' + $ver + ' 了！右鍵 → 關於 → 檢查更新') 80
            try { $script:trayIcon.ShowBalloonTip(8000, '小黑有新版本', ('新版本 ' + $ver + ' 可以更新了：右鍵 → 關於 → 檢查更新'), [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
            return
        }
        $q = '有新版本 ' + $ver + ' 了（現在是 ' + $script:appVersion + '）。' + $nl
        if ($ver -eq $script:appVersion) { $q = '目前的版本 ' + $ver + ' 有些檔案跟 GitHub 上的不一樣（缺檔或舊檔）。' + $nl }
        $q += '要下載 ' + [string]$h['count'] + ' 個新的或改過的檔案（約 ' + $size + '）。' + $nl + $nl +
            '下載時小黑照常陪你，下載好會再問你要不要更新。' + $nl + '現在下載嗎？'
        if (Show-UpdQuestion $q) {
            Set-Bubble '開始下載新版本～好了會告訴你！'
            Start-UpdWorker 'download' $true
        }
        return
    }
    if ($state -eq 'ready') {
        $q = '新版本 ' + $ver + ' 下載好了（' + [string]$h['count'] + ' 個檔案）。' + $nl + $nl +
            '要現在更新嗎？小黑會先關掉，更新好會自己再開起來（大約幾秒鐘）。' + $nl +
            '只會換掉小黑自己的檔案，你的設定和心情都會留著。'
        if (Show-UpdQuestion $q) {
            Start-UpdWorker 'apply' $true
            $script:form.Close()
        } else {
            Set-Bubble '好～下次「檢查更新」再更新，下載好的檔案會先留著。' 70
        }
        return
    }
    $msg = [string]$h['msg']
    if ([string]::IsNullOrEmpty($msg)) { $msg = '沒有結果（state=' + $state + '）' }
    $null = Write-ErrorLog ('檢查更新錯誤：' + $msg)
    if ($script:updManual) { Set-Bubble '連不上 GitHub，等一下再試試～（可能是網路或公司防火牆擋住了）' 70 }
}

function Initialize-TrayIcon {
    # The icon by the clock, always shown: left click = 叫小黑過來, right click = a small menu.
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = Get-PetIcon
    $ni.Text = $script:trayText
    $ni.Add_MouseClick({
        param($sender, $e)
        try {
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Invoke-DogSummon }
        } catch { Write-PetError '右下角圖示' $_ }
    })
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Font = $script:menuFont
    $menu.ShowItemToolTips = $true
    $menu.ImageScalingSize = $script:menuIconSize
    $come = New-PetMenuItem '叫小黑過來' '小黑跑到滑鼠旁邊' 0x1F44B 210 150 60
    $come.Add_Click({
        try { Invoke-DogSummon } catch { Write-PetError '叫小黑過來' $_ }
    })
    [void]$menu.Items.Add($come)
    $quit = New-PetMenuItem '結束' '讓小黑休息（關閉程式）' 0x2716 150 60 60
    $quit.Add_Click({
        try { $script:form.Close() } catch { Write-PetError '結束' $_ }
    })
    [void]$menu.Items.Add($quit)
    $ni.ContextMenuStrip = $menu
    $ni.Visible = $true
    $script:trayIcon = $ni
}

# =============================================================================
# Start
# =============================================================================
try {
    # Only one 小黑 at a time. A second START_Black.cmd asks the first 小黑 to come over and stops quietly.
    $script:instanceMutex = [System.Threading.Mutex]::new($false, 'Local\XiaoheiBlackPet')
    $gotMutex = $false
    try { $gotMutex = $script:instanceMutex.WaitOne(0) } catch { $gotMutex = $true }
    if (-not $gotMutex) {
        try {
            $other = $null
            if ([System.Threading.EventWaitHandle]::TryOpenExisting('Local\XiaoheiBlackPet_Come', [ref]$other)) {
                [void]$other.Set()
                $other.Dispose()
            }
        } catch { }
        exit 0
    }
    $script:summonEvent = $null
    try {
        $script:summonEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, 'Local\XiaoheiBlackPet_Come')
    } catch {
        $script:summonEvent = $null
    }
    # Last safety net: anything a handler did not catch is written down instead of showing an error window.
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            $rec = $e.Exception
            if ($e.Exception -is [System.Management.Automation.IContainsErrorRecord]) { $rec = $e.Exception.ErrorRecord }
            Write-PetError '未處理的錯誤' $rec
        } catch { }
    })

    # ----- Files -----
    $script:picsDir = Join-Path $PSScriptRoot 'pics'
    $script:dataDir = ''
    try {
        $appData = [Environment]::GetFolderPath('ApplicationData')
        if (-not [string]::IsNullOrEmpty($appData)) { $script:dataDir = Join-Path $appData 'BlackPet' }
    } catch {
        $script:dataDir = ''
    }
    $script:settingsFile = ''
    $script:moodFile = ''
    if (-not [string]::IsNullOrEmpty($script:dataDir)) {
        $script:settingsFile = Join-Path $script:dataDir 'settings.txt'
        $script:moodFile = Join-Path $script:dataDir 'mood.txt'
    }
    Import-PetSettings
    Import-DogMood
    $script:moodDecayAt = (Get-Date).AddMinutes(15)

    # ----- Shared state -----
    $script:rng = [System.Random]::new()
    $script:clock = [System.Diagnostics.Stopwatch]::StartNew()
    $script:tickAcc = 0.0
    $script:clockTick = 0
    $script:idleTick = 0
    $script:tickErrors = 0
    $script:nextSlowCheck = 0
    $script:nextUpdWatch = 0
    $script:dogAct = ''
    $script:dogActTick = 0
    $script:dogActLen = 0
    $script:actSerial = 0
    $script:nextIdleTick = $script:rng.Next($script:idleActMin, ($script:idleActMax + 1))
    $script:offX = 0.0
    $script:offY = 0.0
    $script:facingLeft = $false
    $script:moveTarget = $null
    $script:posX = 0.0
    $script:posY = 0.0
    $script:chaseSitting = $false
    $script:chaseRun = $false
    $script:chaseSitTick = 0
    $script:lastChaseMoveTick = 0
    $script:lastInteractTick = 0
    $script:isNight = Test-NightTime
    $script:sleepPose = 'sleep_00'
    $script:sleepKind = ''
    $script:sleepUntil = 0
    $script:sleepYawn = 20
    $script:sleepSettle = 44
    $script:zzzCountdown = 90
    $script:sleepHintTick = -1000
    $script:napAllowedAt = 0
    $script:wakeHappy = $true
    $script:getupHappy = $false
    $script:cuddleHoverTicks = 0
    $script:cuddleMinTicks = 0
    $script:cuddleFrom = @('', 'sit', 'lie', 'yawn', 'tilt', 'sniff', 'happy', 'walk', 'run', 'chase', 'getup', 'land')
    $script:wriggleTicks = 0
    $script:blinkTicks = 0
    $script:blinkCountdown = 60
    $script:wagTicks = 0
    $script:wagPhase = 0
    $script:wagCountdown = 80
    $script:hoverOn = $false
    $script:hoverTicks = 0
    $script:hoverOffTicks = 0
    $script:isDragging = $false
    $script:dragMoved = $false
    $script:dragStart = [System.Drawing.Point]::Empty
    $script:dragGrab = [System.Drawing.Point]::Empty
    $script:dragTrail = [System.Collections.Generic.List[object]]::new()
    $script:dragThreshold = [Math]::Max((Get-Scaled 5), [System.Windows.Forms.SystemInformation]::DragSize.Width)
    $script:flingVX = 0.0
    $script:flingVY = 0.0
    $script:updProc = $null
    $script:updMode = ''
    $script:updManual = $false
    $script:petCursor = $null
    $script:petIcon = $null
    $script:trayIcon = $null
    $script:trayText = '小黑 ' + $script:appVersion
    $script:menuFont = [System.Drawing.Font]::new('Microsoft JhengHei UI', 9)
    $script:menuIconSize = [System.Drawing.Size]::new((Get-Scaled 16), (Get-Scaled 16))
    $script:sizeMenuItems = @()

    # ----- Pictures -----
    $script:frameFile = @{}
    $script:frameChain = @{}
    $script:breathByFrame = $false
    $script:missingCount = 0
    $script:nextFrameScan = 500
    $script:bmpCache = @{}
    $script:pathKey = @{}
    $script:badPaths = @{}
    $script:badRetry = @{}            # pictures OneDrive has not downloaded yet: tried again later (path → tick)
    $script:badLogged = @{}
    $script:currentImagePath = $null
    $script:alphaCutOk = $true
    $script:alphaCutTested = $false
    $script:warmList = [System.Collections.Generic.List[string]]::new()
    $script:warmIndex = 0
    $script:dogBitmap = $null
    Import-DogPictures $true

    # ----- Size (never taller than 60 % of the screen) -----
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $startSize = Get-Scaled $script:baseSize
    $fit = [Math]::Max(60, [int]($primary.Height * 0.6))
    $script:sizeCapped = ($startSize -gt $fit)
    if ($script:sizeCapped) { $startSize = $fit }
    $script:sizeRatio = [double]$startSize / [double](Get-Scaled 250)
    $script:displaySize = $startSize

    # ----- Main window: magenta is the see-through colour (no layered or half see-through windows) -----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $script:appTitle
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.ShowInTaskbar = $false
    $form.TopMost = $script:topMostWanted
    $form.BackColor = [System.Drawing.Color]::Magenta
    $form.TransparencyKey = [System.Drawing.Color]::Magenta
    $form.Size = [System.Drawing.Size]::new($startSize, $startSize)
    $script:baseLocation = [System.Drawing.Point]::new(($primary.Right - $startSize - (Get-Scaled 120)), [int]($primary.Bottom - ($startSize * $script:footLine)))
    $script:posX = [double]$script:baseLocation.X
    $script:posY = [double]$script:baseLocation.Y
    $form.Location = $script:baseLocation
    $script:form = $form
    $form.Icon = Get-PetIcon
    $form.Cursor = Get-PetCursor

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
    $pic.BackColor = [System.Drawing.Color]::Magenta
    $pic.Location = [System.Drawing.Point]::new(0, 0)
    $pic.Size = $form.ClientSize
    $pic.Cursor = $form.Cursor
    [void]$form.Controls.Add($pic)
    $script:pic = $pic

    # Speech bubble: sizes itself to the text and wraps inside the window.
    $bubble = New-Object System.Windows.Forms.Label
    $bubble.AutoSize = $true
    $bubble.BackColor = [System.Drawing.Color]::White
    $bubble.ForeColor = [System.Drawing.Color]::FromArgb(55, 45, 40)
    $bubble.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $bubble.Padding = [System.Windows.Forms.Padding]::new((Get-Scaled 4), (Get-Scaled 3), (Get-Scaled 4), (Get-Scaled 3))
    $bubble.Location = [System.Drawing.Point]::new((Get-Scaled 4), (Get-Scaled 4))
    $bubble.Visible = $false
    $bubble.Cursor = $form.Cursor
    [void]$form.Controls.Add($bubble)
    $bubble.BringToFront()
    $script:bubble = $bubble
    $script:bubbleTicks = 0
    $script:bubbleFont = $null
    Update-BubbleFont

    # The first picture (OneDrive may still be downloading it: a few tries).
    $firstPath = Get-FramePath 'stand_00'
    for ($attempt = 0; $attempt -lt 6 -and $null -eq $script:pic.Image; $attempt++) {
        try {
            $firstBmp = Get-DisplayBitmap $firstPath $false
            $script:pic.Image = $firstBmp
            $script:dogBitmap = $firstBmp
            $script:currentImagePath = $firstPath + '|R'
        } catch {
            if ($attempt -ge 5) { throw ('小黑的圖片讀不到：' + $firstPath + "`r`n" + [string]$_) }
            Start-Sleep -Milliseconds 800
        }
    }
    Update-WarmList

    # ----- Right-click menu -----
    $cms = New-Object System.Windows.Forms.ContextMenuStrip
    $cms.Font = $script:menuFont
    $cms.ShowItemToolTips = $true
    $cms.ImageScalingSize = $script:menuIconSize
    $script:cms = $cms

    $script:miMood = New-PetMenuItem ('心情 ' + (Get-DogMoodHearts)) '小黑現在的心情，點一下聽聽他怎麼說（常摸摸他、陪他玩，心情會變好）' 0x2665 215 60 90
    $script:miMood.Add_Click({
        try {
            $script:lastInteractTick = $script:clockTick
            Set-Bubble (Get-DogMoodText) 70
        } catch { Write-PetError '心情選單' $_ }
    })
    $script:miSleep = New-PetMenuItem '睡覺' '讓小黑趴下來睡覺，睡到你叫醒他' 0x1F4A4 90 90 190
    $script:miSleep.Add_Click({
        try {
            $script:lastInteractTick = $script:clockTick
            Start-DogSleep 'menu' (Get-RandomLine @('好…小黑睡一下…', '哈～啊…晚安～'))
        } catch { Write-PetError '睡覺' $_ }
    })
    $script:miWake = New-PetMenuItem '叫醒' '叫醒小黑（點他一下也可以）' 0x2600 230 150 0
    $script:miWake.Add_Click({
        try {
            $script:lastInteractTick = $script:clockTick
            Stop-DogSleep (Get-RandomLine @('嗯…？早安…', '汪…小黑醒來了！'))
        } catch { Write-PetError '叫醒' $_ }
    })

    $miActions = New-PetMenuItem '動作' '叫小黑做一個動作' 0x1F415 120 85 60
    $actionList = @(
        @('坐下', 'sit', 0x1F4BA, '小黑坐下來一會兒', 150, 100, 60),
        @('趴下', 'lie', 0x1F6CB, '小黑趴下來休息一會兒', 150, 100, 60),
        @('打哈欠', 'yawn', 0x1F62A, '小黑打一個大哈欠', 90, 90, 190),
        @('歪頭', 'tilt', 0x2753, '小黑歪著頭看你', 60, 120, 200),
        @('聞聞', 'sniff', 0x1F443, '小黑低頭聞聞地上', 150, 100, 60),
        @('跑一跑', 'run', 0x1F3C3, '小黑跑到別的地方', 60, 140, 80),
        @('撒嬌', 'cuddle', 0x1F495, '小黑撒嬌：耳朵往後、瞇著眼睛（滑鼠停在他身上一直摸，他會翻肚肚）', 215, 60, 90)
    )
    foreach ($ai in $actionList) {
        $item = New-PetMenuItem ([string]$ai[0]) ([string]$ai[3]) ([int]$ai[2]) ([int]$ai[4]) ([int]$ai[5]) ([int]$ai[6])
        $item.Tag = [string]$ai[1]
        $item.Add_Click({
            param($sender, $e)
            try { Start-MenuAction ([string]$sender.Tag) } catch { Write-PetError '動作選單' $_ }
        })
        [void]$miActions.DropDownItems.Add($item)
    }

    $miGo = New-PetMenuItem '走動' '小黑怎麼走動' 0x1F43E 120 85 60
    $miRoam = New-PetMenuItem '自由走動' '小黑會在螢幕上到處走走（關掉就待在原地，但還是會坐下、趴下、打哈欠）' 0x1F6B6 60 140 80
    $miRoam.CheckOnClick = $true
    $miRoam.Checked = $script:roamEnabled
    $miRoam.Add_Click({
        param($sender, $e)
        try {
            $script:roamEnabled = [bool]$sender.Checked
            $script:lastInteractTick = $script:clockTick
            Save-PetSettings
            if ($script:roamEnabled) {
                Set-Bubble '小黑可以到處走走了～'
            } else {
                if ($script:dogAct -eq 'walk' -or $script:dogAct -eq 'run') { Stop-DogAction }
                Set-Bubble '好，小黑待在這裡～'
            }
        } catch { Write-PetError '自由走動' $_ }
    })
    $miChase = New-PetMenuItem '追滑鼠' '小黑跟著滑鼠走：遠的時候用跑的，近的時候用走的，追到就坐下搖尾巴' 0x1F401 110 110 120
    $miChase.CheckOnClick = $true
    $miChase.Checked = $script:chaseEnabled
    $miChase.Add_Click({
        param($sender, $e)
        try {
            $script:chaseEnabled = [bool]$sender.Checked
            $script:lastInteractTick = $script:clockTick
            Save-PetSettings
            if ($script:chaseEnabled) {
                Set-Bubble '汪！來追你了～'
                if (@('sleep', 'drag', 'fling', 'chase') -notcontains $script:dogAct) { Start-DogChase }
            } else {
                if ($script:dogAct -eq 'chase') { Stop-DogAction }
                Set-Bubble '不追了，小黑自己玩～'
            }
        } catch { Write-PetError '追滑鼠' $_ }
    })
    $miCome = New-PetMenuItem '叫小黑過來' '小黑跑到滑鼠旁邊（左鍵點右下角的小黑圖示也可以）' 0x1F44B 210 150 60
    $miCome.Add_Click({
        try { Invoke-DogSummon } catch { Write-PetError '叫小黑過來' $_ }
    })
    foreach ($it in @($miRoam, $miChase, (New-Object System.Windows.Forms.ToolStripSeparator), $miCome)) { [void]$miGo.DropDownItems.Add($it) }

    $miSet = New-PetMenuItem '設定' '小黑的大小和作息' 0x2699 110 110 120
    $miSize = New-PetMenuItem '尺寸' '小黑的大小（螢幕放不下時會縮到放得下的最大尺寸）' 0x1F4CF 90 110 160
    $sizeNames = @('迷你', '小', '一般', '大', '巨大')
    $sizeIcon = @(0.4, 0.5, 0.62, 0.74, 0.88)
    for ($i = 0; $i -lt $script:sizeChoices.Count; $i++) {
        $px = [int]$script:sizeChoices[$i]
        $si = New-PetMenuItem ([string]$sizeNames[$i]) ('視窗 ' + $px + ' 像素（100% 縮放時）') 0x1F415 120 85 60 ([double]$sizeIcon[$i])
        $si.Tag = $px
        $si.Checked = ($px -eq $script:baseSize)
        $si.Add_Click({
            param($sender, $e)
            try {
                $script:lastInteractTick = $script:clockTick
                Set-PetSize ([int]$sender.Tag)
                if ($script:sizeCapped) { Set-Bubble '螢幕放不下這麼大，小黑變成放得下的最大尺寸了！' 60 } else { Set-Bubble ('小黑變成' + $sender.Text + '尺寸了！') }
            } catch { Write-PetError '尺寸' $_ }
        })
        [void]$miSize.DropDownItems.Add($si)
        $script:sizeMenuItems += $si
    }
    $miTop = New-PetMenuItem '永遠在最上層' '小黑一直顯示在其他視窗的前面' 0x1F4CC 200 60 60
    $miTop.CheckOnClick = $true
    $miTop.Checked = $script:topMostWanted
    $miTop.Add_Click({
        param($sender, $e)
        try {
            $script:topMostWanted = [bool]$sender.Checked
            $script:form.TopMost = $script:topMostWanted
            Save-PetSettings
            if ($script:topMostWanted) { Set-Bubble '小黑會一直在最上面～' } else { Set-Bubble '好，小黑可以被別的視窗蓋住' }
        } catch { Write-PetError '永遠在最上層' $_ }
    })
    $miNight = New-PetMenuItem '晚上自動睡' '晚上 11 點到早上 6 點小黑會去睡覺；被你叫醒會陪你玩一下，2 分鐘沒人理又睡回去' 0x1F319 200 160 30
    $miNight.CheckOnClick = $true
    $miNight.Checked = $script:nightSleepEnabled
    $miNight.Add_Click({
        param($sender, $e)
        try {
            $script:nightSleepEnabled = [bool]$sender.Checked
            $script:lastInteractTick = $script:clockTick
            Save-PetSettings
            if ($script:nightSleepEnabled) {
                Set-Bubble '晚上 11 點到早上 6 點小黑會乖乖睡覺～'
            } elseif ($script:dogAct -eq 'sleep' -and $script:sleepKind -eq 'night') {
                Stop-DogSleep '好～晚上也陪你！'
            } else {
                Set-Bubble '好～晚上也陪你！'
            }
        } catch { Write-PetError '晚上自動睡' $_ }
    })
    $miIdle = New-PetMenuItem '沒人理會自己睡' '大約 10 分鐘沒人點他、摸他、抱他或打開選單，小黑就打哈欠、趴下來睡覺' 0x1F634 90 90 190
    $miIdle.CheckOnClick = $true
    $miIdle.Checked = $script:idleSleepEnabled
    $miIdle.Add_Click({
        param($sender, $e)
        try {
            $script:idleSleepEnabled = [bool]$sender.Checked
            $script:lastInteractTick = $script:clockTick
            Save-PetSettings
            if ($script:idleSleepEnabled) {
                Set-Bubble '沒人理我的話，小黑就去睡覺囉～'
            } elseif ($script:dogAct -eq 'sleep' -and $script:sleepKind -eq 'idle') {
                Stop-DogSleep '不睡了！陪你玩～'
            } else {
                Set-Bubble '好，小黑不自己睡覺了！'
            }
        } catch { Write-PetError '沒人理會自己睡' $_ }
    })
    foreach ($it in @($miSize, $miTop, (New-Object System.Windows.Forms.ToolStripSeparator), $miNight, $miIdle)) { [void]$miSet.DropDownItems.Add($it) }

    $miAbout = New-PetMenuItem '關於' ('小黑桌寵 ' + $script:appVersion) 0x2139 60 110 200
    $miInfo = New-PetMenuItem ('小黑介紹（' + $script:appVersion + '）…') '小黑是誰、怎麼跟他玩' 0x1F436 120 85 60
    $miInfo.Add_Click({
        try {
            $script:lastInteractTick = $script:clockTick
            Show-AboutWindow
        } catch { Write-PetError '關於視窗' $_ }
    })
    $miUpd = New-PetMenuItem '檢查更新' '到 GitHub 看看有沒有小黑的新版本（只下載小黑自己的檔案，下載前會先問你）' 0x1F504 60 140 80
    $miUpd.Add_Click({
        try { Start-UpdCheckByHand } catch { Write-PetError '檢查更新' $_ }
    })
    $miUpdAuto = New-PetMenuItem '自動檢查更新' '每天自動看一次有沒有新版本，有的話提醒你（不會自己下載）' 0x1F4C5 60 110 200
    $miUpdAuto.CheckOnClick = $true
    $miUpdAuto.Checked = $script:updAuto
    $miUpdAuto.Add_Click({
        param($sender, $e)
        try {
            $script:updAuto = [bool]$sender.Checked
            Save-PetSettings
            if ($script:updAuto) { Set-Bubble '好～我每天會去看一次有沒有新版本！' } else { Set-Bubble '好～不自動檢查了，要更新時再按「檢查更新」。' 60 }
        } catch { Write-PetError '自動檢查更新' $_ }
    })
    foreach ($it in @($miInfo, $miUpd, $miUpdAuto)) { [void]$miAbout.DropDownItems.Add($it) }

    $miQuit = New-PetMenuItem '結束' '讓小黑休息（關閉程式）' 0x2716 150 60 60
    $miQuit.Add_Click({
        try { $script:form.Close() } catch { Write-PetError '結束' $_ }
    })

    foreach ($it in @($script:miMood, (New-Object System.Windows.Forms.ToolStripSeparator), $script:miSleep, $script:miWake,
            (New-Object System.Windows.Forms.ToolStripSeparator), $miActions, $miGo, $miSet, $miAbout,
            (New-Object System.Windows.Forms.ToolStripSeparator), $miQuit)) { [void]$cms.Items.Add($it) }
    foreach ($sub in @($miActions, $miGo, $miSet, $miSize, $miAbout)) {
        try {
            $sub.DropDown.Font = $script:menuFont
            $sub.DropDown.ShowItemToolTips = $true
            $sub.DropDown.ImageScalingSize = $script:menuIconSize
        } catch { }
    }
    # The submenus with switches show the tick in its own column, next to the pictures.
    foreach ($sub in @($miGo, $miSet, $miSize, $miAbout)) {
        try { $sub.DropDown.ShowCheckMargin = $true } catch { }
    }
    # Shown only when they can be used: 睡覺 while awake, 叫醒 while asleep. Opening the menu counts as attention.
    $cms.Add_Opening({
        param($sender, $e)
        try {
            $script:lastInteractTick = $script:clockTick
            $script:miMood.Text = '心情 ' + (Get-DogMoodHearts)
            $asleep = ($script:dogAct -eq 'sleep')
            $script:miSleep.Available = -not $asleep
            $script:miWake.Available = $asleep
        } catch { Write-PetError '選單' $_ }
    })

    # ----- Mouse: a click pats 小黑, dragging carries him, letting go fast throws him -----
    $onMouseDown = {
        param($sender, $e)
        try {
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Start-DogPress }
        } catch { Write-PetError '滑鼠按下' $_ }
    }
    $onMouseMove = {
        param($sender, $e)
        try {
            if ($script:isDragging) { Update-DogPress }
        } catch { Write-PetError '拖曳' $_ }
    }
    $onMouseUp = {
        param($sender, $e)
        try {
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Complete-DogDrag }
        } catch { Write-PetError '滑鼠放開' $_ }
    }
    foreach ($ctl in @($form, $pic, $bubble)) {
        $ctl.Add_MouseDown($onMouseDown)
        $ctl.Add_MouseMove($onMouseMove)
        $ctl.Add_MouseUp($onMouseUp)
        $ctl.ContextMenuStrip = $cms
    }

    # ----- Tray icon, animation, start and end -----
    Initialize-TrayIcon
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $script:tickMs
    $script:timer = $timer
    $timer.Add_Tick({
        try {
            Update-PetTick
            $script:tickErrors = 0
        } catch {
            $script:tickErrors++
            if ($script:tickErrors -eq 1) { Write-PetError '動畫' $_ }
            if (($script:tickErrors % 20) -eq 0) {
                # Something keeps failing: back to standing quietly (tried again every 20 failed ticks).
                $script:isDragging = $false
                try { Stop-DogAction } catch { }
            }
        }
    })
    $form.Add_Shown({
        try {
            $script:bubble.BringToFront()
            Set-Bubble '嗨…我是小黑。（右鍵點我有選單）' 80
        } catch { Write-PetError '顯示' $_ }
    })
    $form.Add_FormClosed({
        try {
            try { $script:timer.Stop() } catch { }
            try {
                if ($null -ne $script:trayIcon) {
                    $script:trayIcon.Visible = $false
                    $script:trayIcon.Dispose()
                }
            } catch { }
            try { if ($null -ne $script:summonEvent) { $script:summonEvent.Dispose() } } catch { }
            try { $script:instanceMutex.ReleaseMutex() } catch { }
        } catch { Write-PetError '關閉' $_ }
    })
    # In a OneDrive folder with Files On-Demand, pictures may be only in the cloud: asks OneDrive to keep
    # 小黑's own folder on this PC (always keep on this device). Only this folder, in the background.
    if ($PSScriptRoot -match 'OneDrive') {
        try {
            $attrib = Join-Path $env:SystemRoot 'System32\attrib.exe'
            if (Test-Path -LiteralPath $attrib) {
                Start-Process -FilePath $attrib -ArgumentList @('+P', '-U', '/S', '/D', ('"' + (Join-Path $PSScriptRoot '*') + '"')) -WindowStyle Hidden
            }
        } catch { Write-PetError 'OneDrive 保留在此裝置設定失敗' $_ }
    }
    $timer.Start()
    [System.Windows.Forms.Application]::Run($form)
}
catch {
    $msg = [string]$_ + "`r`n" + 'line ' + $_.InvocationInfo.ScriptLineNumber + "`r`n" + $_.ScriptStackTrace
    $null = Write-ErrorLog $msg -Force
    try {
        $box = '小黑無法啟動。' + "`r`n" + '請把資料夾裡最新的 BlackPet_Error_ 開頭的文字檔提供給維護的人。' + "`r`n`r`n" + $_.Exception.Message
        [void][System.Windows.Forms.MessageBox]::Show($box, '小黑桌寵 啟動錯誤', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { }
    exit 1
}
