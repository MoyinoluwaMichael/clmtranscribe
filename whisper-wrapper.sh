#!/bin/bash

INPUT_FILE=$1
OUTPUT_FILE="${INPUT_FILE%.*}.txt"

./whisper.cpp/build/bin/whisper-cli -m ./whisper.cpp/models/ggml-medium.en.bin -f "$INPUT_FILE" -otxt
