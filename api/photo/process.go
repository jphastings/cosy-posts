package photo

import (
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/adrium/goheif"
	"github.com/gen2brain/jpegli"
	"golang.org/x/image/draw"
)

const (
	maxDimension = 2048
	jpegQuality  = 85
)

// Process reads an image file, downscales it to fit within maxDimension on
// the longest side, and encodes it as JPEG via jpegli. It returns the path
// to the output file. The output filename is the original name with a .jpg
// extension.
func Process(inputPath string) (string, error) {
	img, err := decodeImage(inputPath)
	if err != nil {
		return "", fmt.Errorf("decoding image %s: %w", inputPath, err)
	}

	img = downscale(img, maxDimension)

	// Output path: same directory, same base name, .jpg extension.
	dir := filepath.Dir(inputPath)
	base := strings.TrimSuffix(filepath.Base(inputPath), filepath.Ext(inputPath))
	outPath := filepath.Join(dir, base+".jpg")

	if err := encodeJPEG(outPath, img); err != nil {
		return "", fmt.Errorf("encoding image %s: %w", outPath, err)
	}

	return outPath, nil
}

// decodeImage opens and decodes an image file based on its extension.
// Supports HEIC, JPEG, and PNG.
func decodeImage(path string) (image.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".heic", ".heif":
		return decodeHEIC(f)
	case ".jpg", ".jpeg":
		return jpeg.Decode(f)
	case ".png":
		return png.Decode(f)
	default:
		return nil, fmt.Errorf("unsupported image format: %s", ext)
	}
}

// decodeHEIC decodes a HEIC/HEIF image.
func decodeHEIC(r io.Reader) (image.Image, error) {
	img, err := goheif.Decode(r)
	if err != nil {
		return nil, fmt.Errorf("decoding HEIC: %w", err)
	}
	return img, nil
}

// downscale resizes an image so its longest side is at most maxPx,
// maintaining aspect ratio. Uses CatmullRom for high-quality resampling.
// If the image is already within bounds, it is returned unchanged.
func downscale(img image.Image, maxPx int) image.Image {
	bounds := img.Bounds()
	w := bounds.Dx()
	h := bounds.Dy()

	// No scaling needed.
	if w <= maxPx && h <= maxPx {
		return img
	}

	var newW, newH int
	if w >= h {
		newW = maxPx
		newH = h * maxPx / w
	} else {
		newH = maxPx
		newW = w * maxPx / h
	}

	dst := image.NewRGBA(image.Rect(0, 0, newW, newH))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, bounds, draw.Over, nil)
	return dst
}

// encodeJPEG writes an image to disk as JPEG using jpegli.
func encodeJPEG(path string, img image.Image) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	opts := &jpegli.EncodingOptions{
		Quality: jpegQuality,
	}
	return jpegli.Encode(f, img, opts)
}

// IsImage returns true if the filename has an image extension we process.
func IsImage(filename string) bool {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".heic", ".heif", ".jpg", ".jpeg", ".png":
		return true
	default:
		return false
	}
}
