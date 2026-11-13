# Requires PowerShell 7, gh, and git. Downloads approximately 3 GiB into an external, pinned cache.
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
$pin = '2f6980a2d95757486c7bee24355c360e40e2a224'
$klausPin = '7954e2dbb49c469ea286070bf46cdd71aeb29e4b'
$root = Join-Path $Cache $pin
New-Item -ItemType Directory -Path $root -Force | Out-Null
$treeJson = gh api "repos/SingleStepTests/65x02/git/trees/$pin`?recursive=1"
if ($LASTEXITCODE -ne 0) { throw 'Unable to fetch the pinned MIT test manifest.' }
$tree = ($treeJson | ConvertFrom-Json).tree
$files = @($tree | Where-Object { $_.path -match '^(6502|wdc65c02|rockwell65c02)/v1/[0-9a-f]{2}\.json$' -or $_.path -eq 'LICENSE' })
if ($files.Count -ne 769) { throw "Unexpected fixture manifest: $($files.Count) files." }
$files | ForEach-Object -Parallel {
    $ErrorActionPreference = 'Stop'
    $file = $_
    $path = Join-Path $using:root ($file.path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    if (-not (Test-Path $path)) {
        $temporary = "$path.download"
        Invoke-WebRequest "https://raw.githubusercontent.com/SingleStepTests/65x02/$using:pin/$($file.path)" -OutFile $temporary
        Move-Item $temporary $path
    }
    $hash = git hash-object -- $path
    if ($LASTEXITCODE -ne 0 -or $hash -ne $file.sha) { throw "Fixture hash mismatch: $path" }
} -ThrottleLimit 12
$files | Select-Object path, sha, size | ConvertTo-Json | Set-Content (Join-Path $root 'manifest.json')

# GPL binaries are external test inputs only, never copied into the workspace or packages.
$klaus = Join-Path $Cache $klausPin
New-Item -ItemType Directory -Path $klaus -Force | Out-Null
$klausJson = gh api "repos/Klaus2m5/6502_65C02_functional_tests/git/trees/$klausPin`?recursive=1"
if ($LASTEXITCODE -ne 0) { throw 'Unable to fetch the pinned Klaus test manifest.' }
$klausFiles = @(($klausJson | ConvertFrom-Json).tree | Where-Object { $_.path -match '^bin_files/(6502_functional_test|65C02_extended_opcodes_test)\.bin$' -or $_.path -match '^LICENSE' })
if (@($klausFiles | Where-Object path -Match '\.bin$').Count -ne 2) { throw 'Incomplete Klaus binary manifest.' }
foreach ($file in $klausFiles) {
    $path = Join-Path $klaus (Split-Path $file.path -Leaf)
    if (-not (Test-Path $path)) {
        Invoke-WebRequest "https://raw.githubusercontent.com/Klaus2m5/6502_65C02_functional_tests/$klausPin/$($file.path)" -OutFile $path
    }
    $hash = git hash-object -- $path
    if ($LASTEXITCODE -ne 0 -or $hash -ne $file.sha) { throw "Klaus fixture hash mismatch: $path" }
}
$klausFiles | Select-Object path, sha, size | ConvertTo-Json | Set-Content (Join-Path $klaus 'manifest.json')
Write-Output "Verified MIT SingleStepTests at $root and external GPL Klaus binaries at $klaus."
