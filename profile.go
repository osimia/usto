package main

import (
	"errors"
	"net/http"
	"strings"
)

type UpdateProfileRequest struct {
	Name      string `json:"name"`
	City      string `json:"city"`
	District  string `json:"district"`
	AvatarURL string `json:"avatarUrl"`
}

type MeResponse struct {
	User    AuthUser `json:"user"`
	Profile Profile  `json:"profile"`
}

func (a *App) me(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		a.getMe(w, r)
	case http.MethodPatch:
		a.updateMyProfile(w, r)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) getMe(w http.ResponseWriter, r *http.Request) {
	user, p, ok := a.currentUserProfile(w, r)
	if !ok {
		return
	}
	writeJSON(w, MeResponse{
		User:    authUserFromUserProfile(user, p),
		Profile: p,
	})
}

func (a *App) updateMyProfile(w http.ResponseWriter, r *http.Request) {
	user, _, ok := a.currentUserProfile(w, r)
	if !ok {
		return
	}
	var req UpdateProfileRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	name := strings.TrimSpace(req.Name)
	city := strings.TrimSpace(req.City)
	district := strings.TrimSpace(req.District)
	avatarURL := strings.TrimSpace(req.AvatarURL)

	if name == "" {
		badRequest(w, errors.New("name is required"))
		return
	}
	if city == "" {
		badRequest(w, errors.New("city is required"))
		return
	}

	if _, err := a.db.Exec(sqlf(`UPDATE profiles SET name=?, city=?, district=?, avatar_url=? WHERE id=?`),
		name, city, district, avatarURL, user.ProfileID); err != nil {
		serverError(w, err)
		return
	}
	_ = a.syncUserPhoneFromProfile(user.ProfileID)
	a.getMe(w, r)
}

func (a *App) currentUserProfile(w http.ResponseWriter, r *http.Request) (User, Profile, bool) {
	claims, err := a.claimsFromRequest(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized", "authorization token is required")
		return User{}, Profile{}, false
	}
	user, err := a.userByID(claims.UserID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthorized", "authorization token is invalid")
		return User{}, Profile{}, false
	}
	p, err := a.profileByID(user.ProfileID)
	if err != nil {
		serverError(w, err)
		return User{}, Profile{}, false
	}
	return user, p, true
}

func (a *App) syncUserPhoneFromProfile(profileID int) error {
	var phone string
	if err := a.db.QueryRow(sqlf(`SELECT phone FROM profiles WHERE id=?`), profileID).Scan(&phone); err != nil {
		return err
	}
	_, err := a.db.Exec(sqlf(`UPDATE users SET phone=?, phone_norm=?, updated_at=CURRENT_TIMESTAMP WHERE profile_id=?`),
		phone, normalizePhone(phone), profileID)
	return err
}
