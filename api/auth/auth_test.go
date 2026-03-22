package auth

import "testing"

func TestFeedPassword_Deterministic(t *testing.T) {
	p1 := FeedPassword("alice@example.com", "secret123")
	p2 := FeedPassword("alice@example.com", "secret123")
	if p1 != p2 {
		t.Error("expected same password for same inputs")
	}
}

func TestFeedPassword_CaseInsensitive(t *testing.T) {
	p1 := FeedPassword("Alice@Example.COM", "secret")
	p2 := FeedPassword("alice@example.com", "secret")
	if p1 != p2 {
		t.Error("expected case-insensitive email handling")
	}
}

func TestFeedPassword_DifferentSecrets(t *testing.T) {
	p1 := FeedPassword("alice@example.com", "secret1")
	p2 := FeedPassword("alice@example.com", "secret2")
	if p1 == p2 {
		t.Error("expected different passwords for different secrets")
	}
}

func TestFeedPassword_DifferentEmails(t *testing.T) {
	p1 := FeedPassword("alice@example.com", "secret")
	p2 := FeedPassword("bob@example.com", "secret")
	if p1 == p2 {
		t.Error("expected different passwords for different emails")
	}
}

func TestFeedPassword_HexEncoded(t *testing.T) {
	p := FeedPassword("alice@example.com", "secret")
	if len(p) != 64 {
		t.Errorf("expected 64 hex chars (SHA-256), got %d", len(p))
	}
	for _, c := range p {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			t.Errorf("unexpected character %q in hex output", c)
		}
	}
}
