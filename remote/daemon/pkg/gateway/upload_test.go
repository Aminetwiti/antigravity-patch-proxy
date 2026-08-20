package gateway

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSaveUploadedImage(t *testing.T) {
	dummyContent := "fake png image content for test"
	b64 := base64.StdEncoding.EncodeToString([]byte(dummyContent))
	cascadeID := testUUID()

	filePath, mdRef, err := saveUploadedImage(cascadeID, "screenshot.png", b64)
	if err != nil {
		t.Fatalf("unexpected error saving uploaded image: %v", err)
	}
	defer os.Remove(filePath)

	if !strings.HasPrefix(mdRef, "![Uploaded Image](file:///") {
		t.Fatalf("unexpected markdown reference format: %s", mdRef)
	}

	readBytes, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("failed to read written file: %v", err)
	}
	if string(readBytes) != dummyContent {
		t.Fatalf("expected content %q, got %q", dummyContent, string(readBytes))
	}
}

func TestSaveUploadedImage_DataUrlPrefix(t *testing.T) {
	dummyContent := "jpeg binary data"
	b64 := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString([]byte(dummyContent))
	cascadeID := testUUID()

	filePath, _, err := saveUploadedImage(cascadeID, "photo.jpg", b64)
	if err != nil {
		t.Fatalf("unexpected error saving uploaded image with data url: %v", err)
	}
	defer os.Remove(filePath)

	if !strings.HasSuffix(filePath, ".jpg") {
		t.Fatalf("expected .jpg extension, got %s", filePath)
	}
}

func TestSaveUploadedImage_Validation(t *testing.T) {
	if _, _, err := saveUploadedImage("", "test.png", "abc"); err == nil {
		t.Fatal("expected error on empty cascadeId")
	}
	if _, _, err := saveUploadedImage(testUUID(), "test.png", ""); err == nil {
		t.Fatal("expected error on empty base64Data")
	}
	// Path traversal : un cascadeId malveillant (ex. ../../evil, /etc, \windows) doit être rejeté.
	if _, _, err := saveUploadedImage("../../evil", "test.png", "abc"); err == nil {
		t.Fatal("expected error on path traversal cascadeId")
	}
	if _, _, err := saveUploadedImage("/etc/passwd", "test.png", "abc"); err == nil {
		t.Fatal("expected error on absolute path cascadeId")
	}

	// Safe session IDs (non-UUID mais sûrs, ex: cascade-12345, s3, casc-x) doivent être acceptés.
	b64 := base64.StdEncoding.EncodeToString([]byte("test content"))
	filePath, _, err := saveUploadedImage("cascade-1787194458484", "test.png", b64)
	if err != nil {
		t.Fatalf("expected safe session ID to be accepted: %v", err)
	}
	defer os.Remove(filePath)
}

func TestReadFile_UploadedImageLeadingSlash(t *testing.T) {
	dummyContent := "image binary payload"
	b64 := base64.StdEncoding.EncodeToString([]byte(dummyContent))
	cascadeID := "cascade-img-test"

	filePath, _, err := saveUploadedImage(cascadeID, "photo_1787194458484.jpg", b64)
	if err != nil {
		t.Fatalf("failed to save test image: %v", err)
	}
	defer os.Remove(filePath)

	bDir := findBrainDir(cascadeID)
	if bDir == "" {
		t.Skip("brain directory not available in test environment")
	}

	cleanPath := "/photo_1787194458484.jpg"
	relCleanPath := strings.TrimLeft(cleanPath, "/\\")
	baseFileName := "photo_1787194458484.jpg"

	candidates := []string{
		filePath,
		filepath.Join(bDir, relCleanPath),
		filepath.Join(bDir, ".user_uploaded", relCleanPath),
		filepath.Join(bDir, "scratch", relCleanPath),
		filepath.Join(bDir, ".user_uploaded", baseFileName),
		filepath.Join(bDir, "scratch", baseFileName),
	}

	found := false
	for _, cand := range candidates {
		if content, errRead := os.ReadFile(cand); errRead == nil {
			if string(content) == dummyContent {
				found = true
				break
			}
		}
	}
	if !found {
		t.Fatal("failed to find uploaded image using candidates with leading slash")
	}
}


