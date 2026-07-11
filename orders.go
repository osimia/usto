package main

import (
	"database/sql"
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

type SelectMasterRequest struct {
	ResponseID int `json:"responseId"`
}

type SelectMasterResponse struct {
	Order     Order      `json:"order"`
	Responses []Response `json:"responses"`
	Chat      Chat       `json:"chat"`
}

type OrderFilters struct {
	Category   string
	District   string
	Status     string
	Query      string
	Limit      int
	CustomerID int
}

func (a *App) ordersHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		filters := orderFiltersFromRequest(r)
		if r.URL.Query().Get("mine") == "1" {
			_, profile, ok := a.currentUserProfile(w, r)
			if !ok {
				return
			}
			filters.CustomerID = profile.ID
		}
		orders := a.filteredOrders(filters)
		if r.URL.Query().Get("wrap") == "1" {
			writeJSON(w, OrdersResponse{Orders: orders})
			return
		}
		writeJSON(w, orders)
	case http.MethodPost:
		_, profile, ok := a.currentUserProfile(w, r)
		if !ok {
			return
		}
		if profile.Role != "customer" {
			writeError(w, http.StatusForbidden, "forbidden", "only customers can create orders")
			return
		}
		var req Order
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		order, err := a.createOrder(req, profile.ID)
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
	if action == "select-master" {
		a.orderSelectMasterHandler(w, r, id)
		return
	}
	if action == "status" {
		a.orderStatusHandler(w, r, id)
		return
	}
	if action == "photos" {
		a.orderPhotoUploadHandler(w, r, id)
		return
	}
	if action != "" {
		writeError(w, http.StatusNotFound, "route_not_found", "route not found")
		return
	}
	if !method(w, r, http.MethodGet) {
		return
	}
	if _, ok := a.orderByID(id); !ok {
		writeError(w, http.StatusNotFound, "order_not_found", "order not found")
		return
	}
	a.incrementOrderViews(id)
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

func (a *App) incrementOrderViews(id int) {
	_, _ = a.db.Exec(sqlf(`UPDATE orders SET views = views + 1 WHERE id = ?`), id)
}

func (a *App) orderSelectMasterHandler(w http.ResponseWriter, r *http.Request, orderID int) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req SelectMasterRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	order, chat, err := a.selectMasterForOrder(orderID, req.ResponseID)
	if err != nil {
		badRequest(w, err)
		return
	}
	writeJSON(w, SelectMasterResponse{
		Order:     order,
		Responses: a.responsesForOrder(orderID),
		Chat:      chat,
	})
}

type UpdateOrderStatusRequest struct {
	Status string `json:"status"`
}

// orderStatusHandler lets the order's own customer mark it completed or
// cancelled. Only the owning customer may do this — an order with no
// customer_id (created before this column existed, or via the legacy
// unauthenticated path) has no owner to authorize, so it's rejected too.
func (a *App) orderStatusHandler(w http.ResponseWriter, r *http.Request, orderID int) {
	if !method(w, r, http.MethodPatch) {
		return
	}
	_, profile, ok := a.currentUserProfile(w, r)
	if !ok {
		return
	}
	order, ok := a.orderByID(orderID)
	if !ok {
		writeError(w, http.StatusNotFound, "order_not_found", "order not found")
		return
	}
	if order.CustomerID == 0 || order.CustomerID != profile.ID {
		writeError(w, http.StatusForbidden, "forbidden", "only the order's own customer can change its status")
		return
	}
	var req UpdateOrderStatusRequest
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	updated, err := a.updateOrderStatus(order, strings.TrimSpace(req.Status))
	if err != nil {
		badRequest(w, err)
		return
	}
	writeJSON(w, OrderResponse{Order: updated, Responses: a.responsesForOrder(orderID)})
}

// updateOrderStatus applies a customer-facing status transition. "completed"
// requires a master to already be selected (you can't complete a job with no
// one assigned); "cancelled" is allowed from any non-final state. Completing
// an order also credits the selected master's completed_jobs counter, which
// otherwise never moves off its seed value.
func (a *App) updateOrderStatus(order Order, action string) (Order, error) {
	var newStatus string
	switch action {
	case "completed":
		if order.SelectedMasterID == 0 {
			return Order{}, errors.New("order must have a selected master before it can be completed")
		}
		newStatus = "Завершена"
	case "cancelled":
		if order.Status == "Завершена" || order.Status == "Отменена" {
			return Order{}, errors.New("order is already in a final state")
		}
		newStatus = "Отменена"
	default:
		return Order{}, errors.New("status must be 'completed' or 'cancelled'")
	}
	if _, err := a.db.Exec(sqlf(`UPDATE orders SET status=? WHERE id=?`), newStatus, order.ID); err != nil {
		return Order{}, err
	}
	if newStatus == "Завершена" {
		if profileID, ok := a.profileIDForMaster(order.SelectedMasterID); ok {
			_, _ = a.db.Exec(sqlf(`UPDATE profiles SET completed_jobs = completed_jobs + 1 WHERE id=?`), profileID)
		}
	}
	updated, ok := a.orderByID(order.ID)
	if !ok {
		return Order{}, errors.New("updated order not found")
	}
	return updated, nil
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

func (a *App) createOrder(req Order, customerID int) (Order, error) {
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
	preferredMasterID := req.PreferredMasterID
	if preferredMasterID > 0 {
		if _, ok := a.masterByID(preferredMasterID); !ok {
			return Order{}, errors.New("preferred master not found")
		}
	}

	id, err := insertID(a.db, `INSERT INTO orders(title,"desc",category,district,address,budget,when_label,status,views,preferred_master_id,customer_id) VALUES(?,?,?,?,?,?,?,?,0,?,?)`,
		title, desc, category, district, address, budget, whenLabel, "Активная", nullableInt(preferredMasterID), nullableInt(customerID))
	if err != nil {
		return Order{}, err
	}
	order, ok := a.orderByID(id)
	if !ok {
		return Order{}, errors.New("created order not found")
	}
	return order, nil
}

func (a *App) selectMasterForOrder(orderID, responseID int) (Order, Chat, error) {
	order, ok := a.orderByID(orderID)
	if !ok {
		return Order{}, Chat{}, errors.New("order not found")
	}
	if responseID <= 0 {
		return Order{}, Chat{}, errors.New("responseId is required")
	}

	var selected Response
	found := false
	for _, response := range a.responsesForOrder(orderID) {
		if response.ID == responseID {
			selected = response
			found = true
			break
		}
	}
	if !found {
		return Order{}, Chat{}, errors.New("response not found")
	}

	status := "Мастер выбран"
	if _, err := a.db.Exec(sqlf(`UPDATE orders SET selected_master_id=?, status=? WHERE id=?`), selected.MasterID, status, order.ID); err != nil {
		return Order{}, Chat{}, err
	}
	chat, err := a.ensureChat(order.ID, selected.MasterID)
	if err != nil {
		return Order{}, Chat{}, err
	}
	updatedOrder, ok := a.orderByID(order.ID)
	if !ok {
		return Order{}, Chat{}, errors.New("updated order not found")
	}
	return updatedOrder, chat, nil
}

func (a *App) filteredOrders(filters OrderFilters) []Order {
	return a.queryOrders(filters)
}

// queryOrders pushes category/district/status filters into SQL WHERE clauses
// and caps the result with SQL LIMIT, instead of fetching the whole table and
// filtering/truncating in Go. The free-text query filter still runs in Go
// (SQLite has no good case-insensitive multi-column search here), but only
// over a SQL-bounded result set, not the entire table.
func (a *App) queryOrders(filters OrderFilters) []Order {
	query := `SELECT o.id,o.customer_id,o.selected_master_id,o.preferred_master_id,o.title,o."desc",o.category,o.district,o.address,o.budget,o.when_label,o.status,o.views,o.created_at,COUNT(r.id)
		FROM orders o LEFT JOIN responses r ON r.order_id=o.id`
	var conditions []string
	var args []any
	if filters.Category != "" {
		conditions = append(conditions, equalityCI("o.category"))
		args = append(args, filters.Category)
	}
	if filters.District != "" {
		conditions = append(conditions, equalityCI("o.district"))
		args = append(args, filters.District)
	}
	if filters.Status != "" {
		conditions = append(conditions, equalityCI("o.status"))
		args = append(args, filters.Status)
	}
	if filters.CustomerID > 0 {
		conditions = append(conditions, "o.customer_id = ?")
		args = append(args, filters.CustomerID)
	}
	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += " GROUP BY o.id ORDER BY o.created_at DESC"

	switch {
	case filters.Query != "":
		// Free-text filtering happens in Go below, so fetch a bounded
		// window instead of the whole table to filter against.
		query += " LIMIT 500"
	case filters.Limit > 0:
		query += " LIMIT ?"
		args = append(args, filters.Limit)
	}

	rows, err := a.db.Query(sqlf(query), args...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Order
	var orderIDs []int
	for rows.Next() {
		var o Order
		var customerID sql.NullInt64
		var selectedMasterID sql.NullInt64
		var preferredMasterID sql.NullInt64
		var created string
		if rows.Scan(&o.ID, &customerID, &selectedMasterID, &preferredMasterID, &o.Title, &o.Desc, &o.Category, &o.District, &o.Address, &o.Budget, &o.When, &o.Status, &o.Views, &created, &o.Responses) == nil {
			if customerID.Valid {
				o.CustomerID = int(customerID.Int64)
			}
			if selectedMasterID.Valid {
				o.SelectedMasterID = int(selectedMasterID.Int64)
			}
			if preferredMasterID.Valid {
				o.PreferredMasterID = int(preferredMasterID.Int64)
			}
			o.CreatedAt = relativeTime(created)
			items = append(items, o)
			orderIDs = append(orderIDs, o.ID)
		}
	}
	attachPhotosToOrders(items, orderPhotosFor(a.db, orderIDs))
	if filters.Query == "" {
		return items
	}
	filtered := make([]Order, 0, len(items))
	for _, item := range items {
		if !orderMatchesQuery(item, filters.Query) {
			continue
		}
		filtered = append(filtered, item)
		if filters.Limit > 0 && len(filtered) >= filters.Limit {
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

func nullableInt(v int) any {
	if v <= 0 {
		return nil
	}
	return v
}
