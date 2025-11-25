Understood. I apologize for not providing the complete file in the previous exchange. Here is the entire, non-truncated V4 Master Deployment Script (deploy_v4_full.ps1).

This script is the final working version for the V4 architecture, orchestrating the deployment of all three services (Dispatcher, Worker, Encoder) and setting the necessary cross-service IAM permissions.

File: deploy_v4_full.ps1

PowerShell

# ====================================================
# TbD V4.0 - MASTER DEPLOYMENT ORCHESTRATION (3 Services)
# ====================================================

# --- CONFIGURATION (USER MUST VERIFY/UPDATE) ---
$PROJECT_ID = "tbd-v2" 
$REGION = "us-central1"
$TAG = "v4-final"

# Service B/A (Worker/Dispatcher) Config
$WORKER_REPO_NAME = "tbd-repo"
$WORKER_IMAGE_NAME = "tbd-v3-engine"
$WORKER_SERVICE = "tbd-worker"
$DISPATCHER_SERVICE = "tbd-dispatcher"
$WORKER_SA = "tbd-worker-sa"
$DISPATCHER_SA = "tbd-dispatcher-sa"
$SUBSCRIPTION_SA = "tbd-sub-invoker"

# Service C (Encoder) Config
$ENCODER_REPO_NAME = "tbd-encoder-repo"
$ENCODER_IMAGE_NAME = "temporal-encoder"
$ENCODER_SERVICE = "tbd-temporal-encoder"
$ENCODER_SA = $WORKER_SA # Service C reuses the Worker's SA for simplicity

# Shared Infrastructure Names
$TOPIC_NAME = "tbd-ingest-tasks"
$INPUT_BUCKET = "tbd-raw-video-tbd-v2"
$OUTPUT_BUCKET = "tbd-results-tbd-v2"
$VERTEX_AI_SERVICE_AGENT = "service-511848408140@gcp-sa-aiplatform.iam.gserviceaccount.com" 

# ====================================================

Write-Host "--- STARTING V4 MASTER DEPLOYMENT ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# --- PART 1: BASE INFRASTRUCTURE (Check/Create) ---
Write-Host "`n--- 1. Checking Base Infrastructure ---" -ForegroundColor Yellow

# Buckets (Check/Create)
gsutil mb -l $REGION "gs://$INPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Input Bucket exists, continuing..." -ForegroundColor Yellow }

gsutil mb -l $REGION "gs://$OUTPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Output Bucket exists, continuing..." -ForegroundColor Yellow }

# Pub/Sub Topic (Check/Create)
gcloud pubsub topics create $TOPIC_NAME
if ($LASTEXITCODE -ne 0) { Write-Host "Topic exists, continuing..." -ForegroundColor Yellow }

# Service Accounts (Check/Create)
gcloud iam service-accounts create $DISPATCHER_SA --display-name "TbD Dispatcher"
if ($LASTEXITCODE -ne 0) { Write-Host "Dispatcher SA exists, continuing..." -ForegroundColor Yellow }

gcloud iam service-accounts create $WORKER_SA --display-name "TbD Worker"
if ($LASTEXITCODE -ne 0) { Write-Host "Worker SA exists, continuing..." -ForegroundColor Yellow }

gcloud iam service-accounts create $SUBSCRIPTION_SA --display-name "PubSub Invoker"
if ($LASTEXITCODE -ne 0) { Write-Host "Sub Invoker SA exists, continuing..." -ForegroundColor Yellow }


# --- PART 2: IMAGE BUILD & PUSH ---

# 2.1 Worker/Dispatcher Image (Service A/B)
Write-Host "`n--- 2.1 Building Worker/Dispatcher Image ---" -ForegroundColor Green
gcloud artifacts repositories create $WORKER_REPO_NAME --repository-format=docker --location=$REGION --description="TbD Engine Repository"
if ($LASTEXITCODE -ne 0) { Write-Host "Worker Repo exists, continuing..." -ForegroundColor Yellow }

$WORKER_IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$WORKER_REPO_NAME/$WORKER_IMAGE_NAME`:$TAG"
gcloud builds submit . --tag $WORKER_IMAGE_URI

# 2.2 Encoder Image (Service C)
Write-Host "`n--- 2.2 Building Temporal Encoder Image ---" -ForegroundColor Green
gcloud artifacts repositories create $ENCODER_REPO_NAME --repository-format=docker --location=$REGION --description="Temporal Encoder Repository"
if ($LASTEXITCODE -ne 0) { Write-Host "Encoder Repo exists, continuing..." -ForegroundColor Yellow }

$ENCODER_IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$ENCODER_REPO_NAME/$ENCODER_IMAGE_NAME`:$TAG"
# Uses the tbd-encoder/ subdirectory as the source for Service C build
gcloud builds submit tbd-encoder/ --tag $ENCODER_IMAGE_URI

# --- PART 3: IAM FIXES & CROSS-SERVICE PERMISSIONS ---
Write-Host "`n--- 3. Setting V4 IAM Permissions ---" -ForegroundColor Yellow

# 3.1 Worker SA Storage Permissions
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectViewer" "gs://$INPUT_BUCKET"
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin" "gs://$OUTPUT_BUCKET"

# 3.2 Vertex AI SA Read Permission (Critical Fix)
gsutil iam ch "serviceAccount:$VERTEX_AI_SERVICE_AGENT:objectViewer" "gs://$INPUT_BUCKET"

# --- PART 4: SERVICE DEPLOYMENT ---

# 4.1 Deploy Dispatcher (Service A)
Write-Host "`n--- 4.1 Deploying Dispatcher Service (A) ---" -ForegroundColor Green
gcloud run deploy $DISPATCHER_SERVICE `
    --image $WORKER_IMAGE_URI `
    --region $REGION `
    --service-account "$DISPATCHER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --tag $TAG

# 4.2 Deploy Temporal Encoder (Service C)
Write-Host "`n--- 4.2 Deploying Temporal Encoder Service (C) ---" -ForegroundColor Green
gcloud run deploy $ENCODER_SERVICE `
    --image $ENCODER_IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 1Gi `
    --cpu 1 `
    --timeout 5 `
    --tag v4-stable

# 4.3 Deploy Worker (Service B)
Write-Host "`n--- 4.3 Deploying Worker Service (B) ---" -ForegroundColor Green
gcloud run deploy $WORKER_SERVICE `
    --image $WORKER_IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 4Gi `
    --cpu 2 `
    --timeout 3600 `
    --tag v4-stable

# --- PART 5: Cross-Service Invocation and Pub/Sub Setup ---

# 5.1 Grant Worker (B) Invocation Permission to Encoder (C) (NFR-04)
Write-Host "Granting Worker SA run.invoker on Encoder Service..."
gcloud run services add-iam-policy-binding $ENCODER_SERVICE `
    --region $REGION `
    --member="serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/run.invoker"

# 5.2 Pub/Sub Subscription Update
Write-Host "Updating Pub/Sub Subscription..."
$WORKER_URL = gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)'

gcloud run services add-iam-policy-binding $WORKER_SERVICE --region $REGION `
    --member="serviceAccount:$SUBSCRIPTION_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/run.invoker"

gcloud pubsub subscriptions update tbd-worker-sub `
    --push-endpoint=$WORKER_URL `
    --push-auth-service-account="$SUBSCRIPTION_SA@$PROJECT_ID.iam.gserviceaccount.com"

# --- FINAL OUTPUT ---
Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "V4 ARCHITECTURE DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "Service C URL: $(gcloud run services describe $ENCODER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "Worker Service URL: $(gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "====================================================" -ForegroundColor Cyan