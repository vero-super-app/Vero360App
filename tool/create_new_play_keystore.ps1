# Create a NEW Play upload keystore for com.vero265.app
# Do NOT reuse the old com.vero.vero360 keystore.

param(
  [string]$StorePassword = '',
  [string]$KeyPassword = ''
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

$androidDir = Join-Path (Get-Location) 'android'
$keystore = Join-Path $androidDir 'upload-keystore-vero265.jks'
$keyProps = Join-Path $androidDir 'key.properties'

if (Test-Path $keystore) {
  Write-Host "Keystore already exists: $keystore"
  if (-not (Test-Path $keyProps)) {
    Write-Host 'key.properties missing — recreate passwords into key.properties manually.'
  }
  exit 0
}

$keytool = $null
$cmd = Get-Command keytool -ErrorAction SilentlyContinue
if ($cmd) { $keytool = $cmd.Source }
if (-not $keytool) {
  $candidates = @(
    "$env:JAVA_HOME\bin\keytool.exe",
    'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
    'C:\Program Files\Java\*\bin\keytool.exe'
  )
  foreach ($c in $candidates) {
    $resolved = Resolve-Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { $keytool = $resolved.Path; break }
  }
}
if (-not $keytool) { throw 'keytool not found. Install JDK or Android Studio.' }

if (-not $StorePassword) {
  $secure = Read-Host 'Enter NEW keystore password' -AsSecureString
  $StorePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  )
}
if (-not $KeyPassword) { $KeyPassword = $StorePassword }

Write-Host 'Generating new upload keystore for com.vero265.app...'
& $keytool -genkeypair -v `
  -keystore $keystore `
  -storepass $StorePassword `
  -keypass $KeyPassword `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias upload `
  -dname 'CN=Vero265, OU=Mobile, O=Vero, L=Lilongwe, ST=Central, C=MW'

@"
storePassword=$StorePassword
keyPassword=$KeyPassword
keyAlias=upload
storeFile=upload-keystore-vero265.jks
"@ | Set-Content -Encoding ascii $keyProps

Write-Host @"

Created:
  $keystore
  $keyProps

Next:
  1. Keep the password somewhere safe (Play Console needs it forever)
  2. flutter build appbundle --release
  3. Upload build/app/outputs/bundle/release/app-release.aab to Play Console
  4. Add the upload SHA-1 to Firebase Android app com.vero265.app
"@
