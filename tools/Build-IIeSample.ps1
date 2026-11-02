param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tools = Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'm1-dependencies\cc65-source\src'
if (-not (Test-Path (Join-Path $tools 'ca65.exe'))) { throw 'Cached ca65 is missing. Run Fetch-M1Dependencies.ps1.' }
$output = Join-Path $root 'artifacts\iie-sample'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Push-Location $root
try {
    & (Join-Path $tools 'ca65.exe') -g (Join-Path $root 'sample\iie\main.s') -o (Join-Path $output 'main.o')
    if ($LASTEXITCODE -ne 0) { throw 'ca65 sample assembly failed.' }
    & (Join-Path $tools 'ld65.exe') -C .\sample\iie\link.cfg (Join-Path $output 'main.o') -o (Join-Path $output 'main.bin') --dbgfile (Join-Path $output 'main.dbg') -Ln (Join-Path $output 'main.lbl')
    if ($LASTEXITCODE -ne 0) { throw 'ld65 sample linking failed.' }
}
finally { Pop-Location }
