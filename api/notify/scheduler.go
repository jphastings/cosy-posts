package notify

import (
	"fmt"
	"html"
	"log"
	"mime"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jphastings/cosy-posts/api/auth"
	"github.com/jphastings/cosy-posts/api/config"
	"github.com/jphastings/cosy-posts/api/internal/content"
	appi18n "github.com/jphastings/cosy-posts/api/internal/i18n"
	goI18n "github.com/nicksnyder/go-i18n/v2/i18n"
	"github.com/resend/resend-go/v2"
)

// excerptMaxChars caps the plain-text body excerpt shown in preview emails.
// Truncation breaks at the last word boundary before this cap.
const excerptMaxChars = 280

type postInfo struct {
	author   string // email key from frontmatter
	postID   string // nanoid (post directory basename); used as the cid for inline images
	dir      string // absolute path to the post directory
	body     string // raw body text with frontmatter stripped
	firstImg string // basename of the first image in the post dir, "" if none
}

type frontmatter struct {
	Date   string `yaml:"date"`
	Author string `yaml:"author"`
}

// StartScheduler begins a background loop that checks for new posts and
// sends email notifications. It returns a stop function.
func StartScheduler(cfg *config.Config, list *List) func() {
	window := time.Duration(cfg.NotificationWindowMinutes()) * time.Minute
	if window <= 0 {
		window = 10 * time.Minute
	}

	log.Printf("notify: notifying of new posts every %v", window)

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
	windowEnd := now.Truncate(window).Add(-window)
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

	// Resolve author display names per post (used in preview headers and the summary line).
	authorNameFor := func(emailKey string) string {
		if m, ok := members[emailKey]; ok && m.Name != "" {
			return m.Name
		}
		return emailKey
	}

	// Collect unique author names (deduplicated by email, preserving order).
	seen := make(map[string]bool)
	var authorNames []string
	for _, p := range posts {
		if seen[p.author] {
			continue
		}
		seen[p.author] = true
		authorNames = append(authorNames, authorNameFor(p.author))
	}

	siteName := cfg.SiteName()
	if siteName == "" {
		siteName = "Cosy Posts"
	}
	siteURL := cfg.SiteURL()

	loc := appi18n.NewLocalizer("en")
	joinedAuthors := joinNames(authorNames)
	tplData := map[string]string{"Authors": joinedAuthors, "Site": siteName}

	subject, _ := loc.Localize(&goI18n.LocalizeConfig{
		MessageID:    "NotifySubject",
		PluralCount:  len(posts),
		TemplateData: tplData,
	})
	sentence, _ := loc.Localize(&goI18n.LocalizeConfig{
		MessageID:    "NotifyNewPost",
		PluralCount:  len(posts),
		TemplateData: tplData,
	})
	visitSite := appi18n.T(loc, "NotifyVisitSite")

	// Build the per-post preview HTML and inline image attachments once.
	// Both are reused across all per-recipient emails (only the magic-link
	// token differs per recipient).
	var previewHTML string
	var attachments []*resend.Attachment
	if cfg.SendPostPreview() {
		previewHTML, attachments = buildPreviews(posts, loc, authorNameFor)
	}

	// Build one email per recipient, each with a unique magic link token.
	var emails []*resend.SendEmailRequest
	for _, email := range recipients {
		token, err := auth.CreateToken(cfg.AuthDir, email, 24*time.Hour)
		if err != nil {
			log.Printf("notify: create token for %s: %v", email, err)
			continue
		}

		u, _ := url.Parse(siteURL)
		u = u.JoinPath("/auth/verify")
		q := u.Query()
		q.Set("token", token)
		u.RawQuery = q.Encode()
		link := u.String()

		var htmlBody string
		if previewHTML != "" {
			htmlBody = fmt.Sprintf(
				`<p>%s</p>%s<p><a href="%s">%s</a></p>`,
				sentence, previewHTML, link, visitSite,
			)
		} else {
			htmlBody = fmt.Sprintf(
				`<p>%s</p><p><a href="%s">%s</a></p>`,
				sentence, link, visitSite,
			)
		}

		req := &resend.SendEmailRequest{
			From:    cfg.FromEmail(),
			To:      []string{email},
			Subject: subject,
			Html:    htmlBody,
		}
		if len(attachments) > 0 {
			req.Attachments = attachments
		}
		emails = append(emails, req)
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

// buildPreviews renders one card per post (header, optional inline image, body
// excerpt, "continue reading" cue) and collects the inline image attachments
// referenced by `cid:` in the HTML.
func buildPreviews(posts []postInfo, loc *goI18n.Localizer, authorNameFor func(string) string) (string, []*resend.Attachment) {
	continueReading := appi18n.T(loc, "NotifyContinueReading")

	var sb strings.Builder
	var attachments []*resend.Attachment

	for _, p := range posts {
		sb.WriteString(`<hr style="border:none;border-top:1px solid #eee;margin:24px 0">`)

		header, _ := loc.Localize(&goI18n.LocalizeConfig{
			MessageID:    "NotifyPostHeader",
			TemplateData: map[string]string{"Author": authorNameFor(p.author)},
		})
		sb.WriteString(`<p><strong>`)
		sb.WriteString(html.EscapeString(header))
		sb.WriteString(`</strong></p>`)

		if p.firstImg != "" {
			data, err := os.ReadFile(filepath.Join(p.dir, p.firstImg))
			if err != nil {
				log.Printf("notify: read preview image %s: %v", p.firstImg, err)
			} else {
				ctype := mime.TypeByExtension(strings.ToLower(filepath.Ext(p.firstImg)))
				if ctype == "" {
					ctype = "image/jpeg"
				}
				attachments = append(attachments, &resend.Attachment{
					Content:     data,
					Filename:    p.firstImg,
					ContentType: ctype,
					ContentId:   p.postID,
				})
				sb.WriteString(fmt.Sprintf(
					`<p><img src="cid:%s" alt="" style="max-width:100%%;height:auto;border-radius:4px"></p>`,
					html.EscapeString(p.postID),
				))
			}
		}

		excerpt, truncated := makeExcerpt(p.body, excerptMaxChars)
		if excerpt != "" {
			sb.WriteString(`<p>`)
			sb.WriteString(html.EscapeString(excerpt))
			if truncated {
				sb.WriteString(`…`)
			}
			sb.WriteString(`</p>`)
		}

		if truncated || p.firstImg != "" {
			sb.WriteString(`<p><em>`)
			sb.WriteString(html.EscapeString(continueReading))
			sb.WriteString(`</em></p>`)
		}
	}

	return sb.String(), attachments
}

// makeExcerpt collapses whitespace in the body and truncates at the last word
// boundary at or before max characters. Returns the (possibly trimmed) text
// and whether truncation occurred.
func makeExcerpt(body string, max int) (string, bool) {
	collapsed := strings.Join(strings.Fields(body), " ")
	if len(collapsed) <= max {
		return collapsed, false
	}
	cut := collapsed[:max]
	if i := strings.LastIndexAny(cut, " \t\n"); i > 0 {
		cut = cut[:i]
	}
	return strings.TrimRight(cut, " \t\n"), true
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

		fm, body := content.ParseFrontmatter[frontmatter](raw)
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
			dir := filepath.Dir(path)
			posts = append(posts, postInfo{
				author:   fm.Author,
				postID:   filepath.Base(dir),
				dir:      dir,
				body:     body,
				firstImg: firstImageIn(dir),
			})
		}
		return nil
	})

	return posts
}

// firstImageIn returns the basename of the alphabetically-first image file in
// dir, or "" if none.
func firstImageIn(dir string) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if content.ImageExts[strings.ToLower(filepath.Ext(e.Name()))] {
			names = append(names, e.Name())
		}
	}
	if len(names) == 0 {
		return ""
	}
	sort.Strings(names)
	return names[0]
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
