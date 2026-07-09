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
		writeJSON(w, map[string][]string{"services": servicesForCategory(category.Name)})
		return
	}
	writeJSON(w, CategoryResponse{Category: category, Services: servicesForCategory(category.Name)})
}

func (a *App) categoryByID(id int) (Category, bool) {
	for _, category := range a.categories() {
		if category.ID == id {
			return category, true
		}
	}
	return Category{}, false
}

func servicesForCategory(name string) []string {
	switch name {
	case "Сантехника":
		return []string{"Краны", "Трубы", "Бойлеры", "Засоры"}
	case "Электрика":
		return []string{"Розетки", "Проводка", "Освещение", "Щитки"}
	case "Ремонт":
		return []string{"Плитка", "Покраска", "Штукатурка", "Косметический ремонт"}
	case "Мебель":
		return []string{"Сборка", "Ремонт", "Установка", "Разборка"}
	case "Уборка":
		return []string{"Квартира", "Офис", "После ремонта", "Генеральная"}
	default:
		return []string{name}
	}
}
