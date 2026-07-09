package main

import (
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
	var req TopUpWalletRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	wallet, err := a.topUp(req.Amount)
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
	p, err := a.profile("master")
	if err != nil {
		return Wallet{}, err
	}
	return Wallet{
		Balance:      p.WalletBalance,
		Currency:     "TJS",
		Transactions: a.transactions(),
	}, nil
}

func (a *App) topUp(amount int) (Wallet, error) {
	if amount <= 0 {
		return Wallet{}, errors.New("amount must be positive")
	}
	if _, err := a.db.Exec(`UPDATE profiles SET wallet_balance = wallet_balance + ? WHERE role='master'`, amount); err != nil {
		return Wallet{}, err
	}
	if _, err := a.db.Exec(`INSERT INTO transactions(label,amount) VALUES(?,?)`, "Пополнение кошелька", amount); err != nil {
		return Wallet{}, err
	}
	return a.wallet()
}
