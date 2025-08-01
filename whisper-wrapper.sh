#!/usr/bin/env bash
set -e

# Memory and performance optimizations
export OMP_NUM_THREADS=2
export MALLOC_TRIM_THRESHOLD_=131072

INPUT="$1"
BASE="$(basename "$INPUT" | sed 's/\.[^.]*$//')"
WAV="/tmp/${BASE}.wav"
OUT_PREFIX="/tmp/${BASE}"

# Use smaller, faster model for better memory usage
MODEL="/app/whisper.cpp/models/ggml-base.en.bin"

# Find whisper executable
WHISPER_LOCATIONS=(
    "/app/whisper.cpp/main"
    "/app/whisper.cpp/build/bin/main"
    "/app/whisper.cpp/whisper-cli"
    "/app/whisper.cpp/build/bin/whisper-cli"
)

WHISPER=""
for location in "${WHISPER_LOCATIONS[@]}"; do
    if [ -f "$location" ] && [ -x "$location" ]; then
        WHISPER="$location"
        break
    fi
done

if [ -z "$WHISPER" ]; then
    echo "Error: Whisper executable not found"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model file not found: $MODEL"
    exit 1
fi

# Convert audio with memory-efficient settings
echo "Converting audio..."
ffmpeg -y -i "$INPUT" \
    -ar 16000 \
    -ac 1 \
    -c:a pcm_s16le \
    -f wav \
    -loglevel error \
    "$WAV"

# Check converted file size
WAV_SIZE=$(stat -c%s "$WAV" 2>/dev/null || echo "0")
if [ "$WAV_SIZE" -gt $((100 * 1024 * 1024)) ]; then
    echo "Error: Converted audio file too large"
    rm -f "$WAV"
    exit 1
fi

# Run whisper with memory constraints
echo "Running transcription..."
timeout 300 "$WHISPER" \
    -m "$MODEL" \
    -f "$WAV" \
    -otxt \
    -of "$OUT_PREFIX" \
    --no-timestamps \
    --language en \
    --threads 2 2>/dev/null || {

    EXIT_CODE=$?
    rm -f "$WAV"

    if [ $EXIT_CODE -eq 124 ]; then
        echo "Error: Transcription timed out"
    else
        echo "Error: Transcription failed"
    fi
    exit $EXIT_CODE
}

# Clean up WAV file immediately
rm -f "$WAV"

# Verify output
if [ ! -f "${OUT_PREFIX}.txt" ]; then
    echo "Error: Transcript file not created"
    exit 1
fi

# Check output file size
OUTPUT_SIZE=$(stat -c%s "${OUT_PREFIX}.txt" 2>/dev/null || echo "0")
if [ "$OUTPUT_SIZE" -eq 0 ]; then
    echo "Error: Empty transcript file"
    rm -f "${OUT_PREFIX}.txt"
    exit 1
fi

echo "Transcription completed successfully"
