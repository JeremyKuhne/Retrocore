# Opens the self-hosted extension with the IIe ROMs for debugging; Start-SelfHost.ps1 does the work, and needs no
# ROMs for highlighting and IntelliSense alone.
param(
    [Parameter(Mandatory=$true)][string] $RomDirectory
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Start-SelfHost.ps1') -RomDirectory $RomDirectory -File 'sample\iie\main.s'
