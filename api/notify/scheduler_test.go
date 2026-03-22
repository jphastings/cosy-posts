package notify

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestJoinNames(t *testing.T) {
	tests := []struct {
		names []string
		want  string
	}{
		{nil, ""},
		{[]string{}, ""},
		{[]string{"Alice"}, "Alice"},
		{[]string{"Alice", "Bob"}, "Alice and Bob"},
		{[]string{"Alice", "Bob", "Charlie"}, "Alice, Bob, and Charlie"},
		{[]string{"Alice", "Bob", "Charlie", "Dana"}, "Alice, Bob, Charlie, and Dana"},
	}

	for _, tt := range tests {
		got := joinNames(tt.names)
		if got != tt.want {
			t.Errorf("joinNames(%v) = %q, want %q", tt.names, got, tt.want)
		}
	}
}

func TestBuildSentence(t *testing.T) {
	tests := []struct {
		authors  []string
		siteName string
		want     string
	}{
		{[]string{"Alice"}, "My Site", "There is a new post from Alice on My Site."},
		{[]string{"Alice", "Bob"}, "My Site", "There are new posts from Alice and Bob on My Site."},
		{[]string{"Alice", "Bob", "Charlie"}, "My Site", "There are new posts from Alice, Bob, and Charlie on My Site."},
	}

	for _, tt := range tests {
		got := buildSentence(tt.authors, tt.siteName)
		if got != tt.want {
			t.Errorf("buildSentence(%v, %q) = %q, want %q", tt.authors, tt.siteName, got, tt.want)
		}
	}
}

func TestFindPostsInWindow(t *testing.T) {
	dir := t.TempDir()

	// Helper to create a post with a given date.
	makePost := func(id, date string) {
		postDir := filepath.Join(dir, "2026", "03", "22", id)
		if err := os.MkdirAll(postDir, 0o755); err != nil {
			t.Fatal(err)
		}
		content := "---\ndate: " + date + "\nauthor: test@example.com\n---\n\nHello\n"
		if err := os.WriteFile(filepath.Join(postDir, "index.md"), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	makePost("before", "2026-03-22T14:05:00Z")  // before window
	makePost("start", "2026-03-22T14:10:00Z")    // exactly at window start (inclusive)
	makePost("inside", "2026-03-22T14:15:00Z")   // inside window
	makePost("end", "2026-03-22T14:20:00Z")      // exactly at window end (exclusive)
	makePost("after", "2026-03-22T14:25:00Z")    // after window

	start := time.Date(2026, 3, 22, 14, 10, 0, 0, time.UTC)
	end := time.Date(2026, 3, 22, 14, 20, 0, 0, time.UTC)

	posts := findPostsInWindow(dir, start, end)

	if len(posts) != 2 {
		t.Fatalf("expected 2 posts in window, got %d", len(posts))
	}

	authors := map[string]bool{}
	for _, p := range posts {
		authors[p.author] = true
	}
	if !authors["test@example.com"] {
		t.Error("expected posts to have author test@example.com")
	}
}

func TestFindPostsInWindow_DateOnly(t *testing.T) {
	dir := t.TempDir()

	postDir := filepath.Join(dir, "2026", "03", "22", "dateonly")
	if err := os.MkdirAll(postDir, 0o755); err != nil {
		t.Fatal(err)
	}
	content := "---\ndate: \"2026-03-22\"\nauthor: a@b.com\n---\n\nHello\n"
	if err := os.WriteFile(filepath.Join(postDir, "index.md"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	// Date-only parses as midnight UTC — should be found in a window that spans midnight.
	start := time.Date(2026, 3, 21, 23, 50, 0, 0, time.UTC)
	end := time.Date(2026, 3, 22, 0, 10, 0, 0, time.UTC)

	posts := findPostsInWindow(dir, start, end)
	if len(posts) != 1 {
		t.Fatalf("expected 1 post, got %d", len(posts))
	}
}

func TestFindPostsInWindow_SkipsSiteIndex(t *testing.T) {
	dir := t.TempDir()

	// Site-level index.md in content root should be ignored.
	content := "---\ndate: \"2026-03-22T14:15:00Z\"\nauthor: a@b.com\n---\n\nSite info\n"
	if err := os.WriteFile(filepath.Join(dir, "index.md"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	start := time.Date(2026, 3, 22, 14, 10, 0, 0, time.UTC)
	end := time.Date(2026, 3, 22, 14, 20, 0, 0, time.UTC)

	posts := findPostsInWindow(dir, start, end)
	if len(posts) != 0 {
		t.Fatalf("expected 0 posts (site index should be skipped), got %d", len(posts))
	}
}

func TestFindPostsInWindow_Empty(t *testing.T) {
	dir := t.TempDir()

	start := time.Date(2026, 3, 22, 14, 10, 0, 0, time.UTC)
	end := time.Date(2026, 3, 22, 14, 20, 0, 0, time.UTC)

	posts := findPostsInWindow(dir, start, end)
	if len(posts) != 0 {
		t.Fatalf("expected 0 posts, got %d", len(posts))
	}
}
