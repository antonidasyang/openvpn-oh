# Windows / PowerShell mirror of scripts/fetch-third-party.sh.
# Fetches the native dependencies under entry/src/main/cpp/third_party/.
# Re-running is safe — each clone is skipped if the directory already exists.

$ErrorActionPreference = 'Stop'

Set-Location (Join-Path $PSScriptRoot '..')
$third = 'entry/src/main/cpp/third_party'
New-Item -ItemType Directory -Force -Path $third | Out-Null
Set-Location $third

function Clone-Dep {
    param([string]$Url, [string]$Dir, [string]$Ref)
    if (-not (Test-Path (Join-Path $Dir '.git'))) {
        Write-Host "[clone] $Url -> $Dir @ $Ref"
        & git clone --depth 1 --branch $Ref $Url $Dir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[fallback] full clone of $Url"
            & git clone $Url $Dir
            if ($LASTEXITCODE -ne 0) { throw "clone failed for $Url" }
            Push-Location $Dir
            & git checkout $Ref
            Pop-Location
        }
    } else {
        Write-Host "[skip] $Dir clone exists"
    }
    # mbedtls v3.6+ requires the `framework/` submodule even for non-test
    # builds. Always sync submodules so re-runs pick up anything missed
    # by an older script invocation.
    if (Test-Path (Join-Path $Dir '.gitmodules')) {
        Write-Host "[submodules] $Dir"
        Push-Location $Dir
        & git submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) {
            Pop-Location
            throw "submodule update failed for $Dir"
        }
        Pop-Location
    }
}

Clone-Dep 'https://github.com/OpenVPN/openvpn3.git'       'openvpn3' 'release/3.10'
Clone-Dep 'https://github.com/chriskohlhoff/asio.git'     'asio'     'asio-1-30-2'
Clone-Dep 'https://github.com/Mbed-TLS/mbedtls.git'       'mbedtls'  'v3.6.2'
Clone-Dep 'https://github.com/lz4/lz4.git'                'lz4'      'v1.10.0'

Write-Host ''
Write-Host 'Done. Next steps:'
Write-Host '  1. In DevEco Studio: Build > Clean Project, then Build > Build Hap(s)/App(s).'
Write-Host '  2. If openvpn3 fails to compile against the OHOS NDK, see docs/PATCHES.md.'
