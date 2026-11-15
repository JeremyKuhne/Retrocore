# Trains equal-cycle math, graphics, and active-stereo workloads before replacing the shipping profile.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$PgoTool,
    [string]$OutputProfile = (Join-Path $PSScriptRoot '..\src\Retrocore.Desktop\Profiles\Apple2-win-x64-net11.mibc')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PgoTool = (Resolve-Path -LiteralPath $PgoTool).Path
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new corpus directory to preserve previous evidence.' }
$null = New-Item -ItemType Directory -Path $OutputDirectory
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$profiles = [Collections.Generic.List[string]]::new()
foreach ($workload in @('math', 'Graphics', 'Mockingboard')) {
    $trainingProfile = Join-Path $output "$workload.mibc"
    $arguments = @{
        OutputDirectory = Join-Path $output $workload
        PgoTool = $PgoTool
        OutputProfile = $trainingProfile
    }
    if ($workload -ne 'math') {
        $disk = Join-Path $output "$workload.dsk"
        dotnet run --project (Join-Path $root 'tools\DosDisk') -c Release -- `
            --output $disk --files (Join-Path $PSScriptRoot "PgoWorkloads\$workload") --run BENCH
        if ($LASTEXITCODE -ne 0) { throw "Building the $workload training disk failed." }
        $arguments.TrainingDisk = $disk
        $arguments.Sound = if ($workload -eq 'Mockingboard') { 'mockingboard' } else { 'off' }
    }

    & (Join-Path $PSScriptRoot 'Update-DesktopPgo.ps1') @arguments
    $profiles.Add($trainingProfile)
}

$merged = Join-Path $output 'merged.mibc'
$mergeArguments = @('merge', '--output', $merged)
foreach ($trainingProfile in $profiles) { $mergeArguments += @('--input', $trainingProfile) }
& $PgoTool @mergeArguments
if ($LASTEXITCODE -ne 0) { throw 'Merging the training corpus failed.' }
& $PgoTool dump --input $merged --output (Join-Path $output 'merged.json')
if ($LASTEXITCODE -ne 0) { throw 'Validating the merged profile failed.' }
$destination = [IO.Path]::GetFullPath($OutputProfile)
$null = New-Item -ItemType Directory -Path (Split-Path $destination) -Force
Copy-Item -LiteralPath $merged -Destination $destination -Force
[ordered]@{
    Target = 'net11.0/win-x64'
    ProfileSha256 = (Get-FileHash $destination).Hash
    Workloads = @($profiles | ForEach-Object {
        Get-Content -LiteralPath ([IO.Path]::ChangeExtension($_, '.json')) -Raw | ConvertFrom-Json
    })
} | ConvertTo-Json -Depth 8 | Set-Content ([IO.Path]::ChangeExtension($destination, '.json'))
Write-Output "Validated corpus profile: $destination"
