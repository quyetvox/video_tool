# Stage 1: Build Frontend React App (Vite)
FROM node:20-slim AS react-builder
WORKDIR /app/react_app
COPY react_app/package*.json ./
RUN npm install
COPY react_app/ ./
RUN npm run build

# Stage 2: Final Production Runner Image
FROM python:3.11-slim
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libopus-dev \
    libsndfile1 \
    cmake \
    ffmpeg \
    fonts-noto-cjk \
    curl \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Environment Variables for Centralized AI Models Cache
ENV PYTHONUNBUFFERED=1 \
    HF_HOME=/app/models/huggingface \
    TORCH_HOME=/app/models/torch \
    PADDLE_HOME=/app/models/paddleocr

# Install CPU-only PyTorch first (saves ~5.5GB of CUDA/cuDNN binaries)
RUN pip install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu

# Install Python requirements and purge build compilers to keep image slim
COPY py_engine/requirements.txt ./py_engine/requirements.txt
RUN pip install --no-cache-dir -r ./py_engine/requirements.txt \
    demucs \
    edge-tts \
    gTTS \
    openai-whisper \
    && apt-get purge -y build-essential cmake pkg-config \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install react_app server Node dependencies
COPY react_app/package*.json ./react_app/
RUN cd react_app && npm install --omit=dev

# Copy Application Core & Built react_app
COPY py_engine/ ./py_engine/
COPY config.yaml ./config.yaml
COPY react_app/server.js ./react_app/server.js
COPY --from=react-builder /app/react_app/dist ./react_app/dist

# Expose Web GUI & API Ports
EXPOSE 5173 3001

# Start react_app Server
CMD ["node", "react_app/server.js"]
