# ==============================================================================
# TbD V6 - Service C (Temporal Encoder) Deployment Script
# Strategy: "Architecture Rebuild" (Fixes Keras/TF Legacy Crash)
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
$PROJECT_ID = "tbd-v2"
$REGION = "us-central1"

# Service C Resources
$REPO_NAME = "tbd-encoder-repo"
$IMAGE_NAME = "temporal-encoder"
$SERVICE_NAME = "tbd-temporal-encoder"
$TAG = "v6-rebuild"

# Service B (Worker) Identity - Required for IAM Binding
$WORKER_SA_NAME = "tbd-worker-sa"
$WORKER_SA_EMAIL = "$WORKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# ------------------------------------------------------------------------------

Write-Host "`n--- STARTING SERVICE C (TEMPORAL ENCODER) V6 DEPLOYMENT ---" -ForegroundColor Cyan

# 1. Set Project Context
Write-Host "Setting Google Cloud Project to $PROJECT_ID..." -ForegroundColor Green
gcloud config set project $PROJECT_ID
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set project."; exit 1 }

# 2. Enable Required APIs
Write-Host "Enabling Artifact Registry, Cloud Build, and Cloud Run APIs..." -ForegroundColor Green
gcloud services enable artifactregistry.googleapis.com cloudbuild.googleapis.com run.googleapis.com
if ($LASTEXITCODE -ne 0) { Write-Warning "APIs might already be enabled or you lack permission. Continuing..." }

# 3. Create Artifact Registry Repository (if not exists)
Write-Host "Checking Artifact Registry Repository..." -ForegroundColor Green
$REPO_EXISTS = gcloud artifacts repositories list --project=$PROJECT_ID --location=$REGION --filter="name:$REPO_NAME" --format="value(name)"
if (-not $REPO_EXISTS) {
    Write-Host "Creating repository '$REPO_NAME'..." -ForegroundColor Yellow
    gcloud artifacts repositories create $REPO_NAME `
        --repository-format=docker `
        --location=$REGION `
        --description="TbD Temporal Encoder Repository"
} else {
    Write-Host "Repository '$REPO_NAME' already exists." -ForegroundColor Gray
}

# 4. Build and Push Container Image
$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME`:$TAG"
Write-Host "`n--- Building V6 Container Image ---" -ForegroundColor Cyan
Write-Host "Target Image: $IMAGE_URI" -ForegroundColor Gray

# Submitting the 'tbd-encoder' directory as the build context
if (-not (Test-Path "tbd-encoder/Dockerfile")) {
    Write-Error "CRITICAL: 'tbd-encoder/Dockerfile' not found in current directory."
    exit 1
}

gcloud builds submit tbd-encoder/ --tag $IMAGE_URI
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed."; exit 1 }

# 5. Deploy Service C to Cloud Run
Write-Host "`n--- Deploying Service C to Cloud Run ---" -ForegroundColor Cyan

gcloud run deploy $SERVICE_NAME `
    --image $IMAGE_URI `
    --region $REGION `
    --no-allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --timeout 60 `
    --tag v6-stable

if ($LASTEXITCODE -ne 0) { Write-Error "Deployment failed."; exit 1 }

# 6. Set IAM Permissions (Allow Service B to Call Service C)
Write-Host "`n--- Configuring IAM Security ---" -ForegroundColor Cyan
Write-Host "Granting INVOKER role to Worker SA: $WORKER_SA_EMAIL" -ForegroundColor Yellow

gcloud run services add-iam-policy-binding $SERVICE_NAME `
    --region $REGION `
    --member="serviceAccount:$WORKER_SA_EMAIL" `
    --role="roles/run.invoker"

# 7. Final Output
$SERVICE_URL = gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   SERVICE C (TEMPORAL ENCODER) DEPLOYMENT COMPLETE"
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Service Name : $SERVICE_NAME"
Write-Host "Service URL  : $SERVICE_URL"
Write-Host "Image Tag    : $TAG"
Write-Host "Architecture : V6 Rebuild (TF 2.15 CPU)"
Write-Host "Invoker      : $WORKER_SA_EMAIL"
Write-Host "========================================================" -ForegroundColor Green