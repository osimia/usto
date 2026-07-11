package main

import (
	"net/http"
	"time"
)

// authRateLimitedPaths are throttled per-IP to slow down account
// enumeration/brute-force attempts. This matters even more now that login
// has no SMS code step — the rate limit is the only friction against
// guessing phone numbers.
var authRateLimitedPaths = map[string]bool{
	"/api/auth/login": true,
}

func newHTTPServer(cfg Config, handler http.Handler) *http.Server {
	// Burst of 3 immediately, then refills at 1 request per 10s per IP.
	limiter := newIPRateLimiter(0.1, 3)

	chain := rateLimitMW(limiter, authRateLimitedPaths)(handler)
	chain = withCORS(chain)
	chain = logRequests(chain)
	chain = requestIDMW(chain)
	chain = recoverMW(chain)

	return &http.Server{
		Addr:              cfg.addr(),
		Handler:           chain,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", a.healthz)
	mux.HandleFunc("/api/health", a.healthz)
	mux.HandleFunc("/api/auth/login", a.login)
	mux.HandleFunc("/api/auth/refresh", a.refreshAuthToken)
	mux.HandleFunc("/api/auth/logout", a.logout)
	mux.HandleFunc("/api/me", a.me)
	mux.HandleFunc("/api/me/profile", a.me)
	mux.HandleFunc("/api/bootstrap", a.bootstrap)
	mux.HandleFunc("/api/categories", a.categoriesHandler)
	mux.HandleFunc("/api/categories/", a.categoryDetailHandler)
	mux.HandleFunc("/api/masters", a.mastersHandler)
	mux.HandleFunc("/api/masters/", a.masterDetailHandler)
	mux.HandleFunc("/api/orders", a.ordersHandler)
	mux.HandleFunc("/api/orders/", a.orderDetailHandler)
	mux.HandleFunc("/api/responses", a.responses)
	mux.HandleFunc("/api/chats", a.chatsHandler)
	mux.HandleFunc("/api/chats/", a.chatDetailHandler)
	mux.HandleFunc("/api/messages", a.messages)
	mux.HandleFunc("/api/wallet", a.walletHandler)
	mux.HandleFunc("/api/wallet/topup", a.topUpWallet)
	mux.HandleFunc("/api/wallet/transactions", a.walletTransactionsHandler)
	mux.HandleFunc("/api/verification", a.verifyMaster)
	mux.HandleFunc("/api/verification/status", a.verificationStatusHandler)
	mux.HandleFunc("/api/verification/documents", a.verificationDocumentsHandler)
	mux.HandleFunc("/", staticHandler)
	return mux
}

func (a *App) healthz(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}

	if err := a.db.PingContext(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "db_unavailable", "database unavailable")
		return
	}

	writeJSON(w, map[string]any{
		"ok":  true,
		"env": a.cfg.Env,
	})
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
