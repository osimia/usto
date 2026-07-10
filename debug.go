package main

import (
	"log/slog"
	"net/http"
	_ "net/http/pprof"
)

// startPprofServer exposes net/http/pprof on a separate, non-public address.
// It's a no-op if addr is empty (the default), so pprof is never reachable
// unless an operator explicitly opts in via PPROF_ADDR.
func startPprofServer(addr string) {
	if addr == "" {
		return
	}
	go func() {
		slog.Info("pprof server listening", "addr", addr)
		if err := http.ListenAndServe(addr, nil); err != nil {
			slog.Error("pprof server stopped", "error", err)
		}
	}()
}
