package main

import (
	"net"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Env               string
	Host              string
	Port              string
	DBDriver          string
	DatabaseURL       string
	DBPath            string
	JWTSecret         string
	AccessTokenHours  int
	RefreshTokenHours int
	PprofAddr         string
}

func loadConfig() Config {
	return Config{
		Env:               env("APP_ENV", "development"),
		Host:              env("HOST", "localhost"),
		Port:              env("PORT", "8080"),
		DBDriver:          env("DB_DRIVER", "sqlite"),
		DatabaseURL:       env("DATABASE_URL", ""),
		DBPath:            env("DB_PATH", "usto.db"),
		JWTSecret:         env("JWT_SECRET", "dev-secret-change-me"),
		AccessTokenHours:  envInt("ACCESS_TOKEN_HOURS", 24),
		RefreshTokenHours: envInt("REFRESH_TOKEN_HOURS", 720),
		PprofAddr:         env("PPROF_ADDR", ""),
	}
}

func (c Config) addr() string {
	return net.JoinHostPort("", c.Port)
}

func (c Config) publicURL() string {
	host := c.Host
	if host == "" || host == "0.0.0.0" {
		host = "localhost"
	}
	return "http://" + net.JoinHostPort(host, c.Port)
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return n
}
