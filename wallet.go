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

func (a *App) walletHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	wallet, err := a.wallet()
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
	writeJSON(w, TransactionsResponse{Transactions: a.transactions()})
}

func (a *App) topUpWallet(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
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
	wallet, err := a.topUp(req.Amount, key)
	if err != nil {
		badRequest(w, err)
		return
	}
	if r.URL.Query().Get("wrap") == "1" {
		writeJSON(w, WalletResponse{Wallet: wallet})
		return
	}
	writeJSON(w, a.snapshot())
}

func (a *App) wallet() (Wallet, error) {
	return walletFrom(a.db)
}

func walletFrom(q queryer) (Wallet, error) {
	p, err := profileFrom(q, "master")
	if err != nil {
		return Wallet{}, err
	}
	return Wallet{
		Balance:      p.WalletBalance,
		Currency:     "TJS",
		Transactions: transactionsFrom(q),
	}, nil
}

// topUp credits the wallet and logs the transaction inside one DB
// transaction, with the same idempotency-key handling as createResponse.
func (a *App) topUp(amount int, idempotencyKey string) (Wallet, error) {
	if amount <= 0 {
		return Wallet{}, errors.New("amount must be positive")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return Wallet{}, err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(sqlf(`UPDATE profiles SET wallet_balance = wallet_balance + ? WHERE role='master'`), amount); err != nil {
		return Wallet{}, err
	}
	if _, err := tx.Exec(sqlf(`INSERT INTO transactions(label,amount) VALUES(?,?)`), "Пополнение кошелька", amount); err != nil {
		return Wallet{}, err
	}

	wallet, err := walletFrom(tx)
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
