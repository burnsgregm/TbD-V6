import os
import tempfile
import base64
import json
import asyncio
import requests
import time
from urllib.parse import urlparse
from google.cloud import storage, pubsub_v1, speech
from google.auth.transport.requests import Request
from google.oauth2 import id_token
from typing import List, Dict, Any

# Import internal modules
from app.schema import TaskPayload, Pathway, TelemetryContext
from app.services.pipeline import build_pathway
import uuid

# --- V6 Configuration Constants ---
PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "tbd-v2")
TEMP_DIR = tempfile.gettempdir()

# External Service URLs (Injected by Deployment Script)
# If running locally, these defaults will likely fail, which is expected.
TEMPORAL_ENCODER_URL = os.environ.get("TEMPORAL_ENCODER_URL", "")
OBJECT_DETECTOR_URL = os.environ.get("OBJECT_DETECTOR_URL", "")
MARKETPLACE_API_URL = "https://marketplace.freefuse.com/api/v1/register"
TELEMETRY_API_URL = "http://manufacturing-iot-hub/v1/telemetry" # FR-04: Mock IoT Endpoint

# Pub/Sub & Storage
AGENT_TOPIC_NAME = "pad-agent-tasks"
AUDIO_STAGING_BUCKET = f"tbd-audio-staging-{PROJECT_ID}"

# In-Memory Idempotency (Production would use Redis)
PROCESSED_TASKS = set()

# --- V6 Helper Functions ---

def _get_auth_token(audience: str) -> str:
    """Generates an OIDC token for secure Service-to-Service calls."""
    if not audience or "http://" in audience:
        return "" # No auth needed for mock HTTP endpoints
    try:
        auth_req = Request()
        return id_token.fetch_id_token(auth_req, audience)
    except Exception as e:
        print(f"AUTH WARNING: Could not fetch token for {audience}: {e}")
        return ""

def _extract_audio_track(video_path: str) -> str:
    """Uses ffmpeg to rip audio from the video file."""
    audio_filename = f"audio_{uuid.uuid4()}.mp3"
    audio_path = os.path.join(TEMP_DIR, audio_filename)
    # -q:a 2 -> High quality variable bit rate
    # -vn -> No video
    # -y -> Overwrite output
    cmd = f"ffmpeg -i \"{video_path}\" -vn -acodec libmp3lame -q:a 2 -y \"{audio_path}\""
    exit_code = os.system(cmd)
    if exit_code != 0:
        print("WARNING: ffmpeg audio extraction failed. Creating silent placeholder.")
        with open(audio_path, 'wb') as f: f.write(b'')
    return audio_path

def _upload_audio_to_gcs(local_path: str, task_id: str) -> str:
    """Uploads mp3 to GCS for the Speech-to-Text API."""
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(AUDIO_STAGING_BUCKET)
        blob_name = f"{task_id}/audio.mp3"
        blob = bucket.blob(blob_name)
        blob.upload_from_filename(local_path)
        return f"gs://{AUDIO_STAGING_BUCKET}/{blob_name}"
    except Exception as e:
        print(f"GCS UPLOAD ERROR: {e}")
        return ""

async def _call_speech_to_text(gcs_uri: str) -> str:
    """FR-03: Calls Google Cloud Speech-to-Text API (Live)."""
    if not gcs_uri: return " [Audio Missing] "
    
    print(f"Transcribing audio from: {gcs_uri}")
    try:
        client = speech.SpeechAsyncClient()
        audio = speech.RecognitionAudio(uri=gcs_uri)
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.MP3,
            sample_rate_hertz=16000, # ffmpeg default usually matches this
            language_code="en-US",
            enable_automatic_punctuation=True
        )
        
        operation = await client.long_running_recognize(config=config, audio=audio)
        response = await operation.result(timeout=300)

        transcript = ""
        for result in response.results:
            transcript += result.alternatives[0].transcript + " "
        
        return transcript.strip()
    except Exception as e:
        print(f"STT ERROR: {e}")
        return " [Transcription Failed] "

async def _fetch_iot_telemetry() -> TelemetryContext:
    """FR-04: Fetches machine state from the IoT Hub."""
    # In a real scenario, we'd pass the timestamp to get state at that exact moment.
    # Here we simulate a live fetch.
    try:
        # Simulated secure call
        # token = _get_auth_token(TELEMETRY_API_URL)
        # headers = {"Authorization": f"Bearer {token}"}
        # resp = requests.get(TELEMETRY_API_URL, headers=headers, timeout=1)
        
        # Mock Response for V6 Demo
        return TelemetryContext(
            sensor_id="DED-Robot-Arm-01",
            machine_state="ACTIVE_PRINTING",
            ambient_temp_c=24.5 + (time.time() % 10) * 0.1 # Slight variation
        )
    except Exception as e:
        print(f"IoT FETCH ERROR: {e}")
        return TelemetryContext()

async def _enrich_with_temporal_context(pathway: Pathway):
    """FR-01: Calls Service C (Temporal Encoder) to vectorize the workflow."""
    if not TEMPORAL_ENCODER_URL:
        print("WARNING: Temporal Encoder URL not set. Skipping vectorization.")
        return

    # 1. Extract text sequence from nodes
    text_sequence = [node.description for node in pathway.nodes]
    
    # 2. Call Service C
    payload = {"sequence": text_sequence}
    token = _get_auth_token(TEMPORAL_ENCODER_URL)
    headers = {"Authorization": f"Bearer {token}"}
    
    try:
        print(f"Calling Temporal Encoder at {TEMPORAL_ENCODER_URL}...")
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None, 
            lambda: requests.post(f"{TEMPORAL_ENCODER_URL}/encode_sequence", json=payload, headers=headers, timeout=30)
        )
        response.raise_for_status()
        data = response.json()
        
        # 3. Apply Vector to ALL nodes (Context is global for the pathway in V4 logic)
        # In V5/V6 advanced, we might do step-by-step encoding, but V4 baseline is sequence-level.
        vector = data.get("temporal_context_vector", [])
        
        for node in pathway.nodes:
            node.temporal_context_vector = vector
            
        print("Temporal Vector applied successfully.")
        
    except Exception as e:
        print(f"ENCODER FAILURE: {e}")
        # Fail open - do not crash the pipeline, just leave vectors empty

# --- Main Worker Service ---

class WorkerService:
    def __init__(self):
        self.storage_client = storage.Client()
        self.publisher = pubsub_v1.PublisherClient()

    async def process_pubsub_message(self, pubsub_message_data: dict):
        """Main Orchestration Loop."""
        
        # 1. Parse Message
        try:
            message_data = base64.b64decode(pubsub_message_data['message']['data'])
            payload_dict = json.loads(message_data.decode('utf-8'))
            payload = TaskPayload.model_validate(payload_dict)
            task_id = payload.task_id
            trace_id = pubsub_message_data['message'].get('attributes', {}).get('trace_id', 'no-trace')
        except Exception as e:
            print(f"FATAL: Invalid Pub/Sub message: {e}")
            return # ACK to stop retry loop on bad data

        print(f"--- WORKER V6 START: Task {task_id} [Trace: {trace_id}] ---")

        # 2. Idempotency Check
        if task_id in PROCESSED_TASKS:
            print(f"Skipping duplicate task {task_id}")
            return

        # 3. Setup Local Paths
        input_bucket = urlparse(payload.gcs_uri).netloc
        input_blob_name = urlparse(payload.gcs_uri).path.lstrip('/')
        local_video_path = os.path.join(TEMP_DIR, f"{task_id}_video.mp4")
        
        try:
            # 4. Download Video
            print("Downloading video...")
            bucket = self.storage_client.bucket(input_bucket)
            blob = bucket.blob(input_blob_name)
            blob.download_to_filename(local_video_path)

            # 5. Audio Extraction & Transcription (FR-03)
            print("Processing Audio...")
            local_audio = _extract_audio_track(local_video_path)
            audio_uri = _upload_audio_to_gcs(local_audio, task_id)
            transcript = await _call_speech_to_text(audio_uri)
            
            # 6. Build Pathway (Gemini + Service D) (FR-02)
            # This calls pipeline.py which calls Service D
            print("Building Pathway (Visual + Spatial)...")
            pathway = await build_pathway(
                local_video_path=local_video_path,
                gcs_video_uri=payload.gcs_uri,
                audio_transcript=transcript,
                object_detector_url=OBJECT_DETECTOR_URL
            )
            
            # 7. Post-Processing: IoT & Temporal (FR-01, FR-04)
            print("Enriching Data (IoT + Temporal)...")
            telemetry = await _fetch_iot_telemetry()
            
            # Apply telemetry to all nodes
            for node in pathway.nodes:
                node.telemetry_context = telemetry
            
            # Apply Temporal Vector (Service C)
            await _enrich_with_temporal_context(pathway)

            # 8. Final Upload & Distribution
            output_blob = f"{task_id}/pathway.json"
            output_bucket = self.storage_client.bucket(payload.output_bucket)
            output_bucket.blob(output_blob).upload_from_string(pathway.model_dump_json(indent=2))
            final_uri = f"gs://{payload.output_bucket}/{output_blob}"
            
            print(f"SUCCESS. Pathway uploaded to: {final_uri}")
            
            # 9. Publish to Agent Topic (Execution Trigger)
            topic_path = self.publisher.topic_path(PROJECT_ID, AGENT_TOPIC_NAME)
            self.publisher.publish(topic_path, final_uri.encode("utf-8"), trace_id=trace_id)

            PROCESSED_TASKS.add(task_id)

        except Exception as e:
            print(f"WORKER FAILURE: {e}")
            raise e # Nack message to retry
        finally:
            # Cleanup
            if os.path.exists(local_video_path): os.remove(local_video_path)
            if 'local_audio' in locals() and os.path.exists(local_audio): os.remove(local_audio)