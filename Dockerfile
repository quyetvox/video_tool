# Stage 1: Build Frontend GUI React/Vite
FROM node:20-slim AS gui-builder
WORKDIR /app/gui
COPY gui/package*.json ./
RUN npm install
COPY gui/ ./
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
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    demucs \
    edge-tts \
    gTTS \
    openai-whisper \
    && apt-get purge -y build-essential cmake pkg-config \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Install GUI server Node dependencies
COPY gui/package*.json ./gui/
RUN cd gui && npm install --omit=dev

# Copy Application Core & Built GUI
COPY lib/ ./lib/
COPY main.py trim.py batch_translate.py download.py narrate.py ./
COPY config.yaml ./config.yaml
COPY gui/server.js ./gui/server.js
COPY --from=gui-builder /app/gui/dist ./gui/dist

# Expose Web GUI & API Ports
EXPOSE 5173 3001

# Start GUI Server
CMD ["node", "gui/server.js"]
