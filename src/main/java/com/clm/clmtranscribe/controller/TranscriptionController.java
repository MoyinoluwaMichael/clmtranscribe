package com.clm.clmtranscribe.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/transcribe")
public class TranscriptionController {

    @Value("${transcription.whisper-wrapper:/app/whisper-wrapper.sh}")
    private String whisperWrapper;

    private final String uploadDir = "/app/uploads";

    @PostMapping
    public ResponseEntity<?> transcribe(@RequestParam("file") MultipartFile file) {
        File audioFile = null;

        try {
            // Validate file
            if (file.isEmpty()) {
                return ResponseEntity.badRequest().body("No file provided");
            }

            // Check file size (limit to 25MB)
            if (file.getSize() > 25 * 1024 * 1024) {
                return ResponseEntity.badRequest().body("File size exceeds 25MB limit");
            }

            // Validate file type
            String contentType = file.getContentType();
            if (contentType == null || !isValidAudioType(contentType)) {
                return ResponseEntity.badRequest()
                        .body("Invalid file type. Supported formats: MP3, WAV, M4A, FLAC, OGG");
            }

            // Ensure upload directory exists
            Path uploadPath = Paths.get(uploadDir);
            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }

            // Generate unique filename
            String originalFilename = file.getOriginalFilename();
            String extension = getFileExtension(originalFilename);
            String uniqueId = UUID.randomUUID().toString();
            audioFile = new File(uploadPath.toFile(), "audio-" + uniqueId + extension);

            // Save uploaded file
            file.transferTo(audioFile);
            System.out.println("Saved audio file to: " + audioFile.getAbsolutePath());

            // Run transcription using wrapper script
            ProcessBuilder pb = new ProcessBuilder(whisperWrapper, audioFile.getAbsolutePath());
            pb.directory(new File("/app"));
            pb.redirectErrorStream(true);

            Process process = pb.start();

            // Capture process output with timeout
            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    System.out.println(line);
                    output.append(line).append("\n");
                }
            }

            // Wait for process with timeout (5 minutes max)
            boolean finished = process.waitFor(5, TimeUnit.MINUTES);
            if (!finished) {
                process.destroyForcibly();
                return ResponseEntity.status(HttpStatus.REQUEST_TIMEOUT)
                        .body("Transcription timed out after 5 minutes");
            }

            int exitCode = process.exitValue();
            if (exitCode != 0) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body("Transcription failed with exit code " + exitCode + ": " + output.toString());
            }

            // Read transcript from expected location
            String baseName = audioFile.getName().substring(0, audioFile.getName().lastIndexOf('.'));
            File transcriptFile = new File("/tmp", baseName + ".txt");

            if (!transcriptFile.exists()) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                        .body("Transcription completed but output file not found: " + transcriptFile.getAbsolutePath());
            }

            // Read transcript content
            String transcript = Files.readString(transcriptFile.toPath()).trim();

            // Clean up transcript file
            transcriptFile.delete();

            if (transcript.isEmpty()) {
                transcript = "No speech detected in the audio file.";
            }

            return ResponseEntity.ok(Map.of(
                    "transcript", transcript,
                    "filename", originalFilename,
                    "fileSize", file.getSize(),
                    "duration", "Unknown" // Could be enhanced to detect duration
            ));

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Transcription was interrupted");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Transcription failed: " + e.getMessage());
        } finally {
            // Clean up uploaded file
            if (audioFile != null && audioFile.exists()) {
                try {
                    audioFile.delete();
                } catch (Exception e) {
                    System.err.println("Failed to delete temporary file: " + audioFile.getAbsolutePath());
                }
            }
        }
    }

    @GetMapping("/health")
    public ResponseEntity<?> health() {
        try {
            // Check if whisper wrapper exists and is executable
            File wrapper = new File(whisperWrapper);
            if (!wrapper.exists() || !wrapper.canExecute()) {
                return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                        .body("Whisper wrapper not available");
            }

            // Check upload directory
            Path uploadPath = Paths.get(uploadDir);
            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }

            return ResponseEntity.ok(Map.of(
                    "status", "healthy",
                    "whisperWrapper", whisperWrapper,
                    "uploadDir", uploadDir,
                    "timestamp", System.currentTimeMillis()
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body("Health check failed: " + e.getMessage());
        }
    }

    @GetMapping("/formats")
    public ResponseEntity<?> getSupportedFormats() {
        return ResponseEntity.ok(Map.of(
                "supportedFormats", new String[]{"mp3", "wav", "m4a", "flac", "ogg", "mp4", "avi", "mov"},
                "maxFileSizeMB", 25,
                "maxDurationMinutes", "No limit (but 5min processing timeout)"
        ));
    }

    private boolean isValidAudioType(String contentType) {
        return contentType.startsWith("audio/") ||
                contentType.equals("video/mp4") ||
                contentType.equals("video/quicktime") ||
                contentType.equals("video/x-msvideo");
    }

    private String getFileExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return ".mp3"; // default extension
        }
        return filename.substring(filename.lastIndexOf(".")).toLowerCase();
    }
}
