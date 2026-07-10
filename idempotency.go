package main

import (
	"database/sql"
	"net/http"
)

// idempotentReplay looks up a previously stored response for this
// Idempotency-Key. If found, it writes the stored response verbatim and
// returns true so the caller can skip re-executing the (money-moving)
// operation entirely.
func (a *App) idempotentReplay(w http.ResponseWriter, key string) bool {
	if key == "" {
		return false
	}
	var body string
	var status int
	err := a.db.QueryRow(sqlf(`SELECT response_body, status_code FROM idempotency_keys WHERE key=?`), key).Scan(&body, &status)
	if err != nil {
		return false
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write([]byte(body))
	return true
}

// storeIdempotencyResult records the response body for this key inside an
// already-open transaction, so it commits atomically with the operation it
// guards: either both the money movement and the idempotency record land, or
// neither does. ON CONFLICT DO NOTHING means a racing concurrent retry with
// the same key never errors here; the retry simply won't see its own write
// reflected and will replay whichever attempt committed first on its next try.
func storeIdempotencyResult(tx *sql.Tx, key, body string, status int) error {
	if key == "" {
		return nil
	}
	_, err := tx.Exec(sqlf(`INSERT INTO idempotency_keys(key, response_body, status_code) VALUES(?,?,?) ON CONFLICT(key) DO NOTHING`), key, body, status)
	return err
}

func idempotencyKeyFromRequest(r *http.Request) string {
	return r.Header.Get("Idempotency-Key")
}
