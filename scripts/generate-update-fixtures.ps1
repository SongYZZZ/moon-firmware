# Original synthetic NOR contents. No vendor firmware or device readout is used.
$ErrorActionPreference = 'Stop'
$fixtureDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../tests/fixtures/update'))
[IO.Directory]::CreateDirectory($fixtureDirectory) | Out-Null

function New-IntelRecord([int]$Type, [int]$Offset, [byte[]]$Data) {
    $recordBytes = @($Data.Length, (($Offset -shr 8) -band 255), ($Offset -band 255), $Type) + @($Data)
    $sum = 0
    foreach ($value in $recordBytes) { $sum += [int]$value }
    $recordBytes += ((256 - ($sum -band 255)) -band 255)
    ':' + (($recordBytes | ForEach-Object { '{0:X2}' -f [int]$_ }) -join '')
}

function Write-IntelFixture([string]$Name, [long]$Start, [byte[]]$Data) {
    $lines = [Collections.Generic.List[string]]::new()
    $upper = -1
    for ($offset = 0; $offset -lt $Data.Length; $offset += 32) {
        $address = $Start + $offset
        $nextUpper = [int]($address -shr 16)
        if ($nextUpper -ne $upper) {
            $upper = $nextUpper
            $lines.Add((New-IntelRecord 4 0 ([byte[]]@((($upper -shr 8) -band 255), ($upper -band 255)))))
        }
        $count = [Math]::Min(32, $Data.Length - $offset)
        $chunk = [byte[]]::new($count)
        [Array]::Copy($Data, $offset, $chunk, 0, $count)
        $lines.Add((New-IntelRecord 0 ([int]($address -band 65535)) $chunk))
    }
    $lines.Add(':00000001FF')
    [IO.File]::WriteAllText((Join-Path $fixtureDirectory $Name), ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

$baselineBytes = [byte[]]::new(98304)
for ($index = 0; $index -lt $baselineBytes.Length; $index++) {
    $baselineBytes[$index] = if ($index -lt 16384) { 0x5A } elseif ($index -lt 81920) { 0xA5 } else { 0x33 }
}
Write-IntelFixture 'baseline.hex' 0x08000000 $baselineBytes
Write-IntelFixture 'erase-overlay.hex' 0x08004008 ([byte[]]@(0xFF))
Write-IntelFixture 'program-overlay.hex' 0x08004008 ([byte[]]@(0xA4))
# Original S3 data and S7 entry metadata; the baseline entry is retained.
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'program-overlay.srec'), "S30608004008A405`nS70500000000FA`n", [Text.UTF8Encoding]::new($false))
$baselineBytes[16400] = 0xA4
Write-IntelFixture 'stale-device.hex' 0x08000000 $baselineBytes
Write-IntelFixture 'incomplete-baseline.hex' 0x08004000 ([byte[]]@(0xA5))

$targetProfile = [ordered]@{
    schema = 'moonfirmware.target.v1'
    name = 'synthetic-nor-16k-64k-16k'
    program_unit = 8
    sectors = @(
        @{ name = 'boot'; start = '0x08000000'; size = 16384 },
        @{ name = 'application'; start = '0x08004000'; size = 65536 },
        @{ name = 'calibration'; start = '0x08014000'; size = 16384 }
    )
    writable = @(@{ name = 'application'; start = '0x08004000'; end_exclusive = '0x08014000' })
    protected = @(
        @{ name = 'boot'; start = '0x08000000'; end_exclusive = '0x08004000' },
        @{ name = 'calibration'; start = '0x08014000'; end_exclusive = '0x08018000' }
    )
    max_plan_bytes = 131072
}
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'target.json'), ($targetProfile | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
$targetProfile.name = 'synthetic-nor-shared-calibration'
$targetProfile.protected += @{ name = 'shared-calibration'; start = '0x08013FF0'; end_exclusive = '0x08014000' }
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'shared-calibration.json'), ($targetProfile | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
Write-Output 'Generated original 96 KiB baseline and update safety fixtures.'
