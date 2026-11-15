# Builds the official, pinned .NET 11 profile converter without building the native runtime.
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts\pgo-tool')
)

$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$base = (Resolve-Path -LiteralPath $OutputDirectory).Path
$source = Join-Path $base 'runtime'
$variables = @{
    DOTNET_CLI_HOME = Join-Path $base 'cli-home'
    DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
    DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE = 'true'
    NUGET_PACKAGES = Join-Path $base 'packages'
    NUGET_HTTP_CACHE_PATH = Join-Path $base 'http-cache'
    NUGET_PLUGINS_CACHE_PATH = Join-Path $base 'plugins-cache'
    TEMP = Join-Path $base 'build-temp'
    TMP = Join-Path $base 'build-temp'
}
$previous = @{}
$location = Get-Location
try {
    foreach ($name in $variables.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }

    $null = New-Item -ItemType Directory -Path $variables.TEMP -Force
    Set-Location $base
    if (-not (Test-Path -LiteralPath (Join-Path $source '.git'))) {
        git clone --depth 1 --branch v11.0.0 --filter=blob:none --sparse https://github.com/dotnet/runtime.git $source
        if ($LASTEXITCODE -ne 0) { throw 'Cloning the profile converter source failed.' }
    }

    git -C $source sparse-checkout set eng src/coreclr/tools src/libraries/Common src/libraries/Microsoft.NETCore.Platforms src/libraries/System.Runtime.InteropServices/gen/LibraryImportGenerator docs/design/features
    if ($LASTEXITCODE -ne 0) { throw 'Fetching the profile converter dependencies failed.' }
    $commit = (git -C $source rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -ne 'deae2e32bf0e018e09d64597b7c59b62b73bb3ce') {
        throw "Unexpected runtime source revision: $commit"
    }

    Set-Location $source
    dotnet build .\src\coreclr\tools\dotnet-pgo\dotnet-pgo.csproj -c Release `
        -p:TargetArchitecture=x64 -p:TargetOS=windows -p:NetCoreAppToolCurrent=net11.0 `
        -p:NetCoreAppMinimum=net11.0 -p:BuildNative=false -p:UseSharedCompilation=false `
        -p:_RequiresLiveILLink=false -p:IsTrimmable=false -p:EnableTrimAnalyzer=false `
        -p:RunAnalyzers=false -p:DotNetBuildSourceOnly=true --disable-build-servers --nologo -v minimal
    if ($LASTEXITCODE -ne 0) { throw 'Building the profile converter failed.' }
    $bin = Join-Path $base 'bin'
    $null = New-Item -ItemType Directory -Path $bin -Force
    Copy-Item (Join-Path $source 'artifacts\bin\coreclr\windows.x64.Release\dotnet-pgo\*') $bin -Recurse -Force
    Copy-Item (Join-Path $source 'LICENSE.TXT'), (Join-Path $source 'THIRD-PARTY-NOTICES.TXT') $bin -Force
    & (Join-Path $bin 'dotnet-pgo.exe') --help
    if ($LASTEXITCODE -ne 0) { throw 'The profile converter did not start.' }
    Write-Output "Profile converter: $bin\dotnet-pgo.exe"
}
finally {
    Set-Location $location
    foreach ($name in $previous.Keys) {
        if ($null -eq $previous[$name]) {
            Remove-Item -LiteralPath "Env:\$name"
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}
