# Self-hosts the Retrocore extension: builds it and the language server, then opens the repository in a separate
# VS Code window running the in-repo extension, so its highlighting, IntelliSense and debugging can be seen.
# The window has its own profile and extensions, under artifacts\self-host; your VS Code profile is not touched.
#
#   .\tools\Start-SelfHost.ps1                        # opens sample\trs80\hello.asm
#   .\tools\Start-SelfHost.ps1 -File sample\iie\main.s
#   .\tools\Start-SelfHost.ps1 -SkipBuild             # relaunch without building
#   .\tools\Start-SelfHost.ps1 -RomDirectory <dir>    # IIe launches use these ROM dumps, not the SDK-built ROMs
param(
    [string[]] $File = @('sample\trs80\hello.asm'),
    [string] $RomDirectory = $env:RETROCORE_IIE_ROMS,
    [switch] $SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$code = Get-Command code -ErrorAction SilentlyContinue
if (-not $code) { throw "VS Code's 'code' command is not on PATH. In VS Code run 'Shell Command: Install ''code'' command in PATH', or add its bin folder." }

Push-Location $root
try {
    if (-not $SkipBuild) {
        if (-not (Test-Path -LiteralPath 'extension\node_modules')) {
            npm --prefix .\extension ci
            if ($LASTEXITCODE -ne 0) { throw 'npm ci failed in extension.' }
        }

        npm --prefix .\extension run compile
        if ($LASTEXITCODE -ne 0) { throw 'The extension did not compile.' }

        # The language server runs from the debug host; the extension finds it under artifacts in the workspace.
        dotnet build .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release -warnaserror
        if ($LASTEXITCODE -ne 0) {
            # A stale MSBuild server can fail to load projects that exist; one retry after shutting it down.
            dotnet build-server shutdown | Out-Null
            dotnet build .\src\Retrocore.Debug\Retrocore.Debug.csproj -c Release -warnaserror
            if ($LASTEXITCODE -ne 0) { throw 'The debug host, which runs the language server, did not build.' }
        }
    }

    $files = foreach ($item in $File) {
        $path = if ([IO.Path]::IsPathRooted($item)) { $item } else { Join-Path $root $item }
        if (-not (Test-Path -LiteralPath $path)) { throw "$item does not exist." }
        (Resolve-Path -LiteralPath $path).Path
    }

    if ($RomDirectory) {
        if (-not (Test-Path -LiteralPath $RomDirectory)) { throw "The ROM directory $RomDirectory does not exist." }
        $env:RETROCORE_IIE_ROMS = $RomDirectory
    }

    $selfHost = Join-Path $root 'artifacts\self-host'
    $userData = Join-Path $selfHost 'profile'
    $extensions = Join-Path $selfHost 'extensions'
    New-Item -ItemType Directory -Path $userData, $extensions -Force | Out-Null
    $arguments = @(
        '--new-window', $root,
        "--extensionDevelopmentPath=$(Join-Path $root 'extension')",
        "--user-data-dir=$userData", "--extensions-dir=$extensions",
        '--skip-welcome', '--skip-release-notes'
    ) + $files

    # From VS Code's own terminal, as when Copilot runs this, the CLI hook would hand the request to that window;
    # without it, code starts the separate development instance.
    Remove-Item Env:VSCODE_IPC_HOOK_CLI -ErrorAction SilentlyContinue
    & $code.Source @arguments
    if ($LASTEXITCODE -ne 0) { throw 'VS Code did not start the development window.' }
    "Opened a VS Code window self-hosting the Retrocore extension on $($files -join ', ')."
    if (-not $RomDirectory) { 'Every machine debugs with ROMs built from the SDK sources; -RomDirectory or RETROCORE_IIE_ROMS gives the IIe dumps instead.' }
}
finally { Pop-Location }
