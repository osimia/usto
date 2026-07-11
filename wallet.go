package main

import (
	"encoding/json"
	"errors"
	"net/http"
)

type Wallet struct {
	Balance      int           `json:"balance"`
	Currency     string        `json:"currency"`
	Transactions []Transaction `json:"transactions,omitempty"`
}

type WalletResponse struct {
	Wallet Wallet `json:"wallet"`
}

type TransactionsResponse struct {
	Transactions []Transaction `json:"transactions"`
}

type TopUpWalletRequest struct {
	Amount int `json:"amount"`
}

// walletProfile resolves the wallet owner from the caller's own JWT (role
// must be master — wallet is a master-only concept per PRODUCT_SPEC.md),
// writing an error response and returning ok=false if unauthenticated/wrong role.
func (a *App) walletProfile(w http.ResponseWriter, r *http.Request) (Profile, bool) {
	_, profile, ok := a.currentUserProfile(w, r)
	if !ok {
		return Profile{}, false
	}
	if profile.Role != "master" {
		writeError(w, http.StatusForbidden, "forbidden", "wallet is only available to masters")
		return Profile{}, false
	}
	return profile, true
}

func (a *App) walletHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	profile, ok := a.walletProfile(w, r)
	if !ok {
		return
	}
	wallet, err := a.wallet(profile.ID)
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, WalletResponse{Wallet: wallet})
}

func (a *App) walletTransactionsHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	profile, ok := a.walletProfile(w, r)
	if !ok {
		return
	}
	writeJSON(w, TransactionsResponse{Transactions: transactionsFrom(a.db, profile.ID)})
}

func (a *App) topUpWallet(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	profile, ok := a.walletProfile(w, r)
	if !ok {
		return
	}
	key := idempotencyKeyFromRequest(r)
	if a.idempotentReplay(w, key) {
		return
	}
	var req TopUpWalletRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	wallet, err := a.topUp(profile.ID, req.Amount, key)
	if err != nil {
		badRequest(w, err)
		return
	}
	writeJSON(w, WalletResponse{Wallet: wallet})
}

func (a *App) wallet(profileID int) (Wallet, error) {
	return walletFrom(a.db, profileID)
}

func walletFrom(q queryer, profileID int) (Wallet, error) {
	p, err := profileByIDFrom(q, profileID)
	if err != nil {
		return Wallet{}, err
	}
	return Wallet{
		Balance:      p.WalletBalance,
		Currency:     "TJS",
		Transactions: transactionsFrom(q, profileID),
	}, nil
}

// topUp credits the wallet and logs the transaction inside one DB
// transaction, with the same idempotency-key handling as createResponse.
func (a *App) topUp(profileID, amount int, idempotencyKey string) (Wallet, error) {
	if amount <= 0 {
		return Wallet{}, errors.New("amount must be positive")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return Wallet{}, err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(sqlf(`UPDATE profiles SET wallet_balance = wallet_balance + ? WHERE id=?`), amount, profileID); err != nil {
		return Wallet{}, err
	}
	if _, err := tx.Exec(sqlf(`INSERT INTO transactions(label,amount,profile_id) VALUES(?,?,?)`), "Пополнение кошелька", amount, profileID); err != nil {
		return Wallet{}, err
	}

	wallet, err := walletFrom(tx, profileID)
	if err != nil {
		return Wallet{}, err
	}

	if idempotencyKey != "" {
		body, err := json.Marshal(WalletResponse{Wallet: wallet})
		if err != nil {
			return Wallet{}, err
		}
		if err := storeIdempotencyResult(tx, idempotencyKey, string(body), http.StatusOK); err != nil {
			return Wallet{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return Wallet{}, err
	}
	return wallet, nil
}
