# Requires PowerShell 7, gh, and git. Downloads only the approved MC6809 test programs and license
# into the external processor-test cache; GPL files are never copied into the workspace.
param(
    [string] $Cache = (Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'processor-tests')
)

$ErrorActionPreference = 'Stop'
$Cache = [System.IO.Path]::GetFullPath($Cache)
$repo = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
if ($Cache.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or $Cache.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'External GPL fixtures must not be cached in the workspace.'
}

$repository = 'reyco2000/6809_6309_code_tester'
$pin = 'f445da35665991ec00a7bfc3ab4ce36f4482687e'
$root = Join-Path $Cache $pin
New-Item -ItemType Directory -Path $root -Force | Out-Null
$treeJson = gh api "repos/$repository/git/trees/$pin`?recursive=1"
if ($LASTEXITCODE -ne 0) { throw 'Unable to fetch the pinned MC6809 fixture manifest.' }
$files = @(($treeJson | ConvertFrom-Json).tree | Where-Object {
    $_.type -eq 'blob' -and $_.path -in @(
        'bin/6809_cycle_test.s19',
        'bin/6809_functional_test.s19',
        'bin/6809_interrupt_test.s19',
        'license.txt')
})
if ($files.Count -ne 4) { throw "Unexpected MC6809 fixture manifest: $($files.Count) files." }

foreach ($file in $files) {
    $path = Join-Path $root ($file.path.Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $path)) {
        $temporary = "$path.download"
        $url = "https://raw.githubusercontent.com/$repository/$pin/" +
            (($file.path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
        Invoke-WebRequest $url -OutFile $temporary
        Move-Item -LiteralPath $temporary -Destination $path
    }

    $hash = git hash-object -- $path
    if ($LASTEXITCODE -ne 0 -or $hash -ne $file.sha) { throw "Fixture hash mismatch: $path" }
}

$files | Select-Object path, sha, size | ConvertTo-Json | Set-Content (Join-Path $root 'manifest.json')
Write-Output "Verified the approved MC6809 fixtures at $root."
