# Copyright (c) 2025 Jeremy W Kuhne
# SPDX-License-Identifier: MIT
# See LICENSE file in the project root for full license information

# Directed/synthetic M3 checks are not substitutes for the protected-WOZ and audible-PT3 gates.
param(
    [string] $RomDirectory = $env:RETROCORE_IIE_ROMS,
    [switch] $AutomatedOnly
)
$ErrorActionPreference = 'Stop'
if (-not $RomDirectory -or -not (Test-Path -LiteralPath $RomDirectory)) { throw 'Supply the external IIe ROM directory.' }
$env:RETROCORE_IIE_ROMS = $RomDirectory
$root = Split-Path $PSScriptRoot
Push-Location $root
try {
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --filter 'FullyQualifiedName~Disk|FullyQualifiedName~PeripheralIntegrationTests|FullyQualifiedName~Audio|FullyQualifiedName~Via|FullyQualifiedName~Ay|FullyQualifiedName~Mockingboard|FullyQualifiedName~Apple2Video|FullyQualifiedName~Apple2MachineTests|FullyQualifiedName~Slot7RomTests|FullyQualifiedName~DebugCallStackTests' --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'M3 device or related regression tests failed.' }
    & .\tools\Test-AppleSharp.ps1 -RomDirectory $RomDirectory
    dotnet build .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'M3 debug host build failed.' }
    node .\tools\Test-IIeOracle.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Existing ProDOS differential boot regressed.' }
    & .\tools\Build-IIeSample.ps1
    node .\tools\Test-IIeDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Live Disk II DAP telemetry or source debugging failed.' }
    # The II and II Plus, from their dumps and from the SDK's ROMs; each says it was skipped when the dumps are missing.
    node .\tools\Test-IIPlusDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'II Plus DAP integration failed.' }
    node .\tools\Test-IIDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'II DAP integration failed.' }
    node .\tools\Test-IntegerBasicDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Integer BASIC DAP integration failed.' }
    npm --prefix .\extension run compile
    if ($LASTEXITCODE -ne 0) { throw 'Disk-view extension compilation failed.' }
    if (-not $AutomatedOnly) {
        throw 'M3 external acceptance remains pending: supply P5/P6 firmware, three authorized copy-protected WOZ originals and an AppleWin reference, plus a PT3 track/player for five-minute audible playback. Use -AutomatedOnly for directed/synthetic checks; that is not a full M3 sign-off.'
    }
    'M3 automated device/native/regression checks passed. Protected-WOZ and audible-PT3 sign-off remains pending.'
}
finally { Pop-Location }
