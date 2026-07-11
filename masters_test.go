package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
)

func doGet(t *testing.T, handler http.Handler, path, token string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	var decoded map[string]any
	if rec.Body.Len() > 0 {
		_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	}
	return rec.Code, decoded
}

// TestMasterListingSelfEditRoundTrips confirms a master can fetch and update
// their own directory listing, and that skills/portfolio survive a
// trim-and-clean round trip (joinList/splitList).
func TestMasterListingSelfEditRoundTrips(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()
	_, token := bearerTokenFor(t, app, "+992937770001", "master")

	code, body := doGet(t, handler, "/api/masters/me", token)
	if code != http.StatusOK {
		t.Fatalf("GET /masters/me status = %d, body = %v", code, body)
	}
	master := body["master"].(map[string]any)
	if master["name"] != "" {
		t.Fatalf("expected a brand-new master to have a blank listing, got name=%v", master["name"])
	}

	patchBody := `{"name":"Шер Назаров","service":"Сантехника","bio":"  Опыт 5 лет  ","skills":["краны", " бойлеры ", "", "трубы"],"portfolio":["фото1", ""]}`
	req := httptest.NewRequest(http.MethodPatch, "/api/masters/me", strings.NewReader(patchBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH /masters/me status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var patched map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &patched); err != nil {
		t.Fatalf("decode patch response: %v", err)
	}
	updated := patched["master"].(map[string]any)
	if updated["name"] != "Шер Назаров" || updated["bio"] != "Опыт 5 лет" {
		t.Fatalf("name/bio not saved correctly: %+v", updated)
	}
	skills := updated["skills"].([]any)
	if len(skills) != 3 || skills[0] != "краны" || skills[1] != "бойлеры" || skills[2] != "трубы" {
		t.Fatalf("expected cleaned skills [краны бойлеры трубы], got %v", skills)
	}
	portfolio := updated["portfolio"].([]any)
	if len(portfolio) != 1 || portfolio[0] != "фото1" {
		t.Fatalf("expected cleaned portfolio [фото1], got %v", portfolio)
	}
}

// TestMasterListingRejectsCustomer confirms a customer role can't access the
// master-only listing endpoint.
func TestMasterListingRejectsCustomer(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()
	_, token := bearerTokenFor(t, app, "+992937770002", "customer")

	code, body := doGet(t, handler, "/api/masters/me", token)
	if code != http.StatusForbidden {
		t.Fatalf("expected 403 for customer role, got %d: %v", code, body)
	}
}

// TestMasterVerifiedFlagReflectsProfileVerification confirms the public
// masters listing shows the real, live verification status (from
// profiles.is_verified via verification.go) for a master linked to a real
// account, not just the static seed value.
func TestMasterVerifiedFlagReflectsProfileVerification(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()
	user, token := bearerTokenFor(t, app, "+992937770003", "master")

	masterID, ok := app.masterIDForProfile(user.ProfileID)
	if !ok {
		t.Fatalf("expected a directory entry to exist for the new master")
	}

	code, body := doGet(t, handler, "/api/masters/"+strconv.Itoa(masterID), "")
	if code != http.StatusOK {
		t.Fatalf("GET /masters/{id} status = %d: %v", code, body)
	}
	if body["master"].(map[string]any)["verified"] != false {
		t.Fatalf("expected unverified master to show verified=false, got %v", body)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/verification", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /verification status = %d: %s", rec.Code, rec.Body.String())
	}

	code, body = doGet(t, handler, "/api/masters/"+strconv.Itoa(masterID), "")
	if code != http.StatusOK {
		t.Fatalf("GET /masters/{id} status = %d: %v", code, body)
	}
	if body["master"].(map[string]any)["verified"] != true {
		t.Fatalf("expected verified=true after verification, got %v", body)
	}
}
