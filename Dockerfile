FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    git cmake build-essential ffmpeg curl openjdk-17-jdk maven unzip

# Set up working directory
WORKDIR /app

# Clone and build whisper.cpp
RUN git clone https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && make

# Download model
RUN curl -L -o whisper.cpp/models/ggml-medium.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin

# Copy Spring Boot app
COPY . /app

# Make wrapper executable
RUN chmod +x /app/whisper-wrapper.sh

# Build Spring Boot app
RUN mvn clean package -DskipTests

EXPOSE 8080

CMD ["java", "-jar", "target/your-app-name.jar"]
