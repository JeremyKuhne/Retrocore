# Downloads xtrs's trs_chars.c at a pinned commit into the external cache, where Trs80RomSourceTests compares
# CharacterGeneratorKit.asm with its reconstruction of the Radio Shack lowercase kit's font (CG 2). The file is
# xtrs's own and is never copied into the workspace.
param(
    [string] $Cache = (Join-Path (Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Retrocore' }) 'trs80-fonts') 'xtrs')
)

$ErrorActionPreference = 'Stop'
$commit = '3a2180c063811a715faa28d39a94739c33e0abd0'
$expected = '1B8BBB9D63A8D598E58F64E831FC11A08F61A82E5C2EB0F631E5CC7BE1464166'
$Cache = [System.IO.Path]::GetFullPath($Cache)
$repo = [System.IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
if ($Cache.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or $Cache.StartsWith("$repo$([System.IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'External fixtures must not be cached in the workspace.'
}

New-Item -ItemType Directory -Path $Cache -Force | Out-Null
$path = Join-Path $Cache 'trs_chars.c'
$temporary = "$path.download"
Invoke-WebRequest "https://raw.githubusercontent.com/TimothyPMann/xtrs/$commit/trs_chars.c" -OutFile $temporary
$hash = (Get-FileHash $temporary -Algorithm SHA256).Hash
if ($hash -ne $expected) {
    Remove-Item $temporary
    throw "trs_chars.c has SHA-256 $hash, not $expected."
}

Move-Item $temporary $path -Force
Write-Output "Fetched $path (xtrs $commit)."
