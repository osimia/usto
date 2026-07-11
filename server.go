package main

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
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
	// Auth: burst of 3 immediately, then refills at 1 request per 10s per IP.
	authLimiter := newIPRateLimiter(0.1, 3)
	// Money-moving (responses/topup): more generous, since a legitimate
	// office/NAT full of masters can share one IP.
	moneyLimiter := newIPRateLimiter(0.2, 10)

	chain := rateLimitMW(moneyLimiter, isMoneyMovingPath)(handler)
	chain = rateLimitMW(authLimiter, isAuthPath)(chain)
	chain = withCORS(cfg, chain)
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
	mux.HandleFunc("/readyz", a.readyz)
	mux.HandleFunc("/api/health", a.readyz)
	mux.HandleFunc("/api/auth/login", a.login)
	mux.HandleFunc("/api/auth/refresh", a.refreshAuthToken)
	mux.HandleFunc("/api/auth/logout", a.logout)
	mux.HandleFunc("/api/me", a.me)
	mux.HandleFunc("/api/me/profile", a.me)
	mux.HandleFunc("/api/bootstrap", a.bootstrap)
	mux.HandleFunc("/api/categories", a.categoriesHandler)
	mux.HandleFunc("/api/categories/", a.categoryDetailHandler)
	mux.HandleFunc("/api/masters", a.mastersHandler)
	mux.HandleFunc("/api/masters/me", a.myMasterListingHandler)
	mux.HandleFunc("/api/masters/", a.masterDetailHandler)
	mux.HandleFunc("/api/orders", a.ordersHandler)
	mux.HandleFunc("/api/orders/", a.orderDetailHandler)
	mux.HandleFunc("/api/responses", a.responses)
	mux.HandleFunc("/api/chats", a.chatsHandler)
	mux.HandleFunc("/api/chats/", a.chatDetailHandler)
	mux.HandleFunc("/api/wallet", a.walletHandler)
	mux.HandleFunc("/api/wallet/topup", a.topUpWallet)
	mux.HandleFunc("/api/wallet/transactions", a.walletTransactionsHandler)
	mux.HandleFunc("/api/verification", a.verifyMaster)
	mux.HandleFunc("/api/verification/status", a.verificationStatusHandler)
	mux.HandleFunc("/api/verification/documents", a.verificationDocumentsHandler)
	mux.Handle("/media/", a.mediaFileServer())
	mux.HandleFunc("/", staticHandler)
	return mux
}

func (a *App) mediaFileServer() http.Handler {
	files := http.StripPrefix("/media/", http.FileServer(http.Dir(a.cfg.MediaDir)))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
			return
		}
		rel := strings.TrimPrefix(r.URL.Path, "/media/")
		clean := filepath.Clean("/" + rel)
		diskPath := filepath.Join(a.cfg.MediaDir, filepath.FromSlash(strings.TrimPrefix(clean, "/")))
		if info, err := os.Stat(diskPath); err != nil || info.IsDir() {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		files.ServeHTTP(w, r)
	})
}

func (a *App) healthz(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}

	writeJSON(w, map[string]any{
		"ok":  true,
		"env": a.cfg.Env,
	})
}

func (a *App) readyz(w http.ResponseWriter, r *http.Request) {
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

// withCORS reflects the caller's Origin only if it's allowed. With no
// ALLOWED_ORIGINS configured in development, it falls back to reflecting any
// origin (convenient for local dev against arbitrary ports/emulators); in any
// other environment, an empty allow-list means no cross-origin access at all
// rather than silently trusting everyone.
func withCORS(cfg Config, next http.Handler) http.Handler {
	allowAny := len(cfg.AllowedOrigins) == 0 && cfg.Env == "development"
	allowed := make(map[string]bool, len(cfg.AllowedOrigins))
	for _, origin := range cfg.AllowedOrigins {
		allowed[origin] = true
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" && (allowAny || allowed[origin]) {
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
