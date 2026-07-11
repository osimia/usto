package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func doLogin(t *testing.T, handler http.Handler, body string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	var decoded map[string]any
	if rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
			t.Fatalf("decode login response: %v (body=%s)", err, rec.Body.String())
		}
	}
	return rec.Code, decoded
}

// TestLoginNewPhoneRequiresRegistrationDetails confirms a brand-new phone
// number logging in without a name gets asked for registration details, and
// that no account is created yet at this point.
func TestLoginNewPhoneRequiresRegistrationDetails(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	code, body := doLogin(t, handler, `{"phone":"+992911000001","role":"customer"}`)
	if code != http.StatusOK {
		t.Fatalf("status = %d, body = %v", code, body)
	}
	if body["registrationRequired"] != true {
		t.Fatalf("expected registrationRequired=true, got %v", body)
	}
	if body["accessToken"] != nil {
		t.Fatalf("expected no accessToken before registration, got %v", body)
	}

	if _, err := app.userByPhoneRole(normalizePhone("+992911000001"), "customer"); err == nil {
		t.Fatalf("expected no user to be created before registration details were provided")
	}
}

// TestLoginCreatesAccountWithProvidedDetails confirms that supplying
// name/city/district on the same phone+role completes registration, and that
// those exact fields land on the new profile (not blank, not the demo
// profile's values).
func TestLoginCreatesAccountWithProvidedDetails(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	code, body := doLogin(t, handler, `{"phone":"+992911000002","role":"master","name":"Шер Назаров","city":"Душанбе","district":"Фирдавси"}`)
	if code != http.StatusOK {
		t.Fatalf("status = %d, body = %v", code, body)
	}
	if body["registrationRequired"] == true {
		t.Fatalf("expected registration to complete, got registrationRequired=true")
	}
	token, _ := body["accessToken"].(string)
	if token == "" {
		t.Fatalf("expected an accessToken, got %v", body)
	}

	user, err := app.userByPhoneRole(normalizePhone("+992911000002"), "master")
	if err != nil {
		t.Fatalf("expected user to exist after registration: %v", err)
	}
	profile, err := app.profileByID(user.ProfileID)
	if err != nil {
		t.Fatalf("profileByID: %v", err)
	}
	if profile.Name != "Шер Назаров" || profile.City != "Душанбе" || profile.District != "Фирдавси" {
		t.Fatalf("profile fields not saved correctly: %+v", profile)
	}

	if _, ok := app.masterIDForProfile(profile.ID); !ok {
		t.Fatalf("expected a masters directory entry to be auto-created for the new master")
	}
}

// TestLoginExistingAccountLogsInDirectly confirms that a second login for
// the same (phone, role) — after registration — succeeds immediately with no
// registrationRequired step and without needing name/city/district again.
func TestLoginExistingAccountLogsInDirectly(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	first := `{"phone":"+992911000003","role":"customer","name":"Дилноза К.","city":"Душанбе","district":"Сино"}`
	if code, body := doLogin(t, handler, first); code != http.StatusOK || body["registrationRequired"] == true {
		t.Fatalf("initial registration failed: status=%d body=%v", code, body)
	}

	code, body := doLogin(t, handler, `{"phone":"+992911000003","role":"customer"}`)
	if code != http.StatusOK {
		t.Fatalf("status = %d, body = %v", code, body)
	}
	if body["registrationRequired"] == true {
		t.Fatalf("expected direct login for an existing account, got registrationRequired=true")
	}
	if body["accessToken"] == nil {
		t.Fatalf("expected an accessToken on direct login, got %v", body)
	}
}
