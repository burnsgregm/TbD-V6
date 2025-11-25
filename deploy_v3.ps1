# ====================================================
# TbD V3.0 "Insight" - Automated Deployment Script (PowerShell)
# ====================================================

# --- CONFIGURATION ---
# REPLACE WITH YOUR ACTUAL PROJECT ID
$PROJECT_ID = "tbd-v2"
$REGION = "us-central1"
$REPO_NAME = "tbd-repo"
$IMAGE_NAME = "tbd-v3-engine"
$TAG = "v3.0.0"

# Resource Names
$TOPIC_NAME = "tbd-ingest-tasks"
$INPUT_BUCKET = "tbd-raw-video-$PROJECT_ID"
$OUTPUT_BUCKET = "tbd-results-$PROJECT_ID"
$DISPATCHER_SERVICE = "tbd-dispatcher"
$WORKER_SERVICE = "tbd-worker"

# Service Accounts
$DISPATCHER_SA = "tbd-dispatcher-sa"
$WORKER_SA = "tbd-worker-sa"
$SUBSCRIPTION_SA = "tbd-sub-invoker"

# ====================================================

Write-Host "--- STARTING V3 DEPLOYMENT FOR PROJECT: $PROJECT_ID ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# 1. Enable APIs (Added aiplatform for V3)
Write-Host "--- Enabling GCP APIs (including Vertex AI) ---" -ForegroundColor Green
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com run.googleapis.com pubsub.googleapis.com storage.googleapis.com aiplatform.googleapis.com

# 2. Create Storage Buckets
Write-Host "--- Creating GCS Buckets ---" -ForegroundColor Green
gsutil mb -l $REGION "gs://$INPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Bucket might already exist, continuing..." -ForegroundColor Yellow }
gsutil mb -l $REGION "gs://$OUTPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Bucket might already exist, continuing..." -ForegroundColor Yellow }

# 3. Create Pub/Sub Topic
Write-Host "--- Creating Pub/Sub Topic ---" -ForegroundColor Green
gcloud pubsub topics create $TOPIC_NAME
if ($LASTEXITCODE -ne 0) { Write-Host "Topic might already exist, continuing..." -ForegroundColor Yellow }

# 4. Build & Push Container Image
Write-Host "--- Building V3 Container Image ---" -ForegroundColor Green
gcloud artifacts repositories create $REPO_NAME --repository-format=docker --location=$REGION --description="TbD Engine Repository"
if ($LASTEXITCODE -ne 0) { Write-Host "Repo might already exist, continuing..." -ForegroundColor Yellow }

$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME`:$TAG"

# Submit build (Packages requirements.txt with new scikit-image & google-cloud-aiplatform deps)
gcloud builds submit --tag $IMAGE_URI .

# 5. Setup Service Accounts & IAM
Write-Host "--- Configuring IAM Service Accounts ---" -ForegroundColor Green
gcloud iam service-accounts create $DISPATCHER_SA --display-name "TbD Dispatcher"
if ($LASTEXITCODE -ne 0) { Write-Host "SA might already exist..." -ForegroundColor Yellow }
gcloud iam service-accounts create $WORKER_SA --display-name "TbD Worker"
if ($LASTEXITCODE -ne 0) { Write-Host "SA might already exist..." -ForegroundColor Yellow }
gcloud iam service-accounts create $SUBSCRIPTION_SA --display-name "PubSub Invoker"
if ($LASTEXITCODE -ne 0) { Write-Host "SA might already exist..." -ForegroundColor Yellow }

# Grant Dispatcher permission to Publish
gcloud pubsub topics add-iam-policy-binding $TOPIC_NAME `
    --member="serviceAccount:$DISPATCHER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/pubsub.publisher"

# Grant Worker permission to Read Input/Write Output
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectViewer" "gs://$INPUT_BUCKET"
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectCreator" "gs://$OUTPUT_BUCKET"

# [NEW FOR V3] Grant Worker permission to use Vertex AI (Gemini)
Write-Host "--- Granting Vertex AI User Role to Worker ---" -ForegroundColor Green
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/aiplatform.user"

# 6. Deploy Dispatcher Service
Write-Host "--- Deploying DISPATCHER Service ---" -ForegroundColor Green
gcloud run deploy $DISPATCHER_SERVICE `
    --image $IMAGE_URI `
    --region $REGION `
    --service-account "$DISPATCHER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --set-env-vars "SERVICE_TYPE=dispatcher,GCP_PROJECT_ID=$PROJECT_ID" `
    --tag v3-stable

# 7. Deploy Worker Service (V3 Insight Engine)
Write-Host "--- Deploying WORKER Service (V3 Insight Engine) ---" -ForegroundColor Green
# Increased Memory to 4Gi for V3 to handle Async AI + OpenCV overhead
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

# 8. Create Pub/Sub Push Subscription
Write-Host "--- Linking Pub/Sub to Worker ---" -ForegroundColor Green
Write-Host "Waiting for service propagation..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

$WORKER_URL = gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)'
if (-not $WORKER_URL) {
    Write-Error "Worker Service failed to deploy or URL retrieval failed."
    exit 1
}
Write-Host "Worker URL retrieved: $WORKER_URL" -ForegroundColor Cyan

# Allow Subscription SA to invoke Worker
gcloud run services add-iam-policy-binding $WORKER_SERVICE --region $REGION `
    --member="serviceAccount:$SUBSCRIPTION_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/run.invoker"

# Create or Update Subscription
Write-Host "Configuring Subscription..." -ForegroundColor Cyan
gcloud pubsub subscriptions create tbd-worker-sub `
    --topic $TOPIC_NAME `
    --push-endpoint=$WORKER_URL `
    --push-auth-service-account="$SUBSCRIPTION_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --ack-deadline=600
if ($LASTEXITCODE -ne 0) {
    Write-Host "Subscription exists, updating endpoint..." -ForegroundColor Yellow
    gcloud pubsub subscriptions update tbd-worker-sub `
        --push-endpoint=$WORKER_URL `
        --push-auth-service-account="$SUBSCRIPTION_SA@$PROJECT_ID.iam.gserviceaccount.com"
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "V3 DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "Dispatcher URL: $(gcloud run services describe $DISPATCHER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "Input Bucket: gs://$INPUT_BUCKET"
Write-Host "Output Bucket: gs://$OUTPUT_BUCKET"
Write-Host "====================================================" -ForegroundColor Cyan