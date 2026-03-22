package notify

import (
	"os"
	"path/filepath"
	"sort"
	"testing"
)

func TestList_SetAndHas(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify.txt")
	l, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()

	if l.Has("alice@example.com") {
		t.Error("expected Has to return false for unknown email")
	}

	l.Set("alice@example.com", true)
	if !l.Has("alice@example.com") {
		t.Error("expected Has to return true after Set(true)")
	}

	l.Set("alice@example.com", false)
	if l.Has("alice@example.com") {
		t.Error("expected Has to return false after Set(false)")
	}
}

func TestList_CaseInsensitive(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify.txt")
	l, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()

	l.Set("Alice@Example.COM", true)
	if !l.Has("alice@example.com") {
		t.Error("expected case-insensitive match")
	}
	if !l.Has("ALICE@EXAMPLE.COM") {
		t.Error("expected case-insensitive match")
	}
}

func TestList_Emails(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify.txt")
	l, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()

	l.Set("bob@example.com", true)
	l.Set("alice@example.com", true)

	emails := l.Emails()
	sort.Strings(emails)
	if len(emails) != 2 || emails[0] != "alice@example.com" || emails[1] != "bob@example.com" {
		t.Errorf("unexpected emails: %v", emails)
	}
}

func TestList_Persistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify.txt")

	// Write initial list.
	l1, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	l1.Set("alice@example.com", true)
	l1.Set("bob@example.com", true)
	l1.Close() // flushes to disk

	// Reload from file.
	l2, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l2.Close()

	if !l2.Has("alice@example.com") {
		t.Error("expected alice to persist")
	}
	if !l2.Has("bob@example.com") {
		t.Error("expected bob to persist")
	}
}

func TestList_LoadExistingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notify.txt")
	if err := os.WriteFile(path, []byte("alice@example.com\nbob@example.com\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	l, err := NewList(path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()

	if !l.Has("alice@example.com") {
		t.Error("expected alice from file")
	}
	if !l.Has("bob@example.com") {
		t.Error("expected bob from file")
	}
	if l.Has("charlie@example.com") {
		t.Error("expected charlie to be absent")
	}
}
