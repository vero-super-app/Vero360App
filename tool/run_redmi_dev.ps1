# Live development on Redmi 8A (hot reload).
# Debug on this phone OOMs the Adreno GPU — so debug uses CPU Skia instead.
#
#   .\tool\run_redmi_dev.ps1            → debug + software render (press r to hot-reload)
#   .\tool\run_redmi_dev.ps1 -Profile   → profile / GPU Skia (press R to hot-restart)

param(
  [switch]$Profile,
  [switch]$Debug
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

function Resolve-Adb {
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    (Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'),
    (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk\platform-tools\adb.exe'),
    (Join-Path $env:USERPROFILE 'AppData\Local\Android\sdk\platform-tools\adb.exe')
  )
  if ($env:ANDROID_HOME) {
    $candidates = @(Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe') + $candidates
  }
  if ($env:ANDROID_SDK_ROOT) {
    $candidates = @(Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe') + $candidates
  }

  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

$adb = Resolve-Adb
if ($adb) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $adb start-server 2>&1 | Out-Null
  & $adb shell am force-stop com.vero265.app 2>&1 | Out-Null
  $ErrorActionPreference = $prev
}

$useProfile = $Profile -and -not $Debug
$mode = if ($useProfile) { 'profile' } else { 'debug' }

Write-Host @"
Running in $mode on Redmi 8A (Impeller off, 32-bit ARM).

  Hot reload  -> press r   (debug)
  Hot restart -> press R
  Quit        -> press q

Close Chrome, WhatsApp, and other apps on the phone first.
"@

# `--target-platform` is build-only; `flutter run` rejects it.
$flutterArgs = @(
  'run',
  "--$mode",
  '--no-enable-impeller'
)

if (-not $useProfile) {
  # Bypass Adreno sharedmem OOM so debug + hot reload can stay attached.
  $flutterArgs += '--enable-software-rendering'
  $flutterArgs += '--no-track-widget-creation'
  Write-Host 'Debug uses CPU rendering (not GPU) so this 2GB phone can hot-reload.' -ForegroundColor Cyan
}

& flutter @flutterArgs
