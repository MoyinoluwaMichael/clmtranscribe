FROM eclipse-temurin:17-jdk

# Environment setup
ENV DEBIAN_FRONTEND=noninteractive
ENV WHISPER_DIR=/app/whisper.cpp
ENV MODEL_NAME=ggml-medium.en.bin
ENV MODEL_PATH=$WHISPER_DIR/models/$MODEL_NAME

# Install required dependencies including build tools
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    dos2unix \
    git \
    build-essential \
    cmake \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy Maven config first (for better layer caching)
COPY mvnw pom.xml ./
COPY .mvn .mvn
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B

# Clone whisper.cpp fresh and build it for the container's architecture
RUN git clone https://github.com/ggerganov/whisper.cpp.git $WHISPER_DIR && \
    cd $WHISPER_DIR && \
    echo "=== Building whisper.cpp for container architecture ===" && \
    make clean || true && \
    make -j$(nproc) && \
    echo "=== Building whisper-cli with cmake ===" && \
    mkdir -p build && \
    cd build && \
    cmake .. -DWHISPER_BUILD_EXAMPLES=ON && \
    cmake --build . --config Release --parallel $(nproc)

# Copy your local model file to avoid re-downloading
COPY whisper.cpp/models/$MODEL_NAME $MODEL_PATH

# Verify binaries are working and executable
RUN echo "=== Verifying built binaries ===" && \
    echo "Architecture: $(uname -m)" && \
    echo "Whisper binaries found:" && \
    find $WHISPER_DIR -name "whisper-cli" -o -name "main" | xargs ls -la && \
    echo "Testing whisper-cli:" && \
    $WHISPER_DIR/build/bin/whisper-cli --help | head -5 && \
    echo "Model file:" && \
    ls -la "$MODEL_PATH" && \
    echo "Model size: $(stat -c%s "$MODEL_PATH") bytes"

# Copy scripts
COPY whisper-wrapper.sh .
RUN dos2unix whisper-wrapper.sh && chmod +x whisper-wrapper.sh

# Copy application source
COPY src src

# Create runtime folders
RUN mkdir -p /app/uploads /tmp && \
    chmod 1777 /tmp && \
    chmod 755 /app/uploads

# Build Spring Boot app
RUN ./mvnw clean package -DskipTests

# Verify the built JAR
RUN ls -la target/ && \
    echo "JAR size: $(stat -c%s target/clmtranscribe-0.0.1-SNAPSHOT.jar) bytes"

# Healthcheck
HEALTHCHECK --interval=30s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:1711/api/transcribe/health || exit 1

EXPOSE 1711

# Startup script
RUN echo '#!/bin/bash\n\
echo "=== CLM Transcribe Service Starting ==="\n\
echo "Container architecture: $(uname -m)"\n\
echo "Whisper binaries available:"\n\
find /app/whisper.cpp -name "main" -o -name "whisper-cli" | head -3\n\
echo "Model: $(ls -lh /app/whisper.cpp/models/*.bin | head -1)"\n\
echo "Testing whisper-cli:"\n\
/app/whisper.cpp/build/bin/whisper-cli --help | head -2 || echo "whisper-cli test failed"\n\
echo "Starting Spring Boot application..."\n\
exec java -Xmx2g -Djava.awt.headless=true -jar target/clmtranscribe-0.0.1-SNAPSHOT.jar\n\
' > /app/startup.sh && chmod +x /app/startup.sh

CMD ["/app/startup.sh"]
