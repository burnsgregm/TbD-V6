# ====================================================
# TbD V5.0 - MASTER DEPLOYMENT ORCHESTRATION (4 Services)
# ====================================================

# --- CONFIGURATION (USER MUST VERIFY/UPDATE) ---
$PROJECT_ID = "tbd-v2" 
$REGION = "us-central1"
$TAG = "v5-final"

# Worker/Dispatcher (Service A/B) Config
$WORKER_REPO_NAME = "tbd-repo"
$WORKER_IMAGE_NAME = "tbd-v3-engine"
$WORKER_SERVICE = "tbd-worker"
$DISPATCHER_SERVICE = "tbd-dispatcher"
$WORKER_SA = "tbd-worker-sa"
$SUBSCRIPTION_SA = "tbd-sub-invoker"

# Service D (Detector) Config
$DETECTOR_REPO_NAME = "tbd-detector-repo"
$DETECTOR_IMAGE_NAME = "temporal-detector"
$DETECTOR_SERVICE = "tbd-object-detector"
$DETECTOR_SA = $WORKER_SA 

# Shared Infrastructure Names
$TOPIC_NAME = "tbd-ingest-tasks"
$INPUT_BUCKET = "tbd-raw-video-tbd-v2"
$OUTPUT_BUCKET = "tbd-results-tbd-v2"
$AUDIO_STAGING_BUCKET = "tbd-audio-staging-$PROJECT_ID" # NEW BUCKET NAME
$VERTEX_AI_SERVICE_AGENT = "service-511848408140@gcp-sa-aiplatform.iam.gserviceaccount.com" 

# --- CRITICAL: V4 BYPASS ---
$V4_BYPASS_ENV = "DISABLE_V4_ENCODER=True"

# ====================================================

Write-Host "--- STARTING V5 MASTER DEPLOYMENT ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# --- PART 1: BASE INFRASTRUCTURE (Check/Create) ---
Write-Host "`n--- 1. Checking Base Infrastructure ---" -ForegroundColor Yellow

# Buckets (Check/Create)
gsutil mb -l $REGION "gs://$INPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Input Bucket exists, continuing..." -ForegroundColor Yellow }

gsutil mb -l $REGION "gs://$OUTPUT_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Output Bucket exists, continuing..." -ForegroundColor Yellow }

# V5 FIX: Create the dedicated Audio Staging Bucket for STT API upload
gsutil mb -l $REGION "gs://$AUDIO_STAGING_BUCKET/"
if ($LASTEXITCODE -ne 0) { Write-Host "Audio Staging Bucket exists, continuing..." -ForegroundColor Yellow }

# Pub/Sub Topics
gcloud pubsub topics create $TOPIC_NAME
if ($LASTEXITCODE -ne 0) { Write-Host "Ingest Topic exists, continuing..." -ForegroundColor Yellow }
gcloud pubsub topics create pad-agent-tasks
if ($LASTEXITCODE -ne 0) { Write-Host "Agent Topic exists, continuing..." -ForegroundColor Yellow }

# Service Accounts (Check/Create)
gcloud iam service-accounts create tbd-dispatcher-sa --display-name "TbD Dispatcher"
if ($LASTEXITCODE -ne 0) { Write-Host "Dispatcher SA exists, continuing..." -ForegroundColor Yellow }
gcloud iam service-accounts create tbd-worker-sa --display-name "TbD Worker"
if ($LASTEXITCODE -ne 0) { Write-Host "Worker SA exists, continuing..." -ForegroundColor Yellow }
gcloud iam service-accounts create tbd-sub-invoker --display-name "PubSub Invoker"
if ($LASTEXITCODE -ne 0) { Write-Host "Sub Invoker SA exists, continuing..." -ForegroundColor Yellow }

# --- PART 2: IMAGE BUILD & PUSH (Builds all images) ---

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
gcloud builds submit tbd-encoder/ --tag $ENCODER_IMAGE_URI

# 2.3 Detector Image (Service D)
Write-Host "`n--- 2.3 Building Object Detector Image ---" -ForegroundColor Green
gcloud artifacts repositories create $DETECTOR_REPO_NAME --repository-format=docker --location=$REGION --description="Object Detector Repository"
if ($LASTEXITCODE -ne 0) { Write-Host "Detector Repo exists, continuing..." -ForegroundColor Yellow }
$DETECTOR_IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$DETECTOR_REPO_NAME/$DETECTOR_IMAGE_NAME`:$TAG"
gcloud builds submit tbd-detector/ --tag $DETECTOR_IMAGE_URI

# --- PART 3: IAM FIXES & CROSS-SERVICE PERMISSIONS ---
Write-Host "`n--- 3. Setting V5 IAM Permissions ---" -ForegroundColor Yellow

# 3.1 Worker SA Storage Permissions
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectViewer" "gs://$INPUT_BUCKET"
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin" "gs://$OUTPUT_BUCKET"
# V5 FIX: Worker needs Object Admin on the new Audio Staging Bucket
gsutil iam ch "serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com:objectAdmin" "gs://$AUDIO_STAGING_BUCKET"

# 3.2 Vertex AI SA Read Permission (Critical Fix for Gemini)
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

# 4.3 Deploy Object Detector (Service D)
Write-Host "`n--- 4.3 Deploying Object Detector Service (D) ---" -ForegroundColor Green
gcloud run deploy $DETECTOR_SERVICE `
    --image $DETECTOR_IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --timeout 10 `
    --tag v5-stable

# 4.4 Deploy Worker (Service B) - The final orchestrator
Write-Host "`n--- 4.4 Deploying Worker Service (B) ---" -ForegroundColor Green
$DETECTOR_URL = gcloud run services describe $DETECTOR_SERVICE --region $REGION --format 'value(status.url)'

gcloud run deploy $WORKER_SERVICE `
    --image $WORKER_IMAGE_URI `
    --region $REGION `
    --service-account "$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --no-allow-unauthenticated `
    --memory 4Gi `
    --cpu 2 `
    --timeout 3600 `
    --set-env-vars "SERVICE_TYPE=worker,GCP_PROJECT_ID=$PROJECT_ID,OBJECT_DETECTOR_URL=$DETECTOR_URL,$V4_BYPASS_ENV" `
    --tag v5-final

# --- PART 5: Cross-Service Invocation and Pub/Sub Setup ---

# 5.1 Grant Worker (B) Invocation Permissions (NFR-04)
Write-Host "Granting Worker SA run.invoker on Encoder (C) and Detector (D)..."
gcloud run services add-iam-policy-binding $ENCODER_SERVICE `
    --region $REGION `
    --member="serviceAccount:$WORKER_SA@$PROJECT_ID.iam.gserviceaccount.com" `
    --role="roles/run.invoker"

gcloud run services add-iam-policy-binding $DETECTOR_SERVICE `
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
Write-Host "V5 ARCHITECTURE DEPLOYMENT COMPLETE" -ForegroundColor Cyan
Write-Host "Service C (Encoder) URL: $(gcloud run services describe $ENCODER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "Service D (Detector) URL: $(gcloud run services describe $DETECTOR_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "Worker Service URL: $(gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "====================================================" -ForegroundColor Cyan