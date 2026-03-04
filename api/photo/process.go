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
	"github.com/rwcarlsen/goexif/exif"
	"golang.org/x/image/draw"
)

const (
	maxDimension = 2048
	jpegQuality  = 85
)

// Process reads an image file, applies EXIF orientation, downscales it to fit
// within maxDimension on the longest side, and encodes it as JPEG via jpegli.
// Returns the path to the output file (.jpg extension).
func Process(inputPath string) (string, error) {
	img, err := decodeImage(inputPath)
	if err != nil {
		return "", fmt.Errorf("decoding image %s: %w", inputPath, err)
	}

	// Apply EXIF orientation for JPEG files (HEIC handles this internally).
	ext := strings.ToLower(filepath.Ext(inputPath))
	if ext == ".jpg" || ext == ".jpeg" {
		orientation := readOrientation(inputPath)
		img = applyOrientation(img, orientation)
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

// readOrientation extracts the EXIF orientation tag from a file.
// Returns 1 (normal) if the tag cannot be read.
func readOrientation(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 1
	}
	defer f.Close()

	x, err := exif.Decode(f)
	if err != nil {
		return 1
	}

	tag, err := x.Get(exif.Orientation)
	if err != nil {
		return 1
	}

	v, err := tag.Int(0)
	if err != nil {
		return 1
	}

	return v
}

// applyOrientation transforms an image according to its EXIF orientation value.
//
//	1: Normal
//	2: Flipped horizontally
//	3: Rotated 180°
//	4: Flipped vertically
//	5: Transposed (flip horizontal + rotate 270° CW)
//	6: Rotated 90° CW (common for portrait photos)
//	7: Transverse (flip horizontal + rotate 90° CW)
//	8: Rotated 270° CW
func applyOrientation(img image.Image, orientation int) image.Image {
	if orientation <= 1 || orientation > 8 {
		return img
	}

	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()

	switch orientation {
	case 2:
		return flipH(img, w, h)
	case 3:
		return rotate180(img, w, h)
	case 4:
		return flipV(img, w, h)
	case 5:
		return transpose(img, w, h)
	case 6:
		return rotate90CW(img, w, h)
	case 7:
		return transverse(img, w, h)
	case 8:
		return rotate270CW(img, w, h)
	default:
		return img
	}
}

func rotate90CW(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(h-1-y, x, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func rotate270CW(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(y, w-1-x, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func rotate180(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(w-1-x, h-1-y, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func flipH(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(w-1-x, y, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func flipV(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(x, h-1-y, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func transpose(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(y, x, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
}

func transverse(img image.Image, w, h int) image.Image {
	dst := image.NewRGBA(image.Rect(0, 0, h, w))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dst.Set(h-1-y, w-1-x, img.At(x+img.Bounds().Min.X, y+img.Bounds().Min.Y))
		}
	}
	return dst
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
