package main

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func newTestApp(t *testing.T) *App {
	t.Helper()
	cfg := Config{
		DBDriver:          "sqlite",
		DBPath:            filepath.Join(t.TempDir(), "usto_test.db"),
		DevSMSCode:        "1234",
		JWTSecret:         "test-secret",
		AccessTokenHours:  1,
		RefreshTokenHours: 1,
	}
	db, err := openDB(cfg)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return &App{db: db, cfg: cfg}
}

// TestCreateResponseConcurrentNeverGoesNegative fires many concurrent
// createResponse calls against a wallet with just enough balance for some of
// them to succeed. Before the transactional fix, the debit and insert were
// two separate unguarded statements and concurrent requests could overdraw
// the balance below zero; the guarded single-transaction UPDATE must make
// exactly floor(balance/fee) attempts succeed and leave the balance at
// exactly zero, never negative.
func TestCreateResponseConcurrentNeverGoesNegative(t *testing.T) {
	app := newTestApp(t)

	const startingBalance = 40
	const fee = responseFeeTJS // 4 TJS per response in the current demo pricing
	const attempts = 20        // more attempts than the balance can cover

	if _, err := app.db.Exec(sqlf(`UPDATE profiles SET wallet_balance = ? WHERE role='master'`), startingBalance); err != nil {
		t.Fatalf("seed balance: %v", err)
	}

	var wg sync.WaitGroup
	results := make([]error, attempts)
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			req := CreateResponseRequest{OrderID: 1, Price: 100 + i, Comment: "test response"}
			_, _, err := app.createResponse(req, "")
			results[i] = err
		}(i)
	}
	wg.Wait()

	successes := 0
	for _, err := range results {
		switch {
		case err == nil:
			successes++
		case errors.Is(err, errInsufficientFunds):
			// expected once the balance is drained
		default:
			t.Fatalf("unexpected error: %v", err)
		}
	}

	wantSuccesses := startingBalance / fee
	if successes != wantSuccesses {
		t.Fatalf("expected exactly %d successful responses, got %d", wantSuccesses, successes)
	}

	var balance int
	if err := app.db.QueryRow(`SELECT wallet_balance FROM profiles WHERE role='master'`).Scan(&balance); err != nil {
		t.Fatalf("read balance: %v", err)
	}
	if balance != 0 {
		t.Fatalf("expected balance to be drained to exactly 0, got %d", balance)
	}
}

// TestTopUpIdempotencyKeyPreventsDoubleCredit drives the real HTTP handler
// (not the topUp function directly) twice with the same Idempotency-Key,
// simulating a client retry after a dropped response. The second call must
// replay the first response verbatim and must not credit the wallet again.
func TestTopUpIdempotencyKeyPreventsDoubleCredit(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	before, err := app.wallet()
	if err != nil {
		t.Fatalf("wallet: %v", err)
	}

	doTopUp := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/wallet/topup?wrap=1", strings.NewReader(`{"amount":50}`))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Idempotency-Key", "topup-test-key-1")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		return rec
	}

	first := doTopUp()
	if first.Code != http.StatusOK {
		t.Fatalf("first topUp status = %d, body = %s", first.Code, first.Body.String())
	}
	second := doTopUp()
	if second.Code != http.StatusOK {
		t.Fatalf("second topUp status = %d, body = %s", second.Code, second.Body.String())
	}
	// writeJSON's Encoder appends a trailing newline that the raw
	// json.Marshal bytes stored for replay don't; that's not a meaningful
	// difference to a JSON client, so trim before comparing.
	if strings.TrimSpace(first.Body.String()) != strings.TrimSpace(second.Body.String()) {
		t.Fatalf("replayed response differs from original:\nfirst:  %s\nsecond: %s", first.Body.String(), second.Body.String())
	}

	after, err := app.wallet()
	if err != nil {
		t.Fatalf("wallet: %v", err)
	}
	if after.Balance != before.Balance+50 {
		t.Fatalf("expected balance to increase by exactly 50 once, before=%d after=%d", before.Balance, after.Balance)
	}
}
