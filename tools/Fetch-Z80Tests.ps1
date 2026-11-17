# Requires PowerShell 7, gh, and git. Downloads approximately 1.4 GiB into the external, pinned cache that
# Fetch-ProcessorTests.ps1 also uses: the MIT SingleStepTests Z80 opcode files and the GPL ZEXALL/ZEXDOC
# CP/M programs, and the GPL FUSE Z80 tests. Nothing is copied into the workspace.
# The cache follows the tests' precedence: RETROCORE_TEST_CACHE, then RETROCORE_CACHE\processor-tests, then the
# user profile's Retrocore\processor-tests.
param(
    [string] $Cache = $(if ($env:RETROCORE_TEST_CACHE) { $env:RETROCORE_TEST_CACHE } else { Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Retrocore' }) 'processor-tests' })
)

$ErrorActionPreference = 'Stop'
$Cache = [System.IO.Path]::GetFullPath($Cache)
$repo = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
if ($Cache.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or $Cache.StartsWith("$repo$([System.IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'External GPL fixtures must not be cached in the workspace.'
}

# Downloads the files a pinned tree lists, checking each one's Git blob hash, then writes the manifest.
function Get-Pinned([string] $Repository, [string] $Pin, [scriptblock] $Select, [int] $Expected) {
    $root = Join-Path $Cache $Pin
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $treeJson = gh api "repos/$Repository/git/trees/$Pin`?recursive=1"
    if ($LASTEXITCODE -ne 0) { throw "Unable to fetch the pinned $Repository manifest." }
    $files = @(($treeJson | ConvertFrom-Json).tree | Where-Object { $_.type -eq 'blob' } | Where-Object $Select)
    if ($files.Count -ne $Expected) { throw "Unexpected $Repository manifest: $($files.Count) files." }
    $files | ForEach-Object -Parallel {
        $ErrorActionPreference = 'Stop'
        $file = $_
        $path = Join-Path $using:root ($file.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        if (-not (Test-Path -LiteralPath $path)) {
            $temporary = "$path.download"
            $url = "https://raw.githubusercontent.com/$using:Repository/$using:Pin/" + (($file.path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
            Invoke-WebRequest $url -OutFile $temporary
            Move-Item -LiteralPath $temporary -Destination $path
        }
        $hash = git hash-object -- $path
        if ($LASTEXITCODE -ne 0 -or $hash -ne $file.sha) { throw "Fixture hash mismatch: $path" }
    } -ThrottleLimit 12
    $files | Select-Object path, sha, size | ConvertTo-Json | Set-Content (Join-Path $root 'manifest.json')
    return $root
}

# SingleStepTests/z80: one JSON file per opcode, unprefixed and CB, ED, DD, FD, DD CB and FD CB.
$singleStep = Get-Pinned 'SingleStepTests/z80' 'ebe1875d48f374bcfd4b505d8eb8ee751568b5f7' {
    $_.path -match '^v1/[0-9a-f _]+\.json$' -or $_.path -eq 'LICENSE'
} 1605

# ZEXALL and ZEXDOC, Frank D. Cringle's exercisers as maintained by agn453; GPL binaries are test inputs only.
$zexall = Get-Pinned 'agn453/ZEXALL' '8f71d418bae69a476a5a0e5c6e122c8801b8d9f4' {
    $_.path -in @('zexall.com', 'zexdoc.com', 'LICENSE')
} 3

# FUSE's Z80 tests: an input state per test and the bus events and state it should reach. GPL inputs only.
$fuse = Get-Pinned 'FuseEmulator/fuse-emulator-svn' '6d82fee65377fb68432120c58802b76240198121' {
    $_.path -in @('fuse/z80/tests/tests.in', 'fuse/z80/tests/tests.expected', 'fuse/COPYING')
} 3

Write-Output "Verified MIT SingleStepTests Z80 at $singleStep, and external GPL ZEXALL/ZEXDOC at $zexall and FUSE tests at $fuse."
