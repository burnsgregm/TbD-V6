# ==============================================================================
# TbD V6 - Service D (Object Detector) Deployment Script
# Strategy: Native TensorFlow SavedModel (Zipped)
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
$PROJECT_ID = "tbd-v2"
$REGION = "us-central1"

# Service D Resources
$REPO_NAME = "tbd-detector-repo"
$IMAGE_NAME = "object-detector"
$SERVICE_NAME = "tbd-object-detector"
$TAG = "v6-yolo-native"

# Service B (Worker) Identity - Required for IAM Binding
$WORKER_SA_NAME = "tbd-worker-sa"
$WORKER_SA_EMAIL = "$WORKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# ------------------------------------------------------------------------------

Write-Host "`n--- STARTING SERVICE D (OBJECT DETECTOR) V6 DEPLOYMENT ---" -ForegroundColor Cyan

# 1. Set Project Context
Write-Host "Setting Google Cloud Project to $PROJECT_ID..." -ForegroundColor Green
gcloud config set project $PROJECT_ID
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set project."; exit 1 }

# 2. Check for Model Asset (Updated for V6 Zip Strategy)
if (-not (Test-Path "tbd-detector/model_yolo.zip")) {
    Write-Warning "CRITICAL WARNING: 'model_yolo.zip' not found in tbd-detector/."
    Write-Warning "You must run the Colab build script and place the zip file here."
    Write-Warning "The file should be ~12MB. If you have a 10KB .h5 file, DELETE IT."
    Write-Host "Press ENTER to continue (risky) or CTRL+C to abort..." -ForegroundColor Yellow
    Read-Host
}

# 3. Create Artifact Registry Repository (if not exists)
Write-Host "Checking Artifact Registry Repository..." -ForegroundColor Green
$REPO_EXISTS = gcloud artifacts repositories list --project=$PROJECT_ID --location=$REGION --filter="name:$REPO_NAME" --format="value(name)"
if (-not $REPO_EXISTS) {
    Write-Host "Creating repository '$REPO_NAME'..." -ForegroundColor Yellow
    gcloud artifacts repositories create $REPO_NAME `
        --repository-format=docker `
        --location=$REGION `
        --description="TbD Object Detector Repository"
} else {
    Write-Host "Repository '$REPO_NAME' already exists." -ForegroundColor Gray
}

# 4. Build and Push Container Image
$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME`:$TAG"
Write-Host "`n--- Building V6 Container Image ---" -ForegroundColor Cyan
Write-Host "Target Image: $IMAGE_URI" -ForegroundColor Gray

# Ensure we are submitting the correct directory context
if (-not (Test-Path "tbd-detector/Dockerfile")) {
    Write-Error "CRITICAL: 'tbd-detector/Dockerfile' not found. Are you in the root directory?"
    exit 1
}

gcloud builds submit tbd-detector/ --tag $IMAGE_URI
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed."; exit 1 }

# 5. Deploy Service D to Cloud Run
Write-Host "`n--- Deploying Service D to Cloud Run ---" -ForegroundColor Cyan

gcloud run deploy $SERVICE_NAME `
    --image $IMAGE_URI `
    --region $REGION `
    --no-allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --timeout 60 `
    --tag v6-stable

if ($LASTEXITCODE -ne 0) { Write-Error "Deployment failed."; exit 1 }

# 6. Set IAM Permissions (Allow Service B to Call Service D)
Write-Host "`n--- Configuring IAM Security ---" -ForegroundColor Cyan
Write-Host "Granting INVOKER role to Worker SA: $WORKER_SA_EMAIL" -ForegroundColor Yellow

gcloud run services add-iam-policy-binding $SERVICE_NAME `
    --region $REGION `
    --member="serviceAccount:$WORKER_SA_EMAIL" `
    --role="roles/run.invoker"

# 7. Final Output
$SERVICE_URL = gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   SERVICE D (OBJECT DETECTOR) DEPLOYMENT COMPLETE"
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Service Name : $SERVICE_NAME"
Write-Host "Service URL  : $SERVICE_URL"
Write-Host "Image Tag    : $TAG"
Write-Host "Model Asset  : model_yolo.zip"
Write-Host "Invoker      : $WORKER_SA_EMAIL"
Write-Host "========================================================" -ForegroundColor Green# ==============================================================================
# TbD V6 - Service D (Object Detector) Deployment Script
# Strategy: Native TensorFlow SavedModel (Zipped)
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
$PROJECT_ID = "tbd-v2"
$REGION = "us-central1"

# Service D Resources
$REPO_NAME = "tbd-detector-repo"
$IMAGE_NAME = "object-detector"
$SERVICE_NAME = "tbd-object-detector"
$TAG = "v6-yolo-native"

# Service B (Worker) Identity - Required for IAM Binding
$WORKER_SA_NAME = "tbd-worker-sa"
$WORKER_SA_EMAIL = "$WORKER_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# ------------------------------------------------------------------------------

Write-Host "`n--- STARTING SERVICE D (OBJECT DETECTOR) V6 DEPLOYMENT ---" -ForegroundColor Cyan

# 1. Set Project Context
Write-Host "Setting Google Cloud Project to $PROJECT_ID..." -ForegroundColor Green
gcloud config set project $PROJECT_ID
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set project."; exit 1 }

# 2. Check for Model Asset (Updated for V6 Zip Strategy)
if (-not (Test-Path "tbd-detector/model_yolo.zip")) {
    Write-Warning "CRITICAL WARNING: 'model_yolo.zip' not found in tbd-detector/."
    Write-Warning "You must run the Colab build script and place the zip file here."
    Write-Warning "The file should be ~12MB. If you have a 10KB .h5 file, DELETE IT."
    Write-Host "Press ENTER to continue (risky) or CTRL+C to abort..." -ForegroundColor Yellow
    Read-Host
}

# 3. Create Artifact Registry Repository (if not exists)
Write-Host "Checking Artifact Registry Repository..." -ForegroundColor Green
$REPO_EXISTS = gcloud artifacts repositories list --project=$PROJECT_ID --location=$REGION --filter="name:$REPO_NAME" --format="value(name)"
if (-not $REPO_EXISTS) {
    Write-Host "Creating repository '$REPO_NAME'..." -ForegroundColor Yellow
    gcloud artifacts repositories create $REPO_NAME `
        --repository-format=docker `
        --location=$REGION `
        --description="TbD Object Detector Repository"
} else {
    Write-Host "Repository '$REPO_NAME' already exists." -ForegroundColor Gray
}

# 4. Build and Push Container Image
$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME`:$TAG"
Write-Host "`n--- Building V6 Container Image ---" -ForegroundColor Cyan
Write-Host "Target Image: $IMAGE_URI" -ForegroundColor Gray

# Ensure we are submitting the correct directory context
if (-not (Test-Path "tbd-detector/Dockerfile")) {
    Write-Error "CRITICAL: 'tbd-detector/Dockerfile' not found. Are you in the root directory?"
    exit 1
}

# CRITICAL: The Dockerfile in tbd-detector/ MUST use 'libgl1' instead of 'libgl1-mesa-glx'
# to avoid the 'Package has no installation candidate' error.
gcloud builds submit tbd-detector/ --tag $IMAGE_URI
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed. Check Dockerfile dependencies (libgl1-mesa-glx vs libgl1)."; exit 1 }

# 5. Deploy Service D to Cloud Run
Write-Host "`n--- Deploying Service D to Cloud Run ---" -ForegroundColor Cyan

gcloud run deploy $SERVICE_NAME `
    --image $IMAGE_URI `
    --region $REGION `
    --no-allow-unauthenticated `
    --memory 2Gi `
    --cpu 1 `
    --timeout 60 `
    --tag v6-stable

if ($LASTEXITCODE -ne 0) { Write-Error "Deployment failed."; exit 1 }

# 6. Set IAM Permissions (Allow Service B to Call Service D)
Write-Host "`n--- Configuring IAM Security ---" -ForegroundColor Cyan
Write-Host "Granting INVOKER role to Worker SA: $WORKER_SA_EMAIL" -ForegroundColor Yellow

gcloud run services add-iam-policy-binding $SERVICE_NAME `
    --region $REGION `
    --member="serviceAccount:$WORKER_SA_EMAIL" `
    --role="roles/run.invoker"

# 7. Final Output
$SERVICE_URL = gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   SERVICE D (OBJECT DETECTOR) DEPLOYMENT COMPLETE"
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Service Name : $SERVICE_NAME"
Write-Host "Service URL  : $SERVICE_URL"
Write-Host "Image Tag    : $TAG"
Write-Host "Model Asset  : model_yolo.zip"
Write-Host "Invoker      : $WORKER_SA_EMAIL"
Write-Host "========================================================" -ForegroundColor Green