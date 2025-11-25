from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any

# --- V6 Data Models ---

class TelemetryContext(BaseModel):
    sensor_id: str = Field("default-sensor", description="IoT sensor identifier")
    machine_state: str = Field("IDLE", description="State of DED Robot")
    ambient_temp_c: float = Field(0.0, description="Telemetry data point")

class TaskPayload(BaseModel):
    task_id: str = Field(..., description="UUID-V4 for the task")
    client_id: str = Field(..., description="Identifier for the client")
    gcs_uri: str = Field(..., description="gs://bucket/video.mp4")
    output_bucket: str = Field(..., description="GCS bucket for results")
    config: Dict[str, Any] = Field(default_factory=dict, description="Config params")

# --- V6 Node Object (PAD Schema v0.5) ---

class ActionNode(BaseModel):
    id: str = Field(..., description="Unique node identifier")
    
    # Timing
    timestamp_start: float = Field(..., description="Start time")
    timestamp_end: float = Field(..., description="End time")

    # Semantic Data (Gemini)
    description: str = Field(..., description="High-level summary")
    semantic_description: Optional[str] = Field(None, description="GenAI summary")
    
    # Classification & Location (YOLO)
    action_type: str = Field("click", description="click, type, drag, scroll")
    ui_element_text: str = Field(..., description="OCR result from Active Region")
    ui_region: List[int] = Field(..., description="[x, y, w, h] bounding box")
    
    # Confidence
    confidence: float = Field(..., description="OCR confidence")
    active_region_confidence: float = Field(0.0, description="SSIM/YOLO confidence")

    # --- V6 NEW FIELDS (Fixed Missing Field Error) ---
    temporal_context_vector: List[float] = Field(default_factory=list, description="The V4 LSTM output vector (512D)")
    telemetry_context: Optional[TelemetryContext] = Field(default=None, description="IoT Context")
    
    next_node_id: Optional[str] = Field(None, description="Next node ID")

# --- V6 Root Object ---

class Pathway(BaseModel):
    pathway_id: str = Field(..., description="UUID-v4")
    title: str = Field(..., description="SOP Title")
    author_id: str = Field(..., description="User ID")
    source_video: str = Field(..., description="Source Video URI")
    created_at: str = Field(..., description="ISO-8601 Timestamp")
    total_duration_sec: float = Field(..., description="Total duration")

    # Metadata
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Top-level metadata")
    target_vertical: str = Field("manufacturing", description="Domain of the task")
    compliance_tag: str = Field("AS9100", description="Mandatory compliance tag")
    
    nodes: List[ActionNode] = Field(..., description="List of action nodes")