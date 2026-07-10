package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type AuthRequestCodeRequest struct {
	Phone string `json:"phone"`
}

type AuthRequestCodeResponse struct {
	RequestID  string `json:"requestId"`
	TTLSeconds int    `json:"ttlSeconds"`
}

type AuthVerifyCodeRequest struct {
	Phone string `json:"phone"`
	Code  string `json:"code"`
	Role  string `json:"role"`
}

type AuthRefreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

type AuthResponse struct {
	AccessToken  string   `json:"accessToken"`
	RefreshToken string   `json:"refreshToken"`
	User         AuthUser `json:"user"`
}

type AuthUser struct {
	ID    int    `json:"id"`
	Phone string `json:"phone"`
	Role  string `json:"role"`
	Name  string `json:"name"`
	City  string `json:"city"`
}

type tokenClaims struct {
	Subject   string `json:"sub"`
	UserID    int    `json:"uid"`
	Role      string `json:"role"`
	TokenType string `json:"typ"`
	ExpiresAt int64  `json:"exp"`
	IssuedAt  int64  `json:"iat"`
}

func (a *App) requestAuthCode(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req AuthRequestCodeRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	phone := normalizePhone(req.Phone)
	if len(phone) < 9 {
		badRequest(w, errors.New("phone is required"))
		return
	}
	writeJSON(w, AuthRequestCodeResponse{
		RequestID:  "dev-" + phone,
		TTLSeconds: 120,
	})
}

func (a *App) verifyAuthCode(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req AuthVerifyCodeRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	role := strings.TrimSpace(req.Role)
	if role != "customer" && role != "master" {
		badRequest(w, errors.New("role must be customer or master"))
		return
	}
	phoneNorm := normalizePhone(req.Phone)
	if phoneNorm == "" {
		badRequest(w, errors.New("phone is required"))
		return
	}
	if strings.TrimSpace(req.Code) != a.cfg.DevSMSCode {
		writeError(w, http.StatusUnauthorized, "invalid_code", "invalid SMS code")
		return
	}

	user, err := a.ensureUserForAuth(req.Phone, phoneNorm, role)
	if err != nil {
		serverError(w, err)
		return
	}

	auth, err := a.issueAuthResponse(user)
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, auth)
}

func (a *App) refreshAuthToken(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req AuthRefreshRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	claims, err := a.parseToken(req.RefreshToken)
	if err != nil || claims.TokenType != "refresh" {
		writeError(w, http.StatusUnauthorized, "invalid_token", "invalid refresh token")
		return
	}
	user, err := a.userByID(claims.UserID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid_token", "invalid refresh token")
		return
	}
	auth, err := a.issueAuthResponse(user)
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, auth)
}

func (a *App) logout(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (a *App) issueAuthResponse(user User) (AuthResponse, error) {
	p, err := a.profileByID(user.ProfileID)
	if err != nil {
		return AuthResponse{}, err
	}
	accessToken, err := a.signToken(user, "access", time.Duration(a.cfg.AccessTokenHours)*time.Hour)
	if err != nil {
		return AuthResponse{}, err
	}
	refreshToken, err := a.signToken(user, "refresh", time.Duration(a.cfg.RefreshTokenHours)*time.Hour)
	if err != nil {
		return AuthResponse{}, err
	}
	return AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		User:         authUserFromUserProfile(user, p),
	}, nil
}

func authUserFromUserProfile(user User, p Profile) AuthUser {
	return AuthUser{
		ID:    user.ID,
		Phone: user.Phone,
		Role:  user.Role,
		Name:  p.Name,
		City:  p.City,
	}
}

func (a *App) ensureUserForAuth(phone, phoneNorm, role string) (User, error) {
	if user, err := a.userByPhoneRole(phoneNorm, role); err == nil {
		_, _ = a.db.Exec(sqlf(`UPDATE users SET last_login_at=CURRENT_TIMESTAMP WHERE id=?`), user.ID)
		return user, nil
	}

	p, err := a.profile(role)
	if err != nil {
		return User{}, err
	}
	id, err := insertID(a.db, `INSERT INTO users(phone,phone_norm,role,status,profile_id,last_login_at) VALUES(?,?,?,?,?,CURRENT_TIMESTAMP)`,
		strings.TrimSpace(phone), phoneNorm, role, "active", p.ID)
	if err != nil {
		return User{}, err
	}
	return a.userByID(id)
}

func (a *App) userByPhoneRole(phoneNorm, role string) (User, error) {
	var user User
	err := a.db.QueryRow(sqlf(`SELECT id,phone,phone_norm,role,status,profile_id FROM users WHERE phone_norm=? AND role=?`), phoneNorm, role).
		Scan(&user.ID, &user.Phone, &user.PhoneNorm, &user.Role, &user.Status, &user.ProfileID)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (a *App) userByID(id int) (User, error) {
	var user User
	err := a.db.QueryRow(sqlf(`SELECT id,phone,phone_norm,role,status,profile_id FROM users WHERE id=?`), id).
		Scan(&user.ID, &user.Phone, &user.PhoneNorm, &user.Role, &user.Status, &user.ProfileID)
	if err != nil {
		return User{}, err
	}
	return user, nil
}

func (a *App) signToken(user User, tokenType string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := tokenClaims{
		Subject:   strconv.Itoa(user.ID),
		UserID:    user.ID,
		Role:      user.Role,
		TokenType: tokenType,
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
	}
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	unsigned := jwtEncode(headerJSON) + "." + jwtEncode(claimsJSON)
	sig := hmacSHA256(unsigned, a.cfg.JWTSecret)
	return unsigned + "." + jwtEncode(sig), nil
}

func (a *App) claimsFromRequest(r *http.Request) (tokenClaims, error) {
	auth := strings.TrimSpace(r.Header.Get("Authorization"))
	if auth == "" {
		return tokenClaims{}, errors.New("missing authorization header")
	}
	token := strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
	if token == auth {
		return tokenClaims{}, errors.New("invalid authorization header")
	}
	return a.parseToken(token)
}

func (a *App) parseToken(token string) (tokenClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return tokenClaims{}, errors.New("invalid token")
	}
	unsigned := parts[0] + "." + parts[1]
	expected := hmacSHA256(unsigned, a.cfg.JWTSecret)
	actual, err := jwtDecode(parts[2])
	if err != nil {
		return tokenClaims{}, err
	}
	if !hmac.Equal(actual, expected) {
		return tokenClaims{}, errors.New("invalid token signature")
	}
	payload, err := jwtDecode(parts[1])
	if err != nil {
		return tokenClaims{}, err
	}
	var claims tokenClaims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return tokenClaims{}, err
	}
	if claims.ExpiresAt <= time.Now().Unix() {
		return tokenClaims{}, errors.New("token expired")
	}
	if claims.Role != "customer" && claims.Role != "master" && claims.Role != "admin" {
		return tokenClaims{}, errors.New("invalid token role")
	}
	return claims, nil
}

func normalizePhone(value string) string {
	var b strings.Builder
	for _, r := range value {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func jwtEncode(value []byte) string {
	return base64.RawURLEncoding.EncodeToString(value)
}

func jwtDecode(value string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(value)
}

func hmacSHA256(value, secret string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(value))
	return mac.Sum(nil)
}
