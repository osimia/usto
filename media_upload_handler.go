package main

import (
	"bytes"
	"errors"
	"image"
	"io"
	"net/http"
)

const maxUploadBytes = 10 << 20

type OrderPhotoResponse struct {
	Photo OrderPhoto `json:"photo"`
	Order Order      `json:"order"`
}

func (a *App) orderPhotoUploadHandler(w http.ResponseWriter, r *http.Request, orderID int) {
	if !method(w, r, http.MethodPost) {
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
		writeError(w, http.StatusForbidden, "forbidden", "only the order's own customer can upload photos")
		return
	}

	raw, err := uploadedImageBytes(w, r)
	if err != nil {
		if errors.Is(err, errUploadTooLarge) {
			writeError(w, http.StatusRequestEntityTooLarge, "file_too_large", "file is too large")
			return
		}
		badRequest(w, err)
		return
	}
	stored, err := a.storeOrderImage(raw)
	if err != nil {
		badRequest(w, errors.New("file must be a valid JPEG or PNG image"))
		return
	}
	photo, err := a.attachOrderPhoto(orderID, stored)
	if err != nil {
		serverError(w, err)
		return
	}
	updated, _ := a.orderByID(orderID)
	writeJSON(w, OrderPhotoResponse{Photo: photo, Order: updated})
}

var errUploadTooLarge = errors.New("upload too large")

func uploadedImageBytes(w http.ResponseWriter, r *http.Request) ([]byte, error) {
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
	file, _, err := r.FormFile("file")
	if err != nil {
		if err.Error() == "http: request body too large" {
			return nil, errUploadTooLarge
		}
		return nil, errors.New("multipart field file is required")
	}
	defer file.Close()

	raw, err := io.ReadAll(io.LimitReader(file, maxUploadBytes+1))
	if err != nil {
		return nil, err
	}
	if len(raw) > maxUploadBytes {
		return nil, errUploadTooLarge
	}
	contentType := http.DetectContentType(raw[:min(512, len(raw))])
	if contentType != "image/jpeg" && contentType != "image/png" {
		return nil, errors.New("file must be a JPEG or PNG image")
	}
	if _, _, _, err := imageConfig(raw); err != nil {
		return nil, errors.New("file must be a valid JPEG or PNG image")
	}
	return raw, nil
}

func imageConfig(raw []byte) (string, int, int, error) {
	cfg, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return "", 0, 0, err
	}
	if format != "jpeg" && format != "png" {
		return "", 0, 0, errors.New("unsupported image format")
	}
	return format, cfg.Width, cfg.Height, nil
}

func (a *App) attachOrderPhoto(orderID int, stored storedOrderImage) (OrderPhoto, error) {
	var sortOrder int
	_ = a.db.QueryRow(sqlf(`SELECT COALESCE(MAX(sort_order), -1) + 1 FROM order_photos WHERE order_id=?`), orderID).Scan(&sortOrder)
	id, err := insertID(a.db, `INSERT INTO order_photos(order_id,content_hash,thumb_path,medium_path,full_path,width,height,blurhash,sort_order) VALUES(?,?,?,?,?,?,?,?,?)`,
		orderID, stored.contentHash, stored.thumbPath, stored.mediumPath, stored.fullPath, stored.width, stored.height, "", sortOrder)
	if err != nil {
		return OrderPhoto{}, err
	}
	photos := orderPhotosFor(a.db, []int{orderID})[orderID]
	for _, photo := range photos {
		if photo.ID == id {
			return photo, nil
		}
	}
	return OrderPhoto{}, errors.New("created photo not found")
}
