package main

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
)

type OrdersResponse struct {
	Orders []Order `json:"orders"`
}

type OrderResponse struct {
	Order     Order      `json:"order"`
	Responses []Response `json:"responses,omitempty"`
}

type OrderFilters struct {
	Category string
	District string
	Status   string
	Query    string
	Limit    int
}

func (a *App) ordersHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		orders := a.filteredOrders(orderFiltersFromRequest(r))
		if r.URL.Query().Get("wrap") == "1" {
			writeJSON(w, OrdersResponse{Orders: orders})
			return
		}
		writeJSON(w, orders)
	case http.MethodPost:
		var req Order
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		order, err := a.createOrder(req)
		if err != nil {
			badRequest(w, err)
			return
		}
		writeJSON(w, OrderResponse{Order: order})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) orderDetailHandler(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseOrderSubroute(r.URL.Path)
	if !ok {
		writeError(w, http.StatusNotFound, "order_not_found", "order not found")
		return
	}
	if action == "responses" {
		a.orderResponsesHandler(w, r, id)
		return
	}
	if action != "" {
		writeError(w, http.StatusNotFound, "route_not_found", "route not found")
		return
	}
	if !method(w, r, http.MethodGet) {
		return
	}
	order, ok := a.orderByID(id)
	if !ok {
		writeError(w, http.StatusNotFound, "order_not_found", "order not found")
		return
	}
	writeJSON(w, OrderResponse{
		Order:     order,
		Responses: a.responsesForOrder(id),
	})
}

func parseOrderSubroute(path string) (int, string, bool) {
	rest := strings.TrimPrefix(path, "/api/orders/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		return 0, "", false
	}
	id, err := strconv.Atoi(parts[0])
	if err != nil || id <= 0 {
		return 0, "", false
	}
	if len(parts) == 1 {
		return id, "", true
	}
	if len(parts) == 2 {
		return id, parts[1], true
	}
	return 0, "", false
}

func orderFiltersFromRequest(r *http.Request) OrderFilters {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return OrderFilters{
		Category: strings.TrimSpace(q.Get("category")),
		District: strings.TrimSpace(q.Get("district")),
		Status:   strings.TrimSpace(q.Get("status")),
		Query:    strings.TrimSpace(q.Get("q")),
		Limit:    limit,
	}
}

func (a *App) createOrder(req Order) (Order, error) {
	title := strings.TrimSpace(req.Title)
	if title == "" {
		return Order{}, errors.New("title is required")
	}
	desc := strings.TrimSpace(req.Desc)
	if desc == "" {
		desc = title
	}
	category := strings.TrimSpace(req.Category)
	if category == "" {
		return Order{}, errors.New("category is required")
	}
	district := strings.TrimSpace(req.District)
	address := strings.TrimSpace(req.Address)
	budget := strings.TrimSpace(req.Budget)
	whenLabel := strings.TrimSpace(req.When)
	if whenLabel == "" {
		whenLabel = "В ближайшее время"
	}

	res, err := a.db.Exec(`INSERT INTO orders(title,desc,category,district,address,budget,when_label,status,views) VALUES(?,?,?,?,?,?,?,?,0)`,
		title, desc, category, district, address, budget, whenLabel, "Активная")
	if err != nil {
		return Order{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return Order{}, err
	}
	order, ok := a.orderByID(int(id))
	if !ok {
		return Order{}, errors.New("created order not found")
	}
	return order, nil
}

func (a *App) filteredOrders(filters OrderFilters) []Order {
	items := a.orders()
	filtered := make([]Order, 0, len(items))
	for _, item := range items {
		if filters.Category != "" && !strings.EqualFold(item.Category, filters.Category) {
			continue
		}
		if filters.District != "" && !strings.EqualFold(item.District, filters.District) {
			continue
		}
		if filters.Status != "" && !strings.EqualFold(item.Status, filters.Status) {
			continue
		}
		if filters.Query != "" && !orderMatchesQuery(item, filters.Query) {
			continue
		}
		filtered = append(filtered, item)
		if len(filtered) >= filters.Limit {
			break
		}
	}
	return filtered
}

func orderMatchesQuery(order Order, query string) bool {
	haystack := strings.ToLower(strings.Join([]string{
		order.Title,
		order.Desc,
		order.Category,
		order.District,
		order.Address,
		order.Budget,
		order.Status,
	}, " "))
	return strings.Contains(haystack, strings.ToLower(query))
}
