# ROMs and ProDOS test assets remain external. Run Fetch-M1Dependencies.ps1 and npm install in extension first.
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
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'CPU or IIe machine tests failed.' }
    dotnet build .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'DAP host build failed.' }
    node .\tools\Apple2TsOracle.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Pinned oracle build failed.' }
    node .\tools\Test-IIeOracle.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Original/enhanced ProDOS differential boot failed.' }
    node .\tools\Test-IIeDap.mjs
    if ($LASTEXITCODE -ne 0) { throw 'DAP source-debugging acceptance failed.' }
    npm --prefix .\extension run compile
    if ($LASTEXITCODE -ne 0) { throw 'VS Code extension compilation failed.' }
    npm --prefix .\extension test
    if ($LASTEXITCODE -ne 0) { throw 'Isolated VS Code F5 acceptance failed.' }
    dotnet publish .\tests\Retrocore.Aot.Tests\Retrocore.Aot.Tests.csproj -c Release -r win-x64 -o .\artifacts\aot --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT publication failed.' }
    & .\artifacts\aot\Retrocore.Aot.Tests.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT execution failed.' }
    'M1 passed: IIe MMU, original/enhanced ProDOS boot, all 128 KiB oracle comparison, source F5, conditional breakpoints, step-over JSR, evaluate, and Native AOT.'
}
finally { Pop-Location }
