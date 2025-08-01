# Use Ubuntu for better compatibility with whisper.cpp
FROM eclipse-temurin:17-jre

# Install required packages
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

# Copy source files
COPY . /app

# Clone and build whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    make -j$(nproc) && \
    # Remove git history to save space
    rm -rf .git && \
    # Verify the executable was built
    ls -la main || ls -la build/bin/ || echo "Build verification failed"

# Download smaller model for better memory usage
RUN cd whisper.cpp && \
    bash ./models/download-ggml-model.sh base.en && \
    # List downloaded models
    ls -la models/ && \
    # Remove any other model files to save space
    find models/ -name "*.bin" ! -name "*base.en*" -delete 2>/dev/null || true

# Fix script permissions
RUN dos2unix /app/whisper-wrapper.sh && \
    chmod +x /app/whisper-wrapper.sh

# Build Java application with memory constraints
RUN ./mvnw package -DskipTests -Dmaven.compiler.fork=true -Dmaven.compile.fork=true

# Clean up build dependencies to save space
RUN apt-get remove -y git build-essential cmake && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Remove Maven wrapper and unnecessary files
    rm -rf .mvn mvnw mvnw.cmd src/main/java src/test target/maven-* target/classes target/test-classes 2>/dev/null || true

# Set JVM memory limits and garbage collection options
ENV JAVA_OPTS="-Xms128m -Xmx750m -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -XX:+UseStringDeduplication -XX:MaxMetaspaceSize=128m"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar target/clmtranscribe-0.0.1-SNAPSHOT.jar"]
