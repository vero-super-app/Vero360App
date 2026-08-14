# Build release AAB and upload to Google Play via Fastlane.
# Prerequisites: Ruby, Bundler, signed keystore, Play service-account JSON.
#
# Usage:
#   .\tool\play_deploy.ps1                  # internal track
#   .\tool\play_deploy.ps1 -Track beta
#   .\tool\play_deploy.ps1 -Track production
#   .\tool\play_deploy.ps1 -Bump            # bump build number first
#   .\tool\play_deploy.ps1 -SkipBuild       # upload existing AAB only
#   .\tool\play_deploy.ps1 -Verify          # check setup only

param(
  [ValidateSet('internal', 'beta', 'production')]
  [string]$Track = 'internal',
  [switch]$Bump,
  [switch]$SkipBuild,
  [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# New shells often miss Ruby until PATH is refreshed.
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
  [System.Environment]::GetEnvironmentVariable('Path', 'User')
if (Get-Command ridk -ErrorAction SilentlyContinue) {
  ridk enable | Out-Null
}

Set-Location $PSScriptRoot\..

$android = Join-Path (Get-Location) 'android'
$jsonKey = Join-Path $android 'play-store-service-account.json'
$keyProps = Join-Path $android 'key.properties'

if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
  throw 'Ruby not found. Install Ruby+DevKit from https://rubyinstaller.org/ and open a new terminal.'
}

if (-not (Test-Path $jsonKey) -and -not $env:PLAY_STORE_JSON_KEY) {
  throw @"
Missing Play API key.
  1. Google Cloud Console → enable "Google Play Android Developer API"
  2. Create a service account → Keys → Add JSON key
  3. Play Console → Setup → API access → link that Cloud project
  4. Grant the service account permission to release to testing/production
  5. Save JSON as: android\play-store-service-account.json
  See: android\play-store-service-account.json.example
"@
}

if (-not (Test-Path $keyProps)) {
  throw 'Missing android\key.properties (release signing).'
}

$props = @{}
Get-Content $keyProps | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') { $props[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$storeFile = $props['storeFile']
if (-not $storeFile) { throw 'android\key.properties is missing storeFile=' }
$storeCandidates = @(
  (Join-Path $android $storeFile),
  (Join-Path (Join-Path $android 'app') $storeFile)
)
if (-not ($storeCandidates | Where-Object { Test-Path $_ })) {
  throw "Keystore not found: $storeFile (looked in android\ and android\app\)"
}

if ($Bump) {
  Write-Host 'Bumping pubspec build number...'
  dart run tool/bump_build.dart
}

Push-Location $android
try {
  if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
    Write-Host 'Installing bundler...'
    gem install bundler --no-document
  }
  bundle install
  if ($Verify) {
    bundle exec fastlane verify
  } elseif ($SkipBuild) {
    $env:TRACK = if ($Track -eq 'beta') { 'alpha' } else { $Track }
    bundle exec fastlane upload
  } else {
    bundle exec fastlane $Track
  }
} finally {
  Pop-Location
}

if (-not $Verify) {
  Write-Host @"

Done. Check Play Console → $Track track for com.vero265.app
"@
}
