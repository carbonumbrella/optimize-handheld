# Test-Savings.ps1 - baseline choice and comparison of -Mode Savings on fixtures in a temp folder. Changes nothing else.
$script = Join-Path $PSScriptRoot '..\Optimize-Handheld.ps1'
$errors = $null; $tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $script).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { Write-Host "FAIL parse: $($errors[0].Message)"; exit 1 }
$names = 'Write-Log', 'Get-ErrorText', 'Get-RamUsedGb', 'Get-MemoryByProcess', 'Get-Snapshot', 'Save-Baseline', 'ConvertFrom-LogNumber',
    'Read-LogBaseline', 'Find-Baseline', 'Write-SavingsRow', 'Invoke-Savings'
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($names -contains $f.Name) { Invoke-Expression $f.Extent.Text }
}

$Root = Join-Path $env:TEMP "HandheldTune-test-$PID"
$UserName = 'nobody-here'; $Stamp = '20261103-100000'; $Level = 'Standard'; $ScriptVersion = 'test'
$Failures = 0
function Check([string]$Name, [bool]$Ok) { if ($Ok) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:Failures++ } }

function New-Log([string]$Dir, [string]$Name, [string]$Ram, [string]$Up, [string]$Disk, [bool]$Steps) {
    $l = @('13:49:43 Optimize-Handheld 1.0.0, mode Apply, level Standard, admin True',
        "13:49:45 RAM: $Ram GB used of 31,5 GB, up $Up h; free on C: $Disk GB",
        '13:49:45 --- top memory users (candidates for future versions of this script)',
        '13:49:46     1650 MB x85  svchost',
        '13:49:46      127 MB x9   no-such-process-here',
        '13:49:46 --- autostart entries',
        '13:49:46      999 MB x1   not-in-the-top-section',
        '13:49:47 --- installed Appx packages (current user)',
        '13:49:47   One.App, Two.App, Three.App')
    if ($Steps) { $l += '13:49:57 --- steps' }
    Set-Content -LiteralPath (Join-Path $Dir $Name) -Value $l -Encoding UTF8
}

try {
    # an old log, with a cancelled run before it and a later run after it
    $LogDir = Join-Path $Root 'a'; New-Item -ItemType Directory -Force $LogDir | Out-Null
    $LogFile = Join-Path $LogDir 'Savings-test.log'
    New-Log $LogDir 'Apply-20261102-121333.log' '1,1' '1,0' '100,0' $false
    New-Log $LogDir 'Apply-20261102-134943.log' '8,7' '0,3' '848,3' $true
    New-Log $LogDir 'Apply-20261102-150000.log' '7.5' '0.5' '900.5' $true
    $b = Find-Baseline
    Check 'cancelled run is skipped, oldest finished run is used' ($b.Stamp -eq '20261102-134943')
    Check 'comma decimals' ($b.RamGb -eq 8.7 -and $b.UptimeHours -eq 0.3 -and $b.DiskFreeGb -eq 848.3)
    Check 'top section only' (@($b.Processes).Count -eq 2 -and [int]@($b.Processes | Where-Object { $_.Name -eq 'svchost' })[0].Mb -eq 1650)
    Check 'packages counted' ($b.Packages -eq 3)
    Check 'level read' ($b.Level -eq 'Standard')
    Check 'dot decimals' ((Read-LogBaseline (Join-Path $LogDir 'Apply-20261102-150000.log')).DiskFreeGb -eq 900.5)
    Invoke-Savings 6>&1 | Out-Null
    $out = Get-Content -LiteralPath $LogFile -Raw
    Check 'from a log: process gone' ($out -match 'Gone since then: 127 MB in 1 processes')
    Check 'from a log: the partial list is stated' ($out -match 'only the top 20')
    Check 'from a log: totals' ($out -match 'Used memory, GB' -and $out -match 'Appx packages')

    # a saved baseline beats the log of the same run, and an older log beats both
    $LogDir = Join-Path $Root 'b'; New-Item -ItemType Directory -Force $LogDir | Out-Null
    $LogFile = Join-Path $LogDir 'Savings-test.log'
    Save-Baseline 6>&1 | Out-Null
    New-Log $LogDir "Apply-$Stamp.log" '1,0' '1,0' '1,0' $true
    $b = Find-Baseline
    Check 'baseline file wins over the log of the same run' ($b.File -like '*baseline-*' -and @($b.Processes).Count -gt 2)
    Invoke-Savings 6>&1 | Out-Null
    $out = Get-Content -LiteralPath $LogFile -Raw
    Check 'from a file: all processes, no partial note' ($out -match 'Gone since then' -and $out -notmatch 'only the top 20' -and $out -match 'Processes ')
    New-Log $LogDir 'Apply-20261101-010000.log' '9,0' '1,0' '500,0' $true
    Check 'an older log wins over a newer baseline' ((Find-Baseline).Stamp -eq '20261101-010000')

    # nothing to compare with
    $LogDir = Join-Path $Root 'c'; New-Item -ItemType Directory -Force $LogDir | Out-Null
    $LogFile = Join-Path $LogDir 'Savings-test.log'
    Invoke-Savings 6>&1 | Out-Null
    Check 'no Apply: says so' ((Get-Content -LiteralPath $LogFile -Raw) -match 'No finished Apply found')
} finally {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "failures: $Failures"
exit $Failures
