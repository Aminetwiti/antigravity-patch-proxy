package gateway

import (
	"encoding/base64"
	"os"
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
	// Path traversal : un cascadeId non-UUID (ex. ../../x) doit être rejeté.
	if _, _, err := saveUploadedImage("../../evil", "test.png", "abc"); err == nil {
		t.Fatal("expected error on non-UUID cascadeId (path traversal)")
	}
}
