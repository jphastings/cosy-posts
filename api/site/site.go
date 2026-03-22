package site

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"html/template"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jphastings/cosy-posts/api/internal/content"
	"github.com/jphastings/cosy-posts/api/video"
	_ "golang.org/x/image/webp"
	"github.com/yuin/goldmark"
)

const DefaultSiteName = "Cosy Posts"


// Member represents a contact-able person parsed from the can-post CSV.
type Member struct {
	Name    string   `json:"name"`
	Methods []Method `json:"methods"`
}

// Method is a single contact method (whatsapp, signal, email).
type Method struct {
	Type string `json:"type"`
	URL  string `json:"url"`
}

// Post holds all data needed to render a single post card.
type Post struct {
	ID                string
	Date              time.Time
	Author            string
	AuthorName        string
	Body              string
	BodyHTML          template.HTML
	Locale            string
	Media             []MediaFile
	URL               string
	ISODate           string
	ReadableDate      string
	MediaAspectRatio  float64 // from frontmatter or computed from image dimensions
}

// MediaFile represents a single media item in a post.
type MediaFile struct {
	Filename string
	URL      string
	IsVideo  bool
	Width    int // 0 if unknown (e.g. video)
	Height   int // 0 if unknown (e.g. video)
}

// frontmatter mirrors the YAML frontmatter in post index files.
type frontmatter struct {
	Date             string  `yaml:"date"`
	Author           string  `yaml:"author"`
	Locale           string  `yaml:"locale"`
	MediaAspectRatio float64 `yaml:"media_aspect_ratio"`
}

// Handler serves the embedded site, reading content from the filesystem.
type Handler struct {
	contentDir  string
	csvPath     string
	siteName    string
	homeTmpl    *template.Template
	singleTmpl  *template.Template
	roleFunc        func(*http.Request) string
	feedURLFunc     func(*http.Request) string
	emailNotifyFunc func(*http.Request) bool
}

// SetRoleFunc sets a function that extracts the user's role from a request.
func (h *Handler) SetRoleFunc(fn func(*http.Request) string) {
	h.roleFunc = fn
}

// SetFeedURLFunc sets a function that returns the authenticated RSS feed URL for the current user.
func (h *Handler) SetFeedURLFunc(fn func(*http.Request) string) {
	h.feedURLFunc = fn
}

// SetEmailNotifyFunc sets a function that returns whether the current user has email notifications enabled.
func (h *Handler) SetEmailNotifyFunc(fn func(*http.Request) bool) {
	h.emailNotifyFunc = fn
}

// NewHandler creates a site handler. contentDir is the path to the content
// directory. csvPath is the path to can-post.csv (may be empty).
// siteName is the display name for the site.
func NewHandler(contentDir, csvPath, siteName string) (*Handler, error) {
	if siteName == "" {
		siteName = DefaultSiteName
	}

	absContentDir, err := filepath.Abs(contentDir)
	if err != nil {
		return nil, fmt.Errorf("resolving content dir: %w", err)
	}

	// Build icon template function that inlines SVG content.
	icons := map[string]template.HTML{
		"bookmark":   template.HTML(bookmarkSVG),
		"bookmarked": template.HTML(bookmarkedSVG),
		"trash":      template.HTML(trashSVG),
		"info":       template.HTML(infoSVG),
		"whatsapp":   template.HTML(whatsappSVG),
		"signal":     template.HTML(signalSVG),
		"email":      template.HTML(emailSVG),
		"muted":      template.HTML(mutedSVG),
		"unmuted":    template.HTML(unmutedSVG),
		"pause":      template.HTML(pauseSVG),
	}
	funcMap := template.FuncMap{
		"icon": func(name string) template.HTML {
			if svg, ok := icons[name]; ok {
				return svg
			}
			return ""
		},
	}

	// Parse shared templates (base + post-card), then clone for each page type.
	shared, err := template.New("").Funcs(funcMap).ParseFS(templateFS, "templates/base.html", "templates/post-card.html")
	if err != nil {
		return nil, fmt.Errorf("parsing shared templates: %w", err)
	}

	homeTmpl, err := template.Must(shared.Clone()).ParseFS(templateFS, "templates/home.html")
	if err != nil {
		return nil, fmt.Errorf("parsing home template: %w", err)
	}

	singleTmpl, err := template.Must(shared.Clone()).ParseFS(templateFS, "templates/single.html")
	if err != nil {
		return nil, fmt.Errorf("parsing single template: %w", err)
	}

	return &Handler{
		contentDir: absContentDir,
		csvPath:    csvPath,
		siteName:   siteName,
		homeTmpl:   homeTmpl,
		singleTmpl: singleTmpl,
	}, nil
}

// ServeHTTP routes requests to the appropriate handler.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path

	// Static assets from embedded files (immutable, cache 1 week).
	switch path {
	case "/css/style.css":
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=604800")
		w.Write(styleCSS)
		return
	case "/img/bookmark.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(bookmarkSVG)
		return
	case "/img/bookmarked.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(bookmarkedSVG)
		return
	case "/img/email.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(emailSVG)
		return
	case "/img/signal.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(signalSVG)
		return
	case "/img/whatsapp.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(whatsappSVG)
		return
	case "/img/trash.svg":
		w.Header().Set("Content-Type", "image/svg+xml")
		w.Header().Set("Cache-Control", "public, max-age=15552000")
		w.Write(trashSVG)
		return
	}

	// Home page.
	if path == "/" || path == "" {
		h.serveHome(w, r)
		return
	}

	// Media files from content directory (immutable uploads, cache 1 week).
	// URLs look like /content/2026/03/04/{id}/media_0.jpg
	if strings.HasPrefix(path, "/content/") {
		rel := strings.TrimPrefix(path, "/content/")
		fp := filepath.Join(h.contentDir, filepath.FromSlash(rel))
		fp = filepath.Clean(fp)
		// Security: ensure resolved path is under contentDir.
		abs, err := filepath.Abs(fp)
		if err != nil || !strings.HasPrefix(abs, h.contentDir) {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=604800, immutable")
		http.ServeFile(w, r, abs)
		return
	}

	http.NotFound(w, r)
}

func (h *Handler) serveHome(w http.ResponseWriter, r *http.Request) {
	members := h.parseMembers()
	prefLang := content.PreferredLang(r.Header.Get("Accept-Language"))
	posts := h.loadPosts(members, prefLang)

	membersJSON, _ := json.Marshal(members)

	// RoleFunc is provided by the caller via SetRoleFunc to extract the
	// user's role from the request context.
	role := ""
	if h.roleFunc != nil {
		role = h.roleFunc(r)
	}

	feedURL := ""
	if h.feedURLFunc != nil {
		feedURL = h.feedURLFunc(r)
	}

	siteInfo := h.loadSiteInfo(prefLang)

	data := map[string]any{
		"SiteName":    h.siteName,
		"MembersJSON": template.JS(membersJSON),
		"Posts":       posts,
		"CanDelete":   role == "post",
		"SiteInfo":    siteInfo,
		"FeedURL":     feedURL,
		"EmailNotify": h.emailNotifyFunc != nil && h.emailNotifyFunc(r),
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "private, max-age=21600")
	w.Header().Set("Vary", "Accept-Language")
	if err := h.homeTmpl.ExecuteTemplate(w, "base.html", data); err != nil {
		log.Printf("site: render home: %v", err)
	}
}

func (h *Handler) loadPosts(members map[string]Member, prefLang string) []Post {
	var posts []Post

	filepath.Walk(h.contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		name := info.Name()
		if name != "index.md" && name != "index.djot" {
			return nil
		}

		// Skip the site-level index file in the content root.
		if filepath.Dir(path) == h.contentDir {
			return nil
		}

		post, err := h.parsePost(path, members)
		if err != nil {
			log.Printf("site: parse post %s: %v", path, err)
			return nil
		}

		// If there's a preferred language and it differs from the post's locale,
		// look for a matching translation file and swap in its body.
		if prefLang != "" && prefLang != post.Locale {
			postDir := filepath.Dir(path)
			for _, ext := range []string{".md", ".djot"} {
				tp := filepath.Join(postDir, "index."+prefLang+ext)
				raw, err := os.ReadFile(tp)
				if err != nil {
					continue
				}
				_, tbody := content.ParseFrontmatter[frontmatter](raw)
				if tbody != "" {
					var bodyHTML bytes.Buffer
					goldmark.Convert([]byte(tbody), &bodyHTML)
					post.Body = tbody
					post.BodyHTML = template.HTML(bodyHTML.String())
					post.Locale = prefLang
				}
				break
			}
		}

		posts = append(posts, post)
		return nil
	})

	// Sort by date descending.
	sort.Slice(posts, func(i, j int) bool {
		return posts[i].Date.After(posts[j].Date)
	})

	return posts
}

func (h *Handler) parsePost(indexPath string, members map[string]Member) (Post, error) {
	raw, err := os.ReadFile(indexPath)
	if err != nil {
		return Post{}, err
	}

	fm, body := content.ParseFrontmatter[frontmatter](raw)

	postDir := filepath.Dir(indexPath)
	postID := filepath.Base(postDir)

	// Relative path from content dir for URL construction.
	rel, _ := filepath.Rel(h.contentDir, postDir)
	contentURL := "/content/" + filepath.ToSlash(rel) + "/"

	// Parse date.
	var postDate time.Time
	if fm.Date != "" {
		postDate, _ = time.Parse(time.RFC3339, fm.Date)
		if postDate.IsZero() {
			postDate, _ = time.Parse("2006-01-02", fm.Date)
		}
	}

	// Find sibling media files.
	var media []MediaFile
	entries, _ := os.ReadDir(postDir)
	for _, e := range entries {
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if !content.MediaExts[ext] {
			continue
		}
		mf := MediaFile{
			Filename: e.Name(),
			URL:      contentURL + e.Name(),
			IsVideo:  content.VideoExts[ext],
		}
		// Detect media dimensions for aspect ratio calculation.
		if mf.IsVideo {
			if vi, err := video.Probe(filepath.Join(postDir, e.Name())); err == nil && vi != nil {
				mf.Width = vi.Width
				mf.Height = vi.Height
			}
		} else {
			if f, err := os.Open(filepath.Join(postDir, e.Name())); err == nil {
				if cfg, _, err := image.DecodeConfig(f); err == nil {
					mf.Width = cfg.Width
					mf.Height = cfg.Height
				}
				f.Close()
			}
		}
		media = append(media, mf)
	}
	sort.Slice(media, func(i, j int) bool {
		return media[i].Filename < media[j].Filename
	})

	// Render markdown body.
	var bodyHTML bytes.Buffer
	if body != "" {
		if err := goldmark.Convert([]byte(body), &bodyHTML); err != nil {
			log.Printf("site: markdown render for %s: %v", postID, err)
		}
	}

	// Look up author name.
	authorName := ""
	if fm.Author != "" {
		if m, ok := members[fm.Author]; ok {
			authorName = m.Name
		}
	}

	locale := fm.Locale
	if locale == "" {
		locale = "en"
	}

	// Use frontmatter aspect ratio if available, otherwise compute from image dimensions.
	aspectRatio := fm.MediaAspectRatio
	if aspectRatio == 0 {
		var ratioSum float64
		var ratioCount int
		for _, m := range media {
			if m.Width > 0 && m.Height > 0 {
				ratioSum += float64(m.Width) / float64(m.Height)
				ratioCount++
			}
		}
		if ratioCount > 0 {
			aspectRatio = ratioSum / float64(ratioCount)
			aspectRatio = math.Max(4.0/5.0, math.Min(1.91, aspectRatio))
		}
	}

	return Post{
		ID:               postID,
		Date:             postDate,
		Author:           fm.Author,
		AuthorName:       authorName,
		Body:             body,
		BodyHTML:         template.HTML(bodyHTML.String()),
		Locale:           locale,
		Media:            media,
		URL:              contentURL,
		ISODate:          postDate.Format(time.RFC3339),
		ReadableDate:     postDate.Format("2 Jan 2006"),
		MediaAspectRatio: aspectRatio,
	}, nil
}

// loadSiteInfo reads the site-level index.md (or locale variant) from the
// content directory root and returns rendered HTML. Returns empty if no file exists.
func (h *Handler) loadSiteInfo(prefLang string) template.HTML {
	// Try locale-specific file first.
	if prefLang != "" {
		for _, ext := range []string{".md", ".djot"} {
			path := filepath.Join(h.contentDir, "index."+prefLang+ext)
			raw, err := os.ReadFile(path)
			if err == nil {
				_, body := content.ParseFrontmatter[frontmatter](raw)
				if body != "" {
					var buf bytes.Buffer
					goldmark.Convert([]byte(body), &buf)
					return template.HTML(buf.String())
				}
			}
		}
	}

	// Fall back to default index.md / index.djot.
	for _, name := range []string{"index.md", "index.djot"} {
		path := filepath.Join(h.contentDir, name)
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		_, body := content.ParseFrontmatter[frontmatter](raw)
		if body != "" {
			var buf bytes.Buffer
			goldmark.Convert([]byte(body), &buf)
			return template.HTML(buf.String())
		}
	}

	return ""
}

func (h *Handler) parseMembers() map[string]Member {
	members := make(map[string]Member)
	if h.csvPath == "" {
		return members
	}

	f, err := os.Open(h.csvPath)
	if err != nil {
		return members
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		cols := strings.Split(line, ",")
		for i := range cols {
			cols[i] = strings.TrimSpace(cols[i])
		}

		email := cols[0]
		name := email
		if len(cols) > 1 && cols[1] != "" {
			name = cols[1]
		}

		var methods []Method
		for i := 2; i < len(cols); i++ {
			url := cols[i]
			if url == "" {
				continue
			}
			if strings.Contains(url, "wa.me") {
				methods = append(methods, Method{Type: "whatsapp", URL: url})
			} else if strings.Contains(url, "signal.me") {
				methods = append(methods, Method{Type: "signal", URL: url})
			}
		}
		// Email is always available as fallback.
		methods = append(methods, Method{Type: "email", URL: email})

		members[email] = Member{Name: name, Methods: methods}
	}

	return members
}
