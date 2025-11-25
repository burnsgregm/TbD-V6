import os
import uuid
import time
import cv2
import asyncio
import json
import base64
import requests
from typing import List, Tuple
from app.schema import Pathway, ActionNode
from app.services.genai import analyze_video_native
from app.services.ocr import run_ocr
from google.oauth2 import id_token
from google.auth.transport.requests import Request

# --- CONFIGURATION ---
# INCREASED TIMEOUT: 5s -> 30s to handle Cloud Run Cold Starts
OBJECT_DETECTOR_TIMEOUT = 30.0

def _get_auth_token(audience: str) -> str:
    """Generates an authenticated token for the target Cloud Run service."""
    if not audience or "http://" in audience: return ""
    try:
        auth_request = Request()
        token = id_token.fetch_id_token(auth_request, audience)
        return token
    except Exception as e:
        print(f"AUTH ERROR: {e}")
        return ""

def _get_frame_at_time(cap: cv2.VideoCapture, timestamp: float) -> cv2.typing.MatLike:
    """Extracts a frame at a specific timestamp for coordinate refinement."""
    max_duration = cap.get(cv2.CAP_PROP_FRAME_COUNT) / cap.get(cv2.CAP_PROP_FPS)
    safe_timestamp = min(timestamp, max_duration - 0.1)
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_no = int(safe_timestamp * fps)
    
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_no)
    ret, frame = cap.read()
    
    if not ret:
        # Fallback: Try reading the 2nd to last frame
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.set(cv2.CAP_PROP_POS_FRAMES, total_frames - 2)
        ret, frame = cap.read()
        if not ret: return None
        
    return frame

async def _call_object_detector(frame: cv2.typing.MatLike, target_text: str, detector_url: str) -> Tuple[List[int], float]:
    """FR-07: Calls Service D securely for pixel-accurate coordinate prediction."""
    if frame is None: return [0,0,0,0], 0.0
    
    token = _get_auth_token(detector_url)
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    
    success, buffer = cv2.imencode('.jpg', frame)
    frame_base64 = base64.b64encode(buffer).decode('utf-8')
    
    payload = {"frame_base64": frame_base64, "target_text": target_text}
    
    try:
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(
            None,
            lambda: requests.post(
                f"{detector_url}/detect_coordinates", 
                headers=headers, 
                json=payload, 
                timeout=OBJECT_DETECTOR_TIMEOUT # Updated Timeout
            )
        )
        
        if response.status_code == 200:
            result = response.json()
            return result.get('ui_region', [0,0,0,0]), result.get('confidence', 0.0)
        else:
            print(f"Detector Error {response.status_code}: {response.text}")
            return [0,0,0,0], 0.0
            
    except Exception as e:
        print(f"WARNING: Object Detector call failed: {e}")
        return [0, 0, 0, 0], 0.0

# --- Main V6 Pipeline ---
async def build_pathway(local_video_path: str, gcs_video_uri: str, audio_transcript: str, object_detector_url: str) -> Pathway:
    print(f"Starting 'Native Insight' Pipeline for: {os.path.basename(local_video_path)}")
    start_time = time.time()

    # 1. Semantic Analysis (Gemini)
    print("Phase 1: Semantic Analysis (Gemini)...")
    # Note: Ensure app/services/genai.py is present and correct
    ai_steps = await analyze_video_native(gcs_video_uri, audio_transcript)
    print(f"Gemini identified {len(ai_steps)} steps.")

    # 2. Coordinate Refinement (YOLO)
    print("Phase 2: Coordinate Refinement (YOLO)...")
    cap = cv2.VideoCapture(local_video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    total_duration_sec = total_frames / fps if fps else 0
    
    final_nodes = []
    
    for i, step in enumerate(ai_steps):
        timestamp = float(step.get('timestamp', 0.0))
        target_text = step.get('target_text', "Unlabeled")
        
        # Extract frame and call detector
        frame = _get_frame_at_time(cap, timestamp)
        ui_region, confidence = await _call_object_detector(frame, target_text, object_detector_url)
        
        node = ActionNode(
            id=f"node_{i+1}",
            timestamp_start=timestamp,
            timestamp_end=timestamp + 1.0, # Default duration
            description=step.get('description', 'No description'),
            semantic_description=step.get('description', 'No description'),
            ui_element_text=target_text,
            ui_region=ui_region,
            confidence=confidence,
            active_region_confidence=confidence,
            action_type=step.get('action_type', 'click'),
            # Next node ID logic
            next_node_id=f"node_{i+2}" if i + 1 < len(ai_steps) else None
        )
        final_nodes.append(node)
        
    cap.release()

    # 3. Assembly
    pathway = Pathway(
        pathway_id=str(uuid.uuid4()),
        title=f"Native Insight: {os.path.basename(local_video_path)}",
        author_id="tbd-v6-engine",
        source_video=os.path.basename(local_video_path),
        created_at=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        total_duration_sec=total_duration_sec,
        nodes=final_nodes,
        metadata={
            "target_vertical": "manufacturing",
            "compliance_tag": "AS9100"
        }
    )
    
    print(f"Pipeline complete in {time.time() - start_time:.2f}s")
    return pathway