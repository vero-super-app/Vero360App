# Deploy Didit KYC Cloud Functions.
# Secrets are optional if already set in Secret Manager.

param(
  [switch]$SkipSecrets
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

$project = 'vero360app-ca423'

Write-Host 'Installing functions deps...'
Push-Location functions
npm install
Pop-Location

function Invoke-Firebase {
  param([Parameter(Mandatory)][string]$FirebaseArgs)
  # Prefer global firebase; fall back to npx.
  if (Get-Command firebase -ErrorAction SilentlyContinue) {
    cmd /c "firebase $FirebaseArgs"
  } else {
    cmd /c "npx --yes firebase-tools $FirebaseArgs"
  }
  if ($LASTEXITCODE -ne 0) {
    throw "firebase command failed ($LASTEXITCODE): $FirebaseArgs"
  }
}

Write-Host "Using project $project"
Invoke-Firebase "use $project"

if (-not $SkipSecrets) {
  Write-Host @'

Secrets (paste when prompted, then Enter):
  1) DIDIT_API_KEY
       Didit Console → API & Webhooks → API Keys → copy the API key
  2) DIDIT_WEBHOOK_SECRET
       Didit Console → destination → secret_shared_key
       (If you have no destination yet, paste: pending-after-destination
        then re-run secrets after you create the destination.)

Skip this step next time with:
  .\tool\deploy_kyc.ps1 -SkipSecrets

'@
  Invoke-Firebase "functions:secrets:set DIDIT_API_KEY --project $project"
  Invoke-Firebase "functions:secrets:set DIDIT_WEBHOOK_SECRET --project $project"
} else {
  Write-Host 'Skipping secrets (-SkipSecrets).'
}

Write-Host 'Deploying createDiditSession + diditWebhook...'
Invoke-Firebase "deploy --only functions:createDiditSession,functions:diditWebhook --project $project"

Write-Host @'

Done. After deploy:
  1. Copy the diditWebhook URL from deploy output
  2. Didit Console → Add destination:
       Name: kyc
       Version: v3.0
       Webhook URL: <paste https URL from deploy>
       Events: status.updated, data.updated (+ others you want)
  3. Copy destination secret_shared_key, then:
       npx firebase-tools functions:secrets:set DIDIT_WEBHOOK_SECRET --project vero360app-ca423
       npx firebase-tools deploy --only functions:diditWebhook --project vero360app-ca423
  4. Hot-restart the app (R) and retry KYC
'@
