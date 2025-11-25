# Teach by Doing (TbD) Engine – V6.0

**Status:** Production Ready (Native Insight Release)  
**Version:** 6.0.0  
**Architecture:** Asynchronous Microservices Mesh (GCP)

---

## 1. Executive Summary

The Teach by Doing (TbD) Engine is the core ingestion gateway for the Pathways as Data (PAD) platform. It transforms raw expert demonstrations (video + audio) into structured, machine-executable assets called Pathways.

V6.0 **"Native Insight"** marks the transition from infrastructure to full intelligence. The system now utilizes active Machine Learning microservices to achieve **Pixel-Accurate Coordinate Detection** and **Temporal Procedural Memory**, eliminating the "Data Gap" for downstream AI agents and robotics.

---

## 2. System Architecture

The system utilizes a decoupled, asynchronous **Fan-Out Architecture** deployed on Google Cloud Run.

### Core Microservices

| Service              | Role              | Tech Stack                   | Function                                                                                                                                         |
|----------------------|-------------------|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| Service A: Dispatcher| API Gateway       | Python / FastAPI             | Ingests requests, generates OpenTelemetry Traces, and queues tasks to Pub/Sub. Returns `202 Accepted`.                                          |
| Service B: Worker    | Orchestrator      | Python / OpenCV / Gemini     | The "Brain." Handles audio transcription, LLM reasoning, and coordinates calls to Services C & D.                                               |
| Service C: Temporal Encoder | Memory Engine | TensorFlow (CPU) / LSTM | Processes sequential semantic history to generate a 512D Temporal Context Vector.                                                               |
| Service D: Object Detector | Pixel Accuracy | YOLO / Vision Transformer | Verifies UI elements and returns pixel-perfect bounding boxes (`ui_region`).                                                                    |

### Infrastructure Components

- **Transport:** Google Cloud Pub/Sub (`tbd-ingest-tasks`, `pad-agent-tasks`).
- **Storage:** Google Cloud Storage (GCS) for raw video input and JSON output.
- **State:** Redis/Firestore (for Idempotency checks).
- **AI APIs:** Google Cloud Speech-to-Text, Vertex AI (Gemini 2.5 Pro).

---

## 3. Key V6 Capabilities

- **Multimodal Fusion:**  
  Ingests Video (Pixels), Audio (Voice Transcript via STT), and Context (LLM Reasoning) to determine user intent.

- **Guaranteed Pixel Accuracy:**  
  Replaced Tesseract OCR with a custom Object Detection Model (Service D) to guarantee reliable coordinate data for robotic execution.

- **Sequential Memory:**  
  Uses a dedicated LSTM Microservice (Service C) to embed the procedural state, allowing downstream agents to know where a user is in a long workflow.

- **Enterprise Hardening:**  
  Full Idempotency (prevents duplicate billing) and Distributed Tracing (end-to-end log correlation).

- **Compliance Lock:**  
  Enforces mandatory Marketplace metadata (`license_tier`, `compliance_tag`) before asset release.

---

## 4. Directory Structure

The project must be structured as follows for the deployment scripts to function:

```bash
tbd-v6/
??? deploy_v6_master.ps1       # Master Orchestrator Script
??? requirements.txt           # Shared dependencies
??? app/                       # Service A & B Codebase
?   ??? main.py                # Dispatcher Entrypoint
?   ??? worker.py              # Worker Entrypoint
?   ??? services/              # Business Logic (pipeline, genai, vision)
??? tbd-encoder/               # Service C (LSTM)
?   ??? Dockerfile             # CPU-Optimized TensorFlow Build
?   ??? lstm_model.h5          # Trained Model Weights
?   ??? tokenizer.pickle       # Tokenizer Asset
??? tbd-detector/              # Service D (YOLO)
    ??? Dockerfile             # Inference Container
    ??? model_yolo.zip         # SavedModel Assets

## 5. Usage Guide

### 5.1 Submitting a Job

The Dispatcher exposes a public REST endpoint.

- **Endpoint:** `POST /submit`  
- **Content-Type:** `application/json`

**Request JSON:**

```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "client_id": "streamlit-dashboard",
  "gcs_uri": "gs://pad-raw-video/demo_manufacturing_process.mp4",
  "output_bucket": "pad-results-processed",
  "config": {
    "target_vertical": "manufacturing",
    "compliance_tag": "AS9100"
  }
}

**Response (Immediate):**

```json
{
  "status": "queued",
  "trace_id": "a1b2c3d4e5...",
  "queue_depth": "approximate"
}

### 5.2 The Output (`Pathway.json` v0.5)

The final asset is saved to the output bucket. It is fully compliant with the PAD Schema.

```jsonc
{
  "pathway_id": "...",
  "metadata": {
    "license_tier": "royalty-pro",
    "compliance_tag": "AS9100"
  },
  "nodes": [
    {
      "id": "node_1",
      "type": "action",
      "semantic_description": "User clicks 'Calibrate' to zero the Z-axis.",
      "full_audio_transcript_segment": "Okay, now I'm zeroing the bed height.",
      "ui_region": [100, 200, 50, 25],
      "data": {
        "temporal_context_vector": [0.12, 0.45, ...], // 512D Vector
        "telemetry_context": {}
      }
    }
  ]
}

## 6. Deployment Instructions

### Prerequisites

- Google Cloud Project with Billing enabled.
- APIs Enabled: Cloud Run, Pub/Sub, Artifact Registry, Vertex AI, Speech-to-Text.
- `gcloud` CLI authenticated.

### Deployment Steps

1. **Infrastructure Setup**  
   Ensure Pub/Sub topics (`tbd-ingest-tasks`, `pad-agent-tasks`) and GCS buckets exist.

2. **Service C & D (The Brains)**  
   Deploy the AI microservices first to generate internal URLs.

   ```powershell
   ./deploy_encoder.ps1
   ./deploy_detector.ps1
