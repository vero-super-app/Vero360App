# Compressed build for Redmi 8A (32-bit ARM / 2GB RAM).
# Do NOT use plain `flutter run` (debug) — it will OOM.

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

  throw @"
adb not found. Install Android platform-tools, or add this to PATH:
  $env:LOCALAPPDATA\Android\Sdk\platform-tools
"@
}

function Invoke-Adb {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args,
    [switch]$AllowFail
  )
  # adb prints status on stderr (e.g. "daemon not running"); don't treat that as fatal.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = & $script:adb @Args 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev

  foreach ($line in $output) {
    Write-Host $line
  }

  if (-not $AllowFail -and $code -ne 0) {
    throw "adb $($Args -join ' ') failed ($code)"
  }
  return $code
}

$script:adb = Resolve-Adb
Write-Host "Using adb: $script:adb"

Write-Host 'Starting adb server...'
Invoke-Adb -Args @('start-server') -AllowFail | Out-Null

Write-Host 'Waiting for device (unlock phone + allow USB debugging)...'
Invoke-Adb -Args @('wait-for-device') | Out-Null

Write-Host 'Uninstalling old build (ok if not installed)...'
Invoke-Adb -Args @('uninstall', 'com.vero265.app') -AllowFail | Out-Null
Invoke-Adb -Args @('uninstall', 'com.vero.vero360') -AllowFail | Out-Null

Write-Host 'Building armeabi-v7a release APK (smallest)...'
flutter build apk --release --split-per-abi --target-platform=android-arm
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

$apk = 'build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk'
if (-not (Test-Path $apk)) {
  throw "APK not found: $apk"
}

$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Host "Installing $apk ($sizeMb MB)..."
Invoke-Adb -Args @('install', '-r', $apk) | Out-Null

Invoke-Adb -Args @('shell', 'am', 'start', '-n', 'com.vero265.app/.MainActivity') -AllowFail | Out-Null
Write-Host 'Done. Impeller is forced off in the Android manifest/Application.'
