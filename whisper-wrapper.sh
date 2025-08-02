#!/usr/bin/env bash
set -euo pipefail

echo "=== Whisper Wrapper Started: $(date) ==="
INPUT_FILE="$1"

# Validate input file
if [[ $# -lt 1 || ! -f "$INPUT_FILE" ]]; then
  echo "❌ Error: Invalid or missing input file"
  exit 1
fi

# Extract base name (strip multiple extensions)
BASENAME="$(basename "$INPUT_FILE")"
BASENAME="${BASENAME%.*}"  # strip extension
WAV_FILE="/tmp/${BASENAME}.wav"
OUTPUT_TXT="/tmp/${BASENAME}.txt"

echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_TXT"

# Locate whisper binary (try multiple names and locations)
POSSIBLE_PATHS=(
  # New whisper-cli binary locations (bin directory first)
  "/app/whisper.cpp/build/bin/whisper-cli"
  "/app/whisper.cpp/whisper-cli"
  "/app/whisper.cpp/build/whisper-cli"
  "/app/whisper.cpp/examples/whisper-cli"
  # Old main binary locations (fallback, bin directory first)
  "/app/whisper.cpp/build/bin/main"
  "/app/whisper.cpp/main"
  "/app/whisper.cpp/build/main"
  "/app/whisper.cpp/examples/main"
)

WHISPER_BINARY=""
BINARY_TYPE=""

for path in "${POSSIBLE_PATHS[@]}"; do
  if [[ -x "$path" ]]; then
    WHISPER_BINARY="$path"
    if [[ "$path" == *"whisper-cli"* ]]; then
      BINARY_TYPE="whisper-cli"
      echo "✅ Found whisper-cli at $WHISPER_BINARY"
    else
      BINARY_TYPE="main"
      echo "⚠️ Using deprecated 'main' binary at $WHISPER_BINARY"
    fi
    break
  fi
done

if [[ -z "$WHISPER_BINARY" ]]; then
  echo "❌ Error: No whisper binary found. Searched locations:"
  for path in "${POSSIBLE_PATHS[@]}"; do
    echo "  - $path $([ -f "$path" ] && echo "(exists but not executable)" || echo "(not found)")"
  done

  # Additional debugging info
  echo ""
  echo "🔍 Debug: Searching for any whisper binaries..."
  find /app/whisper.cpp -name "*whisper*" -type f 2>/dev/null || echo "No whisper files found"
  find /app/whisper.cpp -name "main" -type f 2>/dev/null || echo "No main files found"

  exit 1
fi

# Locate model file
MODEL_PATH=""
POSSIBLE_MODELS=(
  "/app/whisper.cpp/models/ggml-medium.en.bin"
  "/app/whisper.cpp/models/ggml-base.en.bin"
  "/app/whisper.cpp/models/ggml-small.en.bin"
  "/app/whisper.cpp/models/ggml-tiny.en.bin"
)

for model in "${POSSIBLE_MODELS[@]}"; do
  if [[ -f "$model" ]]; then
    MODEL_PATH="$model"
    echo "✅ Using model: $MODEL_PATH"
    break
  fi
done

# Fallback: look for any .bin file
if [[ -z "$MODEL_PATH" ]]; then
  for model in /app/whisper.cpp/models/*.bin; do
    if [[ -f "$model" ]]; then
      MODEL_PATH="$model"
      echo "✅ Using model: $MODEL_PATH"
      break
    fi
  done
fi

if [[ -z "$MODEL_PATH" ]]; then
  echo "❌ Error: No model file found. Searched:"
  for model in "${POSSIBLE_MODELS[@]}"; do
    echo "  - $model"
  done
  echo "Available files in models directory:"
  ls -la /app/whisper.cpp/models/ 2>/dev/null || echo "Models directory not found"
  exit 1
fi

# Convert to WAV format
echo "🎙️ Converting to WAV..."
if ! ffmpeg -y -i "$INPUT_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -loglevel error; then
  echo "❌ Audio conversion failed"
  exit 1
fi

echo "📊 Audio file info:"
echo "  Original: $(ls -lh "$INPUT_FILE" | awk '{print $5}')"
echo "  WAV: $(ls -lh "$WAV_FILE" | awk '{print $5}')"

# Build command based on binary type
if [[ "$BINARY_TYPE" == "whisper-cli" ]]; then
  # New whisper-cli command format
  echo "🧠 Running whisper-cli..."
  WHISPER_CMD=("$WHISPER_BINARY" -m "$MODEL_PATH" -f "$WAV_FILE" --output-txt --output-file "/tmp/${BASENAME}" --no-timestamps --no-prints)
else
  # Old main binary command format
  echo "🧠 Running main (deprecated)..."
  WHISPER_CMD=("$WHISPER_BINARY" -m "$MODEL_PATH" -f "$WAV_FILE" -otxt -of "/tmp/${BASENAME}")
fi

echo "Command: ${WHISPER_CMD[*]}"

# Run transcription with timeout and capture output
echo "Running command with full output capture..."
timeout 300s "${WHISPER_CMD[@]}" 2>&1 | tee /tmp/whisper_output.log
TRANSCRIBE_EXIT=${PIPESTATUS[0]}

if [[ $TRANSCRIBE_EXIT -eq 124 ]]; then
  echo "❌ Transcription timed out after 5 minutes"
  rm -f "$WAV_FILE"
  exit 1
elif [[ $TRANSCRIBE_EXIT -ne 0 ]]; then
  echo "❌ Transcription failed with exit code $TRANSCRIBE_EXIT"
  echo "Error output:"
  cat /tmp/whisper_output.log | tail -20
  echo ""
  echo "🔍 Debugging info:"
  echo "Model file exists: $([ -f "$MODEL_PATH" ] && echo 'YES' || echo 'NO')"
  echo "Model size: $(stat -c%s "$MODEL_PATH" 2>/dev/null || echo 'unknown') bytes"
  echo "WAV file exists: $([ -f "$WAV_FILE" ] && echo 'YES' || echo 'NO')"
  echo "WAV file size: $(stat -c%s "$WAV_FILE" 2>/dev/null || echo 'unknown') bytes"
  rm -f "$WAV_FILE"
  exit 1
fi

# Clean up WAV file
rm -f "$WAV_FILE"

# Check if output file was created
if [[ ! -f "$OUTPUT_TXT" ]]; then
  echo "❌ Output file not created: $OUTPUT_TXT"
  echo "Files in /tmp:"
  ls -la /tmp/*${BASENAME}* 2>/dev/null || echo "No matching files found"
  exit 1
fi

# Check if output file has content
if [[ ! -s "$OUTPUT_TXT" ]]; then
  echo "⚠️ No speech detected in audio." > "$OUTPUT_TXT"
fi

echo "✅ Transcription complete: $OUTPUT_TXT"
echo "📝 Output size: $(ls -lh "$OUTPUT_TXT" | awk '{print $5}')"

exit 0
