# Develop on Redmi 8A with Flutter attached (live updates).
# Release APKs cannot hot-reload — use this instead of run_redmi.ps1 while coding.
#
# Modes:
#   .\tool\run_redmi_dev.ps1           → profile (stable on 2GB; press R to hot-restart)
#   .\tool\run_redmi_dev.ps1 -Debug    → debug (press r to hot-reload; heavier, may crash)

param(
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
  $ErrorActionPreference = $prev
}

# Impeller stays off via AndroidManifest / VeroApplication.
# Prefer a single ABI on this phone so the install stays small.
$mode = if ($Debug) { 'debug' } else { 'profile' }

Write-Host @"
Running in $mode on Redmi (Impeller off).

  Hot reload  -> press r   (debug mode only)
  Hot restart -> press R   (profile + debug)
  Quit        -> press q

Close other apps on the phone first.
"@

if ($Debug) {
  flutter run --debug --no-enable-impeller
} else {
  flutter run --profile --no-enable-impeller
}
