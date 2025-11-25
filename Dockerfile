FROM python:3.10-slim

# Set working directory
WORKDIR /usr/src
ENV PYTHONUNBUFFERED=True

# 1. Install System Dependencies (FIXED: Consolidated RUN command for stability)
RUN apt-get update && \
    apt-get install -y tesseract-ocr libtesseract-dev libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 2. Copy and Install Python Dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 3. Copy Application Code
COPY ./app /usr/src/app

# 4. Define Environment
ENV PORT=8080

CMD sh -c "uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"