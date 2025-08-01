package com.clm.clmtranscribe;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;

@RestController
@RequestMapping("/api/transcribe")
public class TranscriptionController {

    @PostMapping
    public ResponseEntity<String> transcribeAudio(@RequestParam("file") MultipartFile file) throws IOException, InterruptedException {
        // Save the uploaded file to a temp file
        File tempFile = File.createTempFile("audio-", ".mp3");
        file.transferTo(tempFile);

        // Command to call whisper.cpp or a wrapper shell script
        String[] command = {
                "bash",
                "-c",
                "./whisper-wrapper.sh " + tempFile.getAbsolutePath()
        };

        Process process = Runtime.getRuntime().exec(command);
        process.waitFor();

        // Read the output from the generated .txt file
        File transcript = new File(tempFile.getAbsolutePath().replace(".mp3", ".txt"));
        String result = Files.readString(transcript.toPath());

        return ResponseEntity.ok(result);
    }
}
