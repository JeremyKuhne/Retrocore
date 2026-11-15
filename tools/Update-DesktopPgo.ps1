# Refreshes the Windows x64 application profile from a deterministic SDK-ROM AppleSoft workload.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$PgoTool,
    [string]$TrainingDisk,
    [ValidateSet('off', 'speaker', 'mockingboard')][string]$Sound = 'off',
    [string]$OutputProfile = (Join-Path $PSScriptRoot '..\src\Retrocore.Desktop\Profiles\Apple2-win-x64-net11.mibc')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PgoTool = (Resolve-Path -LiteralPath $PgoTool).Path
$null = Get-Command dotnet-trace -ErrorAction Stop
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new training directory to preserve previous evidence.' }
$null = New-Item -ItemType Directory -Path $OutputDirectory
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
if ($TrainingDisk) {
    $disk = (Resolve-Path -LiteralPath $TrainingDisk).Path
}
else {
    $files = Join-Path $output 'files'
    $null = New-Item -ItemType Directory -Path $files
@'
10 HOME:PRINT "RETROCORE IIE APPLESOFT BENCHMARK"
20 FOR I=1 TO 1000
30 X=SIN(I):A$=STR$(X)
40 NEXT I
50 PRINT ".";
60 GOTO 20
'@ | Set-Content (Join-Path $files 'BENCH.applesoft.bas') -Encoding ascii
    $disk = Join-Path $output 'training.dsk'
    dotnet run --project (Join-Path $root 'tools\DosDisk') -c Release -- --output $disk --files $files --run BENCH
    if ($LASTEXITCODE -ne 0) { throw 'Building the training disk failed.' }
}
$app = Join-Path $output 'app'
dotnet publish (Join-Path $root 'src\Retrocore.Desktop') -c Release -r win-x64 --self-contained true `
    -p:PublishAot=false -p:PublishReadyToRun=false -o $app --nologo -v minimal
if ($LASTEXITCODE -ne 0) { throw 'Building the JIT training application failed.' }

$variables = @{
    DOTNET_TieredCompilation='1'; DOTNET_TieredPGO='1'; DOTNET_TC_QuickJitForLoops='1'
    DOTNET_TC_CallCountThreshold='10000'; DOTNET_ReadyToRun='0'
}
$previous = @{}
$process = [Diagnostics.Process]::GetCurrentProcess()
$affinity = $process.ProcessorAffinity
try {
    foreach ($name in $variables.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }

    $process.ProcessorAffinity = [IntPtr]0x50
    $configuration = @{machine='apple2'; diskImage=$disk; sound=$Sound} | ConvertTo-Json -Compress
    $escaped = '"' + $configuration.Replace('"','\"') + '"'
    $trace = Join-Path $output 'training.nettrace'
    dotnet-trace collect --providers 'Microsoft-Windows-DotNETRuntime:0x1E000080018:5' --show-child-io `
        --output $trace -- dotnet (Join-Path $app 'retrocore-desktop.dll') --benchmark 25 --machine $escaped
    if ($LASTEXITCODE -ne 0) { throw 'Collecting the instrumented training trace failed.' }
    $trainingProfile = Join-Path $output 'training.mibc'
    & $PgoTool create-mibc --trace $trace --output $trainingProfile --reference (Join-Path $app '*.dll')
    if ($LASTEXITCODE -ne 0) { throw 'Converting the training trace failed.' }
    $statistics = & $PgoTool dump --input $trainingProfile --output (Join-Path $output 'profile.json')
    if ($LASTEXITCODE -ne 0) { throw 'Validating the profile failed.' }
    $statistics | Set-Content (Join-Path $output 'profile-statistics.txt')
    $instrumentation = [regex]::Matches(($statistics -join "`n"), '# Methods with \d+-bit (?:edge|block) counts: (\d+)')
    $count = ($instrumentation | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
    if ($count -le 0) { throw 'The profile contains no instrumented method counts.' }
    $destination = [IO.Path]::GetFullPath($OutputProfile)
    $null = New-Item -ItemType Directory -Path (Split-Path $destination) -Force
    Copy-Item -LiteralPath $trainingProfile -Destination $destination -Force
    $assemblies = @{}
    Get-ChildItem -LiteralPath $app -Filter '*retrocore*.dll' | ForEach-Object {
        $assemblies[$_.Name] = (Get-FileHash -LiteralPath $_.FullName).Hash
    }

    [ordered]@{
        RuntimeSource='deae2e32bf0e018e09d64597b7c59b62b73bb3ce'
        Sdk=(dotnet --version); Target='net11.0/win-x64'; InstrumentedMethods=$count
        SourceCommit=(git -C $root rev-parse HEAD); ProfileSha256=(Get-FileHash $destination).Hash
        SourceChanges=@(git -C $root status --porcelain --untracked-files=no); TrainingAssemblies=$assemblies
        DiskSha256=(Get-FileHash $disk).Hash; Sound=$Sound; Provider='Microsoft-Windows-DotNETRuntime:0x1E000080018:5'
    } | ConvertTo-Json | Set-Content ([IO.Path]::ChangeExtension($destination, '.json'))
    Write-Output "Validated profile: $destination ($count instrumented methods)"
}
finally {
    $process.ProcessorAffinity = $affinity
    $process.Dispose()
    foreach ($name in $previous.Keys) {
        if ($null -eq $previous[$name]) {
            Remove-Item -LiteralPath "Env:\$name"
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}
