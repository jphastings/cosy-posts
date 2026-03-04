package photo

import (
	"bytes"
	"encoding/binary"
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
// All original EXIF metadata is preserved in the output (with orientation
// reset to 1 since the pixels are now correctly oriented).
// Returns the path to the output file (.jpg extension).
func Process(inputPath string) (string, error) {
	img, err := decodeImage(inputPath)
	if err != nil {
		return "", fmt.Errorf("decoding image %s: %w", inputPath, err)
	}

	// Extract EXIF from source before any processing.
	exifData := extractExif(inputPath)

	// Apply EXIF orientation (HEIC handles this internally in the decoder).
	ext := strings.ToLower(filepath.Ext(inputPath))
	if ext == ".jpg" || ext == ".jpeg" {
		orientation := readOrientation(inputPath)
		if orientation > 1 {
			img = applyOrientation(img, orientation)
			// Reset orientation to 1 in the EXIF data since pixels are now correct.
			exifData = patchExifOrientation(exifData)
		}
	}

	img = downscale(img, maxDimension)

	// Output path: same directory, same base name, .jpg extension.
	dir := filepath.Dir(inputPath)
	base := strings.TrimSuffix(filepath.Base(inputPath), filepath.Ext(inputPath))
	outPath := filepath.Join(dir, base+".jpg")

	if err := encodeJPEGWithExif(outPath, img, exifData); err != nil {
		return "", fmt.Errorf("encoding image %s: %w", outPath, err)
	}

	return outPath, nil
}

// extractExif reads raw EXIF bytes from a file.
// Returns nil if EXIF cannot be extracted.
func extractExif(path string) []byte {
	ext := strings.ToLower(filepath.Ext(path))

	switch ext {
	case ".heic", ".heif":
		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()
		data, err := goheif.ExtractExif(f)
		if err != nil {
			return nil
		}
		return data

	case ".jpg", ".jpeg":
		return extractJPEGExif(path)

	default:
		return nil
	}
}

// extractJPEGExif reads the raw EXIF payload (the data inside the APP1
// segment, after the EXIF header) from a JPEG file.
// Returns nil if no EXIF is found.
func extractJPEGExif(path string) []byte {
	data, err := os.ReadFile(path)
	if err != nil || len(data) < 4 {
		return nil
	}

	// Must start with SOI (FF D8).
	if data[0] != 0xFF || data[1] != 0xD8 {
		return nil
	}

	offset := 2
	for offset+4 < len(data) {
		if data[offset] != 0xFF {
			break
		}
		marker := data[offset+1]
		// APP1 = 0xE1
		if marker == 0xE1 {
			segLen := int(binary.BigEndian.Uint16(data[offset+2 : offset+4]))
			segEnd := offset + 2 + segLen
			if segEnd > len(data) {
				break
			}
			// The segment payload starts after the 2-byte length field.
			payload := data[offset+4 : segEnd]
			// Check for "Exif\0\0" header.
			if len(payload) > 6 && string(payload[:4]) == "Exif" {
				// Return just the TIFF data (after "Exif\0\0").
				return payload[6:]
			}
			// Might be XMP in APP1, keep scanning.
		}

		// Skip this segment.
		segLen := int(binary.BigEndian.Uint16(data[offset+2 : offset+4]))
		offset += 2 + segLen

		// Stop if we hit SOS or image data.
		if marker == 0xDA {
			break
		}
	}

	return nil
}

// patchExifOrientation sets the orientation tag to 1 (Normal) in raw TIFF/EXIF
// data. This is needed because we've already rotated the pixels.
func patchExifOrientation(tiffData []byte) []byte {
	if len(tiffData) < 8 {
		return tiffData
	}

	// Make a copy so we don't modify the original.
	data := make([]byte, len(tiffData))
	copy(data, tiffData)

	// Determine byte order from the TIFF header.
	var bo binary.ByteOrder
	switch string(data[:2]) {
	case "II":
		bo = binary.LittleEndian
	case "MM":
		bo = binary.BigEndian
	default:
		return data
	}

	// Walk IFD0 to find the orientation tag (0x0112).
	ifdOffset := int(bo.Uint32(data[4:8]))
	if ifdOffset+2 > len(data) {
		return data
	}

	entryCount := int(bo.Uint16(data[ifdOffset : ifdOffset+2]))
	for i := 0; i < entryCount; i++ {
		entryStart := ifdOffset + 2 + i*12
		if entryStart+12 > len(data) {
			break
		}
		tag := bo.Uint16(data[entryStart : entryStart+2])
		if tag == 0x0112 { // Orientation
			// Type is SHORT (3), count is 1. Value is in bytes 8-9 of the entry.
			bo.PutUint16(data[entryStart+8:entryStart+10], 1)
			break
		}
	}

	return data
}

// encodeJPEGWithExif encodes an image as JPEG via jpegli, then splices
// the provided EXIF data (raw TIFF bytes) into the output file as an APP1
// segment.
func encodeJPEGWithExif(path string, img image.Image, tiffData []byte) error {
	// First, encode to a buffer.
	var buf bytes.Buffer
	opts := &jpegli.EncodingOptions{
		Quality: jpegQuality,
	}
	if err := jpegli.Encode(&buf, img, opts); err != nil {
		return err
	}

	jpegBytes := buf.Bytes()

	// If no EXIF data, just write the encoded JPEG directly.
	if len(tiffData) == 0 {
		return os.WriteFile(path, jpegBytes, 0644)
	}

	// Build the APP1 segment: marker + length + "Exif\0\0" + TIFF data.
	exifHeader := []byte("Exif\x00\x00")
	app1Payload := append(exifHeader, tiffData...)
	app1Len := uint16(len(app1Payload) + 2) // +2 for the length field itself

	var out bytes.Buffer
	// Write SOI from the encoded JPEG.
	out.Write(jpegBytes[:2]) // FF D8

	// Write our APP1 segment.
	out.WriteByte(0xFF)
	out.WriteByte(0xE1)
	binary.Write(&out, binary.BigEndian, app1Len)
	out.Write(app1Payload)

	// Write the rest of the encoded JPEG (everything after SOI).
	out.Write(jpegBytes[2:])

	return os.WriteFile(path, out.Bytes(), 0644)
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

func decodeHEIC(r io.Reader) (image.Image, error) {
	img, err := goheif.Decode(r)
	if err != nil {
		return nil, fmt.Errorf("decoding HEIC: %w", err)
	}
	return img, nil
}

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
