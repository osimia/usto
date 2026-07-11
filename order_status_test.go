package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func doPatch(t *testing.T, handler http.Handler, path, token, body string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPatch, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// TestOrderStatusRequiresSelectedMasterToComplete confirms an order can't be
// marked completed until a master has been selected, but can always be
// cancelled (short of already being in a final state).
func TestOrderStatusRequiresSelectedMasterToComplete(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()
	_, token := bearerTokenFor(t, app, "+992900112233", "customer") // demo customer, owns order 1

	if code, body := doPatch(t, handler, "/api/orders/1/status", token, `{"status":"completed"}`); code != http.StatusBadRequest {
		t.Fatalf("expected 400 completing an order with no selected master, got %d: %s", code, body)
	}

	if code, body := doPatch(t, handler, "/api/orders/1/status", token, `{"status":"cancelled"}`); code != http.StatusOK {
		t.Fatalf("expected cancel to succeed, got %d: %s", code, body)
	}

	if code, body := doPatch(t, handler, "/api/orders/1/status", token, `{"status":"cancelled"}`); code != http.StatusBadRequest {
		t.Fatalf("expected re-cancelling an already-final order to fail, got %d: %s", code, body)
	}
}

// TestOrderStatusRejectsNonOwner confirms only the order's own customer can
// change its status.
func TestOrderStatusRejectsNonOwner(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()
	_, otherToken := bearerTokenFor(t, app, "+992911222333", "customer") // not order 1's owner

	code, body := doPatch(t, handler, "/api/orders/1/status", otherToken, `{"status":"cancelled"}`)
	if code != http.StatusForbidden {
		t.Fatalf("expected 403 for a non-owning customer, got %d: %s", code, body)
	}
}
