# Run after Fetch-ProcessorTests.ps1. Requires .NET 10 and the Windows Native AOT toolchain.
# Tests fail explicitly if cached fixtures are missing. No downloads occur inside the tests.
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot
Push-Location $repo
try {
    dotnet test .\tests\Retrocore.Tests\Retrocore.Tests.csproj -c Release --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'CPU conformance, signal, or functional tests failed.' }

    dotnet publish .\tests\Retrocore.Aot.Tests\Retrocore.Aot.Tests.csproj -c Release -r win-x64 -o .\artifacts\aot --verbosity minimal -warnaserror
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT publication failed.' }
    & .\artifacts\aot\Retrocore.Aot.Tests.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native AOT execution failed.' }

    $artifacts = Join-Path $repo ("artifacts\m0-benchmarks\" + [Guid]::NewGuid().ToString('N'))
    dotnet run --project .\tests\Retrocore.Perf\Retrocore.Perf.csproj -c Release -f net10.0 -- --filter '*ProcessorBenchmarks*' --exporters json --artifacts $artifacts
    if ($LASTEXITCODE -ne 0) { throw 'BenchmarkDotNet execution failed.' }
    $path = Join-Path $artifacts 'results\Retrocore.Perf.ProcessorBenchmarks-report-full-compressed.json'
    $report = Get-Content $path -Raw | ConvertFrom-Json
    if ($report.HostEnvironmentInfo.Configuration -ne 'RELEASE' -or $report.HostEnvironmentInfo.HasAttachedDebugger) {
        throw 'Performance certification requires Release without a debugger.'
    }
    $rows = @($report.Benchmarks)
    if ($rows.Count -ne 3) { throw "Expected three populated benchmark rows, found $($rows.Count)." }
    foreach ($variant in 'Mos6502', 'Wdc65C02', 'Rockwell65C02') {
        $matching = @($rows | Where-Object { $_.FullName -eq "Retrocore.Perf.ProcessorBenchmarks.StepCycles(Variant: $variant)" })
        if ($matching.Count -ne 1) { throw "Missing or duplicate result for $variant." }
        $row = $matching[0]
        $mean = [double]$row.Statistics.Mean
        $upper = [double]$row.Statistics.ConfidenceInterval.Upper
        $actual = @($row.Measurements | Where-Object { $_.IterationStage -eq 'Actual' -and $_.IterationMode -eq 'Workload' })
        # Statistics exclude detected outliers; validate the actual full-job sample count separately.
        if ($actual.Count -lt 15 -or $row.Statistics.N -lt 2 -or -not [double]::IsFinite($mean) -or $mean -le 0 -or -not [double]::IsFinite($upper) -or $upper -le 0) {
            throw "Insufficient or invalid measurement for $variant."
        }
        if ($row.Memory.TotalOperations -le 0 -or $row.Memory.BytesAllocatedPerOperation -ne 0) {
            throw "Empty work or managed allocations in the $variant execution loop."
        }
        $lowerThroughput = 1e9 / $upper
        if ($lowerThroughput -lt 51025000) { throw "$variant failed the 51.025M cycles/sec confidence-bound gate." }
        "$variant : $([math]::Round(1e9 / $mean / 1e6, 2)) M cycles/sec; conservative bound $([math]::Round($lowerThroughput / 1e6, 2)) M; 0 B/cycle."
    }
    "M0 passed: full pinned bus traces, external Klaus success loops, Native AOT, and >=50x real-time throughput."
    "Performance report: $path"
}
finally {
    Pop-Location
}
