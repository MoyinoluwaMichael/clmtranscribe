package com.clm.clmtranscribe;

import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/transcribe")
public class TranscriptionController {

    private static final long MAX_FILE_SIZE = 25 * 1024 * 1024; // Reduced to 25MB
    private static final int TIMEOUT_MINUTES = 5;

    @PostMapping
    public ResponseEntity<Resource> transcribeAudio(@RequestParam("file") MultipartFile file) {
        File tempFile = null;
        File transcriptFile = null;
        Process process = null;

        try {
            // Strict validation
            if (file.getSize() > MAX_FILE_SIZE) {
                throw new IllegalArgumentException("File too large. Maximum size is 25MB.");
            }
            if (file.isEmpty()) {
                throw new IllegalArgumentException("File is empty.");
            }
            if (!isAudioFile(file.getContentType())) {
                throw new IllegalArgumentException("Only audio files are supported.");
            }

            // Create temporary file with proper extension
            String originalName = file.getOriginalFilename();
            String extension = getFileExtension(originalName);
            tempFile = File.createTempFile("audio-", extension);

            // Stream file to disk to avoid loading entire file in memory
            try (InputStream inputStream = file.getInputStream();
                 FileOutputStream outputStream = new FileOutputStream(tempFile)) {
                inputStream.transferTo(outputStream);
            }

            // Define output file
            String baseName = tempFile.getName().replaceAll("\\.[^.]+$", "");
            transcriptFile = new File("/tmp/" + baseName + ".txt");

            // Execute whisper with proper process management
            ProcessBuilder pb = new ProcessBuilder(
                    "/bin/bash",
                    "/app/whisper-wrapper.sh",
                    tempFile.getAbsolutePath()
            );

            // Set working directory and environment
            pb.directory(new File("/app"));
            pb.environment().put("TMPDIR", "/tmp");

            process = pb.start();

            // Handle process streams to prevent hanging
            StreamGobbler outputGobbler = new StreamGobbler(process.getInputStream());
            StreamGobbler errorGobbler = new StreamGobbler(process.getErrorStream());

            outputGobbler.start();
            errorGobbler.start();

            // Wait with timeout
            boolean finished = process.waitFor(TIMEOUT_MINUTES, TimeUnit.MINUTES);

            if (!finished) {
                process.destroyForcibly();
                throw new RuntimeException("Transcription timed out after " + TIMEOUT_MINUTES + " minutes");
            }

            int exitCode = process.exitValue();
            if (exitCode != 0) {
                String errorOutput = errorGobbler.getOutput();
                throw new RuntimeException("Whisper failed with exit code " + exitCode + ": " + errorOutput);
            }

            // Verify output exists
            if (!transcriptFile.exists() || transcriptFile.length() == 0) {
                throw new RuntimeException("Transcript file was not created or is empty");
            }

            // Read transcript efficiently
            byte[] transcriptContent;
            try {
                transcriptContent = Files.readAllBytes(transcriptFile.toPath());
            } catch (OutOfMemoryError e) {
                throw new RuntimeException("Transcript file too large to process");
            }

            // Create response
            String baseFileName = originalName != null
                    ? originalName.replaceFirst("\\.[^.]+$", "")
                    : "transcript";

            return ResponseEntity.ok()
                    .contentType(MediaType.TEXT_PLAIN)
                    .header("Content-Disposition",
                            "attachment; filename=\"" + baseFileName + "_transcript.txt\"")
                    .body(new ByteArrayResource(transcriptContent));

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Transcription was interrupted", e);
        } catch (Exception e) {
            return ResponseEntity.badRequest()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(new ByteArrayResource(
                            ("Transcription failed: " + e.getMessage()).getBytes()));
        } finally {
            // Cleanup resources
            cleanup(tempFile, transcriptFile, process);

            // Suggest garbage collection
            System.gc();
        }
    }

    private boolean isAudioFile(String contentType) {
        return contentType != null && (
                contentType.startsWith("audio/") ||
                        contentType.equals("application/ogg") ||
                        contentType.equals("video/mp4") // Some audio files are detected as video/mp4
        );
    }

    private String getFileExtension(String filename) {
        if (filename == null) return ".mp3";
        int lastDot = filename.lastIndexOf('.');
        return lastDot > 0 ? filename.substring(lastDot) : ".mp3";
    }

    private void cleanup(File tempFile, File transcriptFile, Process process) {
        if (process != null && process.isAlive()) {
            process.destroyForcibly();
        }

        if (tempFile != null && tempFile.exists()) {
            tempFile.delete();
        }

        if (transcriptFile != null && transcriptFile.exists()) {
            transcriptFile.delete();
        }
    }

    // Helper class to handle process streams
    private static class StreamGobbler extends Thread {
        private final InputStream inputStream;
        private final StringBuilder output = new StringBuilder();

        StreamGobbler(InputStream inputStream) {
            this.inputStream = inputStream;
        }

        @Override
        public void run() {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
            } catch (IOException e) {
                // Log error but don't throw
                System.err.println("Error reading process output: " + e.getMessage());
            }
        }

        String getOutput() {
            return output.toString();
        }
    }
}
