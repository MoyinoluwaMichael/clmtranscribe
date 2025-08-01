# Build stage
FROM eclipse-temurin:17-jdk AS builder

# Install build tools
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    cmake \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy source files
COPY . /app

# Build Java application
RUN ./mvnw package -DskipTests

# Clone and build whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    make -j$(nproc) && \
    rm -rf .git

# Download model
RUN cd whisper.cpp && \
    bash ./models/download-ggml-model.sh tiny.en

# Fix script permissions
RUN dos2unix /app/whisper-wrapper.sh && \
    chmod +x /app/whisper-wrapper.sh

# Runtime stage
FROM eclipse-temurin:17-jre

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built artifacts from builder stage
COPY --from=builder /app/target/clmtranscribe-0.0.1-SNAPSHOT.jar /app/
COPY --from=builder /app/whisper.cpp /app/whisper.cpp
COPY --from=builder /app/whisper-wrapper.sh /app/

# Set JVM memory limits and garbage collection options
ENV JAVA_OPTS="-Xms128m -Xmx750m -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:+UseStringDeduplication -XX:MaxMetaspaceSize=128m"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar clmtranscribe-0.0.1-SNAPSHOT.jar"]
