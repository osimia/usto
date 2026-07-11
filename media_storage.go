package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
)

type storedOrderImage struct {
	contentHash string
	thumbPath   string
	mediumPath  string
	fullPath    string
	width       int
	height      int
}

func contentHash(raw []byte) string {
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

func orderImagePaths(hash string) (thumb, medium, full string) {
	dir := filepath.ToSlash(filepath.Join("orders", hash[:2], hash[2:4]))
	return filepath.ToSlash(filepath.Join(dir, hash+"_thumb.jpg")),
		filepath.ToSlash(filepath.Join(dir, hash+"_medium.jpg")),
		filepath.ToSlash(filepath.Join(dir, hash+"_full.jpg"))
}

func (a *App) storeOrderImage(raw []byte) (storedOrderImage, error) {
	hash := contentHash(raw)
	thumbPath, mediumPath, fullPath := orderImagePaths(hash)
	fullDiskPath := filepath.Join(a.cfg.MediaDir, filepath.FromSlash(fullPath))

	if filesExist(
		filepath.Join(a.cfg.MediaDir, filepath.FromSlash(thumbPath)),
		filepath.Join(a.cfg.MediaDir, filepath.FromSlash(mediumPath)),
		fullDiskPath,
	) {
		img, width, height, err := decodeUploadedImage(raw)
		if err != nil {
			return storedOrderImage{}, err
		}
		_ = img
		return storedOrderImage{
			contentHash: hash,
			thumbPath:   thumbPath,
			mediumPath:  mediumPath,
			fullPath:    fullPath,
			width:       width,
			height:      height,
		}, nil
	}

	img, width, height, err := decodeUploadedImage(raw)
	if err != nil {
		return storedOrderImage{}, err
	}
	thumb, err := resizeAndEncodeJPEG(img, 320, 75)
	if err != nil {
		return storedOrderImage{}, err
	}
	medium, err := resizeAndEncodeJPEG(img, 800, 82)
	if err != nil {
		return storedOrderImage{}, err
	}
	full, err := resizeAndEncodeJPEG(img, 1600, 82)
	if err != nil {
		return storedOrderImage{}, err
	}

	if err := writeMediaFile(filepath.Join(a.cfg.MediaDir, filepath.FromSlash(thumbPath)), thumb.data); err != nil {
		return storedOrderImage{}, err
	}
	if err := writeMediaFile(filepath.Join(a.cfg.MediaDir, filepath.FromSlash(mediumPath)), medium.data); err != nil {
		return storedOrderImage{}, err
	}
	if err := writeMediaFile(fullDiskPath, full.data); err != nil {
		return storedOrderImage{}, err
	}

	return storedOrderImage{
		contentHash: hash,
		thumbPath:   thumbPath,
		mediumPath:  mediumPath,
		fullPath:    fullPath,
		width:       width,
		height:      height,
	}, nil
}

func filesExist(paths ...string) bool {
	for _, path := range paths {
		if info, err := os.Stat(path); err != nil || info.IsDir() {
			return false
		}
	}
	return true
}

func writeMediaFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
