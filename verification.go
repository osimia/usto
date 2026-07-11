package main

import (
	"errors"
	"net/http"
	"strings"
)

type VerificationDocument struct {
	ID              int    `json:"id"`
	MasterProfileID int    `json:"masterProfileId"`
	DocumentType    string `json:"documentType"`
	FileURL         string `json:"fileUrl"`
	Status          string `json:"status"`
	RejectionReason string `json:"rejectionReason,omitempty"`
	CreatedAt       string `json:"createdAt"`
	ReviewedAt      string `json:"reviewedAt,omitempty"`
}

type VerificationStatusResponse struct {
	Status    string                 `json:"status"`
	Verified  bool                   `json:"verified"`
	Documents []VerificationDocument `json:"documents"`
}

type UploadVerificationDocumentRequest struct {
	DocumentType string `json:"documentType"`
	FileURL      string `json:"fileUrl"`
}

type VerificationDocumentResponse struct {
	Document VerificationDocument `json:"document"`
	Status   string               `json:"status"`
}

// verificationMasterProfile resolves the calling master's own profile from
// their JWT — verification is a master-only concept.
func (a *App) verificationMasterProfile(w http.ResponseWriter, r *http.Request) (Profile, bool) {
	_, profile, ok := a.currentUserProfile(w, r)
	if !ok {
		return Profile{}, false
	}
	if profile.Role != "master" {
		writeError(w, http.StatusForbidden, "forbidden", "verification is only available to masters")
		return Profile{}, false
	}
	return profile, true
}

func (a *App) verificationStatusHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	master, ok := a.verificationMasterProfile(w, r)
	if !ok {
		return
	}
	writeJSON(w, a.verificationStatus(master))
}

func (a *App) verificationDocumentsHandler(w http.ResponseWriter, r *http.Request) {
	master, ok := a.verificationMasterProfile(w, r)
	if !ok {
		return
	}
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, map[string][]VerificationDocument{"documents": a.verificationStatus(master).Documents})
	case http.MethodPost:
		var req UploadVerificationDocumentRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		doc, err := a.uploadVerificationDocument(master.ID, req)
		if err != nil {
			badRequest(w, err)
			return
		}
		status := a.verificationStatus(master)
		writeJSON(w, VerificationDocumentResponse{Document: doc, Status: status.Status})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

// verifyMaster is the current self-service "dev-confirm" approval action.
// Scoping it to the caller's own profile (instead of the singleton demo
// master) is a Priority-1 identity fix; whether self-approval should exist at
// all is a separate, larger question for a future admin/moderation flow.
func (a *App) verifyMaster(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	master, ok := a.verificationMasterProfile(w, r)
	if !ok {
		return
	}
	if _, err := a.db.Exec(sqlf(`UPDATE profiles SET is_verified=1 WHERE id=?`), master.ID); err != nil {
		serverError(w, err)
		return
	}
	if _, err := a.db.Exec(sqlf(`UPDATE verification_documents SET status='approved', reviewed_at=CURRENT_TIMESTAMP WHERE master_profile_id=?`), master.ID); err != nil {
		serverError(w, err)
		return
	}
	master.IsVerified = true
	writeJSON(w, a.verificationStatus(master))
}

func (a *App) verificationStatus(master Profile) VerificationStatusResponse {
	documents := a.verificationDocuments(master.ID)
	status := "new"
	if master.IsVerified {
		status = "verified"
	} else if len(documents) > 0 {
		status = "pending_verification"
	}
	return VerificationStatusResponse{
		Status:    status,
		Verified:  master.IsVerified,
		Documents: documents,
	}
}

func (a *App) uploadVerificationDocument(masterProfileID int, req UploadVerificationDocumentRequest) (VerificationDocument, error) {
	documentType := strings.TrimSpace(req.DocumentType)
	fileURL := strings.TrimSpace(req.FileURL)
	if documentType == "" {
		return VerificationDocument{}, errors.New("documentType is required")
	}
	if fileURL == "" {
		return VerificationDocument{}, errors.New("fileUrl is required")
	}
	id, err := insertID(a.db, `INSERT INTO verification_documents(master_profile_id,document_type,file_url,status) VALUES(?,?,?,?)`,
		masterProfileID, documentType, fileURL, "pending")
	if err != nil {
		return VerificationDocument{}, err
	}
	if _, err := a.db.Exec(sqlf(`UPDATE profiles SET is_verified=0 WHERE id=?`), masterProfileID); err != nil {
		return VerificationDocument{}, err
	}
	doc, ok := a.verificationDocumentByID(id, masterProfileID)
	if !ok {
		return VerificationDocument{}, errors.New("created document not found")
	}
	return doc, nil
}

func (a *App) verificationDocuments(masterProfileID int) []VerificationDocument {
	query := `SELECT id,master_profile_id,document_type,file_url,status,rejection_reason,created_at,COALESCE(reviewed_at,'')
		FROM verification_documents WHERE master_profile_id=? ORDER BY created_at DESC,id DESC`
	if activeSQLDriver == "postgres" {
		query = `SELECT id,master_profile_id,document_type,file_url,status,rejection_reason,created_at,COALESCE(reviewed_at::text,'')
			FROM verification_documents WHERE master_profile_id=? ORDER BY created_at DESC,id DESC`
	}
	rows, err := a.db.Query(sqlf(query), masterProfileID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []VerificationDocument
	for rows.Next() {
		var item VerificationDocument
		var created string
		if rows.Scan(&item.ID, &item.MasterProfileID, &item.DocumentType, &item.FileURL, &item.Status, &item.RejectionReason, &created, &item.ReviewedAt) == nil {
			item.CreatedAt = relativeTime(created)
			items = append(items, item)
		}
	}
	return items
}

func (a *App) verificationDocumentByID(id, masterProfileID int) (VerificationDocument, bool) {
	for _, item := range a.verificationDocuments(masterProfileID) {
		if item.ID == id {
			return item, true
		}
	}
	return VerificationDocument{}, false
}
