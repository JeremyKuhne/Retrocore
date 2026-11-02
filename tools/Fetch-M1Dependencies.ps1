# ROMs are supplied by the caller and are never downloaded or bundled.
param()
$ErrorActionPreference = 'Stop'
$root = Join-Path $(if ($env:RETROCORE_CACHE) { $env:RETROCORE_CACHE } else { Join-Path $env:USERPROFILE 'Retrocore' }) 'm1-dependencies'
New-Item -ItemType Directory -Path $root -Force | Out-Null
foreach ($dependency in @(
    @{ Name='cc65-source'; Url='https://github.com/cc65/cc65.git'; Pin='52727a5b407bfeac0dfac1fdd84be8cd2af4f814'; Paths=@('src','cfg','asminc') }
)) {
    $path = Join-Path $root $dependency.Name
    if (-not (Test-Path $path)) {
        git clone --filter=blob:none --sparse $dependency.Url $path
        if ($LASTEXITCODE -ne 0) { throw "Clone failed: $($dependency.Name)" }
        git -C $path sparse-checkout set @($dependency.Paths)
        if ($LASTEXITCODE -ne 0) { throw "Sparse checkout failed: $($dependency.Name)" }
    }
    git -C $path checkout $dependency.Pin
    if ($LASTEXITCODE -ne 0) { throw "Pinned checkout failed: $($dependency.Name)" }
}
$image = Join-Path $root 'ProDOS_2_4_3.po'
if (-not (Test-Path $image)) {
    # The official releases host currently has a mismatched HTTPS certificate. Verify the published image by hash.
    Invoke-WebRequest 'http://releases.prodos8.com/ProDOS_2_4_3.po' -OutFile $image
}
if ((Get-FileHash $image -Algorithm SHA256).Hash -ne '398D333CB2AB92DF9F8BB2CF64B946F2567116910EB8359CF4BDEE5D4194F0FA') {
    throw 'ProDOS 2.4.3 image hash mismatch.'
}
# Microsoft BASIC for 6502 1.1 (MIT), the MACRO-10 source the IIe SDK builds AppleSoft from.
$basicPin = '7460af2c03ae19c0e60ff327489229d2005b9357'
$basic = Join-Path $root "BASIC-M6502-$basicPin"
if (-not (Test-Path (Join-Path $basic 'm6502.asm'))) {
    $archive = "$basic.zip"
    Invoke-WebRequest "https://github.com/microsoft/BASIC-M6502/archive/$basicPin.zip" -OutFile $archive
    Expand-Archive $archive -DestinationPath $root -Force
}
if ((Get-FileHash (Join-Path $basic 'm6502.asm') -Algorithm SHA256).Hash -ne '8F9E48DCAE34EEFCE0462F1E7C4379DFE2C8AA98C0B772041D9989B40BCBFF3B') {
    throw 'm6502.asm hash mismatch.'
}
# Original BASIC 1.x builds from Michael Steil's msbasic, kept local as references for the MACRO-10 front end.
$msbasicPin = '2a0bc2fe0db13f8cf1b5c40b1d5617263cdb9cb4'
$msbasic = Join-Path $root 'msbasic-2a0bc2fe\orig'
New-Item -ItemType Directory -Path $msbasic -Force | Out-Null
foreach ($binary in @(
    @{ Name='applesoft.bin'; Hash='B2EB363219EEF8B0284122E2A2794FCB1B5DC9882E16700E2E57B2EC9F6911C1' },
    @{ Name='kb9.bin'; Hash='AD10087535C7802B7F2F8FDD643F9AC977EE3D53038E30E10B068DC3152131C0' },
    @{ Name='osi.bin'; Hash='3FBB052D13D376CC8B7D2D72A45F386DEAFA88A5BC0FA1A74D6B69B2352F14C3' },
    @{ Name='cbmbasic1.bin'; Hash='4132164E8C930EF9E5BD0E5D3BD155CE7F74EE7EC65C15492690ECD8AFA20679' }
)) {
    $file = Join-Path $msbasic $binary.Name
    if (-not (Test-Path $file)) {
        Invoke-WebRequest "https://raw.githubusercontent.com/mist64/msbasic/$msbasicPin/orig/$($binary.Name)" -OutFile $file
    }
    if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $binary.Hash) { throw "$($binary.Name) hash mismatch." }
}
$source = Join-Path $root 'cc65-source\src'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio C++ build tools are required for the cached cc65 build.' }
$setup = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
foreach ($tool in 'ca65','ld65') {
    if (-not (Test-Path (Join-Path $source "$tool.exe"))) {
        & $env:ComSpec /c "call `"$setup`" >nul && cd /d `"$source`" && cl /nologo /O2 /std:c17 /I common /D_CRT_SECURE_NO_WARNINGS /Fe:$tool.exe common\*.c $tool\*.c"
        if ($LASTEXITCODE -ne 0) { throw "Native $tool build failed." }
    }
}
"M1 dependencies cached at $root. cc65 is zlib; ROMs remain external."
$oracle = Join-Path $root 'apple2ts'
if (-not (Test-Path $oracle)) {
    git clone --filter=blob:none --sparse https://github.com/ct6502/apple2ts.git $oracle
    if ($LASTEXITCODE -ne 0) { throw 'Apple2TS clone failed.' }
    git -C $oracle sparse-checkout set --no-cone '/src/' '!/src/worker/roms/' '/LICENSE' '/package.json'
    if ($LASTEXITCODE -ne 0) { throw 'Apple2TS sparse checkout failed.' }
}
git -C $oracle checkout ca16c7f487d5980003a2fa87ffc60bbbf3fc8ee3
if ($LASTEXITCODE -ne 0) { throw 'Pinned Apple2TS checkout failed.' }
