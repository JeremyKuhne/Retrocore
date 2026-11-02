# Copyright (c) 2025 Jeremy W Kuhne
# SPDX-License-Identifier: MIT
# See LICENSE file in the project root for full license information

# ROM inputs and derived disassemblies stay external to the repository.
param(
    [string] $RomDirectory = $env:RETROCORE_IIE_ROMS,
    [string] $OutputDirectory = (Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'rom-analysis\system')
)

$ErrorActionPreference = 'Stop'
if (-not $RomDirectory -or -not (Test-Path -LiteralPath $RomDirectory -PathType Container)) {
    throw 'An external directory containing the original/enhanced CD, EF and video ROM chips is required.'
}

$RomDirectory = (Resolve-Path -LiteralPath $RomDirectory).Path
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$previousRoms = $env:RETROCORE_IIE_ROMS
$previousOutput = $env:RETROCORE_SYSTEM_ROM_OUTPUT
$started = [DateTimeOffset]::UtcNow
Push-Location (Split-Path $PSScriptRoot)
try {
    $env:RETROCORE_IIE_ROMS = $RomDirectory
    $env:RETROCORE_SYSTEM_ROM_OUTPUT = $OutputDirectory
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --no-restore --filter 'FullyQualifiedName~SystemRomRoundTripTests' --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw 'System-ROM round-trip tests failed.' }

    foreach ($model in @('Original', 'Enhanced')) {
        $report = Get-Content -LiteralPath (Join-Path $OutputDirectory "$model.roundtrip.json") -Raw | ConvertFrom-Json
        if ($report.Model -ne $model -or $report.Size -ne 16384 -or
            [DateTimeOffset]$report.GeneratedUtc -lt $started -or $report.Results.Count -ne 2) {
            throw "$model round-trip report is stale, incomplete or invalid."
        }

        foreach ($mode in @('Linear', 'Flow')) {
            $rows = @($report.Results | Where-Object Mode -eq $mode)
            if ($rows.Count -ne 1 -or $rows[0].InstructionCount -le 0 -or
                $rows[0].TextByteDifferences -ne 0 -or $rows[0].ModelByteDifferences -ne 0 -or
                $rows[0].TextSha256 -ne $rows[0].OriginalSha256 -or
                $rows[0].ModelSha256 -ne $rows[0].OriginalSha256) {
                throw "$model/$mode did not produce a verified byte-exact reconstruction."
            }

            foreach ($suffix in @('reassembled.bin', 'model.bin')) {
                $path = Join-Path $OutputDirectory "$model.$mode.$suffix"
                if ((Get-Item -LiteralPath $path).Length -ne $report.Size -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $rows[0].OriginalSha256) {
                    throw "Persisted ROM reconstruction differs from its verified report: $path"
                }
            }
        }
    }

    "Eight byte-exact reconstructions verified. Source, rebuilt binaries and provenance: $OutputDirectory"
}
finally {
    $env:RETROCORE_IIE_ROMS = $previousRoms
    $env:RETROCORE_SYSTEM_ROM_OUTPUT = $previousOutput
    Pop-Location
}
