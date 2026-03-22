package auth

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseMembers_Basic(t *testing.T) {
	path := filepath.Join(t.TempDir(), "can-post.csv")
	csv := "alice@example.com,Alice\nbob@example.com,Bob,https://wa.me/123\n"
	if err := os.WriteFile(path, []byte(csv), 0o644); err != nil {
		t.Fatal(err)
	}

	members := ParseMembers(path)

	if len(members) != 2 {
		t.Fatalf("expected 2 members, got %d", len(members))
	}

	alice := members["alice@example.com"]
	if alice.Name != "Alice" {
		t.Errorf("alice name = %q, want Alice", alice.Name)
	}
	// Email method is always present.
	if len(alice.Methods) != 1 || alice.Methods[0].Type != "email" {
		t.Errorf("alice methods = %v, want [email]", alice.Methods)
	}

	bob := members["bob@example.com"]
	if bob.Name != "Bob" {
		t.Errorf("bob name = %q, want Bob", bob.Name)
	}
	if len(bob.Methods) != 2 {
		t.Fatalf("bob methods count = %d, want 2", len(bob.Methods))
	}
	if bob.Methods[0].Type != "whatsapp" {
		t.Errorf("bob methods[0].Type = %q, want whatsapp", bob.Methods[0].Type)
	}
}

func TestParseMembers_NameFallsBackToEmail(t *testing.T) {
	path := filepath.Join(t.TempDir(), "can-post.csv")
	csv := "alice@example.com\n"
	if err := os.WriteFile(path, []byte(csv), 0o644); err != nil {
		t.Fatal(err)
	}

	members := ParseMembers(path)
	if members["alice@example.com"].Name != "alice@example.com" {
		t.Errorf("expected name to fall back to email")
	}
}

func TestParseMembers_EmptyLinesAndWhitespace(t *testing.T) {
	path := filepath.Join(t.TempDir(), "can-post.csv")
	csv := "\n  alice@example.com , Alice \n\n  bob@example.com,Bob\n\n"
	if err := os.WriteFile(path, []byte(csv), 0o644); err != nil {
		t.Fatal(err)
	}

	members := ParseMembers(path)
	if len(members) != 2 {
		t.Fatalf("expected 2 members, got %d", len(members))
	}
	if members["alice@example.com"].Name != "Alice" {
		t.Errorf("expected trimmed name, got %q", members["alice@example.com"].Name)
	}
}

func TestParseMembers_SignalMethod(t *testing.T) {
	path := filepath.Join(t.TempDir(), "can-post.csv")
	csv := "alice@example.com,Alice,https://signal.me/#p/123\n"
	if err := os.WriteFile(path, []byte(csv), 0o644); err != nil {
		t.Fatal(err)
	}

	members := ParseMembers(path)
	alice := members["alice@example.com"]
	if len(alice.Methods) != 2 {
		t.Fatalf("expected 2 methods, got %d", len(alice.Methods))
	}
	if alice.Methods[0].Type != "signal" {
		t.Errorf("methods[0].Type = %q, want signal", alice.Methods[0].Type)
	}
}

func TestParseMembers_MissingFile(t *testing.T) {
	members := ParseMembers("/nonexistent/path.csv")
	if len(members) != 0 {
		t.Errorf("expected empty map for missing file, got %d entries", len(members))
	}
}

func TestParseMembers_EmptyPath(t *testing.T) {
	members := ParseMembers("")
	if len(members) != 0 {
		t.Errorf("expected empty map for empty path, got %d entries", len(members))
	}
}
