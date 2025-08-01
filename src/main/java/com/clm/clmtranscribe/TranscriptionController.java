package com.clm.clmtranscribe;

import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.nio.file.Files;

@RestController
@RequestMapping("/api/transcribe")
public class TranscriptionController {

    @PostMapping
    public ResponseEntity<Resource> transcribeAudio(@RequestParam("file") MultipartFile file) {
        File tempFile = null;
        File transcriptFile = null;

        try {
            // Basic validation
            if (file.getSize() > 100 * 1024 * 1024) {
                throw new IllegalArgumentException("File is too large. Limit is 100MB.");
            }
            if (!file.getContentType().startsWith("audio")) {
                throw new IllegalArgumentException("Only audio files are allowed.");
            }

            // Save the uploaded file to a temporary file
            tempFile = File.createTempFile("audio-", ".mp3");
            file.transferTo(tempFile);

            // Define transcript output path
            String baseName = tempFile.getName().replaceAll("\\.mp3$", "");
            transcriptFile = new File("/tmp/" + baseName + ".txt");

            // Build and run the whisper command
            String[] command = {
                    "/bin/bash",
                    new File("whisper-wrapper.sh").getAbsolutePath(),
                    tempFile.getAbsolutePath()
            };

            Process process = Runtime.getRuntime().exec(command);
            String stdout = new String(process.getInputStream().readAllBytes());
            String stderr = new String(process.getErrorStream().readAllBytes());

            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException("Whisper failed.\nSTDOUT: " + stdout + "\nSTDERR: " + stderr);
            }

            // Check that output file exists
            if (!transcriptFile.exists()) {
                throw new RuntimeException("Transcript file was not created: " + transcriptFile.getAbsolutePath());
            }

            // Read the transcript content into memory
            byte[] transcriptContent = Files.readAllBytes(transcriptFile.toPath());

            // Clean up the transcript file immediately after reading
            transcriptFile.delete();

            // Create a ByteArrayResource with the content
            Resource resource = new ByteArrayResource(transcriptContent);

            String originalFileName = file.getOriginalFilename();
            String baseFileName = originalFileName != null
                    ? originalFileName.replaceFirst("[.][^.]+$", "")
                    : "transcript";

            return ResponseEntity.ok()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(resource);

        } catch (Exception e) {
            return ResponseEntity.internalServerError()
                    .contentType(MediaType.TEXT_PLAIN)
                    .body(new ByteArrayResource(("Transcription failed.\n\n" + e.getMessage()).getBytes()));
        } finally {
            // Always delete the temporary input file
            if (tempFile != null && tempFile.exists()) {
                tempFile.delete();
            }
            // Note: transcriptFile is already deleted after reading
        }
    }
}
