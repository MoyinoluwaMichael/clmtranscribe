FROM eclipse-temurin:17-jdk

# Install ffmpeg, dos2unix, and build tools
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    build-essential \
    cmake \
    curl \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /app

# Copy all source files including wrapper script
COPY . /app

# Clone whisper.cpp and build it
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    make -j$(nproc) && \
    echo "Build completed, listing build directory:" && \
    ls -la /app/whisper.cpp/build/bin/ || echo "build/bin directory not found" && \
    ls -la /app/whisper.cpp/ | grep -E "(main|whisper)" || echo "No whisper executables found in root"

# Download the medium English model
RUN cd whisper.cpp && \
    bash ./models/download-ggml-model.sh medium.en && \
    ls -la models/

# Convert whisper-wrapper.sh line endings and grant execute permission
RUN dos2unix /app/whisper-wrapper.sh && \
    chmod +x /app/whisper-wrapper.sh && \
    sed -i '1s|.*|#!/bin/bash|' /app/whisper-wrapper.sh

# Package Java project
RUN ./mvnw package -DskipTests

# Set entry point
ENTRYPOINT ["java", "-jar", "target/clmtranscribe-0.0.1-SNAPSHOT.jar"]
