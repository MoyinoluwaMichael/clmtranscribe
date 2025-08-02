#!/usr/bin/env bash
set -euo pipefail

echo "=== Whisper Installation Debug ==="
echo "Date: $(date)"
echo ""

echo "🔍 Whisper Directory Structure:"
if [[ -d "/app/whisper.cpp" ]]; then
  echo "✅ /app/whisper.cpp exists"
  echo "Directory size: $(du -sh /app/whisper.cpp 2>/dev/null | cut -f1)"

  echo ""
  echo "📁 Top level contents:"
  ls -la /app/whisper.cpp/ | head -20

  echo ""
  echo "🔍 Looking for whisper binaries:"
  find /app/whisper.cpp -name "*whisper*" -type f 2>/dev/null | while read file; do
    echo "  Found: $file $([ -x "$file" ] && echo "[executable]" || echo "[not executable]")"
  done

  echo ""
  echo "🔍 Looking for main binary:"
  find /app/whisper.cpp -name "main" -type f 2>/dev/null | while read file; do
    echo "  Found: $file $([ -x "$file" ] && echo "[executable]" || echo "[not executable]")"
  done

  echo ""
  echo "📁 Build directory:"
  if [[ -d "/app/whisper.cpp/build" ]]; then
    echo "✅ Build directory exists"
    ls -la /app/whisper.cpp/build/ 2>/dev/null | head -10

    if [[ -d "/app/whisper.cpp/build/bin" ]]; then
      echo ""
      echo "📁 Build/bin directory:"
      ls -la /app/whisper.cpp/build/bin/ 2>/dev/null
    fi
  else
    echo "❌ No build directory found"
  fi

  echo ""
  echo "📁 Examples directory:"
  if [[ -d "/app/whisper.cpp/examples" ]]; then
    echo "✅ Examples directory exists"
    ls -la /app/whisper.cpp/examples/ 2>/dev/null | head -10
  else
    echo "❌ No examples directory found"
  fi

  echo ""
  echo "🎯 Models directory:"
  if [[ -d "/app/whisper.cpp/models" ]]; then
    echo "✅ Models directory exists"
    ls -la /app/whisper.cpp/models/ 2>/dev/null
  else
    echo "❌ No models directory found"
  fi

else
  echo "❌ /app/whisper.cpp directory not found"
fi

echo ""
echo "🔧 System Info:"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Architecture: $(uname -m)"
echo "Available cores: $(nproc)"
echo "Memory: $(free -h | grep Mem)"

echo ""
echo "📦 Installed packages:"
dpkg -l | grep -E "(ffmpeg|cmake|build)" | awk '{print $2 " " $3}'

echo ""
echo "🎵 FFmpeg info:"
ffmpeg -version 2>/dev/null | head -1 || echo "FFmpeg not found"

echo ""
echo "=== End Debug Info ==="
