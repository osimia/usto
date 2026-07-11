package main

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/jpeg"
	_ "image/png"
)

type encodedImage struct {
	data   []byte
	width  int
	height int
}

func decodeUploadedImage(raw []byte) (image.Image, int, int, error) {
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, 0, 0, err
	}
	bounds := img.Bounds()
	return img, bounds.Dx(), bounds.Dy(), nil
}

func resizeAndEncodeJPEG(img image.Image, maxSide, quality int) (encodedImage, error) {
	resized := resizeToMaxSide(img, maxSide)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, resized, &jpeg.Options{Quality: quality}); err != nil {
		return encodedImage{}, err
	}
	bounds := resized.Bounds()
	return encodedImage{
		data:   buf.Bytes(),
		width:  bounds.Dx(),
		height: bounds.Dy(),
	}, nil
}

func resizeToMaxSide(src image.Image, maxSide int) *image.RGBA {
	bounds := src.Bounds()
	srcW := bounds.Dx()
	srcH := bounds.Dy()
	dstW, dstH := srcW, srcH
	if maxSide > 0 && (srcW > maxSide || srcH > maxSide) {
		if srcW >= srcH {
			dstW = maxSide
			dstH = max(1, srcH*maxSide/srcW)
		} else {
			dstH = maxSide
			dstW = max(1, srcW*maxSide/srcH)
		}
	}

	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	for y := 0; y < dstH; y++ {
		srcY := bounds.Min.Y + y*srcH/dstH
		for x := 0; x < dstW; x++ {
			srcX := bounds.Min.X + x*srcW/dstW
			dst.Set(x, y, flattenAlpha(src.At(srcX, srcY)))
		}
	}
	return dst
}

func flattenAlpha(c color.Color) color.Color {
	r, g, b, a := c.RGBA()
	if a == 0xffff {
		return c
	}
	if a == 0 {
		return color.White
	}
	const white = 0xffff
	r = (r*a + white*(0xffff-a)) / 0xffff
	g = (g*a + white*(0xffff-a)) / 0xffff
	b = (b*a + white*(0xffff-a)) / 0xffff
	return color.RGBA64{R: uint16(r), G: uint16(g), B: uint16(b), A: 0xffff}
}
