package feed

import (
	"strings"
	"testing"
)

func TestSignURL_AppendsParams(t *testing.T) {
	signed := SignURL("https://example.com/content/img.jpg", "alice@example.com", "secret")

	if !strings.Contains(signed, "email=alice%40example.com") {
		t.Errorf("expected email param, got %s", signed)
	}
	if !strings.Contains(signed, "sig=") {
		t.Errorf("expected sig param, got %s", signed)
	}
	if !strings.HasPrefix(signed, "https://example.com/content/img.jpg?") {
		t.Errorf("expected original URL prefix, got %s", signed)
	}
}

func TestSignURL_Deterministic(t *testing.T) {
	s1 := SignURL("https://example.com/a.jpg", "alice@example.com", "secret")
	s2 := SignURL("https://example.com/a.jpg", "alice@example.com", "secret")
	if s1 != s2 {
		t.Error("expected deterministic output")
	}
}

func TestSignURL_DifferentEmailsDifferentSigs(t *testing.T) {
	s1 := SignURL("https://example.com/a.jpg", "alice@example.com", "secret")
	s2 := SignURL("https://example.com/a.jpg", "bob@example.com", "secret")
	if s1 == s2 {
		t.Error("expected different signed URLs for different emails")
	}
}

func TestSignURL_PreservesExistingQuery(t *testing.T) {
	signed := SignURL("https://example.com/a.jpg?v=1", "alice@example.com", "secret")
	if !strings.Contains(signed, "v=1") {
		t.Errorf("expected existing query param preserved, got %s", signed)
	}
	if !strings.Contains(signed, "email=") {
		t.Errorf("expected email param added, got %s", signed)
	}
}

func TestSignURL_InvalidURL(t *testing.T) {
	signed := SignURL("://bad", "alice@example.com", "secret")
	if signed != "://bad" {
		t.Errorf("expected passthrough for invalid URL, got %s", signed)
	}
}
