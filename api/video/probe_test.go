package video

import (
	"os"
	"testing"
)

func TestProbe_Dimensions(t *testing.T) {
	// Use an existing video from the content directory if available.
	path := os.Getenv("TEST_VIDEO_PATH")
	if path == "" {
		t.Skip("set TEST_VIDEO_PATH to run this test")
	}

	info, err := Probe(path)
	if err != nil {
		t.Fatalf("Probe(%s) error: %v", path, err)
	}
	if info == nil {
		t.Fatalf("Probe(%s) returned nil info", path)
	}
	if info.Width == 0 || info.Height == 0 {
		t.Errorf("expected non-zero dimensions, got %dx%d", info.Width, info.Height)
	}
	t.Logf("Video: %dx%d", info.Width, info.Height)
	if info.Lat != nil && info.Lng != nil {
		t.Logf("GPS: %f, %f", *info.Lat, *info.Lng)
	} else {
		t.Log("GPS: not found")
	}
}

func TestParseGPSString(t *testing.T) {
	tests := []struct {
		input   string
		wantLat float64
		wantLng float64
		wantNil bool
	}{
		{"+40.3524+018.1705/", 40.3524, 18.1705, false},
		{"+37.7749-122.4194/", 37.7749, -122.4194, false},
		{"-33.8688+151.2093/", -33.8688, 151.2093, false},
		{"no gps here", 0, 0, true},
		{"", 0, 0, true},
	}

	for _, tt := range tests {
		lat, lng := parseGPSString(tt.input)
		if tt.wantNil {
			if lat != nil || lng != nil {
				t.Errorf("parseGPSString(%q) = %v, %v; want nil", tt.input, lat, lng)
			}
			continue
		}
		if lat == nil || lng == nil {
			t.Errorf("parseGPSString(%q) = nil; want %f, %f", tt.input, tt.wantLat, tt.wantLng)
			continue
		}
		if *lat != tt.wantLat || *lng != tt.wantLng {
			t.Errorf("parseGPSString(%q) = %f, %f; want %f, %f", tt.input, *lat, *lng, tt.wantLat, tt.wantLng)
		}
	}
}
