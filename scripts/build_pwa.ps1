# Builds the Flutter PWA into hosting/app/.
# Does NOT replace the Android/iOS apps or the Next.js marketing site.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

flutter build web --release --base-href /app/

$dest = Join-Path $root "hosting\app"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -Path (Join-Path $root "build\web\*") -Destination $dest -Recurse

Write-Host "PWA copied to hosting/app/"
Write-Host "Native Android/iOS builds are unchanged."
Write-Host "Deploy with: npx firebase-tools deploy --only hosting"
