# Copyright (c) 2025 Jeremy W Kuhne
# SPDX-License-Identifier: MIT
# See LICENSE file in the project root for full license information

# Native standalone acceptance uses caller-supplied firmware and the external ProDOS test image.
param(
    [string] $RomDirectory = $env:RETROCORE_IIE_ROMS,
    [string] $DiskImage = (Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'm1-dependencies\ProDOS_2_4_3.po')
)
$ErrorActionPreference = 'Stop'
if (-not $RomDirectory -or -not (Test-Path -LiteralPath $RomDirectory)) { throw 'Supply the external IIe ROM directory.' }
if (-not (Test-Path -LiteralPath $DiskImage)) { throw 'Supply ProDOS_2_4_3.po or run Fetch-M1Dependencies.ps1.' }
$root = Split-Path $PSScriptRoot
Push-Location $root
try {
    dotnet test .\tests\AppleSharp.tests\AppleSharp.tests.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'AppleSharp configuration/storage/pacing tests failed.' }
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --filter 'FullyQualifiedName~Apple2Video|FullyQualifiedName~Apple2MachineTests|FullyQualifiedName~Slot7RomTests' --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'Related core video/machine/firmware tests failed.' }
    dotnet publish .\src\AppleSharp\AppleSharp.csproj -c Release -r win-x64 -o .\artifacts\AppleSharp --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'AppleSharp Native AOT publish failed.' }
    $executable = Join-Path $root 'artifacts\AppleSharp\AppleSharp.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $root 'artifacts\AppleSharp\SDL3.dll'))) {
        throw 'The published application is missing its native SDL3 binary.'
    }
    $settings = Join-Path $root ('artifacts\AppleSharp\acceptance-' + [Guid]::NewGuid().ToString('N') + '.json')
    $before = (Get-FileHash -LiteralPath $DiskImage -Algorithm SHA256).Hash
    foreach ($model in 'original','enhanced') {
        $start = [Diagnostics.ProcessStartInfo]::new($executable)
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('--rom-directory', $RomDirectory, '--disk', $DiskImage, '--model', $model, '--read-only', '--settings', $settings, '--smoke-test')) {
            $start.ArgumentList.Add($argument)
        }
        $process = [Diagnostics.Process]::Start($start)
        try {
            $output = $process.StandardOutput.ReadToEndAsync()
            $errors = $process.StandardError.ReadToEndAsync()
            $ready = [Diagnostics.Stopwatch]::StartNew()
            while (-not $process.HasExited -and $process.MainWindowHandle -eq 0 -and $ready.Elapsed.TotalSeconds -lt 5) {
                Start-Sleep -Milliseconds 50
                $process.Refresh()
            }
            $windowSeen = $process.MainWindowHandle -ne 0
            if (-not $process.WaitForExit(30000)) {
                Stop-Process -Id $process.Id
                throw "Native $model AppleSharp exceeded its 30-second acceptance budget."
            }
            $diagnostics = $errors.GetAwaiter().GetResult()
            $null = $output.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0) { throw "Native $model AppleSharp failed: $diagnostics" }
            if (-not $windowSeen) { throw "Native $model acceptance did not show an SDL3 window." }
            "${model}: native SDL3 window, ProDOS boot, text input, pause, reset and fullscreen passed."
        }
        finally { $process.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $DiskImage -Algorithm SHA256).Hash -ne $before) {
        throw 'The read-only acceptance run changed the external test image.'
    }
    if (Test-Path -LiteralPath $settings) { Remove-Item -LiteralPath $settings }
    'AppleSharp M2.a Native AOT acceptance passed without VS Code or a DAP host.'
}
finally { Pop-Location }
