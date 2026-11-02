# Packages the Retrocore extension, with the debug host and language server it runs, as a VSIX and installs it in
# VS Code, so your everyday editor uses it in any folder. Run it again after a fix you want to keep; then reload
# VS Code's windows. Self-hosting (Start-SelfHost.ps1) is separate: it runs the in-repo extension in its own profile.
#
#   .\tools\Install-Extension.ps1                   # build, package and install in your VS Code
#   .\tools\Install-Extension.ps1 -PackageOnly      # just write artifacts\vsix\retrocore-<version>.vsix
#   .\tools\Install-Extension.ps1 -UserDataDir <dir> -ExtensionsDir <dir>   # install in another profile
param(
    [switch] $PackageOnly,
    [string] $UserDataDir,
    [string] $ExtensionsDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$extension = Join-Path $root 'extension'
$server = Join-Path $extension 'server'
$license = Join-Path $extension 'LICENSE'
Push-Location $root
try {
    if (-not (Test-Path -LiteralPath (Join-Path $extension 'node_modules'))) {
        npm --prefix .\extension ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed in extension.' }
    }

    npm --prefix .\extension run compile
    if ($LASTEXITCODE -ne 0) { throw 'The extension did not compile.' }

    # The host the installed extension runs, framework-dependent: it needs the .NET 10 runtime.
    if (Test-Path -LiteralPath $server) { Remove-Item -LiteralPath $server -Recurse -Force }
    dotnet publish .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release -o $server -warnaserror
    if ($LASTEXITCODE -ne 0) {
        # A stale MSBuild server can fail to load projects that exist; one retry after shutting it down.
        dotnet build-server shutdown | Out-Null
        dotnet publish .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release -o $server -warnaserror
        if ($LASTEXITCODE -ne 0) { throw 'The debug host did not publish.' }
    }

    $version = (Get-Content -LiteralPath (Join-Path $extension 'package.json') -Raw | ConvertFrom-Json).version
    $output = Join-Path $root "artifacts\vsix\retrocore-$version.vsix"
    New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null

    # The repository's license goes in the package beside the extension, for the time it is packaged.
    Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $license -Force
    Push-Location $extension
    try {
        # The README's links point into the repository, which has no public home yet.
        npx vsce package --out $output --allow-missing-repository --no-rewrite-relative-links
        if ($LASTEXITCODE -ne 0) { throw 'vsce could not package the extension.' }
    }
    finally {
        Pop-Location
        Remove-Item -LiteralPath $license -Force -ErrorAction SilentlyContinue
    }

    "Packaged $output."
    if ($PackageOnly) { return }

    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) { throw "VS Code's 'code' command is not on PATH." }
    $arguments = @('--install-extension', $output, '--force')
    if ($UserDataDir) { $arguments += "--user-data-dir=$UserDataDir" }
    if ($ExtensionsDir) { $arguments += "--extensions-dir=$ExtensionsDir" }

    # Another profile needs its own instance, not the running window's.
    if ($UserDataDir -or $ExtensionsDir) { Remove-Item Env:VSCODE_IPC_HOOK_CLI -ErrorAction SilentlyContinue }
    & $code.Source @arguments
    if ($LASTEXITCODE -ne 0) { throw 'VS Code could not install the extension.' }
    "Installed Retrocore $version. Reload VS Code's windows to use it."
}
finally { Pop-Location }
