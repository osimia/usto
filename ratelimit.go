package main

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// tokenBucket is a minimal per-client rate limiter: it refills continuously
// at `refillPerSecond` tokens/second, up to `burst`, and each request costs
// one token. No external dependency needed for this small a use case.
type tokenBucket struct {
	mu              sync.Mutex
	tokens          float64
	burst           float64
	refillPerSecond float64
	lastRefillAt    time.Time
}

func newTokenBucket(refillPerSecond, burst float64) *tokenBucket {
	return &tokenBucket{tokens: burst, burst: burst, refillPerSecond: refillPerSecond, lastRefillAt: time.Now()}
}

func (b *tokenBucket) allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := time.Now()
	elapsed := now.Sub(b.lastRefillAt).Seconds()
	b.lastRefillAt = now
	b.tokens += elapsed * b.refillPerSecond
	if b.tokens > b.burst {
		b.tokens = b.burst
	}
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// ipRateLimiter hands out one token bucket per client IP, created lazily.
type ipRateLimiter struct {
	mu              sync.Mutex
	buckets         map[string]*tokenBucket
	refillPerSecond float64
	burst           float64
}

func newIPRateLimiter(refillPerSecond, burst float64) *ipRateLimiter {
	return &ipRateLimiter{buckets: make(map[string]*tokenBucket), refillPerSecond: refillPerSecond, burst: burst}
}

func (l *ipRateLimiter) allow(ip string) bool {
	l.mu.Lock()
	bucket, ok := l.buckets[ip]
	if !ok {
		bucket = newTokenBucket(l.refillPerSecond, l.burst)
		l.buckets[ip] = bucket
	}
	l.mu.Unlock()
	return bucket.allow()
}

// rateLimitMW throttles only requests matched by `matches`, per client IP.
func rateLimitMW(limiter *ipRateLimiter, matches func(*http.Request) bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if matches(r) && !limiter.allow(clientIP(r)) {
				writeError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// isAuthPath matches the login endpoint, guessed at per-IP since there's no
// SMS code to prove phone ownership.
func isAuthPath(r *http.Request) bool {
	return authRateLimitedPaths[r.URL.Path]
}

// isMoneyMovingPath matches wallet top-up and response creation (including
// the legacy /api/responses path) — anything that debits/credits a wallet,
// throttled to slow down spamming rather than to enforce a hard security
// boundary (that's the caller's own auth, checked separately).
func isMoneyMovingPath(r *http.Request) bool {
	if r.Method != http.MethodPost {
		return false
	}
	return r.URL.Path == "/api/wallet/topup" || strings.HasSuffix(r.URL.Path, "/responses")
}

func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if first := strings.SplitN(fwd, ",", 2)[0]; first != "" {
			return strings.TrimSpace(first)
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
