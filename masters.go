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
	if !method(w, r, http.MethodGet) {
		return
	}
	idText := strings.TrimPrefix(r.URL.Path, "/api/masters/")
	idText = strings.Trim(idText, "/")
	id, err := strconv.Atoi(idText)
	if err != nil || id <= 0 {
		writeError(w, http.StatusNotFound, "master_not_found", "master not found")
		return
	}
	master, ok := a.masterByID(id)
	if !ok {
		writeError(w, http.StatusNotFound, "master_not_found", "master not found")
		return
	}
	writeJSON(w, MasterResponse{Master: master})
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
	items := a.masters()
	filtered := make([]Master, 0, len(items))
	for _, item := range items {
		if filters.Service != "" && !strings.EqualFold(item.Service, filters.Service) {
			continue
		}
		if filters.Query != "" && !masterMatchesQuery(item, filters.Query) {
			continue
		}
		filtered = append(filtered, item)
		if len(filtered) >= filters.Limit {
			break
		}
	}
	return filtered
}

func (a *App) masterByID(id int) (Master, bool) {
	for _, master := range a.masters() {
		if master.ID == id {
			return master, true
		}
	}
	return Master{}, false
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
