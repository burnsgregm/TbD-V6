FROM python:3.10-slim
WORKDIR /usr/src/app

# Install dependencies
RUN apt-get update && apt-get install -y build-essential libhdf5-dev pkg-config && rm -rf /var/lib/apt/lists/*

# Install Python libs first
COPY encoder_requirements.txt .
RUN pip install --no-cache-dir -r encoder_requirements.txt

# --- CRITICAL FIX: Generate Tokenizer In-Situ ---
# We copy the script and RUN it here. 
# This creates 'tokenizer.pickle' inside the image using the container's TF version.
COPY create_tokenizer.py .
RUN python create_tokenizer.py

# Copy the Model
COPY lstm_model.h5 .

# Copy App Code
COPY encoder_app/ ./encoder_app/

ENV PORT=8080
CMD ["uvicorn", "encoder_app.main:app", "--host", "0.0.0.0", "--port", "8080"]