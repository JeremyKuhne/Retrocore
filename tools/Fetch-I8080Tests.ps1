# Requires PowerShell 7, gh, and git. Downloads about 26 KiB into the external, pinned cache that
# Fetch-ProcessorTests.ps1 also uses: the 8080 CP/M test programs 8080PRE, TST8080 (Microcosm Associates),
# CPUTEST (SuperSoft Associates) and 8080EXM (Frank D. Cringle's exerciser, ported to the 8080 by Ian Bartholomew),
# as collected in superzazu/8080. They are test inputs only; nothing is copied into the workspace.
param(
    [string] $Cache = (Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'processor-tests')
)

$ErrorActionPreference = 'Stop'
$Cache = [System.IO.Path]::GetFullPath($Cache)
$repo = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
if ($Cache.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or $Cache.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'External test programs must not be cached in the workspace.'
}

# Downloads the files a pinned tree lists, checking each one's Git blob hash, then writes the manifest.
function Get-Pinned([string] $Repository, [string] $Pin, [scriptblock] $Select, [int] $Expected) {
    $root = Join-Path $Cache $Pin
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $treeJson = gh api "repos/$Repository/git/trees/$Pin`?recursive=1"
    if ($LASTEXITCODE -ne 0) { throw "Unable to fetch the pinned $Repository manifest." }
    $files = @(($treeJson | ConvertFrom-Json).tree | Where-Object { $_.type -eq 'blob' } | Where-Object $Select)
    if ($files.Count -ne $Expected) { throw "Unexpected $Repository manifest: $($files.Count) files." }
    foreach ($file in $files) {
        $path = Join-Path $root ($file.path.Replace('/', '\'))
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        if (-not (Test-Path -LiteralPath $path)) {
            $temporary = "$path.download"
            Invoke-WebRequest "https://raw.githubusercontent.com/$Repository/$Pin/$($file.path)" -OutFile $temporary
            Move-Item -LiteralPath $temporary -Destination $path
        }
        $hash = git hash-object -- $path
        if ($LASTEXITCODE -ne 0 -or $hash -ne $file.sha) { throw "Fixture hash mismatch: $path" }
    }
    $files | Select-Object path, sha, size | ConvertTo-Json | Set-Content (Join-Path $root 'manifest.json')
    return $root
}

$programs = Get-Pinned 'superzazu/8080' '274ffd700b81baabea99b0963bc1260b67132185' {
    $_.path -in @('cpu_tests/8080PRE.COM', 'cpu_tests/TST8080.COM', 'cpu_tests/CPUTEST.COM', 'cpu_tests/8080EXM.COM', 'LICENSE')
} 5

Write-Output "Verified the 8080 test programs at $programs."
