package site

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/yuin/goldmark"
	"gopkg.in/yaml.v3"
)

const DefaultSiteName = "Cosy Posts"

var videoExts = map[string]bool{
	".mp4": true, ".mov": true, ".webm": true,
}

var mediaExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
	".mp4": true, ".mov": true, ".webm": true,
	".m4a": true, ".mp3": true,
}

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
	ID           string
	Date         time.Time
	Author       string
	AuthorName   string
	Body         string
	BodyHTML     template.HTML
	Media        []MediaFile
	URL          string
	ISODate      string
	ReadableDate string
}

// MediaFile represents a single media item in a post.
type MediaFile struct {
	Filename string
	URL      string
	IsVideo  bool
}

// frontmatter mirrors the YAML frontmatter in post index files.
type frontmatter struct {
	Date   string `yaml:"date"`
	Author string `yaml:"author"`
}

// Handler serves the embedded site, reading content from the filesystem.
type Handler struct {
	contentDir string
	csvPath    string
	siteName   string
	homeTmpl   *template.Template
	singleTmpl *template.Template
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

	// Parse shared templates (base + post-card), then clone for each page type.
	shared, err := template.ParseFS(templateFS, "templates/base.html", "templates/post-card.html")
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
	posts := h.loadPosts(members)

	membersJSON, _ := json.Marshal(members)

	data := map[string]any{
		"SiteName":    h.siteName,
		"MembersJSON": template.JS(membersJSON),
		"Posts":       posts,
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=21600")
	if err := h.homeTmpl.ExecuteTemplate(w, "base.html", data); err != nil {
		log.Printf("site: render home: %v", err)
	}
}

func (h *Handler) loadPosts(members map[string]Member) []Post {
	var posts []Post

	filepath.Walk(h.contentDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		name := info.Name()
		if name != "index.md" && name != "index.djot" {
			return nil
		}

		post, err := h.parsePost(path, members)
		if err != nil {
			log.Printf("site: parse post %s: %v", path, err)
			return nil
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

	fm, body := parseFrontmatter(raw)

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
		if !mediaExts[ext] {
			continue
		}
		media = append(media, MediaFile{
			Filename: e.Name(),
			URL:      contentURL + e.Name(),
			IsVideo:  videoExts[ext],
		})
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

	return Post{
		ID:           postID,
		Date:         postDate,
		Author:       fm.Author,
		AuthorName:   authorName,
		Body:         body,
		BodyHTML:     template.HTML(bodyHTML.String()),
		Media:        media,
		URL:          contentURL,
		ISODate:      postDate.Format(time.RFC3339),
		ReadableDate: postDate.Format("2 Jan 2006"),
	}, nil
}

func parseFrontmatter(raw []byte) (frontmatter, string) {
	content := string(raw)
	var fm frontmatter

	if !strings.HasPrefix(content, "---\n") {
		return fm, strings.TrimSpace(content)
	}

	end := strings.Index(content[4:], "\n---\n")
	if end == -1 {
		return fm, strings.TrimSpace(content)
	}

	fmStr := content[4 : 4+end]
	body := content[4+end+5:]

	yaml.Unmarshal([]byte(fmStr), &fm)
	return fm, strings.TrimSpace(body)
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
