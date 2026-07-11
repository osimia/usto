package main

import (
	"net/http"
	"strconv"
	"strings"
)

type MastersResponse struct {
	Masters []Master `json:"masters"`
}

type MasterResponse struct {
	Master Master `json:"master"`
}

type MasterReviewsResponse struct {
	Reviews []MasterReview `json:"reviews"`
}

type MasterFilters struct {
	Service string
	Query   string
	Limit   int
}

func (a *App) mastersHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	masters := a.filteredMasters(masterFiltersFromRequest(r))
	if r.URL.Query().Get("wrap") == "1" {
		writeJSON(w, MastersResponse{Masters: masters})
		return
	}
	writeJSON(w, masters)
}

func (a *App) masterDetailHandler(w http.ResponseWriter, r *http.Request) {
	id, action, ok := parseMasterSubroute(r.URL.Path)
	if !ok {
		writeError(w, http.StatusNotFound, "master_not_found", "master not found")
		return
	}
	switch action {
	case "":
		if !method(w, r, http.MethodGet) {
			return
		}
		master, ok := a.masterByID(id)
		if !ok {
			writeError(w, http.StatusNotFound, "master_not_found", "master not found")
			return
		}
		writeJSON(w, MasterResponse{Master: master})
	case "reviews":
		if !method(w, r, http.MethodGet) {
			return
		}
		writeJSON(w, MasterReviewsResponse{Reviews: a.masterReviews(id)})
	default:
		writeError(w, http.StatusNotFound, "route_not_found", "route not found")
	}
}

func parseMasterSubroute(path string) (int, string, bool) {
	rest := strings.TrimPrefix(path, "/api/masters/")
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

func masterFiltersFromRequest(r *http.Request) MasterFilters {
	q := r.URL.Query()
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return MasterFilters{
		Service: strings.TrimSpace(q.Get("service")),
		Query:   strings.TrimSpace(q.Get("q")),
		Limit:   limit,
	}
}

func (a *App) filteredMasters(filters MasterFilters) []Master {
	return a.queryMasters(filters)
}

// queryMasters pushes the service filter into SQL and caps with SQL LIMIT;
// the free-text query filter still runs in Go, over a SQL-bounded window.
func (a *App) queryMasters(filters MasterFilters) []Master {
	query := `SELECT id,name,service,rating,reviews,price,verified,bio,skills,portfolio FROM masters`
	var conditions []string
	var args []any
	if filters.Service != "" {
		conditions = append(conditions, equalityCI("service"))
		args = append(args, filters.Service)
	}
	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += " ORDER BY rating DESC"

	switch {
	case filters.Query != "":
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
	var items []Master
	for rows.Next() {
		var m Master
		var verified int
		var skills, portfolio string
		if rows.Scan(&m.ID, &m.Name, &m.Service, &m.Rating, &m.Reviews, &m.Price, &verified, &m.Bio, &skills, &portfolio) == nil {
			m.Verified = verified == 1
			m.Skills = splitList(skills)
			m.Portfolio = splitList(portfolio)
			items = append(items, m)
		}
	}
	if filters.Query == "" {
		return items
	}
	filtered := make([]Master, 0, len(items))
	for _, item := range items {
		if !masterMatchesQuery(item, filters.Query) {
			continue
		}
		filtered = append(filtered, item)
		if filters.Limit > 0 && len(filtered) >= filters.Limit {
			break
		}
	}
	return filtered
}

func (a *App) masterByID(id int) (Master, bool) {
	row := a.db.QueryRow(sqlf(`SELECT id,name,service,rating,reviews,price,verified,bio,skills,portfolio FROM masters WHERE id=?`), id)
	var m Master
	var verified int
	var skills, portfolio string
	if err := row.Scan(&m.ID, &m.Name, &m.Service, &m.Rating, &m.Reviews, &m.Price, &verified, &m.Bio, &skills, &portfolio); err != nil {
		return Master{}, false
	}
	m.Verified = verified == 1
	m.Skills = splitList(skills)
	m.Portfolio = splitList(portfolio)
	return m, true
}

func masterMatchesQuery(master Master, query string) bool {
	parts := []string{
		master.Name,
		master.Service,
		master.Price,
		master.Bio,
		strings.Join(master.Skills, " "),
	}
	haystack := strings.ToLower(strings.Join(parts, " "))
	return strings.Contains(haystack, strings.ToLower(query))
}

func (a *App) masterReviews(masterID int) []MasterReview {
	rows, err := a.db.Query(sqlf(`SELECT id,master_id,author_name,rating,text,created_at FROM master_reviews WHERE master_id=? ORDER BY created_at DESC,id DESC`), masterID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []MasterReview
	for rows.Next() {
		var item MasterReview
		var created string
		if rows.Scan(&item.ID, &item.MasterID, &item.AuthorName, &item.Rating, &item.Text, &created) == nil {
			item.CreatedAt = relativeTime(created)
			items = append(items, item)
		}
	}
	return items
}
