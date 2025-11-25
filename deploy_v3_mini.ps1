# ====================================================
# TbD V3.0 - Quick Update Script (Worker Only)
# ====================================================

# --- CONFIGURATION ---
# [CRITICAL] ENSURE THIS MATCHES YOUR ACTIVE PROJECT
$PROJECT_ID = "tbd-v2" 

$REGION = "us-central1"
$REPO_NAME = "tbd-repo"
$IMAGE_NAME = "tbd-v3-engine"
$TAG = "v3.0.0"
$WORKER_SERVICE = "tbd-worker"
$WORKER_SA = "tbd-worker-sa"

# ====================================================

Write-Host "--- STARTING QUICK UPDATE FOR: $PROJECT_ID ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# 1. Build & Push Container Image (Mandatory to apply code/dependency changes)
Write-Host "--- Rebuilding Container Image ---" -ForegroundColor Green
$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME`:$TAG"
gcloud builds submit --tag $IMAGE_URI .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build Failed. Aborting deployment."
    exit 1
}

# 2. Deploy Worker Service Only
Write-Host "--- Redeploying Worker Service ---" -ForegroundColor Green
# We retain the memory setting and service account
gcloud run deploy $WORKER_SERVICE `
    --image $IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 4Gi `
    --cpu 2 `
    --timeout 3600 `
    --set-env-vars "SERVICE_TYPE=worker,GCP_PROJECT_ID=$PROJECT_ID" `
    --tag v3-stable

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "UPDATE COMPLETE" -ForegroundColor Cyan
Write-Host "Worker URL: $(gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "====================================================" -ForegroundColor Cyan