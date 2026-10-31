# Round trip of Apply + Undo on a scratch registry key (no admin, touches nothing else). Loads the real functions
# from Optimize-Handheld.ps1 and replaces its item lists. Exit 0 = passed.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\Optimize-Handheld.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script), [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($f.Extent.Text))
}

$LogDir = Join-Path $env:TEMP "ht-roundtrip-$(Get-Random)"
New-Item -ItemType Directory $LogDir | Out-Null
$LogFile = Join-Path $LogDir 'test.log'
$Stamp = 'test'
$UserName = $env:USERNAME
$Results = New-Object System.Collections.ArrayList
$State = New-Object System.Collections.ArrayList
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$TargetSid = $Identity.User.Value
$Categories = [ordered]@{ T1 = 1; T2 = 2 }
$Only = $null; $Skip = $null; $TierMax = 1; $Yes = $true; $StateFile = $null

$Sub = 'Software\HandheldTuneTest'
$Raw = "Registry::HKEY_USERS\$TargetSid\$Sub"
$fails = 0
function Check([string]$What, [bool]$Ok) {
    if ($Ok) { Write-Host "ok   $What" -ForegroundColor Green } else { Write-Host "FAIL $What" -ForegroundColor Red; $script:fails++ }
}
try {
    New-Item -Path "$Raw\Run" -Force | Out-Null
    New-ItemProperty -LiteralPath $Raw -Name Changed -Value 7 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $Raw -Name Same -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath "$Raw\Run" -Name 'MicrosoftEdgeAutoLaunch_X' -Value 'edge.exe --x' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath "$Raw\Run" -Name 'Keep' -Value 'keep.exe' -PropertyType String -Force | Out-Null

    $RegList = @(
        @('T1', "USER\$Sub", 'Changed', 0),
        @('T1', "USER\$Sub", 'Same', 1),
        @('T1', "USER\$Sub", 'New', 5),
        @('T2', "USER\$Sub", 'Tier2Only', 9)
    )
    $RunList = @(, @('T1', "USER\$Sub\Run", '^MicrosoftEdgeAutoLaunch_'))

    # the audit must change nothing
    $Mode = 'Audit'
    Invoke-RegItems; Invoke-RunItems
    Check 'audit leaves values' ((Read-RegValue $Raw 'Changed').Value -eq 7 -and -not (Read-RegValue $Raw 'New').Exists)
    Check 'audit leaves autostart' ((Read-RegValue "$Raw\Run" 'MicrosoftEdgeAutoLaunch_X').Exists)
    Check 'audit writes no state' ($State.Count -eq 0)

    $Mode = 'Apply'
    Invoke-RegItems; Invoke-RunItems
    Check 'apply changes a value' ((Read-RegValue $Raw 'Changed').Value -eq 0)
    Check 'apply creates a value' ((Read-RegValue $Raw 'New').Value -eq 5)
    Check 'higher tier is skipped' (-not (Read-RegValue $Raw 'Tier2Only').Exists)
    Check 'apply removes the autostart' (-not (Read-RegValue "$Raw\Run" 'MicrosoftEdgeAutoLaunch_X').Exists)
    Check 'other autostarts stay' ((Read-RegValue "$Raw\Run" 'Keep').Exists)
    Check 'state has 3 entries, not Same' ($State.Count -eq 3)
    $sameRow = @($Results | Where-Object { $_.Item -like '*\Same=1' -and $_.Status -eq 'SAME' })
    Check 'an unchanged value is reported SAME' ($sameRow.Count -ge 1)

    # a second Apply is a no-op
    $n = $State.Count
    Invoke-RegItems; Invoke-RunItems
    Check 'second apply changes nothing' ($State.Count -eq $n)

    $Mode = 'Undo'
    Invoke-Undo
    Check 'undo restores a value' ((Read-RegValue $Raw 'Changed').Value -eq 7)
    Check 'undo removes a created value' (-not (Read-RegValue $Raw 'New').Exists)
    Check 'undo restores the autostart' ((Read-RegValue "$Raw\Run" 'MicrosoftEdgeAutoLaunch_X').Value -eq 'edge.exe --x')
    Check 'undo had no failures' (@($Results | Where-Object { $_.Status -eq 'FAIL' }).Count -eq 0)
} finally {
    Remove-Item -LiteralPath $Raw -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $LogDir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host $(if ($fails) { "$fails FAILED" } else { 'ALL PASSED' })
exit $fails
