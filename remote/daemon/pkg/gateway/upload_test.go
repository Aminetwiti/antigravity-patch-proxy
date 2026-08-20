package gateway

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/antigravity/remote-daemon/pkg/connectrpc"
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

type mediaCapturingRPCClient struct {
	fakeRPCClient
	lastMedia   []connectrpc.MediaAttachment
	lastPrompt  string
	lastModel   string
}

func (m *mediaCapturingRPCClient) SendMessageStreamModelWithMedia(cascadeID, text, modelUID string, modelEnum uint64, media []connectrpc.MediaAttachment, onFrame func([]byte) error, noTools ...bool) error {
	m.lastPrompt = text
	m.lastMedia = media
	m.lastModel = modelUID
	return onFrame(pbTextFrame("delta-response"))
}

func TestSendPrompt_MediaAttachmentsAndCleanPrompt(t *testing.T) {
	backend := &mediaCapturingRPCClient{}
	srv := newTestServer(backend)
	defer srv.Close()

	client := dialWS(t, "ws"+strings.TrimPrefix(srv.URL, "http")+"/ws")
	defer client.conn.Close()

	// 1. Envoi d'un prompt avec pièces jointes structurées media
	client.sendJSON(t, IncomingMessage{
		Type:      "send_prompt",
		RequestID: "req-media-1",
		CascadeID: "casc-1",
		Prompt:    "analyser cette image",
		Media: []connectrpc.MediaAttachment{
			{
				URI:         "file:///C:/test/path/photo.png",
				MimeType:    "image/png",
				Description: "photo.png",
			},
		},
	})
	_ = client.recv(t) // stream_start
	_ = client.recv(t) // stream_delta
	_ = client.recv(t) // stream_end

	if backend.lastPrompt != "analyser cette image" {
		t.Errorf("expected clean prompt 'analyser cette image', got %q", backend.lastPrompt)
	}
	if len(backend.lastMedia) != 1 {
		t.Fatalf("expected 1 media attachment, got %d", len(backend.lastMedia))
	}
	if backend.lastMedia[0].URI != "file:///C:/test/path/photo.png" {
		t.Errorf("expected URI 'file:///C:/test/path/photo.png', got %q", backend.lastMedia[0].URI)
	}

	// 2. Envoi d'un prompt avec markdown tag legacy ![name](file:///...) -> doit être extrait et nettoyé
	client.sendJSON(t, IncomingMessage{
		Type:      "send_prompt",
		RequestID: "req-media-2",
		CascadeID: "casc-1",
		Prompt:    "![screenshot.jpg](file:///C:/Users/test/screenshot.jpg)\n\nvoici mon texte",
	})
	_ = client.recv(t) // stream_start
	_ = client.recv(t) // stream_delta
	_ = client.recv(t) // stream_end

	if backend.lastPrompt != "voici mon texte" {
		t.Errorf("expected cleaned prompt 'voici mon texte', got %q", backend.lastPrompt)
	}
	if len(backend.lastMedia) != 1 {
		t.Fatalf("expected 1 extracted media attachment from markdown, got %d", len(backend.lastMedia))
	}
	if backend.lastMedia[0].URI != "file:///C:/Users/test/screenshot.jpg" {
		t.Errorf("expected URI 'file:///C:/Users/test/screenshot.jpg', got %q", backend.lastMedia[0].URI)
	}
}



