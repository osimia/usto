package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
)

// errInsufficientFunds signals a guarded balance check failed inside a
// transaction (not a validation error), so handlers map it to 402 instead
// of the generic 400 used for bad request bodies.
var errInsufficientFunds = errors.New("insufficient funds")

const responseFeeTJS = 4

type CreateResponseRequest struct {
	OrderID int    `json:"orderId"`
	Price   int    `json:"price"`
	Comment string `json:"comment"`
}

type ResponsesResponse struct {
	Responses []Response `json:"responses"`
}

type CreateResponseResponse struct {
	Response Response   `json:"response"`
	Order    Order      `json:"order"`
	Snapshot *Bootstrap `json:"snapshot,omitempty"`
}

func (a *App) orderResponsesHandler(w http.ResponseWriter, r *http.Request, orderID int) {
	switch r.Method {
	case http.MethodGet:
		if _, ok := a.orderByID(orderID); !ok {
			writeError(w, http.StatusNotFound, "order_not_found", "order not found")
			return
		}
		writeJSON(w, ResponsesResponse{Responses: a.responsesForOrder(orderID)})
	case http.MethodPost:
		var req CreateResponseRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		key := idempotencyKeyFromRequest(r)
		if a.idempotentReplay(w, key) {
			return
		}
		req.OrderID = orderID
		response, order, err := a.createResponse(req, key)
		if err != nil {
			if errors.Is(err, errInsufficientFunds) {
				writeError(w, http.StatusPaymentRequired, "insufficient_funds", err.Error())
				return
			}
			badRequest(w, err)
			return
		}
		writeJSON(w, CreateResponseResponse{Response: response, Order: order})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) responses(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	key := idempotencyKeyFromRequest(r)
	if a.idempotentReplay(w, key) {
		return
	}
	var req CreateResponseRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	response, order, err := a.createResponse(req, key)
	if err != nil {
		if errors.Is(err, errInsufficientFunds) {
			writeError(w, http.StatusPaymentRequired, "insufficient_funds", err.Error())
			return
		}
		badRequest(w, err)
		return
	}
	if r.URL.Query().Get("wrap") == "1" {
		snapshot := a.snapshot()
		writeJSON(w, CreateResponseResponse{
			Response: response,
			Order:    order,
			Snapshot: &snapshot,
		})
		return
	}
	writeJSON(w, a.snapshot())
}

// createResponse debits the master's wallet, inserts the response, and logs
// the transaction all inside one DB transaction — either all three happen or
// none do. The debit is guarded (wallet_balance >= fee in the same UPDATE),
// so a too-low balance rolls back cleanly instead of ever going negative.
// idempotencyKey, if non-empty, makes a retry with the same key replay the
// original result instead of debiting twice.
func (a *App) createResponse(req CreateResponseRequest, idempotencyKey string) (Response, Order, error) {
	if req.OrderID <= 0 {
		return Response{}, Order{}, errors.New("orderId is required")
	}
	if req.Price <= 0 {
		return Response{}, Order{}, errors.New("price must be positive")
	}
	comment := strings.TrimSpace(req.Comment)
	if comment == "" {
		return Response{}, Order{}, errors.New("comment is required")
	}
	if _, ok := a.orderByID(req.OrderID); !ok {
		return Response{}, Order{}, errors.New("order not found")
	}

	tx, err := a.db.Begin()
	if err != nil {
		return Response{}, Order{}, err
	}
	defer tx.Rollback()

	debit, err := tx.Exec(sqlf(`UPDATE profiles SET wallet_balance = wallet_balance - ? WHERE role='master' AND wallet_balance >= ?`),
		responseFeeTJS, responseFeeTJS)
	if err != nil {
		return Response{}, Order{}, err
	}
	affected, err := debit.RowsAffected()
	if err != nil {
		return Response{}, Order{}, err
	}
	if affected == 0 {
		return Response{}, Order{}, errInsufficientFunds
	}

	id, err := insertID(tx, `INSERT INTO responses(order_id,master_id,price,comment) VALUES(?,?,?,?)`, req.OrderID, 1, req.Price, comment)
	if err != nil {
		return Response{}, Order{}, err
	}
	if _, err := tx.Exec(sqlf(`INSERT INTO transactions(label,amount) VALUES(?,?)`), "Отклик на заявку", -responseFeeTJS); err != nil {
		return Response{}, Order{}, err
	}

	response, ok := responseByIDFrom(tx, id, req.OrderID)
	if !ok {
		return Response{}, Order{}, errors.New("created response not found")
	}
	order, ok := orderByIDFrom(tx, req.OrderID)
	if !ok {
		return Response{}, Order{}, errors.New("updated order not found")
	}

	if idempotencyKey != "" {
		body, err := json.Marshal(CreateResponseResponse{Response: response, Order: order})
		if err != nil {
			return Response{}, Order{}, err
		}
		if err := storeIdempotencyResult(tx, idempotencyKey, string(body), http.StatusOK); err != nil {
			return Response{}, Order{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return Response{}, Order{}, err
	}
	return response, order, nil
}

func (a *App) responseByID(id, orderID int) (Response, bool) {
	return responseByIDFrom(a.db, id, orderID)
}

func responseByIDFrom(q queryer, id, orderID int) (Response, bool) {
	row := q.QueryRow(sqlf(`SELECT r.id,r.order_id,r.master_id,m.name,m.rating,r.price,r.comment,r.created_at
		FROM responses r JOIN masters m ON m.id=r.master_id
		WHERE r.id=? AND r.order_id=?`), id, orderID)
	var item Response
	var rating float64
	var created string
	if err := row.Scan(&item.ID, &item.OrderID, &item.MasterID, &item.Master, &rating, &item.Price, &item.Comment, &created); err != nil {
		return Response{}, false
	}
	item.Rating = strconv.FormatFloat(rating, 'f', 1, 64)
	item.CreatedAt = relativeTime(created)
	return item, true
}
