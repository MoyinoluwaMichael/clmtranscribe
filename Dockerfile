FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    git cmake build-essential ffmpeg curl openjdk-17-jdk maven unzip

# Set working directory
WORKDIR /app

# Clone and build whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && make

# Download Whisper model
RUN curl -L -o whisper.cpp/models/ggml-medium.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin

# Copy your Spring Boot app code into the container
COPY . .

# Make your wrapper script executable
RUN chmod +x /app/whisper-wrapper.sh

# Build the Spring Boot app
RUN mvn clean package -DskipTests

# Expose port
EXPOSE 8080

# Run the application
ENTRYPOINT ["java", "-jar", "target/clmtranscribe-0.0.1-SNAPSHOT.jar"]
