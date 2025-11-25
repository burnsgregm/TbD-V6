# ==============================================================================
# TbD V6 - MASTER DEPLOYMENT (Worker + Dispatcher)
# Wires up Service C (Encoder) and Service D (Detector)
# ==============================================================================

$PROJECT_ID = "tbd-v2"
$REGION = "us-central1"

# Service Names
$WORKER_SERVICE = "tbd-worker"
$DISPATCHER_SERVICE = "tbd-dispatcher"
$ENCODER_SERVICE = "tbd-temporal-encoder"
$DETECTOR_SERVICE = "tbd-object-detector"

# Identity
$WORKER_SA_EMAIL = "tbd-worker-sa@$PROJECT_ID.iam.gserviceaccount.com"

Write-Host "--- STARTING V6 MASTER DEPLOYMENT ---" -ForegroundColor Cyan
gcloud config set project $PROJECT_ID

# 1. Discovery: Get URLs of the dependency services
Write-Host "Discovering dependency URLs..." -ForegroundColor Yellow
$ENCODER_URL = gcloud run services describe $ENCODER_SERVICE --region $REGION --format 'value(status.url)'
$DETECTOR_URL = gcloud run services describe $DETECTOR_SERVICE --region $REGION --format 'value(status.url)'

if (-not $ENCODER_URL) { Write-Error "Service C (Encoder) not found. Did you run deploy_encoder.ps1?"; exit 1 }
if (-not $DETECTOR_URL) { Write-Error "Service D (Detector) not found. Did you run deploy_detector.ps1?"; exit 1 }

Write-Host "Found Encoder: $ENCODER_URL" -ForegroundColor Green
Write-Host "Found Detector: $DETECTOR_URL" -ForegroundColor Green

# 2. Build Worker/Dispatcher Image
Write-Host "`n--- Building Worker/Dispatcher Image ---" -ForegroundColor Cyan
$IMAGE_NAME = "tbd-v6-core"
$IMAGE_URI = "$REGION-docker.pkg.dev/$PROJECT_ID/tbd-repo/$IMAGE_NAME`:$TAG"

# This builds the ROOT directory (containing app/ and requirements.txt)
gcloud builds submit . --tag $IMAGE_URI

# 3. Deploy Dispatcher (Service A)
Write-Host "`n--- Deploying Service A (Dispatcher) ---" -ForegroundColor Cyan
gcloud run deploy $DISPATCHER_SERVICE `
    --image $IMAGE_URI `
    --region $REGION `
    --service-account "tbd-dispatcher-sa@$PROJECT_ID.iam.gserviceaccount.com" `
    --allow-unauthenticated `
    --memory 1Gi `
    --set-env-vars "SERVICE_TYPE=dispatcher,GCP_PROJECT_ID=$PROJECT_ID"

# 4. Deploy Worker (Service B) - The Brain
Write-Host "`n--- Deploying Service B (Worker) ---" -ForegroundColor Cyan
# Note: DISABLE_V4_ENCODER is REMOVED. New URLs are INJECTED.
gcloud run deploy $WORKER_SERVICE `
    --image $IMAGE_URI `
    --region $REGION `
    --service-account $WORKER_SA_EMAIL `
    --no-allow-unauthenticated `
    --memory 4Gi `
    --cpu 2 `
    --timeout 3600 `
    --set-env-vars "SERVICE_TYPE=worker,GCP_PROJECT_ID=$PROJECT_ID,TEMPORAL_ENCODER_URL=$ENCODER_URL,OBJECT_DETECTOR_URL=$DETECTOR_URL"

# 5. Setup Pub/Sub Trigger
Write-Host "`n--- Linking Pub/Sub to Worker ---" -ForegroundColor Cyan
$WORKER_URL = gcloud run services describe $WORKER_SERVICE --region $REGION --format 'value(status.url)'
$TOPIC_NAME = "tb-d-ingest-tasks"
$SUB_SA = "tbd-sub-invoker@$PROJECT_ID.iam.gserviceaccount.com"

# Allow Pub/Sub to invoke Worker
gcloud run services add-iam-policy-binding $WORKER_SERVICE --region $REGION --member="serviceAccount:$SUB_SA" --role="roles/run.invoker"

# Update Subscription
gcloud pubsub subscriptions update tbd-worker-sub `
    --push-endpoint=$WORKER_URL `
    --push-auth-service-account=$SUB_SA

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   V6 MASTER ACTIVATION COMPLETE"
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Dispatcher : $(gcloud run services describe $DISPATCHER_SERVICE --region $REGION --format 'value(status.url)')"
Write-Host "Worker     : $WORKER_URL"
Write-Host "Encoder    : $ENCODER_URL"
Write-Host "Detector   : $DETECTOR_URL"
Write-Host "Status     : FULLY INTEGRATED"
Write-Host "========================================================" -ForegroundColor Green