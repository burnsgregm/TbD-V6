FROM python:3.10-slim

# Set working directory
WORKDIR /usr/src/app

# Install system dependencies (OpenCV requires libgl1)
# We also add 'unzip' to handle the model artifact
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY detector_requirements.txt .
RUN pip install --no-cache-dir -r detector_requirements.txt

# Copy the Model Artifact (The Zip file from Colab)
COPY model_yolo.zip .

# Unzip the model into a specific directory
# This creates /usr/src/app/model_yolo_dir/ containing saved_model.pb
RUN unzip model_yolo.zip -d model_yolo_dir && rm model_yolo.zip

# Copy the Application Code
COPY detector_app/ ./detector_app/

# Environment Configuration
ENV PORT=8080

# Launch the Service
CMD ["uvicorn", "detector_app.main:app", "--host", "0.0.0.0", "--port", "8080"]