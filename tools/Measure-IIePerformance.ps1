# Measures already-published executables; never builds while timing.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BuildRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$DiskImage,
    [string]$Variant = 'baseline',
    [ValidateSet('jit', 'r2r', 'aot')][string[]]$Modes = @('jit', 'r2r', 'aot'),
    [ValidateRange(1, 100)][int]$Repetitions = 3,
    [ValidateRange(1, 3600)][double]$Seconds = 15,
    [ValidateSet('off', 'speaker', 'mockingboard')][string]$Sound = 'off',
    [switch]$SkipCpu,
    [switch]$SkipHeadless
)

$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$BuildRoot = (Resolve-Path -LiteralPath $BuildRoot).Path
$DiskImage = (Resolve-Path -LiteralPath $DiskImage).Path
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Use a new output directory to preserve previous results.' }
$null = New-Item -ItemType Directory -Path $OutputDirectory
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$results = [Collections.Generic.List[object]]::new()

function Invoke-Measurement([string]$Executable, [string]$Arguments, [string]$Label) {
    $stdout = Join-Path $OutputDirectory "$Label.txt"
    $stderr = Join-Path $OutputDirectory "$Label.err"
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    try {
        if (($process.ProcessorAffinity.ToInt64() -band 0x50) -eq 0x50) {
            $process.ProcessorAffinity = [IntPtr]0x50
        }
        else {
            Write-Verbose "Keeping inherited processor affinity for $Label; cores selected by 0x50 are unavailable."
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "$Label exited $($process.ExitCode): $(Get-Content $stderr -Raw)" }
        if ((Get-Item -LiteralPath $stderr).Length -ne 0) { throw "$Label wrote stderr: $(Get-Content $stderr -Raw)" }
        $text = Get-Content -LiteralPath $stdout -Raw
        Write-Host "Completed $Label"
        return $text
    }
    finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
        $process.Dispose()
    }
}

$configuration = @{machine='apple2'; diskImage=$DiskImage; sound=$Sound} | ConvertTo-Json -Compress
$windowArguments = '--smoke-seconds ' + $Seconds.ToString($invariant) + ' --speed 0 --fast-drives off --machine "' +
    $configuration.Replace('"', '\"') + '"'

foreach ($run in 1..$Repetitions) {
    foreach ($mode in $Modes) {
        $exe = Join-Path $BuildRoot "desktop-$mode-$Variant\retrocore-desktop.exe"
        if (-not $SkipHeadless) {
            $text = Invoke-Measurement $exe '--benchmark 10' "$mode-headless-$run"
            if ($text -notmatch 'RunCycles ends where stepping does: yes') { throw 'Headless parity failed.' }
            $match = [regex]::Match($text, 'host at max speed: ([\d.]+) MHz')
            if (-not $match.Success) { throw 'Missing headless throughput.' }
            $results.Add([pscustomobject]@{Mode=$mode; Scenario='headless-idle'; Run=$run; MHz=[double]::Parse($match.Groups[1].Value, $invariant)})
        }

        $text = Invoke-Measurement $exe $windowArguments "$mode-applesoft-$run"
        if ($text -notmatch 'RETROCORE IIE APPLESOFT BENCHMARK' -or $text -notmatch 'screen: \.{3}') {
            throw 'AppleSoft workload did not produce its title and progress.'
        }

        $match = [regex]::Match($text, 'emulated throughput: ([\d.]+) MHz, ([\d,]+) cycles')
        $duration = [regex]::Match($text, '(?m)^seconds: ([\d.]+)')
        if (-not $match.Success -or -not $duration.Success) { throw 'Missing complete-interval measurement.' }
        $results.Add([pscustomobject]@{
            Mode=$mode; Scenario='visible-applesoft'; Run=$run; MHz=[double]::Parse($match.Groups[1].Value, $invariant)
            Cycles=[ulong]::Parse($match.Groups[2].Value, [Globalization.NumberStyles]::AllowThousands, $invariant)
            Seconds=[double]::Parse($duration.Groups[1].Value, $invariant)
        })
    }
}

if (-not $SkipCpu) {
    foreach ($mode in $Modes) {
        $exe = Join-Path $BuildRoot "cpu-$mode-$Variant\Retrocore.Aot.Tests.exe"
        $null = Invoke-Measurement $exe '--benchmark-cpu' "$mode-cpu"
    }
}

$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'results.json')
$results | Group-Object Mode,Scenario | ForEach-Object {
    $values = @($_.Group.MHz | Sort-Object)
    $middle = [int][Math]::Floor($values.Count / 2)
    $median = if ($values.Count % 2) { $values[$middle] } else { ($values[$middle - 1] + $values[$middle]) / 2 }
    [pscustomobject]@{
        Scenario=$_.Name; MedianMHz=$median
        MinMHz=$values[0]; MaxMHz=$values[-1]
    }
} | Format-Table -AutoSize
