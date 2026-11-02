# Optimize-Handheld.ps1 - Windows 10/11 debloat and tuning for handheld PCs (MSI Claw first, works on others).
# Allow-list only: it removes or changes exactly what is listed below; Xbox, Game Bar, Store and vendor tools
# are never touched. Writes a full log for fixing the script, and a state file for undo.
#
#   .\Optimize-Handheld.ps1                          Audit: report only, changes nothing
#   .\Optimize-Handheld.ps1 -Mode Apply              Apply the Standard level (asks to type YES)
#   .\Optimize-Handheld.ps1 -Mode Apply -Level Full  Standard + the extras (see $Categories)
#   .\Optimize-Handheld.ps1 -Mode Undo               Roll back the latest Apply (or -StateFile <path>)
#   -Only Apps,AI / -Skip AppsExtra                  Limit by category
#   -Yes                                             No prompt (remote runs)   -NoElevate  Audit without UAC
#
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Apply', 'Undo')][string]$Mode = 'Audit',
    [ValidateSet('Standard', 'Full')][string]$Level = 'Standard',
    [string[]]$Only,
    [string[]]$Skip,
    [string]$StateFile,
    [string]$LogDir,
    [switch]$Yes,
    [switch]$NoElevate,
    [switch]$NoRestorePoint,
    [switch]$Pause
)

$ScriptVersion = '1.0.1'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
# "-Only A,B" arrives as one string through powershell -File (the launcher and the elevated restart use it)
if ($Only) { $Only = @($Only -split ',' | Where-Object { $_ }) }
if ($Skip) { $Skip = @($Skip -split ',' | Where-Object { $_ }) }

# ------------------------------------------------------------------ what it does
# Tier 1 = Standard, tier 2 = Full only. Full is everything done on the reference Claw 8 AI+.
$Categories = [ordered]@{
    Apps          = 1  # preinstalled apps nobody needs on a handheld
    AppsExtra     = 2  # small apps some people do use: Media Player, Clock, Maps, Phone Link, Quick Assist...
    AI            = 1  # Copilot app, on-device AI packages (Recall, Click to Do...), their policies
    Policies      = 1  # suggestions, ads, Bing in Start, widgets, OneDrive auto-install
    Telemetry     = 1  # telemetry policy, DiagTrack, data collection tasks
    TelemetryExtra = 2 # compatibility appraiser and disk diagnostics tasks
    Capabilities  = 1  # legacy Windows components
    CapabilitiesExtra = 2 # WMIC (some vendor installers call it), old Windows Media Player
    UserTweaks    = 1  # per-user: suggestions, ads id, Start recommendations, widgets button
    RamTrim       = 1  # Edge preload, Cross-device Resume
    RamTrimVendor = 2  # vendor background services and autostarts; apps still open by hand. Changes audio effects!
    LoginKeyboard = 1  # touch keyboard works at the login screen (ARSO off)
}

$AppList = @{
    Apps = @('Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10', 'Microsoft.BingNews', 'Microsoft.BingWeather',
        'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.OutlookForWindows', 'Microsoft.People',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.Windows.DevHome',
        'microsoft.windowscommunicationsapps', 'Microsoft.WindowsFeedbackHub', 'MSTeams')
    AppsExtra = @('Microsoft.WindowsMaps', 'Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice',
        'MicrosoftWindows.Client.WebExperience', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
        'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftStickyNotes',
        'MicrosoftCorporationII.QuickAssist')
    AI = @('Microsoft.Copilot', 'WindowsWorkload.*')
}
# Checked after Apply: if one of these is gone, something is wrong with the list above
$MustStay = @('Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller', 'Microsoft.XboxGamingOverlay', 'Microsoft.GamingApp')

$PolicyRoot = 'HKLM\SOFTWARE\Policies\Microsoft\Windows'
$RegList = @(
    # category, key (HKLM\... or USER\...), value name, DWORD value, soft = a refusal is only a warning
    @('AI', "$PolicyRoot\WindowsCopilot", 'TurnOffWindowsCopilot', 1),
    @('AI', "$PolicyRoot\WindowsAI", 'DisableAIDataAnalysis', 1),
    @('AI', "$PolicyRoot\WindowsAI", 'DisableClickToDo', 1),
    @('AI', "$PolicyRoot\WindowsAI", 'TurnOffClickToDo', 1),
    @('AI', 'USER\Software\Policies\Google\Chrome', 'GenAILocalFoundationalModelSettings', 1),
    @('Policies', "$PolicyRoot\CloudContent", 'DisableWindowsConsumerFeatures', 1),
    @('Policies', "$PolicyRoot\CloudContent", 'DisableConsumerAccountStateContent', 1),
    @('Policies', "$PolicyRoot\CloudContent", 'DisableWindowsSpotlightFeatures', 1),
    @('Policies', "$PolicyRoot\CloudContent", 'DisableSoftLanding', 1),
    @('Policies', "$PolicyRoot\Explorer", 'DisableSearchBoxSuggestions', 1),
    @('Policies', 'HKLM\SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', 0),
    @('Policies', "$PolicyRoot\AdvertisingInfo", 'DisabledByGroupPolicy', 1),
    @('Policies', "$PolicyRoot\OneDrive", 'DisableFileSyncNGSC', 1),
    @('Telemetry', "$PolicyRoot\DataCollection", 'AllowTelemetry', 0),
    @('Telemetry', "$PolicyRoot\DataCollection", 'DoNotShowFeedbackNotifications', 1),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'FeatureManagementEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SilentInstalledAppsEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'PreInstalledAppsEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'OemPreInstalledAppsEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SoftLandingEnabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0),
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_IrisRecommendations', 0),
    # newer Windows may refuse TaskbarDa (protected value); the Dsh policy above hides widgets anyway
    @('UserTweaks', 'USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarDa', 0, 'soft'),
    @('RamTrim', 'USER\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsResumeAllowed', 0),
    @('RamTrim', 'USER\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration', 'IsOneDriveResumeAllowed', 0),
    @('RamTrim', 'HKLM\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 0),
    @('RamTrim', 'HKLM\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 0),
    @('LoginKeyboard', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'DisableAutomaticRestartSignOn', 1),
    @('LoginKeyboard', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI', 'ShowTabletKeyboard', 1),
    @('LoginKeyboard', 'USER\Software\Microsoft\TabletTip\1.7', 'EnableDesktopModeAutoInvoke', 1)
)

$ServiceList = @(
    # category, service, target start type. Absent services are skipped (other vendors, other drivers).
    @('Telemetry', 'DiagTrack', 'Disabled'),
    @('RamTrimVendor', 'DSAService', 'Manual'),
    @('RamTrimVendor', 'DSAUpdateService', 'Manual'),
    @('RamTrimVendor', 'OptionsPlusUpdaterService', 'Manual'),
    @('RamTrimVendor', 'DtsApo4Service', 'Manual'),
    @('RamTrimVendor', 'IgoAudioService', 'Manual')
)

$TaskList = @(
    # category, task path, task name regex
    @('Telemetry', '\Microsoft\Windows\Customer Experience Improvement Program\', '^(Consolidator|UsbCeip)$'),
    @('Telemetry', '\Microsoft\Windows\Autochk\', '^Proxy$'),
    @('Telemetry', '\Microsoft\Windows\Feedback\Siuf\', '^DmClient(OnScenarioDownload)?$'),
    @('Telemetry', '\Microsoft\Windows\Windows Error Reporting\', '^QueueReporting$'),
    @('TelemetryExtra', '\Microsoft\Windows\Application Experience\', '^(Microsoft Compatibility Appraiser.*|ProgramDataUpdater)$'),
    @('TelemetryExtra', '\Microsoft\Windows\DiskDiagnostic\', 'DataCollector$')
)

$CapabilityList = @(
    @('Capabilities', 'App.StepsRecorder~'), @('Capabilities', 'Browser.InternetExplorer~'),
    @('Capabilities', 'Microsoft.Windows.WordPad~'), @('Capabilities', 'MathRecognizer~'),
    @('Capabilities', 'Microsoft.Windows.PowerShell.ISE~'), @('Capabilities', 'Microsoft.Wallpapers.Extended~'),
    @('CapabilitiesExtra', 'WMIC~'), @('CapabilitiesExtra', 'Media.WindowsMediaPlayer~')
)
$FeatureList = @(
    @('Capabilities', 'MicrosoftWindowsPowerShellV2'), @('Capabilities', 'MicrosoftWindowsPowerShellV2Root'),
    @('Capabilities', 'WorkFolders-Client')
)

$RunList = @(
    # category, key, value name regex: autostart entries to remove (the program still opens by hand)
    @('RamTrim', 'USER\Software\Microsoft\Windows\CurrentVersion\Run', '^MicrosoftEdgeAutoLaunch_'),
    @('RamTrimVendor', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', '^Intel.*Graphics Software$')
)

# ------------------------------------------------------------------ elevation
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$IsAdmin = (New-Object Security.Principal.WindowsPrincipal($Identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin -and -not $NoElevate) {
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Level', $Level)
    if ($Only) { $argv += '-Only'; $argv += ($Only -join ',') }
    if ($Skip) { $argv += '-Skip'; $argv += ($Skip -join ',') }
    if ($StateFile) { $argv += '-StateFile'; $argv += "`"$StateFile`"" }
    if ($LogDir) { $argv += '-LogDir'; $argv += "`"$LogDir`"" }
    foreach ($s in 'Yes', 'NoRestorePoint', 'Pause') { if ((Get-Variable $s).Value) { $argv += "-$s" } }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argv -ErrorAction Stop | Out-Null
        Write-Host 'Continues in the elevated window.'
        exit 0
    } catch {
        if ($Mode -ne 'Audit') { Write-Host "Administrator rights are required for -Mode $Mode. Not started."; exit 2 }
        Write-Host 'No administrator rights: a limited audit continues here.'
    }
}

# ------------------------------------------------------------------ log
if (-not $LogDir) { $LogDir = Join-Path $PSScriptRoot 'logs' }
try { New-Item -ItemType Directory -Force $LogDir -ErrorAction Stop | Out-Null }
catch { $LogDir = Join-Path $env:TEMP 'HandheldTune-logs'; New-Item -ItemType Directory -Force $LogDir | Out-Null }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "$Mode-$Stamp.log"
$Results = New-Object System.Collections.ArrayList
$State = New-Object System.Collections.ArrayList
$UserName = $env:USERNAME

function Write-Log([string]$Text, [string]$Color = 'Gray') {
    # the log gets sent around: no account or computer names in it
    $clean = $Text -replace [regex]::Escape($UserName), '<user>' -replace [regex]::Escape($env:COMPUTERNAME), '<pc>'
    $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $clean
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $clean -ForegroundColor $Color
}

function Add-Result([string]$Cat, [string]$Item, [string]$Status, [string]$Detail = '') {
    [void]$Results.Add([pscustomobject]@{ Cat = $Cat; Item = $Item; Status = $Status; Detail = $Detail })
    $color = switch ($Status) { 'CHANGED' { 'Green' } 'WOULD' { 'Yellow' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } 'NOADMIN' { 'DarkYellow' } default { 'DarkGray' } }
    Write-Log ('{0,-8} {1,-17} {2} {3}' -f $Status, $Cat, $Item, $Detail) $color
}

function Get-ErrorText($e) {
    $text = ($e.Exception.Message -replace '\s*[\r\n]+\s*', ' ').Trim()
    return "$($e.Exception.GetType().Name): $text @ line $($e.InvocationInfo.ScriptLineNumber)"
}

function Save-State([hashtable]$Entry) {
    if ($Mode -ne 'Apply') { return }
    [void]$State.Add($Entry)
    try { $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LogDir "state-$Stamp.json") -Encoding UTF8 }
    catch { Write-Log "state file not written: $(Get-ErrorText $_)" 'Red' }
}

function Test-Active([string]$Cat) {
    if ($Only -and ($Only -notcontains $Cat)) { return $false }
    if ($Skip -and ($Skip -contains $Cat)) { return $false }
    if (-not $Only -and $Categories[$Cat] -gt $TierMax) { return $false }
    return $true
}

# ------------------------------------------------------------------ the logged-on user's registry
# An elevated window may run under another admin account: HKCU would then be the wrong user.
function Get-TargetUserSid {
    $me = $Identity.User.Value
    $owners = @()
    try {
        foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)) {
            $owners += (Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop).Sid
        }
    } catch { }
    if ($owners -contains $me -or $owners.Count -eq 0) { return $me }
    return $owners[0]
}

function Resolve-RegPath([string]$Key) {
    if ($Key -like 'USER\*') { return 'Registry::HKEY_USERS\' + $TargetSid + '\' + $Key.Substring(5) }
    return 'Registry::HKEY_LOCAL_MACHINE\' + $Key.Substring(5)
}

function Read-RegValue([string]$Path, [string]$Name) {
    $k = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $k -or ($k.GetValueNames() -notcontains $Name)) { return @{ Exists = $false } }
    return @{ Exists = $true; Value = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames'); Kind = $k.GetValueKind($Name).ToString() }
}

# ------------------------------------------------------------------ steps
function Invoke-RegItems {
    foreach ($r in $RegList) {
        $cat, $key, $name, $want = $r[0], $r[1], $r[2], $r[3]
        if (-not (Test-Active $cat)) { continue }
        $soft = $r.Count -gt 4
        $path = Resolve-RegPath $key
        $item = "$key\$name=$want"
        try {
            $cur = Read-RegValue $path $name
            if ($cur.Exists -and "$($cur.Value)" -eq "$want") { Add-Result $cat $item 'SAME'; continue }
            $was = if ($cur.Exists) { "was $($cur.Value)" } else { 'was absent' }
            if ($Mode -eq 'Audit') { Add-Result $cat $item 'WOULD' $was; continue }
            if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -LiteralPath $path -Name $name -Value $want -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            Save-State @{ Type = 'Reg'; Cat = $cat; Path = $path; Name = $name; Existed = $cur.Exists; Value = $cur.Value; Kind = $cur.Kind }
            Add-Result $cat $item 'CHANGED' $was
        } catch {
            Add-Result $cat $item $(if ($soft) { 'WARN' } else { 'FAIL' }) (Get-ErrorText $_)
        }
    }
}

function Invoke-RunItems {
    foreach ($r in $RunList) {
        $cat, $key, $rx = $r[0], $r[1], $r[2]
        if (-not (Test-Active $cat)) { continue }
        $path = Resolve-RegPath $key
        try {
            $k = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
            $names = if ($k) { @($k.GetValueNames() | Where-Object { $_ -match $rx }) } else { @() }
            if ($names.Count -eq 0) { Add-Result $cat "autostart $rx" 'SAME' 'not present'; continue }
            foreach ($n in $names) {
                if ($Mode -eq 'Audit') { Add-Result $cat "autostart $n" 'WOULD' 'remove'; continue }
                $v = Read-RegValue $path $n
                Remove-ItemProperty -LiteralPath $path -Name $n -ErrorAction Stop
                Save-State @{ Type = 'Reg'; Cat = $cat; Path = $path; Name = $n; Existed = $true; Value = $v.Value; Kind = $v.Kind }
                Add-Result $cat "autostart $n" 'CHANGED' 'removed'
            }
        } catch { Add-Result $cat "autostart $rx" 'FAIL' (Get-ErrorText $_) }
    }
}

function Invoke-Services {
    foreach ($r in $ServiceList) {
        $cat, $name, $want = $r[0], $r[1], $r[2]
        if (-not (Test-Active $cat)) { continue }
        try {
            $s = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $s) { Add-Result $cat "service $name" 'SKIP' 'not on this device'; continue }
            $was = "$($s.StartType)/$($s.Status)"
            if ("$($s.StartType)" -eq $want -and "$($s.Status)" -eq 'Stopped') { Add-Result $cat "service $name" 'SAME' $was; continue }
            if ($Mode -eq 'Audit') { Add-Result $cat "service $name -> $want" 'WOULD' "was $was"; continue }
            Save-State @{ Type = 'Service'; Cat = $cat; Name = $name; StartType = "$($s.StartType)"; WasRunning = ("$($s.Status)" -eq 'Running') }
            Set-Service -Name $name -StartupType $want -ErrorAction Stop
            if ("$($s.Status)" -ne 'Stopped') { Stop-Service -Name $name -Force -ErrorAction Stop }
            Add-Result $cat "service $name -> $want" 'CHANGED' "was $was"
        } catch { Add-Result $cat "service $name" 'FAIL' (Get-ErrorText $_) }
    }
}

function Invoke-Tasks {
    foreach ($r in $TaskList) {
        $cat, $path, $rx = $r[0], $r[1], $r[2]
        if (-not (Test-Active $cat)) { continue }
        try {
            $found = @(Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $rx })
            if ($found.Count -eq 0) { Add-Result $cat "task $path$rx" 'SKIP' 'not on this Windows'; continue }
            foreach ($t in $found) {
                $item = "task $($t.TaskName)"
                if ("$($t.State)" -eq 'Disabled') { Add-Result $cat $item 'SAME'; continue }
                if ($Mode -eq 'Audit') { Add-Result $cat $item 'WOULD' "was $($t.State)"; continue }
                try {
                    Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
                    Save-State @{ Type = 'Task'; Cat = $cat; Path = $t.TaskPath; Name = $t.TaskName }
                    Add-Result $cat $item 'CHANGED' "was $($t.State)"
                } catch { Add-Result $cat $item 'FAIL' (Get-ErrorText $_) }
            }
        } catch { Add-Result $cat "task $path$rx" 'FAIL' (Get-ErrorText $_) }
    }
}

function Invoke-Capabilities {
    $caps = @($CapabilityList | Where-Object { Test-Active $_[0] })
    $feats = @($FeatureList | Where-Object { Test-Active $_[0] })
    if (($caps.Count + $feats.Count) -eq 0) { return }
    if (-not $IsAdmin) { Add-Result 'Capabilities' 'capabilities and features' 'NOADMIN' 'reading them needs administrator rights'; return }
    Write-Log 'Reading Windows capabilities (can take a minute)...'
    try { $all = @(Get-WindowsCapability -Online -ErrorAction Stop) }
    catch { Add-Result 'Capabilities' 'Get-WindowsCapability' 'FAIL' (Get-ErrorText $_); $all = @() }
    foreach ($r in $caps) {
        $cat, $prefix = $r[0], $r[1]
        $found = @($all | Where-Object { $_.Name -like "$prefix*" -and "$($_.State)" -eq 'Installed' })
        if ($found.Count -eq 0) { Add-Result $cat "capability $prefix" 'SAME' 'not installed'; continue }
        foreach ($c in $found) {
            if ($Mode -eq 'Audit') { Add-Result $cat "capability $($c.Name)" 'WOULD' 'remove'; continue }
            try {
                Remove-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null
                Save-State @{ Type = 'Capability'; Cat = $cat; Name = $c.Name }
                Add-Result $cat "capability $($c.Name)" 'CHANGED' 'removed'
            } catch { Add-Result $cat "capability $($c.Name)" 'FAIL' (Get-ErrorText $_) }
        }
    }
    foreach ($r in $feats) {
        $cat, $name = $r[0], $r[1]
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
            if (-not $f) { Add-Result $cat "feature $name" 'SKIP' 'not on this Windows'; continue }
            if ("$($f.State)" -ne 'Enabled') { Add-Result $cat "feature $name" 'SAME' "$($f.State)"; continue }
            if ($Mode -eq 'Audit') { Add-Result $cat "feature $name" 'WOULD' 'disable'; continue }
            Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop | Out-Null
            Save-State @{ Type = 'Feature'; Cat = $cat; Name = $name }
            Add-Result $cat "feature $name" 'CHANGED' 'disabled'
        } catch { Add-Result $cat "feature $name" 'SKIP' (Get-ErrorText $_) }
    }
}

function Invoke-Apps {
    $cats = @($AppList.Keys | Where-Object { Test-Active $_ })
    if ($cats.Count -eq 0) { return }
    $installed = @(); $provisioned = @()
    if ($IsAdmin) {
        try { $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch { Add-Result 'Apps' 'Get-AppxPackage -AllUsers' 'FAIL' (Get-ErrorText $_) }
        try { $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { Add-Result 'Apps' 'Get-AppxProvisionedPackage' 'FAIL' (Get-ErrorText $_) }
    } else {
        $installed = @(Get-AppxPackage -ErrorAction SilentlyContinue)
        Add-Result 'Apps' 'apps of other users' 'NOADMIN' 'only the current user is checked'
    }
    foreach ($cat in ($Categories.Keys | Where-Object { $cats -contains $_ })) {
        foreach ($pattern in $AppList[$cat]) {
            $pkgs = @($installed | Where-Object { $_.Name -like $pattern })
            $provs = @($provisioned | Where-Object { $_.DisplayName -like $pattern })
            if ($pkgs.Count -eq 0 -and $provs.Count -eq 0) { Add-Result $cat "app $pattern" 'SAME' 'not installed'; continue }
            if ($Mode -eq 'Audit') {
                $names = @($pkgs | Select-Object -First 5 | ForEach-Object { "$($_.PackageFullName) [$(@($_.PackageUserInformation | ForEach-Object { $_.InstallState }) -join '/')]" }) -join '; '
                Add-Result $cat "app $pattern" 'WOULD' "installed $($pkgs.Count), provisioned $($provs.Count): $names"
                continue
            }
            foreach ($p in ($pkgs | Sort-Object PackageFullName -Unique)) {
                # dependent packages can refuse until the others are gone: the failures get a second pass below
                try {
                    Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                    Save-State @{ Type = 'App'; Cat = $cat; Name = $p.Name }
                    Add-Result $cat "app $($p.Name)" 'CHANGED' 'removed for all users'
                } catch {
                    try {
                        Start-Sleep -Milliseconds 500
                        Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                        Save-State @{ Type = 'App'; Cat = $cat; Name = $p.Name }
                        Add-Result $cat "app $($p.Name)" 'CHANGED' 'removed on the second try'
                    } catch { Add-Result $cat "app $($p.Name)" 'FAIL' (Get-ErrorText $_) }
                }
            }
            foreach ($p in $provs) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                    Add-Result $cat "provisioned $($p.DisplayName)" 'CHANGED' 'new users will not get it'
                } catch {
                    # removing the other packages can take this one along ("file not found"): only a package that
                    # is still provisioned is a real failure
                    $err = Get-ErrorText $_
                    $still = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -eq $p.PackageName })
                    if ($still.Count -eq 0) { Add-Result $cat "provisioned $($p.DisplayName)" 'CHANGED' 'gone with the other packages' }
                    else { Add-Result $cat "provisioned $($p.DisplayName)" 'FAIL' $err }
                }
            }
        }
    }
}

function Test-MustStay {
    try {
        $names = if ($IsAdmin) { @(Get-AppxPackage -AllUsers -ErrorAction Stop | ForEach-Object { $_.Name }) } else { @(Get-AppxPackage | ForEach-Object { $_.Name }) }
        foreach ($n in $MustStay) {
            if ($names -contains $n) { Write-Log "  kept: $n" } else { Write-Log "  not installed: $n (this script never removes it)" 'Yellow' }
        }
    } catch { Write-Log "  check failed: $(Get-ErrorText $_)" 'Yellow' }
}

function Invoke-Undo {
    $file = $StateFile
    if (-not $file) {
        $latest = Get-ChildItem -LiteralPath $LogDir -Filter 'state-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if ($latest) { $file = $latest.FullName }
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { Write-Log 'No state file found: nothing to undo.' 'Red'; return }
    Write-Log "Undo from $file"
    # PowerShell 5.1 passes a parsed JSON array down the pipeline as one object: assign first, then enumerate
    $parsed = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $entries = @($parsed | ForEach-Object { $_ })
    [array]::Reverse($entries)
    foreach ($e in $entries) {
        try {
            switch ($e.Type) {
                'Reg' {
                    if ($e.Existed) {
                        New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $e.Value -PropertyType $e.Kind -Force -ErrorAction Stop | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction Stop
                    }
                    Add-Result $e.Cat "$($e.Path)\$($e.Name)" 'CHANGED' 'restored'
                }
                'Service' {
                    Set-Service -Name $e.Name -StartupType $e.StartType -ErrorAction Stop
                    if ($e.WasRunning) { Start-Service -Name $e.Name -ErrorAction Stop }
                    Add-Result $e.Cat "service $($e.Name)" 'CHANGED' "back to $($e.StartType)"
                }
                'Task' {
                    Enable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction Stop | Out-Null
                    Add-Result $e.Cat "task $($e.Name)" 'CHANGED' 'enabled'
                }
                'Capability' {
                    Add-WindowsCapability -Online -Name $e.Name -ErrorAction Stop | Out-Null
                    Add-Result $e.Cat "capability $($e.Name)" 'CHANGED' 'installed'
                }
                'Feature' {
                    Enable-WindowsOptionalFeature -Online -FeatureName $e.Name -NoRestart -All -ErrorAction Stop | Out-Null
                    Add-Result $e.Cat "feature $($e.Name)" 'CHANGED' 'enabled'
                }
                'App' { Add-Result $e.Cat "app $($e.Name)" 'WARN' 'cannot be restored here: reinstall it from the Microsoft Store' }
            }
        } catch { Add-Result $e.Cat "$($e.Type) $($e.Name)" 'FAIL' (Get-ErrorText $_) }
    }
}

# ------------------------------------------------------------------ inventory for the log
function Get-RamUsedGb {
    $o = Get-CimInstance Win32_OperatingSystem
    return [math]::Round(($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) / 1MB, 2)
}

function Write-Inventory {
    Write-Log '--- system'
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $drive = Get-PSDrive ($env:SystemDrive.TrimEnd(':'))
        Write-Log "Device: $($cs.Manufacturer) $($cs.Model) (chassis $((Get-CimInstance Win32_SystemEnclosure).ChassisTypes -join ','))"
        Write-Log "CPU: $((Get-CimInstance Win32_Processor).Name.Trim())"
        Write-Log "GPU: $((Get-CimInstance Win32_VideoController).Name -join '; ')"
        Write-Log "BIOS: $((Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion)"
        Write-Log "Windows: $($os.Caption) $($v.DisplayVersion) build $($v.CurrentBuild).$($v.UBR), locale $((Get-Culture).Name)"
        Write-Log ("RAM: {0} GB used of {1} GB, up {2:N1} h; free on {3} {4} GB" -f (Get-RamUsedGb), [math]::Round($cs.TotalPhysicalMemory / 1GB, 1), (((Get-Date) - $os.LastBootUpTime).TotalHours), $env:SystemDrive, [math]::Round($drive.Free / 1GB, 1))
    } catch { Write-Log "system info: $(Get-ErrorText $_)" 'Yellow' }

    Write-Log '--- handheld tools (never changed by this script)'
    try {
        foreach ($n in 'HidHide', 'MSI_Center_M_Service', 'MSI Foundation Service', 'ArmouryCrateService', 'LenovoLegionSpaceService') {
            $s = Get-Service -Name $n -ErrorAction SilentlyContinue
            if ($s) { Write-Log "  service $n : $($s.StartType)/$($s.Status)" }
        }
        foreach ($p in (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ClawTweaks|MSI|ASUS|Armoury|Lenovo|Legion|Ayaneo|GPD|\bSteam' })) {
            Write-Log "  app $($p.Name) $($p.Version)"
        }
    } catch { Write-Log "tools: $(Get-ErrorText $_)" 'Yellow' }

    Write-Log '--- top memory users (candidates for future versions of this script)'
    try {
        Get-Process | Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Mb = [math]::Round((($_.Group | Measure-Object WorkingSet64 -Sum).Sum) / 1MB); N = $_.Count }
        } | Sort-Object Mb -Descending | Select-Object -First 20 | ForEach-Object { Write-Log ("  {0,6} MB x{1,-3} {2}" -f $_.Mb, $_.N, $_.Name) }
    } catch { Write-Log "processes: $(Get-ErrorText $_)" 'Yellow' }

    Write-Log '--- autostart entries'
    foreach ($k in 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'USER\Software\Microsoft\Windows\CurrentVersion\Run') {
        try {
            $item = Get-Item -LiteralPath (Resolve-RegPath $k) -ErrorAction SilentlyContinue
            if ($item) { foreach ($n in $item.GetValueNames()) { Write-Log "  $k : $n" } }
        } catch { }
    }

    Write-Log '--- automatic non-Windows services'
    try {
        Get-CimInstance Win32_Service -Filter "StartMode='Auto'" |
            Where-Object { $_.PathName -and $_.PathName -notmatch '(?i)\\Windows\\(system32|servicing|Microsoft\.NET)' } |
            Sort-Object Name | ForEach-Object { Write-Log "  $($_.Name) [$($_.State)] $($_.DisplayName)" }
    } catch { Write-Log "services: $(Get-ErrorText $_)" 'Yellow' }

    Write-Log '--- installed Appx packages (current user)'
    try { Write-Log ('  ' + ((Get-AppxPackage -ErrorAction Stop | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')) }
    catch { Write-Log "appx: $(Get-ErrorText $_)" 'Yellow' }
}

function Test-YesAnswer([string]$Answer) {
    # yes in any case, also typed on a Russian keyboard layout (char codes: the script stays ASCII)
    $a = "$Answer".Trim()
    return ($a -eq 'yes') -or ($a -eq (-join ([char]0x43D, [char]0x443, [char]0x44B)))
}

function Confirm-Yes([string]$Prompt) {
    $answer = Read-Host $Prompt
    if (Test-YesAnswer $answer) { return $true }
    Write-Log "Cancelled: the answer was '$answer', not YES. Nothing was changed. Run again and type YES to continue." 'Yellow'
    return $false
}

# ------------------------------------------------------------------ main
$TierMax = if ($Level -eq 'Full') { 2 } else { 1 }
$Failed = $false
try {
    Write-Log "Optimize-Handheld $ScriptVersion, mode $Mode, level $Level, admin $IsAdmin" 'Cyan'
    Write-Log "Args: Only=[$($Only -join ',')] Skip=[$($Skip -join ',')] StateFile=[$StateFile]; PowerShell $($PSVersionTable.PSVersion)"
    Write-Log "Log: $LogFile"
    foreach ($c in (@($Only) + @($Skip))) {
        if ($c -and -not $Categories.Contains($c)) { Write-Log "Unknown category '$c'. Known: $($Categories.Keys -join ', ')" 'Red'; exit 2 }
    }
    $Build = [Environment]::OSVersion.Version.Build
    if ($Build -lt 19041) { Write-Log "Windows build $Build is too old: 19041 or newer is required." 'Red'; exit 2 }

    $TargetSid = Get-TargetUserSid
    if ($TargetSid -ne $Identity.User.Value) { Write-Log 'Elevated under another account: per-user settings go to the logged-on user.' 'Yellow' }
    if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$TargetSid")) { Write-Log 'User registry hive is not loaded: per-user items will fail.' 'Yellow' }

    Write-Inventory

    if ($Mode -eq 'Undo') {
        if (-not $IsAdmin) { Write-Log 'Undo needs administrator rights.' 'Red'; exit 2 }
        if (-not $Yes) {
            if (-not (Confirm-Yes 'Roll back the latest Apply? Type YES')) { exit 0 }
        }
        Invoke-Undo
    } else {
        if ($Mode -eq 'Apply') {
            if (-not $IsAdmin) { Write-Log 'Apply needs administrator rights.' 'Red'; exit 2 }
            $active = @($Categories.Keys | Where-Object { Test-Active $_ })
            Write-Log "Categories: $($active -join ', ')" 'Cyan'
            if (-not $Yes) {
                if (-not (Confirm-Yes 'Apply these changes? Type YES')) { exit 0 }
            }
            if (-not $NoRestorePoint) {
                try {
                    Checkpoint-Computer -Description "Optimize-Handheld $Stamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
                    Write-Log 'Restore point requested (Windows creates at most one a day).'
                } catch { Write-Log "No restore point (System Restore may be off): $($_.Exception.Message)" 'Yellow' }
            }
        }
        Write-Log '--- steps' 'Cyan'
        $ramBefore = Get-RamUsedGb
        Invoke-Apps
        Invoke-RegItems
        Invoke-RunItems
        Invoke-Services
        Invoke-Tasks
        Invoke-Capabilities
        if ($Mode -eq 'Apply') {
            Write-Log '--- must stay'
            Test-MustStay
            Write-Log "RAM now $(Get-RamUsedGb) GB (before $ramBefore GB). The real number is after a reboot: run the audit then."
        }
    }
} catch {
    $Failed = $true
    Write-Log "FATAL $(Get-ErrorText $_)" 'Red'
    Write-Log "$($_.ScriptStackTrace)" 'Red'
}

Write-Log '--- summary' 'Cyan'
foreach ($g in ($Results | Group-Object Status | Sort-Object Name)) { Write-Log ('{0,-8} {1}' -f $g.Name, $g.Count) }
$bad = @($Results | Where-Object { $_.Status -eq 'FAIL' })
foreach ($b in $bad) { Write-Log "FAIL $($b.Cat) $($b.Item): $($b.Detail)" 'Red' }
if ($Mode -ne 'Audit' -and @($Results | Where-Object { $_.Status -eq 'CHANGED' }).Count -gt 0) {
    Write-Log 'Reboot to finish. Big Windows updates can bring things back: run the audit again after them.' 'Cyan'
}
if ($Mode -eq 'Apply' -and $State.Count -gt 0) { Write-Log "Undo data: $(Join-Path $LogDir "state-$Stamp.json")" }
Write-Log "Log saved: $LogFile" 'Cyan'
if ($Pause) { Read-Host 'Press Enter to close' | Out-Null }
if ($Failed -or $bad.Count -gt 0) { exit 1 }
exit 0
