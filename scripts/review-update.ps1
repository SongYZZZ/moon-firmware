param([string]$Executable = '')
$ErrorActionPreference = 'Stop'
$repositoryDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$Executable) {
    $buildExecutable = Join-Path $repositoryDirectory '_build/native/release/build/cmd/moon-firmware/moon-firmware'
    $Executable = if (Test-Path -LiteralPath "$buildExecutable.exe" -PathType Leaf) { "$buildExecutable.exe" } else { $buildExecutable }
}
$Executable = [IO.Path]::GetFullPath($Executable)
if (!(Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Run moon build --release first.' }
$fixtureDirectory = Join-Path $repositoryDirectory 'tests/fixtures/update'
$evidenceDirectory = Join-Path $repositoryDirectory 'artifacts/update-review'
[IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
$caseResults = [Collections.Generic.List[object]]::new()

function Invoke-UpdateCase([string]$Name, [string]$Baseline, [string]$Overlay, [string]$Profile, [int]$ExpectedExit, [string]$ExpectedCode = '', [string]$Observed = '') {
    $commandArgs = @('plan-update', (Join-Path $fixtureDirectory $Baseline), (Join-Path $fixtureDirectory $Overlay), '--profile', (Join-Path $fixtureDirectory $Profile), '--json')
    if ($Observed) { $commandArgs += @('--observed', (Join-Path $fixtureDirectory $Observed)) }
    $outputLines = & $Executable @commandArgs
    $actualExit = $LASTEXITCODE
    if ($actualExit -ne $ExpectedExit) { throw "$Name exit $actualExit; expected $ExpectedExit" }
    $result = ($outputLines -join "`n") | ConvertFrom-Json
    if ($ExpectedCode -and $result.code -ne $ExpectedCode) { throw "$Name wrong refusal code" }
    [IO.File]::WriteAllText((Join-Path $evidenceDirectory "$Name.json"), ($outputLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    $caseResults.Add([ordered]@{ case = $Name; exit = $actualExit; status = $result.status; code = $result.code })
    $result
}

$erase = Invoke-UpdateCase 'preserve-sector' 'baseline.hex' 'erase-overlay.hex' 'target.json' 0
if ($erase.plan.affected_sectors -ne 1 -or $erase.plan.erase_count -ne 1 -or $erase.plan.changed_bytes -ne 1 -or $erase.plan.sectors[0].preserved_bytes -ne 65535) { throw 'Wrong sector preservation summary' }
$verify = @($erase.plan.operations | Where-Object { $_.op -eq 'verify' })[0]
$expectedHex = ('A5' * 8) + 'FF' + ('A5' * 65527)
if ($verify.expected_hex -cne $expectedHex) { throw 'Full 64 KiB sector differs from independent preservation expectation' }
if ($erase.simulation_evidence[0].actual_hex -cne $expectedHex) { throw 'Actual replayed 64 KiB sector differs from independent preservation expectation' }
if ($erase.baseline_source -ne 'supplied_baseline_only') { throw 'Baseline provenance must be explicit' }
$direct = Invoke-UpdateCase 'program-without-erase' 'baseline.hex' 'program-overlay.hex' 'target.json' 0
if ($direct.plan.erase_count -ne 0 -or $direct.plan.program_bytes -ne 8) { throw 'Wrong direct NOR program plan' }
$srec = Invoke-UpdateCase 'srec-upstream-input' 'baseline.hex' 'program-overlay.srec' 'target.json' 0
if ($srec.plan.program_bytes -ne 8 -or $srec.plan.erase_count -ne 0) { throw 'Wrong upstream SREC input plan' }
$null = Invoke-UpdateCase 'protected-collateral' 'baseline.hex' 'erase-overlay.hex' 'shared-calibration.json' 1 'ProtectedErase'
$null = Invoke-UpdateCase 'stale-device' 'baseline.hex' 'erase-overlay.hex' 'target.json' 1 'StaleBaseline' 'stale-device.hex'
$null = Invoke-UpdateCase 'unknown-baseline' 'incomplete-baseline.hex' 'erase-overlay.hex' 'target.json' 1 'MissingBaseline'
$null = Invoke-UpdateCase 'checksum-error' 'baseline.hex' '../bad_checksum.hex' 'target.json' 2 'InputFormat'
$caseResults | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'summary.json') -Encoding utf8
$caseResults | ForEach-Object { Write-Output ("PASS {0}: exit={1}, status={2}, code={3}" -f $_.case, $_.exit, $_.status, $_.code) }
# Expected refusal cases return nonzero native codes. After all assertions
# passed, do not leak the last native code into a CI shell's exit handling.
exit 0
