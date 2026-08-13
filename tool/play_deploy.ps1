# Build release AAB and upload to Google Play via Fastlane.
# Prerequisites: Ruby, Bundler, signed keystore, Play service-account JSON.
#
# Usage:
#   .\tool\play_deploy.ps1                  # internal track
#   .\tool\play_deploy.ps1 -Track beta
#   .\tool\play_deploy.ps1 -Track production
#   .\tool\play_deploy.ps1 -Bump            # bump build number first
#   .\tool\play_deploy.ps1 -SkipBuild       # upload existing AAB only

param(
  [ValidateSet('internal', 'beta', 'production')]
  [string]$Track = 'internal',
  [switch]$Bump,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

$android = Join-Path (Get-Location) 'android'
$jsonKey = Join-Path $android 'play-store-service-account.json'
$keyProps = Join-Path $android 'key.properties'

if (-not (Test-Path $jsonKey) -and -not $env:PLAY_STORE_JSON_KEY) {
  throw @"
Missing Play API key.
  1. Create a Google Cloud service account + JSON key
  2. Link it in Play Console → Setup → API access
  3. Save JSON as: android\play-store-service-account.json
  See: android\play-store-service-account.json.example
"@
}

if (-not (Test-Path $keyProps)) {
  throw 'Missing android\key.properties (release signing). Run .\tool\create_new_play_keystore.ps1 first.'
}

$kp = Get-Content $keyProps -Raw
if ($kp -match '<password-from-previous-step>' -or $kp -match '<keystore-file-location>') {
  throw 'android\key.properties still has placeholders. Fill in real storePassword/keyPassword/storeFile.'
}

if ($Bump) {
  Write-Host 'Bumping pubspec build number...'
  dart run tool/bump_build.dart
}

Push-Location $android
try {
  if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing bundler...'
    gem install bundler
  }
  bundle install
  if ($SkipBuild) {
    $env:TRACK = if ($Track -eq 'beta') { 'alpha' } else { $Track }
    bundle exec fastlane upload
  } else {
    bundle exec fastlane $Track
  }
} finally {
  Pop-Location
}

Write-Host @"

Done. Check Play Console → $Track track for com.vero265.app
"@
