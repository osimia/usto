package main

import (
	"errors"
	"net/http"
	"strings"
)

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
		req.OrderID = orderID
		response, order, err := a.createResponse(req)
		if err != nil {
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
	var req CreateResponseRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	response, order, err := a.createResponse(req)
	if err != nil {
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

func (a *App) createResponse(req CreateResponseRequest) (Response, Order, error) {
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
	order, ok := a.orderByID(req.OrderID)
	if !ok {
		return Response{}, Order{}, errors.New("order not found")
	}

	res, err := a.db.Exec(`INSERT INTO responses(order_id,master_id,price,comment) VALUES(?,?,?,?)`, req.OrderID, 1, req.Price, comment)
	if err != nil {
		return Response{}, Order{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Response{}, Order{}, err
	}
	if _, err := a.db.Exec(`UPDATE profiles SET wallet_balance = wallet_balance - 4 WHERE role='master'`); err != nil {
		return Response{}, Order{}, err
	}
	if _, err := a.db.Exec(`INSERT INTO transactions(label,amount) VALUES(?,?)`, "Отклик на заявку", -4); err != nil {
		return Response{}, Order{}, err
	}
	response, ok := a.responseByID(int(id), req.OrderID)
	if !ok {
		return Response{}, Order{}, errors.New("created response not found")
	}
	updatedOrder, ok := a.orderByID(order.ID)
	if ok {
		order = updatedOrder
	}
	return response, order, nil
}

func (a *App) responseByID(id, orderID int) (Response, bool) {
	for _, item := range a.responsesForOrder(orderID) {
		if item.ID == id {
			return item, true
		}
	}
	return Response{}, false
}
