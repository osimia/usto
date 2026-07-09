package main

import (
	"net/http"
	"time"
)

func newHTTPServer(cfg Config, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              cfg.addr(),
		Handler:           logRequests(withCORS(handler)),
		ReadHeaderTimeout: 5 * time.Second,
	}
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/auth/request-code", a.requestAuthCode)
	mux.HandleFunc("/api/auth/verify-code", a.verifyAuthCode)
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
