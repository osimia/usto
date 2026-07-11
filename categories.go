package main

import (
	"net/http"
	"strconv"
	"strings"
)

type CategoriesResponse struct {
	Categories []Category `json:"categories"`
}

type CategoryResponse struct {
	Category Category `json:"category"`
	Services []string `json:"services"`
}

func (a *App) categoriesHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	if r.URL.Query().Get("wrap") == "1" {
		writeJSON(w, CategoriesResponse{Categories: a.categories()})
		return
	}
	writeJSON(w, a.categories())
}

func (a *App) categoryDetailHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	rest := strings.TrimPrefix(r.URL.Path, "/api/categories/")
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeError(w, http.StatusNotFound, "category_not_found", "category not found")
		return
	}
	id, err := strconv.Atoi(parts[0])
	if err != nil || id <= 0 {
		writeError(w, http.StatusNotFound, "category_not_found", "category not found")
		return
	}
	category, ok := a.categoryByID(id)
	if !ok {
		writeError(w, http.StatusNotFound, "category_not_found", "category not found")
		return
	}
	if len(parts) == 2 && parts[1] == "services" {
		writeJSON(w, map[string][]string{"services": a.servicesForCategory(category.ID)})
		return
	}
	writeJSON(w, CategoryResponse{Category: category, Services: a.servicesForCategory(category.ID)})
}

func (a *App) categoryByID(id int) (Category, bool) {
	for _, category := range a.categories() {
		if category.ID == id {
			return category, true
		}
	}
	return Category{}, false
}

func (a *App) servicesForCategory(categoryID int) []string {
	rows, err := a.db.Query(sqlf(`SELECT name FROM services WHERE category_id=? ORDER BY id`), categoryID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []string
	for rows.Next() {
		var name string
		if rows.Scan(&name) == nil {
			items = append(items, name)
		}
	}
	return items
}
