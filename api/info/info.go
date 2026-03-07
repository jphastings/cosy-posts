package info

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/jphastings/cosy-posts/api/config"
	"github.com/yuin/goldmark"
)

// Version and GitSHA are set at build time via ldflags.
var (
	Version = "dev"
	GitSHA  = "unknown"
)

type Response struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	GitSHA  string `json:"git_sha"`
	Stats   Stats  `json:"stats"`
}

type Stats struct {
	Posts   int `json:"posts"`
	Photos  int `json:"photos"`
	Videos  int `json:"videos"`
	Audio   int `json:"audio"`
	Members int `json:"members"`
}

func Handler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		stats := countContent(cfg.ContentDir)
		stats.Members = countMembers(cfg.AuthDir)

		resp := Response{
			Name:    cfg.SiteName(),
			Version: Version,
			GitSHA:  GitSHA,
			Stats:   stats,
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

// SiteInfoHandler returns the rendered site-level index.md content as JSON.
// Supports Accept-Language header for locale fallback.
func SiteInfoHandler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		prefLang := preferredLang(r)
		html := loadSiteInfo(cfg.ContentDir, prefLang)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"html": string(html),
		})
	}
}

func preferredLang(r *http.Request) string {
	accept := r.Header.Get("Accept-Language")
	if accept == "" {
		return ""
	}
	for _, part := range strings.Split(accept, ",") {
		tag := strings.TrimSpace(strings.SplitN(part, ";", 2)[0])
		if tag == "" || tag == "*" {
			continue
		}
		lang, _, _ := strings.Cut(tag, "-")
		return strings.ToLower(lang)
	}
	return ""
}

func loadSiteInfo(contentDir, prefLang string) string {
	if prefLang != "" {
		for _, ext := range []string{".md", ".djot"} {
			path := filepath.Join(contentDir, "index."+prefLang+ext)
			raw, err := os.ReadFile(path)
			if err == nil {
				body := extractBody(raw)
				if body != "" {
					var buf bytes.Buffer
					goldmark.Convert([]byte(body), &buf)
					return buf.String()
				}
			}
		}
	}
	for _, name := range []string{"index.md", "index.djot"} {
		path := filepath.Join(contentDir, name)
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		body := extractBody(raw)
		if body != "" {
			var buf bytes.Buffer
			goldmark.Convert([]byte(body), &buf)
			return buf.String()
		}
	}
	return ""
}

func extractBody(raw []byte) string {
	content := string(raw)
	if !strings.HasPrefix(content, "---\n") {
		return strings.TrimSpace(content)
	}
	end := strings.Index(content[4:], "\n---\n")
	if end == -1 {
		return strings.TrimSpace(content)
	}
	return strings.TrimSpace(content[4+end+5:])
}

func countContent(contentDir string) Stats {
	var stats Stats

	filepath.WalkDir(contentDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}

		name := strings.ToLower(d.Name())

		// A post directory contains an index file
		if name == "index.md" || name == "index.djot" {
			stats.Posts++
			return nil
		}

		ext := strings.ToLower(filepath.Ext(name))
		switch ext {
		case ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic":
			stats.Photos++
		case ".mp4", ".mov", ".webm":
			stats.Videos++
		case ".m4a", ".mp3", ".wav", ".aac":
			stats.Audio++
		}

		return nil
	})

	return stats
}

func countMembers(authDir string) int {
	count := 0
	for _, name := range []string{"can-post.csv", "can-view.csv"} {
		f, err := os.Open(filepath.Join(authDir, name))
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if strings.TrimSpace(scanner.Text()) != "" {
				count++
			}
		}
		f.Close()
	}
	return count
}
