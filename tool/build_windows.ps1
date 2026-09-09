param(
    [switch]$StandaloneToolchain,
    [ValidateSet('x64', 'arm64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot
try {
    $dartVersion = & dart.bat --version 2>&1
    if ($LASTEXITCODE -ne 0 -or ($dartVersion -join "`n") -notmatch 'windows_(x64|arm64)') {
        throw 'A native Windows x64 or ARM64 Dart SDK is required'
    }
    $hostArchitecture = $Matches[1]
    if ($Architecture -and $Architecture -ne $hostArchitecture) {
        throw "Build on a matching OS/CPU: Dart is $hostArchitecture, requested $Architecture"
    }
    $Architecture = $hostArchitecture
    $targetArchitecture = if ($Architecture -eq 'x64') { 'x86_64' } else { 'arm64' }
    if ($StandaloneToolchain) {
        # Run inside an environment with cl.exe, rc.exe, cmake and ninja on PATH,
        # and INCLUDE/LIB set to the matching MSVC and Windows SDK directories.
        foreach ($command in @('cl.exe', 'rc.exe', 'cmake.exe', 'ninja.exe', 'flutter.bat')) {
            Get-Command $command -ErrorAction Stop | Out-Null
        }
        & flutter.bat pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed' }
        # Flutter generates its standard CMake environment before VS discovery.
        $configuration = & flutter.bat build windows --release --config-only 2>&1
        $configuration | Set-Content -LiteralPath 'build/windows-configuration.log'
        if ($LASTEXITCODE -ne 0 -and (($configuration -join "`n") -notmatch 'Unable to find suitable Visual Studio toolchain')) {
            throw ($configuration -join "`n")
        }
        if (-not (Test-Path -LiteralPath 'windows/flutter/ephemeral/generated_config.cmake')) {
            throw 'Flutter did not generate its CMake environment'
        }
        $output = "build/windows/$Architecture"
        & cmake.exe -S windows -B $output -G 'Ninja Multi-Config' '-DCMAKE_C_COMPILER=cl.exe' '-DCMAKE_CXX_COMPILER=cl.exe'
        if ($LASTEXITCODE -ne 0) { throw 'Windows CMake configuration failed' }
        # Ninja needs the generated import library before it plans runner linkage.
        & cmake.exe --build $output --config Release --target flutter_assemble
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows assembly failed' }
        & cmake.exe --build $output --config Release
        if ($LASTEXITCODE -ne 0) { throw 'Windows compilation failed' }
        & cmake.exe --install $output --config Release
        if ($LASTEXITCODE -ne 0) { throw 'Windows bundle installation failed' }
        & dart.bat run tool/build.dart --skip-build --target-arch $targetArchitecture
    } else {
        & dart.bat run tool/build.dart --target-arch $targetArchitecture
    }
    if ($LASTEXITCODE -ne 0) { throw 'Windows portable directory packaging failed' }
} finally {
    Pop-Location
}
