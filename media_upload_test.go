package main

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestOrderPhotoUploadStoresAndReturnsMediaURLs(t *testing.T) {
	app := newTestApp(t)
	app.cfg.MediaDir = t.TempDir()
	handler := app.routes()
	_, token := bearerTokenFor(t, app, "+992900112233", "customer")

	code, body := uploadOrderPhoto(t, handler, "/api/orders/1/photos", token, testJPEG(t))
	if code != http.StatusOK {
		t.Fatalf("expected upload to succeed, got %d: %s", code, body)
	}
	var decoded map[string]any
	if err := json.Unmarshal([]byte(body), &decoded); err != nil {
		t.Fatalf("decode upload response: %v", err)
	}
	photo := decoded["photo"].(map[string]any)
	for _, key := range []string{"thumbUrl", "mediumUrl", "fullUrl"} {
		url, _ := photo[key].(string)
		if !strings.HasPrefix(url, "/media/") {
			t.Fatalf("%s should be a /media URL, got %q", key, url)
		}
		diskPath := filepath.Join(app.cfg.MediaDir, filepath.FromSlash(strings.TrimPrefix(url, "/media/")))
		if info, err := os.Stat(diskPath); err != nil || info.IsDir() {
			t.Fatalf("%s file was not written at %s: %v", key, diskPath, err)
		}
	}
	order := decoded["order"].(map[string]any)
	photos := order["photos"].([]any)
	if len(photos) != 1 {
		t.Fatalf("expected updated order to include one photo, got %v", photos)
	}
}

func TestOrderPhotoUploadRejectsNonOwner(t *testing.T) {
	app := newTestApp(t)
	app.cfg.MediaDir = t.TempDir()
	handler := app.routes()
	_, token := bearerTokenFor(t, app, "+992911222333", "customer")

	code, body := uploadOrderPhoto(t, handler, "/api/orders/1/photos", token, testJPEG(t))
	if code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-owner upload, got %d: %s", code, body)
	}
}

func uploadOrderPhoto(t *testing.T, handler http.Handler, path, token string, file []byte) (int, string) {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", "photo.jpg")
	if err != nil {
		t.Fatalf("CreateFormFile: %v", err)
	}
	if _, err := part.Write(file); err != nil {
		t.Fatalf("write multipart file: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, path, &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

func testJPEG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 24, 18))
	for y := 0; y < 18; y++ {
		for x := 0; x < 24; x++ {
			img.Set(x, y, color.RGBA{R: uint8(40 + x), G: uint8(80 + y), B: 180, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80}); err != nil {
		t.Fatalf("jpeg encode: %v", err)
	}
	return buf.Bytes()
}
