package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func newTestApp(t *testing.T) *App {
	t.Helper()
	cfg := Config{
		DBDriver:          "sqlite",
		DBPath:            filepath.Join(t.TempDir(), "usto_test.db"),
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

// bearerTokenFor logs in as (phone, role) — creating a brand-new per-user
// profile via loginOrRegister (with placeholder demo details) if this phone
// hasn't been seen before, exactly as the real /auth/login handler does for
// a first-time number — and returns a valid access token plus the resulting
// user.
func bearerTokenFor(t *testing.T, app *App, phone, role string) (User, string) {
	t.Helper()
	user, registrationRequired, err := app.loginOrRegister(phone, normalizePhone(phone), role, "Тестовый пользователь", "Душанбе", "Сино")
	if err != nil {
		t.Fatalf("loginOrRegister(%s,%s): %v", phone, role, err)
	}
	if registrationRequired {
		t.Fatalf("loginOrRegister(%s,%s): unexpectedly required registration despite name being set", phone, role)
	}
	token, err := app.signToken(user, "access", time.Hour)
	if err != nil {
		t.Fatalf("signToken: %v", err)
	}
	return user, token
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

	demoMaster, err := app.profile("master")
	if err != nil {
		t.Fatalf("profile(master): %v", err)
	}
	masterID, ok := app.masterIDForProfile(demoMaster.ID)
	if !ok {
		t.Fatalf("demo master has no linked masters directory entry")
	}
	if _, err := app.db.Exec(sqlf(`UPDATE profiles SET wallet_balance = ? WHERE id=?`), startingBalance, demoMaster.ID); err != nil {
		t.Fatalf("seed balance: %v", err)
	}

	var wg sync.WaitGroup
	results := make([]error, attempts)
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			req := CreateResponseRequest{OrderID: 1, Price: 100 + i, Comment: "test response"}
			_, _, err := app.createResponse(req, "", masterID, demoMaster.ID)
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
	if err := app.db.QueryRow(sqlf(`SELECT wallet_balance FROM profiles WHERE id=?`), demoMaster.ID).Scan(&balance); err != nil {
		t.Fatalf("read balance: %v", err)
	}
	if balance != 0 {
		t.Fatalf("expected balance to be drained to exactly 0, got %d", balance)
	}
}

// TestSecondMasterIsIndependentFromDemoMaster is the core multitenancy
// regression: a brand-new master account (not the seeded demo master) must
// get its own profile, its own masters-directory entry, its own wallet, and
// its own responses — none of which may touch or be attributed to the demo
// master. Before the per-user-profile fix, every new master shared the demo
// master's single profile row.
func TestSecondMasterIsIndependentFromDemoMaster(t *testing.T) {
	app := newTestApp(t)

	demoMaster, err := app.profile("master")
	if err != nil {
		t.Fatalf("profile(master): %v", err)
	}

	newUser, _ := bearerTokenFor(t, app, "+992937001122", "master")
	if newUser.ProfileID == demoMaster.ID {
		t.Fatalf("new master was assigned the demo master's profile ID %d", demoMaster.ID)
	}

	newMasterID, ok := app.masterIDForProfile(newUser.ProfileID)
	if !ok {
		t.Fatalf("new master has no linked masters directory entry")
	}
	demoMasterID, ok := app.masterIDForProfile(demoMaster.ID)
	if !ok {
		t.Fatalf("demo master has no linked masters directory entry")
	}
	if newMasterID == demoMasterID {
		t.Fatalf("new master reused the demo master's directory entry %d", demoMasterID)
	}

	// Fund the new master's wallet independently and confirm a response
	// debits *their* balance, not the demo master's.
	if _, err := app.db.Exec(sqlf(`UPDATE profiles SET wallet_balance = ? WHERE id=?`), 20, newUser.ProfileID); err != nil {
		t.Fatalf("seed new master balance: %v", err)
	}
	demoMasterBefore, err := app.wallet(demoMaster.ID)
	if err != nil {
		t.Fatalf("wallet(demoMaster): %v", err)
	}

	req := CreateResponseRequest{OrderID: 1, Price: 150, Comment: "second master response"}
	response, _, err := app.createResponse(req, "", newMasterID, newUser.ProfileID)
	if err != nil {
		t.Fatalf("createResponse for second master: %v", err)
	}
	if response.MasterID != newMasterID {
		t.Fatalf("response attributed to master %d, want %d", response.MasterID, newMasterID)
	}

	newMasterWallet, err := app.wallet(newUser.ProfileID)
	if err != nil {
		t.Fatalf("wallet(newMaster): %v", err)
	}
	if newMasterWallet.Balance != 20-responseFeeTJS {
		t.Fatalf("new master balance = %d, want %d", newMasterWallet.Balance, 20-responseFeeTJS)
	}

	demoMasterAfter, err := app.wallet(demoMaster.ID)
	if err != nil {
		t.Fatalf("wallet(demoMaster) after: %v", err)
	}
	if demoMasterAfter.Balance != demoMasterBefore.Balance {
		t.Fatalf("demo master balance changed from %d to %d after a different master's response",
			demoMasterBefore.Balance, demoMasterAfter.Balance)
	}
}

// TestTopUpIdempotencyKeyPreventsDoubleCredit drives the real HTTP handler
// (not the topUp function directly) twice with the same Idempotency-Key,
// simulating a client retry after a dropped response. The second call must
// replay the first response verbatim and must not credit the wallet again.
func TestTopUpIdempotencyKeyPreventsDoubleCredit(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	demoMaster, err := app.profile("master")
	if err != nil {
		t.Fatalf("profile(master): %v", err)
	}
	_, token := bearerTokenFor(t, app, demoMaster.Phone, "master")

	before, err := app.wallet(demoMaster.ID)
	if err != nil {
		t.Fatalf("wallet: %v", err)
	}

	doTopUp := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/wallet/topup?wrap=1", strings.NewReader(`{"amount":50}`))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
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

	after, err := app.wallet(demoMaster.ID)
	if err != nil {
		t.Fatalf("wallet: %v", err)
	}
	if after.Balance != before.Balance+50 {
		t.Fatalf("expected balance to increase by exactly 50 once, before=%d after=%d", before.Balance, after.Balance)
	}
}

// TestTopUpRequiresAuth confirms the wallet-topup endpoint now rejects
// unauthenticated calls instead of silently crediting the shared demo wallet.
func TestTopUpRequiresAuth(t *testing.T) {
	app := newTestApp(t)
	handler := app.routes()

	req := httptest.NewRequest(http.MethodPost, "/api/wallet/topup", strings.NewReader(`{"amount":50}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated topup, got %d: %s", rec.Code, rec.Body.String())
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
}
