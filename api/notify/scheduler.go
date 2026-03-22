package notify

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/internal/content"
	"github.com/resend/resend-go/v2"
)

type postInfo struct {
	author string // email key from frontmatter
}

type frontmatter struct {
	Date   string `yaml:"date"`
	Author string `yaml:"author"`
}

// StartScheduler begins a background loop that checks for new posts and
// sends email notifications. It returns a stop function.
func StartScheduler(cfg *config.Config, list *List) func() {
	window := time.Duration(cfg.EmailWindowMinutes) * time.Minute
	if window <= 0 {
		window = 10 * time.Minute
	}

	stop := make(chan struct{})
	done := make(chan struct{})

	go func() {
		defer close(done)

		// Align to the next window boundary.
		now := time.Now()
		next := now.Truncate(window).Add(window)
		timer := time.NewTimer(time.Until(next))
		defer timer.Stop()

		for {
			select {
			case <-stop:
				return
			case t := <-timer.C:
				tick(cfg, list, t, window)
				// Schedule next tick aligned to window.
				next = t.Truncate(window).Add(window)
				timer.Reset(time.Until(next))
			}
		}
	}()

	return func() {
		close(stop)
		<-done
	}
}

func tick(cfg *config.Config, list *List, now time.Time, window time.Duration) {
	// Look one window back: [now - 2*window, now - window)
	windowEnd := now.Truncate(window)
	windowStart := windowEnd.Add(-window)

	posts := findPostsInWindow(cfg.ContentDir, windowStart, windowEnd)
	if len(posts) == 0 {
		return
	}

	recipients := list.Emails()
	if len(recipients) == 0 {
		return
	}

	// Look up author names.
	csvPath := filepath.Join(cfg.AuthDir, "can-post.csv")
	members := auth.ParseMembers(csvPath)

	// Collect unique author names (deduplicated by email, preserving order).
	seen := make(map[string]bool)
	var authorNames []string
	for _, p := range posts {
		if seen[p.author] {
			continue
		}
		seen[p.author] = true
		name := p.author
		if m, ok := members[p.author]; ok {
			name = m.Name
		}
		authorNames = append(authorNames, name)
	}

	siteName := cfg.SiteName()
	if siteName == "" {
		siteName = "Cosy Posts"
	}
	siteURL := cfg.SiteURL()

	subject := fmt.Sprintf("New post on %s", siteName)
	sentence := buildSentence(authorNames, siteName)

	// Build one email per recipient, each with a unique magic link token.
	var emails []*resend.SendEmailRequest
	for _, email := range recipients {
		token, err := auth.CreateToken(cfg.AuthDir, email)
		if err != nil {
			log.Printf("notify: create token for %s: %v", email, err)
			continue
		}

		link := siteURL + "/auth/verify?token=" + token
		html := fmt.Sprintf(`<p>%s</p><p><a href="%s">Visit the site</a></p>`, sentence, link)

		emails = append(emails, &resend.SendEmailRequest{
			From:    cfg.FromEmail(),
			To:      []string{email},
			Subject: subject,
			Html:    html,
		})
	}

	if len(emails) == 0 {
		return
	}

	client := resend.NewClient(cfg.ResendAPIKey())
	_, err := client.Batch.Send(emails)
	if err != nil {
		log.Printf("notify: send batch: %v", err)
		return
	}

	log.Printf("notify: sent %d notification emails (%d new posts by %s)",
		len(emails), len(posts), strings.Join(authorNames, ", "))
}

func findPostsInWindow(contentDir string, start, end time.Time) []postInfo {
	var posts []postInfo

	filepath.Walk(contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		name := info.Name()
		if name != "index.md" && name != "index.djot" {
			return nil
		}
		if filepath.Dir(path) == contentDir {
			return nil
		}

		raw, err := os.ReadFile(path)
		if err != nil {
			return nil
		}

		fm, _ := content.ParseFrontmatter[frontmatter](raw)
		if fm.Date == "" {
			return nil
		}

		postDate, err := time.Parse(time.RFC3339, fm.Date)
		if err != nil {
			postDate, err = time.Parse("2006-01-02", fm.Date)
			if err != nil {
				return nil
			}
		}

		if !postDate.Before(start) && postDate.Before(end) {
			posts = append(posts, postInfo{author: fm.Author})
		}
		return nil
	})

	return posts
}

// buildSentence constructs "There is a new post from X on Site" or
// "There are new posts from X, Y, and Z on Site".
func buildSentence(authors []string, siteName string) string {
	if len(authors) == 1 {
		return fmt.Sprintf("There is a new post from %s on %s.", authors[0], siteName)
	}
	return fmt.Sprintf("There are new posts from %s on %s.", joinNames(authors), siteName)
}

// joinNames joins names with commas and "and":
// [A] → "A", [A, B] → "A and B", [A, B, C] → "A, B, and C"
func joinNames(names []string) string {
	switch len(names) {
	case 0:
		return ""
	case 1:
		return names[0]
	case 2:
		return names[0] + " and " + names[1]
	default:
		return strings.Join(names[:len(names)-1], ", ") + ", and " + names[len(names)-1]
	}
}
