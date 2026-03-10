// Package video provides metadata extraction from video files using pure Go.
package video

import (
	"fmt"
	"os"
	"regexp"
	"strconv"

	mp4 "github.com/abema/go-mp4"
)

// Info holds extracted metadata from a video file.
type Info struct {
	Width  int
	Height int
	// GPS location from MP4 metadata, if present.
	Lat *float64
	Lng *float64
}

// Probe extracts video dimensions and GPS location from a video file.
// Returns nil info (no error) if the file has no video stream.
func Probe(path string) (*Info, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("opening video: %w", err)
	}
	defer f.Close()

	info := &Info{}

	// Extract video dimensions from the VisualSampleEntry (stsd) box.
	// This works for all common codecs: H.264, H.265, AV1, VP8/VP9.
	boxes, err := mp4.ExtractBoxWithPayload(f, nil,
		mp4.BoxPath{mp4.BoxTypeMoov(), mp4.BoxTypeTrak(), mp4.BoxTypeMdia(), mp4.BoxTypeMinf(), mp4.BoxTypeStbl(), mp4.BoxTypeStsd()},
	)
	if err != nil {
		return nil, fmt.Errorf("extracting stsd: %w", err)
	}

	for _, b := range boxes {
		stsd, ok := b.Payload.(*mp4.Stsd)
		if !ok || stsd == nil {
			continue
		}
		// The stsd box is a container; we need to look at its children for
		// VisualSampleEntry types. Re-seek and extract known video types.
		break
	}

	// Try extracting VisualSampleEntry directly — go-mp4 registers all common
	// video codecs (avc1, hev1, hvc1, av01, vp08, vp09, mp4v, encv) as
	// VisualSampleEntry types.
	videoBoxTypes := []mp4.BoxType{
		mp4.BoxTypeAvc1(), mp4.BoxTypeHev1(), mp4.BoxTypeHvc1(),
		mp4.BoxTypeAv01(), mp4.BoxTypeVp08(), mp4.BoxTypeVp09(),
		mp4.BoxTypeMp4v(), mp4.BoxTypeEncv(),
	}

	for _, vbt := range videoBoxTypes {
		if _, err := f.Seek(0, 0); err != nil {
			return nil, fmt.Errorf("seeking: %w", err)
		}
		vbs, err := mp4.ExtractBoxWithPayload(f, nil,
			mp4.BoxPath{mp4.BoxTypeMoov(), mp4.BoxTypeTrak(), mp4.BoxTypeMdia(), mp4.BoxTypeMinf(), mp4.BoxTypeStbl(), mp4.BoxTypeStsd(), vbt},
		)
		if err != nil || len(vbs) == 0 {
			continue
		}
		if vse, ok := vbs[0].Payload.(*mp4.VisualSampleEntry); ok {
			info.Width = int(vse.Width)
			info.Height = int(vse.Height)
			break
		}
	}

	if info.Width == 0 || info.Height == 0 {
		return nil, nil // no video stream found
	}

	// Extract GPS location from the ©xyz atom under moov > udta.
	// Apple encodes location as a string like "+37.7749-122.4194/" or "+40.3524+018.1705/".
	if _, err := f.Seek(0, 0); err == nil {
		info.Lat, info.Lng = extractGPSFromMP4(f)
	}

	return info, nil
}

// Apple's ©xyz box type (0xA9 'x' 'y' 'z').
var boxTypeXYZ = mp4.BoxType{0xA9, 'x', 'y', 'z'}

// gpsPattern matches ISO 6709 location strings like "+37.7749-122.4194/" or "+40.3524+018.1705/".
var gpsPattern = regexp.MustCompile(`([+-]\d+\.\d+)([+-]\d+\.\d+)`)

func extractGPSFromMP4(f *os.File) (*float64, *float64) {
	// Try the ©xyz atom under moov > udta (Apple-style GPS).
	boxes, err := mp4.ExtractBox(f, nil,
		mp4.BoxPath{mp4.BoxTypeMoov(), mp4.BoxTypeUdta(), boxTypeXYZ},
	)
	if err != nil || len(boxes) == 0 {
		return nil, nil
	}

	// Read the raw bytes of the ©xyz box payload.
	bi := boxes[0]
	offset := int64(bi.Offset + bi.HeaderSize)
	size := int64(bi.Size - bi.HeaderSize)
	if size <= 0 || size > 1024 {
		return nil, nil
	}

	buf := make([]byte, size)
	if _, err := f.ReadAt(buf, offset); err != nil {
		return nil, nil
	}

	return parseGPSString(string(buf))
}

// parseGPSString parses ISO 6709 location strings like "+37.7749-122.4194/".
func parseGPSString(s string) (*float64, *float64) {
	m := gpsPattern.FindStringSubmatch(s)
	if len(m) < 3 {
		return nil, nil
	}

	lat, err1 := strconv.ParseFloat(m[1], 64)
	lng, err2 := strconv.ParseFloat(m[2], 64)
	if err1 != nil || err2 != nil {
		return nil, nil
	}

	return &lat, &lng
}
