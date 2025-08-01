#!/usr/bin/env bash
set -e

echo "Debug: Current working directory: $(pwd)"
echo "Debug: Contents of /app: $(ls -la /app)"
echo "Debug: Contents of /app/whisper.cpp: $(ls -la /app/whisper.cpp)"

INPUT="$1"
BASE="$(basename "$INPUT" .mp3)"
WAV="/tmp/${BASE}.wav"
OUT_PREFIX="/tmp/${BASE}"
MODEL="/app/whisper.cpp/models/ggml-medium.en.bin"

# Try different possible locations for the whisper executable
WHISPER_LOCATIONS=(
    "/app/whisper.cpp/build/bin/whisper-cli"
    "/app/whisper.cpp/whisper-cli"
    "/app/whisper.cpp/build/bin/main"
    "/app/whisper.cpp/main"
    "/app/whisper.cpp/build/main"
)

WHISPER=""
for location in "${WHISPER_LOCATIONS[@]}"; do
    echo "Debug: Checking for whisper executable at: $location"
    if [ -f "$location" ]; then
        WHISPER="$location"
        echo "Debug: Found whisper executable at: $WHISPER"
        break
    fi
done

if [ -z "$WHISPER" ]; then
    echo "Debug: Whisper executable NOT found in any expected location"
    echo "Debug: Available files in whisper.cpp directory:"
    find /app/whisper.cpp -name "*main*" -type f 2>/dev/null || echo "No main files found"

    # Try to build whisper if it's not found
    echo "Debug: Attempting to build whisper..."
    cd /app/whisper.cpp
    make clean || true
    make -j$(nproc)

    # Check again for the executable
    for location in "${WHISPER_LOCATIONS[@]}"; do
        if [ -f "$location" ]; then
            WHISPER="$location"
            echo "Debug: Built whisper executable found at: $WHISPER"
            break
        fi
    done

    if [ -z "$WHISPER" ]; then
        echo "Error: Could not find or build whisper executable"
        exit 1
    fi
fi

echo "Debug: Checking if model exists: $MODEL"
if [ -f "$MODEL" ]; then
    echo "Debug: Model found"
else
    echo "Debug: Model NOT found"
    echo "Debug: Available model files:"
    ls -la /app/whisper.cpp/models/ || echo "Models directory not found"
    exit 1
fi

echo "Converting → $WAV"
ffmpeg -y -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV"

echo "Running whisper..."
echo "Debug: Command: $WHISPER -m $MODEL -f $WAV -otxt -of $OUT_PREFIX --print-progress"

# Add timeout and progress output (no --verbose flag exists)
timeout 300 "$WHISPER" -m "$MODEL" -f "$WAV" -otxt -of "$OUT_PREFIX" --print-progress || {
    EXIT_CODE=$?
    echo "Debug: Whisper command failed with exit code: $EXIT_CODE"
    if [ $EXIT_CODE -eq 124 ]; then
        echo "Debug: Whisper timed out after 300 seconds"
    fi
    exit $EXIT_CODE
}

echo "Done  →  ${OUT_PREFIX}.txt"

# Verify the output file was created
if [ -f "${OUT_PREFIX}.txt" ]; then
    echo "Debug: Transcript file created successfully"
    echo "Debug: File size: $(stat -c%s "${OUT_PREFIX}.txt") bytes"
    echo "Debug: First few lines:"
    head -3 "${OUT_PREFIX}.txt" || echo "Could not read transcript file"
else
    echo "Debug: ERROR - Transcript file was not created"
    echo "Debug: Contents of /tmp:"
    ls -la /tmp/ | grep "$BASE" || echo "No files with base name found"
    exit 1
fi
