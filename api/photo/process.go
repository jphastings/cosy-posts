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

	"github.com/adrium/goheif/heif"
	"github.com/gen2brain/heic"
	"github.com/gen2brain/jpegli"
	"github.com/rwcarlsen/goexif/exif"
	"golang.org/x/image/draw"
)

const (
	maxDimension = 2048
	jpegQuality  = 85
)

// imageFormat detected by magic bytes.
type imageFormat int

const (
	formatUnknown imageFormat = iota
	formatJPEG
	formatPNG
	formatHEIC
)

// detectFormat reads the first bytes of a file to determine the image format.
func detectFormat(path string) imageFormat {
	f, err := os.Open(path)
	if err != nil {
		return formatUnknown
	}
	defer f.Close()

	header := make([]byte, 12)
	n, _ := f.Read(header)
	if n < 4 {
		return formatUnknown
	}

	// JPEG: FF D8 FF
	if header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
		return formatJPEG
	}

	// PNG: 89 50 4E 47
	if header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 {
		return formatPNG
	}

	// HEIC/HEIF: ftyp box at offset 4
	if n >= 12 && string(header[4:8]) == "ftyp" {
		brand := string(header[8:12])
		switch brand {
		case "heic", "heix", "MiHE", "mif1":
			return formatHEIC
		}
	}

	return formatUnknown
}

// Process reads an image file, applies EXIF orientation, downscales it to fit
// within maxDimension on the longest side, and encodes it as JPEG via jpegli.
// All original EXIF metadata is preserved in the output (with orientation
// reset to 1 since the pixels are now correctly oriented).
// Returns the path to the output file (.jpg extension).
func Process(inputPath string) (string, error) {
	format := detectFormat(inputPath)

	img, err := decodeImage(inputPath, format)
	if err != nil {
		return "", fmt.Errorf("decoding image %s: %w", inputPath, err)
	}

	// Extract EXIF from source before any processing.
	exifData := extractExif(inputPath, format)

	// Apply EXIF orientation for JPEG files (HEIC handles this internally).
	if format == formatJPEG {
		orientation := readOrientation(inputPath)
		if orientation > 1 {
			img = applyOrientation(img, orientation)
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

// extractExif reads raw EXIF bytes (TIFF data) from a file.
// Returns nil if EXIF cannot be extracted.
func extractExif(path string, format imageFormat) []byte {
	switch format {
	case formatHEIC:
		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()
		hf := heif.Open(f)
		data, err := hf.EXIF()
		if err != nil {
			return nil
		}
		return data

	case formatJPEG:
		return extractJPEGExif(path)

	default:
		return nil
	}
}

// extractJPEGExif reads the raw EXIF payload (TIFF bytes) from a JPEG file.
func extractJPEGExif(path string) []byte {
	data, err := os.ReadFile(path)
	if err != nil || len(data) < 4 {
		return nil
	}

	if data[0] != 0xFF || data[1] != 0xD8 {
		return nil
	}

	offset := 2
	for offset+4 < len(data) {
		if data[offset] != 0xFF {
			break
		}
		marker := data[offset+1]
		segLen := int(binary.BigEndian.Uint16(data[offset+2 : offset+4]))

		// APP1 = 0xE1
		if marker == 0xE1 {
			segEnd := offset + 2 + segLen
			if segEnd > len(data) {
				break
			}
			payload := data[offset+4 : segEnd]
			if len(payload) > 6 && string(payload[:4]) == "Exif" {
				return payload[6:]
			}
		}

		offset += 2 + segLen

		// Stop at SOS.
		if marker == 0xDA {
			break
		}
	}

	return nil
}

// patchExifOrientation sets the orientation tag to 1 (Normal) in raw TIFF data.
func patchExifOrientation(tiffData []byte) []byte {
	if len(tiffData) < 8 {
		return tiffData
	}

	data := make([]byte, len(tiffData))
	copy(data, tiffData)

	var bo binary.ByteOrder
	switch string(data[:2]) {
	case "II":
		bo = binary.LittleEndian
	case "MM":
		bo = binary.BigEndian
	default:
		return data
	}

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
		if tag == 0x0112 {
			bo.PutUint16(data[entryStart+8:entryStart+10], 1)
			break
		}
	}

	return data
}

// encodeJPEGWithExif encodes an image as JPEG via jpegli, then splices
// the provided EXIF data into the output file as an APP1 segment.
func encodeJPEGWithExif(path string, img image.Image, tiffData []byte) error {
	var buf bytes.Buffer
	opts := &jpegli.EncodingOptions{
		Quality: jpegQuality,
	}
	if err := jpegli.Encode(&buf, img, opts); err != nil {
		return err
	}

	jpegBytes := buf.Bytes()

	if len(tiffData) == 0 {
		return os.WriteFile(path, jpegBytes, 0644)
	}

	exifHeader := []byte("Exif\x00\x00")
	app1Payload := append(exifHeader, tiffData...)
	app1Len := uint16(len(app1Payload) + 2)

	var out bytes.Buffer
	out.Write(jpegBytes[:2]) // FF D8

	out.WriteByte(0xFF)
	out.WriteByte(0xE1)
	binary.Write(&out, binary.BigEndian, app1Len)
	out.Write(app1Payload)

	out.Write(jpegBytes[2:])

	return os.WriteFile(path, out.Bytes(), 0644)
}

// readOrientation extracts the EXIF orientation tag from a JPEG file.
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

// decodeImage opens and decodes an image file based on detected format.
func decodeImage(path string, format imageFormat) (image.Image, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	switch format {
	case formatHEIC:
		return decodeHEIC(f)
	case formatJPEG:
		return jpeg.Decode(f)
	case formatPNG:
		return png.Decode(f)
	default:
		return nil, fmt.Errorf("unsupported image format for %s", path)
	}
}

func decodeHEIC(r io.Reader) (image.Image, error) {
	img, err := heic.Decode(r)
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
