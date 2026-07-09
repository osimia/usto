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

func (a *App) verificationStatusHandler(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	status, err := a.verificationStatus()
	if err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, status)
}

func (a *App) verificationDocumentsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		status, err := a.verificationStatus()
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, map[string][]VerificationDocument{"documents": status.Documents})
	case http.MethodPost:
		var req UploadVerificationDocumentRequest
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		doc, err := a.uploadVerificationDocument(req)
		if err != nil {
			badRequest(w, err)
			return
		}
		status, _ := a.verificationStatus()
		writeJSON(w, VerificationDocumentResponse{Document: doc, Status: status.Status})
	default:
		writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

func (a *App) verifyMaster(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	if _, err := a.db.Exec(`UPDATE profiles SET is_verified=1 WHERE role='master'`); err != nil {
		serverError(w, err)
		return
	}
	if _, err := a.db.Exec(`UPDATE verification_documents SET status='approved', reviewed_at=CURRENT_TIMESTAMP WHERE master_profile_id=(SELECT id FROM profiles WHERE role='master' LIMIT 1)`); err != nil {
		serverError(w, err)
		return
	}
	if r.URL.Query().Get("wrap") == "1" {
		status, err := a.verificationStatus()
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, status)
		return
	}
	writeJSON(w, a.snapshot())
}

func (a *App) verificationStatus() (VerificationStatusResponse, error) {
	master, err := a.profile("master")
	if err != nil {
		return VerificationStatusResponse{}, err
	}
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
	}, nil
}

func (a *App) uploadVerificationDocument(req UploadVerificationDocumentRequest) (VerificationDocument, error) {
	documentType := strings.TrimSpace(req.DocumentType)
	fileURL := strings.TrimSpace(req.FileURL)
	if documentType == "" {
		return VerificationDocument{}, errors.New("documentType is required")
	}
	if fileURL == "" {
		return VerificationDocument{}, errors.New("fileUrl is required")
	}
	master, err := a.profile("master")
	if err != nil {
		return VerificationDocument{}, err
	}
	res, err := a.db.Exec(`INSERT INTO verification_documents(master_profile_id,document_type,file_url,status) VALUES(?,?,?,?)`,
		master.ID, documentType, fileURL, "pending")
	if err != nil {
		return VerificationDocument{}, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return VerificationDocument{}, err
	}
	if _, err := a.db.Exec(`UPDATE profiles SET is_verified=0 WHERE id=?`, master.ID); err != nil {
		return VerificationDocument{}, err
	}
	doc, ok := a.verificationDocumentByID(int(id), master.ID)
	if !ok {
		return VerificationDocument{}, errors.New("created document not found")
	}
	return doc, nil
}

func (a *App) verificationDocuments(masterProfileID int) []VerificationDocument {
	rows, err := a.db.Query(`SELECT id,master_profile_id,document_type,file_url,status,rejection_reason,created_at,COALESCE(reviewed_at,'')
		FROM verification_documents WHERE master_profile_id=? ORDER BY created_at DESC,id DESC`, masterProfileID)
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
