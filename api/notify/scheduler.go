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

// preview is a per-post chunk used to build preview emails. Image bytes have
// already been read off disk and registered as a Resend attachment; only the
// magic-link URL still has to be substituted per recipient.
type preview struct {
	name     string // resolved author display name
	cid      string // Content-Id of the inline image attachment, or "" if no image
	excerpt  string // plain-text body excerpt (already collapsed/truncated)
	ellipsis bool   // whether to append "…" to the excerpt
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
	continueReading := appi18n.T(loc, "NotifyContinueReading")

	// When previews are enabled, read image bytes once and pre-build per-post
	// chunks. Per-recipient assembly only swaps in the magic link.
	//
	// Resend's batch endpoint silently drops attachments, so previews must be
	// sent one email at a time via client.Emails.Send. The plain-notification
	// path keeps using the batch endpoint.
	var previews []preview
	var attachments []*resend.Attachment
	if cfg.SendPostPreview() {
		previews, attachments = buildPreviews(posts, authorNameFor)
	}

	client := resend.NewClient(cfg.ResendAPIKey())

	if cfg.SendPostPreview() {
		var sent int
		for _, email := range recipients {
			link, err := magicLink(cfg, siteURL, email)
			if err != nil {
				log.Printf("notify: create token for %s: %v", email, err)
				continue
			}

			req := &resend.SendEmailRequest{
				From:        cfg.FromEmail(),
				To:          []string{email},
				Subject:     subject,
				Html:        renderPreviewEmail(sentence, previews, link, continueReading),
				Attachments: attachments,
			}
			if _, err := client.Emails.Send(req); err != nil {
				log.Printf("notify: send to %s: %v", email, err)
				continue
			}
			sent++
		}
		log.Printf("notify: sent %d preview notification emails (%d new posts by %s)",
			sent, len(posts), strings.Join(authorNames, ", "))
		return
	}

	// Plain (no-preview) path: use Batch.Send for efficiency.
	var emails []*resend.SendEmailRequest
	for _, email := range recipients {
		link, err := magicLink(cfg, siteURL, email)
		if err != nil {
			log.Printf("notify: create token for %s: %v", email, err)
			continue
		}
		htmlBody := fmt.Sprintf(
			`<p>%s</p><p><a href="%s">%s</a></p>`,
			sentence, link, visitSite,
		)
		emails = append(emails, &resend.SendEmailRequest{
			From:    cfg.FromEmail(),
			To:      []string{email},
			Subject: subject,
			Html:    htmlBody,
		})
	}

	if len(emails) == 0 {
		return
	}
	if _, err := client.Batch.Send(emails); err != nil {
		log.Printf("notify: send batch: %v", err)
		return
	}
	log.Printf("notify: sent %d notification emails (%d new posts by %s)",
		len(emails), len(posts), strings.Join(authorNames, ", "))
}

// magicLink mints a 24h auth token and returns the verify URL for the given
// recipient.
func magicLink(cfg *config.Config, siteURL, email string) (string, error) {
	token, err := auth.CreateToken(cfg.AuthDir, email, 24*time.Hour)
	if err != nil {
		return "", err
	}
	u, _ := url.Parse(siteURL)
	u = u.JoinPath("/auth/verify")
	q := u.Query()
	q.Set("token", token)
	u.RawQuery = q.Encode()
	return u.String(), nil
}

// buildPreviews reads each post's first image from disk into an inline
// attachment and prepares the per-post preview struct used during HTML render.
func buildPreviews(posts []postInfo, authorNameFor func(string) string) ([]preview, []*resend.Attachment) {
	var previews []preview
	var attachments []*resend.Attachment

	for _, p := range posts {
		pp := preview{name: authorNameFor(p.author)}
		pp.excerpt, pp.ellipsis = makeExcerpt(p.body, excerptMaxChars)

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
				pp.cid = p.postID
			}
		}

		previews = append(previews, pp)
	}
	return previews, attachments
}

// renderPreviewEmail composes the final HTML for a single recipient. The
// `link` is the recipient's unique magic link and is used as the
// "Continue reading" CTA on every post.
func renderPreviewEmail(sentence string, previews []preview, link, continueReading string) string {
	escapedLink := html.EscapeString(link)

	var sb strings.Builder
	fmt.Fprintf(&sb, `<p>%s</p>`, sentence)

	for _, p := range previews {
		sb.WriteString(`<hr style="border:none;border-top:1px solid #eee;margin:24px 0">`)

		if p.cid != "" {
			fmt.Fprintf(&sb,
				`<p><img src="cid:%s" alt="" style="max-width:100%%;height:auto;border-radius:4px"></p>`,
				html.EscapeString(p.cid),
			)
		}

		sb.WriteString(`<p><strong>`)
		sb.WriteString(html.EscapeString(p.name))
		sb.WriteString(`:</strong> `)
		if p.excerpt != "" {
			sb.WriteString(html.EscapeString(p.excerpt))
			if p.ellipsis {
				sb.WriteString(`… `)
			} else {
				sb.WriteString(` `)
			}
		}
		fmt.Fprintf(&sb, `</p><p><a href="%s">%s</a></p>`, escapedLink, html.EscapeString(continueReading))
	}

	return sb.String()
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
