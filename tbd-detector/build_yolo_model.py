import os
import sys
import shutil
import tensorflow as tf
from ultralytics import YOLO
from unittest.mock import MagicMock

# --- CONFIGURATION ---
MODEL_VERSION = "yolov8n.pt" 
ONNX_MODEL = "yolov8n.onnx"
TF_MODEL_DIR = "yolov8n_saved_model"
FINAL_MODEL_NAME = "model_yolo.h5"

# --- MOCKING FIX FOR WINDOWS ---
# onnx2tf requires 'ai_edge_litert' which is not available on Windows.
# We mock it here so the import succeeds, allowing us to use the rest of the tool.
print("--- applying Windows compatibility patch for onnx2tf ---")
sys.modules["ai_edge_litert"] = MagicMock()
sys.modules["ai_edge_litert.interpreter"] = MagicMock()

# Now we can safely import onnx2tf
import onnx2tf

def build_model():
    print(f"--- 1. Loading YOLOv8 Model ({MODEL_VERSION}) ---")
    model = YOLO(MODEL_VERSION)

    print("--- 2. Exporting to ONNX ---")
    # opset=12 is widely supported for TF conversion
    model.export(format="onnx", opset=12) 

    print("--- 3. Converting ONNX to TensorFlow SavedModel (In-Process) ---")
    if os.path.exists(TF_MODEL_DIR):
        shutil.rmtree(TF_MODEL_DIR)
    
    # Convert using the Python API directly
    # This generates the SavedModel in the output folder
    onnx2tf.convert(
        input_onnx_file_path=ONNX_MODEL,
        output_folder_path=TF_MODEL_DIR,
        copy_onnx_input=False,
        non_verbose=True,
        # We skip TFLite generation to avoid triggering the mocked code which might crash logic
        output_integer_quantized_tflite=False,
        output_float16_quantized_tflite=False
    )
    
    print(f"--- 4. Converting to Keras .h5 ({FINAL_MODEL_NAME}) ---")
    # Load the generated SavedModel
    # Note: onnx2tf saves the model in a standard TF format compatible with Keras
    keras_model = tf.keras.models.load_model(TF_MODEL_DIR)
    
    # Save as the legacy HDF5 format required by Service D
    keras_model.save(FINAL_MODEL_NAME, save_format="h5")
    
    # Cleanup intermediate files
    if os.path.exists(ONNX_MODEL):
        os.remove(ONNX_MODEL)
    if os.path.exists(TF_MODEL_DIR):
        shutil.rmtree(TF_MODEL_DIR)

    print(f"--- SUCCESS ---")
    print(f"Generated: {os.path.abspath(FINAL_MODEL_NAME)}")
    print(f"Action: Move this file to your 'tbd-detector/' directory before deploying.")

if __name__ == "__main__":
    build_model()