# Exercises the measurement script with deterministic child-process results; no benchmarks or builds run.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$measurement = Join-Path $PSScriptRoot 'Measure-IIePerformance.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('retrocore-performance-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
$disk = Join-Path $temporary 'input.dsk'
[IO.File]::WriteAllBytes($disk, [byte[]]@(0))
$culture = [Globalization.CultureInfo]::CurrentCulture
$cases = @(
    @{Culture='en-US'; Rates=@(40, 60); Affinity=0xF; ExpectedAffinity=0xF},
    @{Culture='de-DE'; Rates=@(40, 60); Affinity=0xF5; ExpectedAffinity=0x50},
    @{Culture='de-DE'; Rates=@(60, 40, 50); Affinity=0x1; ExpectedAffinity=0x1}
)

function Start-Process {
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError,
        [switch]$PassThru
    )

    if ($ArgumentList -ne '--benchmark 10' -and $ArgumentList -notlike '--smoke-seconds 1.5 *') {
        throw "Duration argument is not invariant: $ArgumentList"
    }

    $run = [int][regex]::Match($RedirectStandardOutput, '-(\d+)\.txt$').Groups[1].Value
    $rate = $script:rates[$run - 1].ToString('0.000', [Globalization.CultureInfo]::InvariantCulture)
    [IO.File]::WriteAllText($RedirectStandardOutput, @"
RunCycles ends where stepping does: yes
host at max speed: $rate MHz
seconds: 1.500
emulated throughput: $rate MHz, 1,000 cycles
  screen: RETROCORE IIE APPLESOFT BENCHMARK
  screen: ...
"@)
    [IO.File]::WriteAllText($RedirectStandardError, '')
    $child = [pscustomobject]@{
        ProcessorAffinity=[IntPtr]$script:initialAffinity; ExitCode=0; HasExited=$false; Id=0
    }
    $child | Add-Member ScriptMethod WaitForExit { $this.HasExited = $true }
    $child | Add-Member ScriptMethod Dispose {}
    $script:children.Add($child)
    return $child
}

# Preserve structured summaries so their numeric values, not table formatting, are checked.
function Format-Table {
    param([Parameter(ValueFromPipeline)]$InputObject, [switch]$AutoSize)
    process { $InputObject }
}

try {
    foreach ($case in $cases) {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($case.Culture)
        $script:rates = $case.Rates
        $script:initialAffinity = $case.Affinity
        $script:children = [Collections.Generic.List[object]]::new()
        $output = Join-Path $temporary "$($case.Culture)-$($case.Affinity)"
        $summaries = @(. $measurement -BuildRoot $temporary -OutputDirectory $output -DiskImage $disk `
            -Modes aot -Repetitions $case.Rates.Count -Seconds 1.5 -SkipCpu)
        if ($summaries.Count -ne 2) { throw 'Expected headless and visible-window summaries.' }
        foreach ($summary in $summaries) {
            if ($summary.MedianMHz -ne 50 -or $summary.MinMHz -ne 40 -or $summary.MaxMHz -ne 60) {
                throw "Incorrect summary: $($summary | ConvertTo-Json -Compress)"
            }
        }

        $results = @(Get-Content (Join-Path $output 'results.json') -Raw | ConvertFrom-Json)
        if ($results.Count -ne $case.Rates.Count * 2) { throw 'Measurements are missing.' }
        foreach ($result in $results | Where-Object Scenario -EQ 'visible-applesoft') {
            if ($result.Seconds -ne 1.5 -or $result.Cycles -ne 1000) { throw 'Incorrect invariant parsing.' }
        }
        foreach ($child in $script:children) {
            if ($child.ProcessorAffinity.ToInt64() -ne $case.ExpectedAffinity) {
                throw 'The preferred mask was not applied or inherited affinity was not preserved.'
            }
        }

        Write-Host "Passed $($case.Culture), $($case.Rates.Count) samples, inherited mask $($case.Affinity)."
    }
}
finally {
    [Globalization.CultureInfo]::CurrentCulture = $culture
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
