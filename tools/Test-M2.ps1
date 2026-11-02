# Copyright (c) 2025 Jeremy W Kuhne
# SPDX-License-Identifier: MIT
# See LICENSE file in the project root for full license information

# M2 lookup video and beam foundations. ROMs and the pinned MIT Apple2TS oracle remain external.
# Coordinates: 262 lines, 65 CPU clocks per line; visible columns 25-64, VBL starts at 192:0.
# This checks complete DHGR frames against Apple2TS and automated timing/debugger behavior.
# The separate AppleWin BPV comparison on a known vapour-lock demo is still a pending manual gate.
param(
    [string] $RomDirectory = $env:RETROCORE_IIE_ROMS
)
$ErrorActionPreference = 'Stop'
if (-not $RomDirectory -or -not (Test-Path -LiteralPath $RomDirectory)) { throw 'An external IIe ROM directory is required.' }
$env:RETROCORE_IIE_ROMS = $RomDirectory
$root = Split-Path $PSScriptRoot
Push-Location $root
try {
    & .\tools\Build-IIeSample.ps1
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --filter 'FullyQualifiedName~Apple2Video|FullyQualifiedName~Apple2MachineTests|FullyQualifiedName~DebugCallStackTests|FullyQualifiedName~Slot7RomTests' --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'Video, beam or related IIe tests failed.' }
    dotnet build .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'DAP host build failed.' }
    node .\tools\Test-IIeDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'DAP video, beam or source-cycle tests failed.' }
    npm --prefix .\extension run compile
    if ($LASTEXITCODE -ne 0) { throw 'VS Code extension compilation failed.' }
    npm --prefix .\extension test
    if ($LASTEXITCODE -ne 0) { throw 'Isolated VS Code beam/cycle tests failed.' }
    dotnet publish .\tests\Retrocore.Aot.Tests\Retrocore.Aot.Tests.csproj -c Release -r win-x64 -o .\artifacts\aot --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT video publication failed.' }
    & .\artifacts\aot\Retrocore.Aot.Tests.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT video execution failed.' }
    'M2 automated foundations passed. AppleWin BPV/vapour-lock acceptance remains pending; this is not a full M2 sign-off.'
}
finally { Pop-Location }
