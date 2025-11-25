# ====================================================
# TbD V5.0 - FAST WORKER ONLY REDEPLOY SCRIPT
# Use this for code verification cycles.
# ====================================================

# Configuration needed for the Worker build/deploy
$PROJECT_ID = "tbd-v2" 
$REGION = "us-central1"
$WORKER_REPO_NAME = "tbd-repo"
$WORKER_IMAGE_NAME = "tbd-v3-engine"
$WORKER_SERVICE = "tbd-worker"
$DISPATCHER_SERVICE = "tbd-dispatcher"
$WORKER_SA = "tbd-worker-sa"
$DISPATCHER_SA = "tbd-dispatcher-sa"
$TAG = "v5-final"

# V5 Environment Variables (Needed to keep the pipeline working)
$OBJECT_DETECTOR_URL = "https://tbd-object-detector-uxsmugd25a-uc.a.run.app"
$V4_BYPASS_ENV = "DISABLE_V4_ENCODER=True"

# --- CORE SCRIPT ---

Write-Host "--- STARTING TARGETED WORKER REDEPLOY (3-5 min cycle) ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# 1. Build Worker Image (This is the only part that needs rebuilding)
Write-Host "`n--- 1. Building Worker/Dispatcher Image ---" -ForegroundColor Green
$WORKER_IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$WORKER_REPO_NAME/$WORKER_IMAGE_NAME`:$TAG"
gcloud builds submit . --tag $WORKER_IMAGE_URI

if ($LASTEXITCODE -ne 0) {
    Write-Error "Container build failed. Aborting deployment."
    exit 1
}

# 2. Deploy Worker (Service B)
Write-Host "`n--- 2. Deploying WORKER Service (B) ---" -ForegroundColor Green
gcloud run deploy $WORKER_SERVICE `
    --image $WORKER_IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 4Gi `
    --cpu 2 `
    --timeout 3600 `
    --set-env-vars "SERVICE_TYPE=worker,GCP_PROJECT_ID=$PROJECT_ID,OBJECT_DETECTOR_URL=$OBJECT_DETECTOR_URL,$V4_BYPASS_ENV" `
    --tag v5-final

# 3. Deploy Dispatcher (Service A) - Quick verification deploy
Write-Host "`n--- 3. Redeploying Dispatcher Service (A) ---" -ForegroundColor Green
gcloud run deploy $DISPATCHER_SERVICE `
    --image $WORKER_IMAGE_URI `
    --region $REGION `
    --service-account "$DISPATCHER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --tag $TAG

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "TARGETED DEPLOYMENT COMPLETE (Worker Updated)" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan