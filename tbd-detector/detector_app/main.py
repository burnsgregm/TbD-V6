import os
import base64
import numpy as np
import cv2
import tensorflow as tf
from tensorflow.keras.layers import TFSMLayer
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List

# --- Configuration ---
INPUT_DIM = 640
# This matches the folder name created in the Dockerfile
MODEL_PATH = "model_yolo_dir" 

# --- Data Models ---
class FramePayload(BaseModel):
    frame_base64: str
    target_text: str = "default"

class DetectionResult(BaseModel):
    ui_region: List[int] # [x, y, w, h]
    confidence: float

# --- Global State ---
model = None

# --- Application Startup ---
app = FastAPI(title="TbD V6 Object Detector")

@app.on_event("startup")
async def startup_event():
    global model
    try:
        print(f"--- Loading YOLOv8 SavedModel from {MODEL_PATH} ---")
        # V6 Fix: Use TFSMLayer to load raw SavedModel folder
        # 'serving_default' is the standard signature key for TF SavedModels
        layer = TFSMLayer(MODEL_PATH, call_endpoint='serving_default')
        
        # Wrap in a Sequential model to restore the familiar .predict() API
        model = tf.keras.Sequential([layer])
        
        # Warmup inference (Optional but good for Cloud Run cold starts)
        dummy_input = np.zeros((1, INPUT_DIM, INPUT_DIM, 3), dtype=np.float32)
        model.predict(dummy_input, verbose=0)
        
        print(f"✅ Model loaded and warmed up successfully.")
    except Exception as e:
        print(f"CRITICAL: Failed to load YOLO model: {e}")
        model = None

# --- Helper Functions ---
def preprocess_image(frame: np.ndarray):
    """Resizes image to 640x640 and normalizes to 0-1."""
    resized = cv2.resize(frame, (INPUT_DIM, INPUT_DIM))
    # Convert to float32 and normalize
    normalized = resized.astype(np.float32) / 255.0
    # Add batch dimension: (1, 640, 640, 3)
    return np.expand_dims(normalized, axis=0)

def process_yolo_output(predictions, orig_w: int, orig_h: int):
    """
    Parses raw YOLOv8 output tensor.
    """
    # TFSMLayer output is often a dictionary {'output_0': tensor}
    if isinstance(predictions, dict):
        # Extract the first value (the main output tensor)
        predictions = list(predictions.values())[0]
    
    # Predictions shape is (1, 84, 8400) -> 4 box coords + 80 classes
    # We need to transpose to (1, 8400, 84) to iterate over anchors
    output = predictions[0].T 

    # Simple Post-Processing: Find single highest confidence box
    # (For V6, we assume we are looking for ONE primary UI element interaction)
    
    # Columns 4+ are class probabilities
    class_scores = np.max(output[:, 4:], axis=1)
    best_idx = np.argmax(class_scores)
    max_conf = class_scores[best_idx]
    
    # Extract the best box [center_x, center_y, width, height] (Normalized relative to 640x640)
    best_box = output[best_idx, :4]
    xc, yc, w, h = best_box

    # Map from 640x640 back to Original Resolution
    # Note: YOLOv8 outputs are relative to the *input* image size (640)
    scale_x = orig_w / INPUT_DIM
    scale_y = orig_h / INPUT_DIM

    pixel_w = int(w * scale_x)
    pixel_h = int(h * scale_y)
    
    center_x = int(xc * scale_x)
    center_y = int(yc * scale_y)
    
    pixel_x = int(center_x - (pixel_w / 2))
    pixel_y = int(center_y - (pixel_h / 2))

    # Clamp to image boundaries
    pixel_x = max(0, pixel_x)
    pixel_y = max(0, pixel_y)

    return [pixel_x, pixel_y, pixel_w, pixel_h], float(max_conf)

# --- Endpoint ---
@app.post("/detect_coordinates", response_model=DetectionResult)
async def detect_coordinates(payload: FramePayload):
    global model
    
    if model is None:
        return DetectionResult(ui_region=[0,0,0,0], confidence=0.0)

    try:
        # 1. Decode Base64
        image_bytes = base64.b64decode(payload.frame_base64)
        np_arr = np.frombuffer(image_bytes, np.uint8)
        frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        
        if frame is None:
            raise ValueError("Image decode failed")

        orig_h, orig_w = frame.shape[:2]

        # 2. Preprocess
        input_tensor = preprocess_image(frame)
        
        # 3. Inference
        raw_preds = model.predict(input_tensor, verbose=0)
        
        # 4. Post-Process & Map Coordinates
        ui_region, conf = process_yolo_output(raw_preds, orig_w, orig_h)

        return DetectionResult(ui_region=ui_region, confidence=conf)

    except Exception as e:
        print(f"Inference Error: {e}")
        # Graceful failure: return 0,0,0,0 so pipeline continues
        return DetectionResult(ui_region=[0,0,0,0], confidence=0.0)