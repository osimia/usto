package main

import (
	"database/sql"
	"errors"
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

// masterSelectColumns is shared by queryMasters/masterByID: verified is
// COALESCE(p.is_verified, m.verified) so a master linked to a real profile
// (m.profile_id set) shows the live verification status that
// verification.go actually manages, while seed/demo masters with no linked
// profile keep falling back to their static seed value. This is a read-time
// join rather than a write-time sync so there's exactly one place that can
// drift, not one per call site that touches is_verified.
const masterSelectColumns = `m.id,m.name,m.service,m.rating,m.reviews,m.price,
	COALESCE(p.is_verified, m.verified) AS verified,m.bio,m.skills,m.portfolio`

const masterSelectFrom = `FROM masters m LEFT JOIN profiles p ON p.id = m.profile_id`

// queryMasters pushes the service filter into SQL and caps with SQL LIMIT;
// the free-text query filter still runs in Go, over a SQL-bounded window.
func (a *App) queryMasters(filters MasterFilters) []Master {
	query := `SELECT ` + masterSelectColumns + ` ` + masterSelectFrom
	var conditions []string
	var args []any
	if filters.Service != "" {
		conditions = append(conditions, equalityCI("m.service"))
		args = append(args, filters.Service)
	}
	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}
	query += " ORDER BY m.rating DESC"

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
	row := a.db.QueryRow(sqlf(`SELECT `+masterSelectColumns+` `+masterSelectFrom+` WHERE m.id=?`), id)
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

// masterIDForProfile resolves a real master's directory row by their profile
// ID, so responses/wallet code can attribute actions to the actual logged-in
// master instead of a hardcoded demo ID.
func (a *App) masterIDForProfile(profileID int) (int, bool) {
	var id int
	if err := a.db.QueryRow(sqlf(`SELECT id FROM masters WHERE profile_id=?`), profileID).Scan(&id); err != nil {
		return 0, false
	}
	return id, true
}

// profileIDForMaster is the inverse of masterIDForProfile: given a
// masters-directory row, find the profile it's linked to (if any — seed/demo
// masters predating this link may have none).
func (a *App) profileIDForMaster(masterID int) (int, bool) {
	var profileID sql.NullInt64
	if err := a.db.QueryRow(sqlf(`SELECT profile_id FROM masters WHERE id=?`), masterID).Scan(&profileID); err != nil || !profileID.Valid {
		return 0, false
	}
	return int(profileID.Int64), true
}

// ensureMasterDirectoryEntry creates a blank, editable-later directory row
// for a newly-registered master profile (or returns the existing one), so
// every real master has somewhere for responses to attribute to and can
// eventually appear in search once they fill in their details.
func (a *App) ensureMasterDirectoryEntry(profileID int) (int, error) {
	if id, ok := a.masterIDForProfile(profileID); ok {
		return id, nil
	}
	return insertID(a.db, `INSERT INTO masters(name,service,rating,reviews,price,verified,bio,skills,portfolio,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?)`,
		"", "", 0, 0, "", 0, "", "", "", profileID)
}

type UpdateMasterListingRequest struct {
	Name      string   `json:"name"`
	Service   string   `json:"service"`
	Bio       string   `json:"bio"`
	Skills    []string `json:"skills"`
	Portfolio []string `json:"portfolio"`
}

// myMasterListingProfile resolves the caller's own profile from their JWT —
// editing a directory listing is a master-only concept, same pattern as
// walletProfile/verificationMasterProfile.
func (a *App) myMasterListingProfile(w http.ResponseWriter, r *http.Request) (Profile, bool) {
	_, profile, ok := a.currentUserProfile(w, r)
	if !ok {
		return Profile{}, false
	}
	if profile.Role != "master" {
		writeError(w, http.StatusForbidden, "forbidden", "only masters have a directory listing")
		return Profile{}, false
	}
	return profile, true
}

func (a *App) myMasterListingHandler(w http.ResponseWriter, r *http.Request) {
	profile, ok := a.myMasterListingProfile(w, r)
	if !ok {
		return
	}
	switch r.Method {
	case http.MethodGet:
		a.writeMyMasterListing(w, profile)
	case http.MethodPatch:
		var req UpdateMasterListingRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		if err := a.updateMyMasterListing(profile.ID, req); err != nil {
			badRequest(w, err)
			return
		}
		a.writeMyMasterListing(w, profile)
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) writeMyMasterListing(w http.ResponseWriter, profile Profile) {
	// ensureMasterDirectoryEntry also lazily backfills a listing for masters
	// registered before masters.profile_id existed, so GET/PATCH /masters/me
	// is robust for pre-existing accounts too, not just newly-registered ones.
	masterID, err := a.ensureMasterDirectoryEntry(profile.ID)
	if err != nil {
		serverError(w, err)
		return
	}
	master, ok := a.masterByID(masterID)
	if !ok {
		serverError(w, errors.New("master listing not found after ensure"))
		return
	}
	writeJSON(w, MasterResponse{Master: master})
}

func (a *App) updateMyMasterListing(profileID int, req UpdateMasterListingRequest) error {
	name := strings.TrimSpace(req.Name)
	service := strings.TrimSpace(req.Service)
	if name == "" {
		return errors.New("name is required")
	}
	if service == "" {
		return errors.New("service is required")
	}
	masterID, err := a.ensureMasterDirectoryEntry(profileID)
	if err != nil {
		return err
	}
	_, err = a.db.Exec(sqlf(`UPDATE masters SET name=?, service=?, bio=?, skills=?, portfolio=? WHERE id=?`),
		name, service, strings.TrimSpace(req.Bio), joinList(req.Skills), joinList(req.Portfolio), masterID)
	return err
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
