# Use a more memory-efficient base image
FROM eclipse-temurin:17-jre-alpine

# Install required packages
RUN apk add --no-cache \
    ffmpeg \
    git \
    build-base \
    cmake \
    bash \
    dos2unix

# Set workdir
WORKDIR /app

# Copy source files
COPY . /app

# Clone and build whisper.cpp with optimizations
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    # Build with optimizations and smaller memory footprint
    make -j$(nproc) WHISPER_NO_AVX=1 WHISPER_NO_AVX2=1 && \
    # Clean up build artifacts to save space
    make clean && \
    # Remove git history to save space
    rm -rf .git

# Download smaller model for better memory usage
RUN cd whisper.cpp && \
    bash ./models/download-ggml-model.sh base.en && \
    # Remove other model files if they exist
    find models/ -name "*.bin" ! -name "*base.en*" -delete 2>/dev/null || true

# Fix script permissions
RUN dos2unix /app/whisper-wrapper.sh && \
    chmod +x /app/whisper-wrapper.sh

# Build Java application
RUN ./mvnw package -DskipTests && \
    # Remove Maven wrapper and source files to save space
    rm -rf .mvn mvnw mvnw.cmd src target/maven-* target/classes/com target/test-classes 2>/dev/null || true

# Set JVM memory limits and garbage collection options
ENV JAVA_OPTS="-Xms128m -Xmx512m -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:+UseStringDeduplication"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar target/clmtranscribe-0.0.1-SNAPSHOT.jar"]
